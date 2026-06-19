import AgentBarCore
import Foundation
import ServiceManagement

enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate(String)
    case available(version: String, url: URL)
    case failed(String)
}

enum CodexQuotaCardState: Equatable {
    case loading
    case ready(CodexQuotaSnapshot, isStale: Bool)
    case unsupportedAPIKey
    case notConfigured
    case notLoggedIn
    case error(String)
}

@MainActor
final class AgentBarModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var usageSummary: UsageSummary = .empty
    @Published var quotaState: CodexQuotaCardState = .loading
    @Published var isRefreshing = false
    @Published var statusMessage = "Ready"
    @Published var errorMessage: String?
    @Published var lastRefresh: Date?
    @Published var updateState: AppUpdateState = .idle
    @Published var installMethod: AppInstallMethod = .unknown
    @Published var codexQuotaRefreshFailure: String?

    private let settingsStore: AppSettingsStore
    private let authLoader: CodexAuthLoader
    private let client: CodexQuotaClient
    private let quotaCacheStore: CodexQuotaCacheStore
    private let now: () -> Date
    private let database: UsageDatabase?
    private let scanner: UsageScanner?

    private var refreshLoop: Task<Void, Never>?
    private var startupLocalUsageScanTask: Task<Void, Never>?
    private var isScanningLocalUsage = false
    private var lastSuccessfulSnapshot: CodexQuotaSnapshot?
    private var lastNetworkAttempt: Date?

    private let startupLocalUsageScanDelay: UInt64 = 1_500_000_000
    private let freshQuotaTTL: TimeInterval = 60
    private let codexQuotaRetryLimit = 3

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        authLoader: CodexAuthLoader = CodexAuthLoader(),
        client: CodexQuotaClient = CodexQuotaClient(),
        quotaCacheStore: CodexQuotaCacheStore = CodexQuotaCacheStore(),
        database: UsageDatabase? = try? UsageDatabase(),
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.authLoader = authLoader
        self.client = client
        self.quotaCacheStore = quotaCacheStore
        self.now = now
        self.settings = settingsStore.load()
        self.database = database
        self.scanner = database.map { UsageScanner(database: $0) }

        if let database {
            do {
                self.usageSummary = try database.usageSummary(now: now(), settings: settings)
            } catch {
                self.errorMessage = PrivacyScrubber.scrub(error.localizedDescription)
                self.statusMessage = "Database error"
            }
        } else {
            self.errorMessage = "Unable to open local database"
            self.statusMessage = "Database error"
        }

        loadCachedCodexQuota()
        scheduleRefresh()
        scheduleStartupLocalUsageScan()
        Task { await refreshInstallMethod() }
        Task { await refresh(force: false, scansLocalUsage: false) }
    }

    deinit {
        refreshLoop?.cancel()
        startupLocalUsageScanTask?.cancel()
    }

    func persistSettings() {
        settings = settings.sanitized
        do {
            try settingsStore.save(settings)
            scheduleRefresh()
            if let database {
                usageSummary = try database.usageSummary(now: now(), settings: settings)
            }
            statusMessage = "Settings saved"
            errorMessage = nil
        } catch {
            errorMessage = PrivacyScrubber.scrub(error.localizedDescription)
        }
    }

    func refresh(force: Bool = false, honorsCodexRefreshInterval: Bool = true) async {
        await refresh(
            force: force,
            honorsCodexRefreshInterval: honorsCodexRefreshInterval,
            scansLocalUsage: true
        )
    }

    private func refresh(
        force: Bool,
        honorsCodexRefreshInterval: Bool = true,
        scansLocalUsage: Bool
    ) async {
        guard !isRefreshing else { return }

        isRefreshing = true
        statusMessage = force ? "Scanning" : "Refreshing"
        errorMessage = nil
        let currentDate = now()
        if scansLocalUsage {
            await refreshLocalUsage(currentDate: currentDate)
        }
        await refreshCodexQuota(
            force: force,
            currentDate: currentDate,
            honorsRefreshInterval: honorsCodexRefreshInterval
        )
        isRefreshing = false
    }

    private func refreshLocalUsage(currentDate: Date) async {
        guard !isScanningLocalUsage else { return }
        guard let database, let scanner else {
            errorMessage = "Unable to open local database"
            statusMessage = "Database error"
            return
        }

        isScanningLocalUsage = true
        defer { isScanningLocalUsage = false }

        let settings = self.settings

        do {
            let output = try await Task.detached(priority: .utility) {
                let scanResult = try scanner.scan()
                let summary = try database.usageSummary(now: currentDate, settings: settings)
                return (scanResult: scanResult, summary: summary)
            }.value

            usageSummary = output.summary
            lastRefresh = Date()
            statusMessage = output.scanResult.scannedFiles > 0
                ? "Scanned \(output.scanResult.scannedFiles) files"
                : "Up to date"
        } catch {
            errorMessage = PrivacyScrubber.scrub(error.localizedDescription)
            statusMessage = "Scan failed"
        }
    }

    private func refreshLocalUsageAfterStartup() async {
        let ownsRefreshIndicator = !isRefreshing
        if ownsRefreshIndicator {
            isRefreshing = true
        }
        if statusMessage == "Ready" || statusMessage == "Refreshing" {
            statusMessage = "Scanning"
        }

        await refreshLocalUsage(currentDate: now())

        if ownsRefreshIndicator {
            isRefreshing = false
        }
    }

    private func refreshCodexQuota(force: Bool, currentDate: Date, honorsRefreshInterval: Bool) async {
        let minimumRefreshInterval = TimeInterval(settings.sanitized.codexRefreshIntervalSeconds)
        if honorsRefreshInterval,
           !force,
           let lastNetworkAttempt,
           currentDate.timeIntervalSince(lastNetworkAttempt) < minimumRefreshInterval {
            _ = showCachedSnapshot(now: currentDate, stale: shouldMarkCachedQuotaStale(currentDate))
            return
        }

        switch authLoader.load() {
        case let .credentials(credentials):
            await refreshCodexQuota(credentials: credentials, force: force, currentDate: currentDate)
        case .unsupportedAPIKey:
            showCachedOrClear(status: "API key 模式不支持订阅额度查询", state: .unsupportedAPIKey, currentDate: currentDate)
        case .notLoggedIn:
            showCachedOrClear(status: "未登录,运行 codex login", state: .notLoggedIn, currentDate: currentDate)
        case .notConfigured:
            showCachedOrClear(status: "Codex 未配置", state: .notConfigured, currentDate: currentDate)
        case let .invalid(message):
            showCachedOrClear(status: message, state: .error(message), currentDate: currentDate)
        }
    }

    private func refreshCodexQuota(credentials: CodexCredentials, force: Bool, currentDate: Date) async {
        lastNetworkAttempt = currentDate

        do {
            let snapshot = try await fetchCodexQuotaWithRetries(credentials: credentials, force: force)
            lastSuccessfulSnapshot = snapshot
            lastRefresh = snapshot.fetchedAt
            try? quotaCacheStore.save(
                CodexQuotaCacheRecord(
                    snapshot: snapshot,
                    lastNetworkAttemptAt: currentDate,
                    cachedAt: now()
                )
            )
            quotaState = .ready(snapshot.refreshed(now: now()), isStale: false)
            codexQuotaRefreshFailure = nil
            if statusMessage == "Refreshing" || statusMessage == "Scanning" {
                statusMessage = "Updated"
            }
        } catch {
            let message = PrivacyScrubber.scrub(error.localizedDescription)
            codexQuotaRefreshFailure = message
            let hadSnapshot = lastSuccessfulSnapshot != nil
            if !showCachedSnapshot(now: now(), stale: true) {
                _ = loadCachedCodexQuota(markStale: true)
            }
            if !isQuotaReady {
                let displayMessage = hadSnapshot ? "Unable to refresh Codex quota" : message
                clearQuota(status: displayMessage, state: .error(displayMessage))
            } else {
                statusMessage = message
            }
        }
    }

    private func fetchCodexQuotaWithRetries(credentials: CodexCredentials, force: Bool) async throws -> CodexQuotaSnapshot {
        var lastError: Error?

        for attempt in 1...codexQuotaRetryLimit {
            do {
                return try await client.fetch(credentials: credentials, force: force)
            } catch {
                lastError = error
                guard attempt < codexQuotaRetryLimit else { break }
            }
        }

        let message = PrivacyScrubber.scrub(lastError?.localizedDescription ?? "Unable to refresh Codex quota")
        throw CodexQuotaRefreshError(attempts: codexQuotaRetryLimit, message: message)
    }

    func popoverOpened() {
        Task { await refresh(force: false) }
    }

    func resetPricing() {
        guard let database else { return }
        do {
            try database.resetPricingToDefaults()
            try database.recalculateHistoricalCosts()
            usageSummary = try database.usageSummary(now: now(), settings: settings)
            statusMessage = "Pricing reset"
            errorMessage = nil
        } catch {
            errorMessage = PrivacyScrubber.scrub(error.localizedDescription)
            statusMessage = "Pricing reset failed"
        }
    }

    func recalculateCosts() {
        guard let database else { return }
        do {
            try database.recalculateHistoricalCosts()
            usageSummary = try database.usageSummary(now: now(), settings: settings)
            statusMessage = "Costs recalculated"
            errorMessage = nil
        } catch {
            errorMessage = PrivacyScrubber.scrub(error.localizedDescription)
            statusMessage = "Recalculate failed"
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let previous = settings.launchAtLogin
        settings.launchAtLogin = enabled

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            persistSettings()
            statusMessage = enabled ? "Launch at login enabled" : "Launch at login disabled"
        } catch {
            settings.launchAtLogin = previous
            errorMessage = PrivacyScrubber.scrub(error.localizedDescription)
            statusMessage = "Login item update failed"
        }
    }

    func checkForUpdates() async {
        guard updateState != .checking else { return }
        updateState = .checking

        do {
            let latest = try await AppUpdateChecker().latestRelease()
            let currentVersion = AppVersion.current.shortVersion
            if AppVersion.isNewer(latest.version, than: currentVersion) {
                updateState = .available(version: latest.version, url: latest.url)
                statusMessage = "Update available"
            } else {
                updateState = .upToDate(currentVersion)
                statusMessage = "AgentBar is up to date"
            }
            errorMessage = nil
        } catch {
            let message = PrivacyScrubber.scrub(error.localizedDescription)
            updateState = .failed(message)
            statusMessage = "Update check failed"
        }
    }

    func refreshInstallMethod() async {
        installMethod = await AppInstaller.currentInstallMethod()
    }

    func updateWithHomebrew() {
        do {
            try AppInstaller.openHomebrewUpdateTerminal()
            statusMessage = "Homebrew update started"
        } catch {
            let message = PrivacyScrubber.scrub(error.localizedDescription)
            updateState = .failed(message)
            statusMessage = "Update failed"
        }
    }

    var menuBarTitle: String {
        switch settings.codexMenuBarMode {
        case .iconOnly:
            return localUsageMenuBarTitle
        case .alerts:
            guard case let .ready(snapshot, _) = quotaState else { return "" }
            let count = snapshot.warningCount
            return count > 0 ? limitedTitle("\(count)⚠") : ""
        case .plan:
            guard case let .ready(snapshot, _) = quotaState else {
                return "--"
            }
            let parts = settings.codexMenuBarQuotaItems
                .filter(\.isEnabled)
                .map { menuBarPart(for: $0, snapshot: snapshot) }
            guard !parts.isEmpty else { return localUsageMenuBarTitle }
            return limitedTitle(parts.joined(separator: " · "))
        }
    }

    var menuBarTooltip: String {
        let currentDate = now()
        let copy = AgentBarCopy(language: settings.language)
        let todayModel = usageSummary.todayTopModel?.model ?? copy.noModel
        var lines = codexTooltipLines(now: currentDate)
        lines.append(contentsOf: [
            "\(copy.today)    \(AgentBarFormatters.compactTokens(usageSummary.today.totalTokens)) tokens · \(AgentBarFormatters.usd(usageSummary.today.costUSD)) · \(todayModel)",
            "\(copy.sevenDaysShort)     \(AgentBarFormatters.compactTokens(usageSummary.sevenDayTokens)) tokens · \(AgentBarFormatters.usd(usageSummary.sevenDayCostUSD))",
            "\(copy.all)      \(AgentBarFormatters.compactTokens(usageSummary.allTimeTokens)) tokens · \(AgentBarFormatters.usd(usageSummary.allTimeCostUSD))"
        ])
        return lines.joined(separator: "\n")
    }

    private func scheduleRefresh() {
        refreshLoop?.cancel()

        let seconds = settings.sanitized.codexRefreshIntervalSeconds
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                let nanoseconds = UInt64(seconds) * 1_000_000_000
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await self?.refresh(force: false, honorsCodexRefreshInterval: false)
            }
        }
    }

    private func scheduleStartupLocalUsageScan() {
        startupLocalUsageScanTask?.cancel()
        let delay = startupLocalUsageScanDelay
        startupLocalUsageScanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.refreshLocalUsageAfterStartup()
        }
    }

    private func limitedTitle(_ value: String) -> String {
        guard value.count > 32 else { return value }
        return String(value.prefix(32)) + "..."
    }

    private var localUsageMenuBarTitle: String {
        switch settings.menuBarMetric {
        case .usedTokens:
            return limitedTitle(AgentBarFormatters.compactTokens(usageSummary.today.totalTokens))
        case .usedCost:
            return limitedTitle(AgentBarFormatters.usd(usageSummary.today.costUSD))
        case .remainingPercent:
            guard let remainingPercent = usageSummary.quota.preferredRemainingPercent else {
                return AgentBarCopy(language: settings.language).noBudget
            }
            return limitedTitle(AgentBarFormatters.percent(remainingPercent))
        }
    }

    @discardableResult
    private func showCachedSnapshot(now currentDate: Date, stale: Bool) -> Bool {
        guard let cached = lastSuccessfulSnapshot else {
            return false
        }
        let isStale = stale || currentDate.timeIntervalSince(cached.fetchedAt) > freshQuotaTTL
        quotaState = .ready(cached.refreshed(now: currentDate), isStale: isStale)
        lastRefresh = cached.fetchedAt
        return true
    }

    @discardableResult
    private func loadCachedCodexQuota(markStale: Bool = true) -> Bool {
        guard let record = try? quotaCacheStore.load() else {
            return false
        }
        lastSuccessfulSnapshot = record.snapshot
        lastNetworkAttempt = record.lastNetworkAttemptAt ?? record.snapshot.fetchedAt
        return showCachedSnapshot(now: now(), stale: markStale)
    }

    private var isQuotaReady: Bool {
        if case .ready = quotaState {
            return true
        }
        return false
    }

    private func shouldMarkCachedQuotaStale(_ currentDate: Date) -> Bool {
        guard let cached = lastSuccessfulSnapshot else {
            return true
        }
        return currentDate.timeIntervalSince(cached.fetchedAt) > freshQuotaTTL
    }

    private func showCachedOrClear(status: String, state: CodexQuotaCardState, currentDate: Date) {
        codexQuotaRefreshFailure = nil
        if showCachedSnapshot(now: currentDate, stale: true) || loadCachedCodexQuota(markStale: true) {
            statusMessage = "\(status) · showing cached quota"
        } else {
            clearQuota(status: status, state: state)
        }
    }

    private func clearQuota(status: String, state: CodexQuotaCardState) {
        lastSuccessfulSnapshot = nil
        quotaState = state
        if case let .error(message) = state {
            errorMessage = message
        }
        statusMessage = status
    }

    private func codexTooltipLines(now currentDate: Date) -> [String] {
        let copy = AgentBarCopy(language: settings.language)
        switch quotaState {
        case let .ready(snapshot, isStale):
            var lines = [snapshot.displayPlan]
            for key in CodexMenuBarQuotaItem.supportedKeys {
                if let window = snapshot.window(for: key) {
                    let used = AgentBarFormatters.percent(window.usedPercent)
                    let reset = AgentBarFormatters.relativeReset(from: currentDate, to: window.resetsAt, language: settings.language)
                    lines.append("\(key.label):  \(used) \(copy.used) · \(reset)")
                } else {
                    lines.append("\(key.label):  -- \(copy.used) · \(copy.unavailable)")
                }
            }
            if isStale {
                let age = AgentBarFormatters.relativeAge(from: currentDate, to: snapshot.fetchedAt)
                lines.append(settings.language == .simplifiedChinese ? "已过期 · 获取于 \(age)" : "Stale · fetched \(age)")
            } else {
                lines.append(copy.updated(at: snapshot.fetchedAt))
            }
            if let codexQuotaRefreshFailure {
                lines.append(codexQuotaRefreshFailure)
            }
            return lines
        case .unsupportedAPIKey:
            return ["Codex: \(copy.unsupportedAPIKey)"]
        case .notConfigured:
            return ["Codex: \(settings.language == .simplifiedChinese ? "未配置" : "Not configured")"]
        case .notLoggedIn:
            return ["Codex: \(settings.language == .simplifiedChinese ? "未登录，请运行 codex login" : "Not signed in. Run codex login")"]
        case let .error(message):
            return ["Codex: \(message)"]
        case .loading:
            return ["Codex: \(copy.refreshingQuota)"]
        }
    }

    private func menuBarPart(for item: CodexMenuBarQuotaItem, snapshot: CodexQuotaSnapshot) -> String {
        guard let window = snapshot.window(for: item.key) else {
            return "\(item.key.label) --"
        }

        let percent: String
        switch item.basis {
        case .used:
            percent = AgentBarFormatters.percent(window.usedPercent)
        case .remaining:
            percent = AgentBarFormatters.percent(window.remainingPercent)
        }

        guard settings.codexMenuBarShowsQuotaLabels else {
            return percent
        }
        return "\(item.key.label) \(percent)"
    }
}

private struct CodexQuotaRefreshError: LocalizedError {
    let attempts: Int
    let message: String

    var errorDescription: String? {
        "Codex 额度刷新连续 \(attempts) 次失败: \(message)"
    }
}
