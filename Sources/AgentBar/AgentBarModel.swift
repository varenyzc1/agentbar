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

enum CodexResetCreditsState: Equatable {
    case idle
    case loading
    case ready(CodexResetCreditsSnapshot)
    case error(String)
}

enum GrokQuotaCardState: Equatable {
    case loading
    case ready(GrokQuotaSnapshot, isStale: Bool)
    case unsupportedAPIKey
    case notConfigured
    case notLoggedIn
    case error(String)
}

enum ClaudeQuotaCardState: Equatable {
    case loading
    case ready(ClaudeQuotaSnapshot, isStale: Bool)
    case error(String)
}

enum ClaudeEgressIPState: Equatable {
    case idle
    case checking
    case ready(ClaudeEgressIPSnapshot)
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
    @Published var resetCreditsState: CodexResetCreditsState = .idle
    @Published var resetCreditsRefreshFailure: String?
    @Published var grokQuotaState: GrokQuotaCardState = .loading
    @Published var grokQuotaRefreshFailure: String?
    @Published var claudeQuotaState: ClaudeQuotaCardState = .loading
    @Published var claudeQuotaRefreshFailure: String?
    @Published var isRefreshingClaudeQuota = false
    @Published private(set) var claudeEgressIPState: ClaudeEgressIPState = .idle

    private let settingsStore: AppSettingsStore
    private let authLoader: CodexAuthLoader
    private let client: CodexQuotaClient
    private let resetCreditsClient: CodexResetCreditsClient
    private let quotaCacheStore: CodexQuotaCacheStore
    private let resetCreditsCacheStore: CodexResetCreditsCacheStore
    private let grokAuthLoader: GrokAuthLoader
    private let grokQuotaClient: GrokQuotaClient
    private let grokQuotaCacheStore: GrokQuotaCacheStore
    private let claudeAuthLoader: ClaudeAuthLoader
    private let claudeQuotaClient: ClaudeQuotaClient
    private let claudeEgressIPClient: ClaudeEgressIPClient
    private var claudeEgressIPTask: Task<Void, Never>?
    private var claudeEgressIPRequestID: UUID?
    private let claudeQuotaCacheStore: ClaudeQuotaCacheStore
    private var claudeQuotaCache: ClaudeQuotaCacheRecord?
    private let now: () -> Date
    private let database: UsageDatabase?
    private let scanner: UsageScanner?

    private var refreshLoop: Task<Void, Never>?
    private var startupLocalUsageScanTask: Task<Void, Never>?
    private var isScanningLocalUsage = false
    private var lastSuccessfulSnapshot: CodexQuotaSnapshot?
    private var lastNetworkAttempt: Date?
    private var lastSuccessfulResetCreditsSnapshot: CodexResetCreditsSnapshot?
    private var lastSuccessfulGrokSnapshot: GrokQuotaSnapshot?
    private var lastGrokNetworkAttempt: Date?

    private let startupLocalUsageScanDelay: UInt64 = 1_500_000_000
    private let freshQuotaTTL: TimeInterval = 60
    private let codexQuotaRetryLimit = 3

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        authLoader: CodexAuthLoader = CodexAuthLoader(),
        client: CodexQuotaClient = CodexQuotaClient(),
        resetCreditsClient: CodexResetCreditsClient = CodexResetCreditsClient(),
        quotaCacheStore: CodexQuotaCacheStore = CodexQuotaCacheStore(),
        resetCreditsCacheStore: CodexResetCreditsCacheStore = CodexResetCreditsCacheStore(),
        grokAuthLoader: GrokAuthLoader = GrokAuthLoader(),
        grokQuotaClient: GrokQuotaClient = GrokQuotaClient(),
        grokQuotaCacheStore: GrokQuotaCacheStore = GrokQuotaCacheStore(),
        claudeAuthLoader: ClaudeAuthLoader = ClaudeAuthLoader(),
        claudeQuotaClient: ClaudeQuotaClient = ClaudeQuotaClient(),
        claudeEgressIPClient: ClaudeEgressIPClient = ClaudeEgressIPClient(),
        claudeQuotaCacheStore: ClaudeQuotaCacheStore = ClaudeQuotaCacheStore(),
        database: UsageDatabase? = try? UsageDatabase(),
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.authLoader = authLoader
        self.client = client
        self.resetCreditsClient = resetCreditsClient
        self.quotaCacheStore = quotaCacheStore
        self.resetCreditsCacheStore = resetCreditsCacheStore
        self.grokAuthLoader = grokAuthLoader
        self.grokQuotaClient = grokQuotaClient
        self.grokQuotaCacheStore = grokQuotaCacheStore
        self.claudeAuthLoader = claudeAuthLoader
        self.claudeQuotaClient = claudeQuotaClient
        self.claudeEgressIPClient = claudeEgressIPClient
        self.claudeQuotaCacheStore = claudeQuotaCacheStore
        self.claudeQuotaCache = try? claudeQuotaCacheStore.load()
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
        loadCachedResetCredits()
        loadCachedGrokQuota()
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
        await refreshGrokQuota(
            force: force,
            currentDate: currentDate,
            honorsRefreshInterval: honorsCodexRefreshInterval
        )
        await refreshClaudeQuota(force: force)
        await refreshResetCredits(updatesStatus: false)
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

    private func refreshGrokQuota(force: Bool, currentDate: Date, honorsRefreshInterval: Bool) async {
        let minimumRefreshInterval = TimeInterval(settings.sanitized.codexRefreshIntervalSeconds)
        if honorsRefreshInterval,
           !force,
           let lastGrokNetworkAttempt,
           currentDate.timeIntervalSince(lastGrokNetworkAttempt) < minimumRefreshInterval {
            _ = showCachedGrokSnapshot(now: currentDate, stale: shouldMarkCachedGrokQuotaStale(currentDate))
            return
        }

        switch await grokAuthLoader.loadRefreshingIfNeeded() {
        case let .credentials(credentials):
            lastGrokNetworkAttempt = currentDate
            do {
                let snapshot = try await fetchGrokQuotaWithTokenRefresh(credentials: credentials)
                lastSuccessfulGrokSnapshot = snapshot
                grokQuotaState = .ready(snapshot, isStale: false)
                grokQuotaRefreshFailure = nil
                try? grokQuotaCacheStore.save(
                    GrokQuotaCacheRecord(
                        snapshot: snapshot,
                        lastNetworkAttemptAt: currentDate,
                        cachedAt: now()
                    )
                )
            } catch {
                let message = PrivacyScrubber.scrub(error.localizedDescription)
                grokQuotaRefreshFailure = message
                if !showCachedGrokSnapshot(now: now(), stale: true),
                   !loadCachedGrokQuota(markStale: true) {
                    grokQuotaState = .error(message)
                }
            }
        case .unsupportedAPIKey:
            showCachedGrokOrSet(.unsupportedAPIKey, currentDate: currentDate)
        case .notLoggedIn:
            showCachedGrokOrSet(.notLoggedIn, currentDate: currentDate)
        case .notConfigured:
            showCachedGrokOrSet(.notConfigured, currentDate: currentDate)
        case let .invalid(message):
            showCachedGrokOrSet(.error(message), currentDate: currentDate)
        }
    }

    private func fetchGrokQuotaWithTokenRefresh(credentials: GrokCredentials) async throws -> GrokQuotaSnapshot {
        do {
            return try await grokQuotaClient.fetch(credentials: credentials)
        } catch GrokQuotaClientError.tokenExpired {
            switch await grokAuthLoader.loadRefreshingIfNeeded(force: true) {
            case let .credentials(refreshedCredentials):
                return try await grokQuotaClient.fetch(credentials: refreshedCredentials)
            case let .invalid(message):
                throw GrokQuotaClientError.authRefresh(message)
            default:
                throw GrokQuotaClientError.tokenExpired
            }
        }
    }

    func popoverOpened() {
        Task { await refresh(force: false) }
    }

    func refreshClaudeQuota(force: Bool = true) async {
        guard !isRefreshingClaudeQuota else { return }
        isRefreshingClaudeQuota = true
        defer { isRefreshingClaudeQuota = false }
        let loader = claudeAuthLoader
        let auth = await Task.detached(priority: .utility) { loader.load(allowInteraction: force) }.value
        let credentials: ClaudeCredentials
        switch auth {
        case let .credentials(value): credentials = value
        case .notLoggedIn:
            setClaudeAuthError("Sign in to Claude Code with claude auth login.")
            return
        case .expired:
            setClaudeAuthError(ClaudeQuotaClientError.tokenExpired.localizedDescription)
            return
        case .missingScope:
            setClaudeAuthError("Claude login lacks usage access. Run claude auth login; setup-token is not sufficient.")
            return
        case .keychainAccessRequired:
            setClaudeAuthError("Allow Keychain access by clicking Refresh Claude quota.")
            return
        case .invalid:
            setClaudeAuthError("Could not read Claude login. Run claude auth login.")
            return
        }

        if claudeQuotaCache?.belongs(to: credentials) != true {
            claudeQuotaCache = ClaudeQuotaCacheRecord(credentialIdentity: credentials.cacheIdentity)
            claudeQuotaRefreshFailure = nil
            claudeQuotaState = .loading
        }
        guard var record = claudeQuotaCache else { return }
        let currentDate = now()
        let interval = TimeInterval(max(60, settings.sanitized.codexRefreshIntervalSeconds))
        guard record.schedule.allowsRequest(at: currentDate, interval: interval, force: force) else {
            if let retryAfter = record.schedule.retryAfter, retryAfter > currentDate {
                claudeQuotaRefreshFailure = ClaudeQuotaClientError.rateLimited(retryAfter: retryAfter).localizedDescription
            }
            if !showCachedClaudeQuota(stale: claudeQuotaRefreshFailure != nil), record.snapshot == nil {
                claudeQuotaState = .error(claudeQuotaRefreshFailure ?? "Waiting for the next Claude quota refresh.")
            }
            return
        }
        let proxy = settings.claudeProxy
        record.schedule.recordAttempt(at: currentDate)
        claudeQuotaCache = record
        let result: Result<ClaudeQuotaSnapshot, Error>
        do {
            result = .success(try await claudeQuotaClient.fetch(credentials: credentials, proxy: proxy))
        } catch {
            result = .failure(error)
        }
        // Recheck before publishing either new data or a cached result after a failed request.
        let latestAuth = await Task.detached(priority: .utility) { loader.load() }.value
        if case let .credentials(latest) = latestAuth, latest.cacheIdentity != credentials.cacheIdentity {
            setClaudeAuthError("Claude login changed. Refresh Claude quota.")
            return
        }
        if latestAuth == .notLoggedIn || latestAuth == .expired || latestAuth == .missingScope || latestAuth == .invalid {
            setClaudeAuthError("Claude login changed. Refresh Claude quota.")
            return
        }
        guard settings.claudeProxy == proxy else { return }
        switch result {
        case let .success(snapshot):
            record.snapshot = snapshot
            record.schedule.recordSuccess()
            claudeQuotaCache = record
            claudeQuotaRefreshFailure = nil
            _ = showCachedClaudeQuota(stale: false)
        case let .failure(error):
            let message = PrivacyScrubber.scrub(error.localizedDescription)
            claudeQuotaRefreshFailure = message
            if case let ClaudeQuotaClientError.rateLimited(retryAfter) = error {
                record.schedule.recordRateLimit(at: now(), serverRetryAfter: retryAfter)
            }
            if error as? ClaudeQuotaClientError == .tokenExpired || error as? ClaudeQuotaClientError == .forbidden {
                record.snapshot = nil
            }
            claudeQuotaCache = record
            if !showCachedClaudeQuota(stale: true) { claudeQuotaState = .error(message) }
        }
        if let record = claudeQuotaCache { try? claudeQuotaCacheStore.save(record) }
    }

    @discardableResult
    func setClaudeProxy(_ proxy: NetworkProxySettings) -> Bool {
        guard !isRefreshingClaudeQuota else { return false }
        do {
            try proxy.validate()
            var updated = settings
            updated.claudeProxy = proxy
            try settingsStore.save(updated.sanitized)
            settings = updated.sanitized
            statusMessage = "Settings saved"
            errorMessage = nil
            Task { await refreshClaudeQuota(force: true) }
            return true
        } catch {
            errorMessage = PrivacyScrubber.scrub(error.localizedDescription)
            return false
        }
    }

    func detectClaudeEgressIP(proxy: NetworkProxySettings) {
        clearClaudeEgressIP()
        let requestID = UUID()
        claudeEgressIPRequestID = requestID
        claudeEgressIPState = .checking
        let client = claudeEgressIPClient
        claudeEgressIPTask = Task {
            do {
                let snapshot = try await client.fetch(proxy: proxy)
                guard !Task.isCancelled, claudeEgressIPRequestID == requestID else { return }
                claudeEgressIPState = .ready(snapshot)
            } catch {
                guard !Task.isCancelled, claudeEgressIPRequestID == requestID else { return }
                claudeEgressIPState = .error(PrivacyScrubber.scrub(error.localizedDescription))
            }
            claudeEgressIPTask = nil
        }
    }

    func clearClaudeEgressIP() {
        claudeEgressIPTask?.cancel()
        claudeEgressIPTask = nil
        claudeEgressIPRequestID = nil
        claudeEgressIPState = .idle
    }

    private func setClaudeAuthError(_ message: String) {
        claudeQuotaState = .error(message)
        claudeQuotaRefreshFailure = nil
    }

    @discardableResult
    private func showCachedClaudeQuota(stale: Bool) -> Bool {
        guard let snapshot = claudeQuotaCache?.snapshot else { return false }
        let interval = TimeInterval(max(60, settings.sanitized.codexRefreshIntervalSeconds))
        claudeQuotaState = .ready(snapshot, isStale: stale || snapshot.isStale(at: now(), interval: interval))
        return true
    }

    func refreshResetCredits() async {
        await refreshResetCredits(updatesStatus: true)
    }

    private func refreshResetCredits(updatesStatus: Bool) async {
        guard resetCreditsState != .loading else { return }
        resetCreditsState = .loading
        resetCreditsRefreshFailure = nil

        switch authLoader.load() {
        case let .credentials(credentials):
            do {
                let snapshot = try await resetCreditsClient.fetch(credentials: credentials)
                lastSuccessfulResetCreditsSnapshot = snapshot
                resetCreditsState = .ready(snapshot)
                try? resetCreditsCacheStore.save(CodexResetCreditsCacheRecord(snapshot: snapshot))
                if updatesStatus {
                    statusMessage = "Reset credits updated"
                }
            } catch {
                let message = PrivacyScrubber.scrub(error.localizedDescription)
                showCachedResetCreditsOrError(message)
                if updatesStatus {
                    statusMessage = "Reset credits failed"
                }
            }
        case .unsupportedAPIKey:
            showCachedResetCreditsOrError("API key 模式不支持重置卡查询")
            if updatesStatus {
                statusMessage = "Reset credits failed"
            }
        case .notLoggedIn:
            showCachedResetCreditsOrError("未登录,运行 codex login")
            if updatesStatus {
                statusMessage = "Reset credits failed"
            }
        case .notConfigured:
            showCachedResetCreditsOrError("Codex 未配置")
            if updatesStatus {
                statusMessage = "Reset credits failed"
            }
        case let .invalid(message):
            showCachedResetCreditsOrError(message)
            if updatesStatus {
                statusMessage = "Reset credits failed"
            }
        }
    }

    private func loadCachedResetCredits() {
        guard let record = try? resetCreditsCacheStore.load() else { return }
        lastSuccessfulResetCreditsSnapshot = record.snapshot
        resetCreditsState = .ready(record.snapshot)
    }

    @discardableResult
    private func loadCachedGrokQuota(markStale: Bool = true) -> Bool {
        guard let record = try? grokQuotaCacheStore.load() else { return false }
        lastSuccessfulGrokSnapshot = record.snapshot
        lastGrokNetworkAttempt = record.lastNetworkAttemptAt ?? record.snapshot.fetchedAt
        return showCachedGrokSnapshot(now: now(), stale: markStale)
    }

    @discardableResult
    private func showCachedGrokSnapshot(now currentDate: Date, stale: Bool) -> Bool {
        guard let snapshot = lastSuccessfulGrokSnapshot else { return false }
        let expired = currentDate > snapshot.resetsAt.addingTimeInterval(60)
        let isStale = stale || expired || currentDate.timeIntervalSince(snapshot.fetchedAt) > freshQuotaTTL
        grokQuotaState = .ready(snapshot, isStale: isStale)
        return true
    }

    private func shouldMarkCachedGrokQuotaStale(_ currentDate: Date) -> Bool {
        guard let snapshot = lastSuccessfulGrokSnapshot else { return true }
        return currentDate > snapshot.resetsAt.addingTimeInterval(60)
            || currentDate.timeIntervalSince(snapshot.fetchedAt) > freshQuotaTTL
    }

    private func showCachedGrokOrSet(_ state: GrokQuotaCardState, currentDate: Date) {
        grokQuotaRefreshFailure = nil
        if !showCachedGrokSnapshot(now: currentDate, stale: true),
           !loadCachedGrokQuota(markStale: true) {
            grokQuotaState = state
        }
    }

    private func showCachedResetCreditsOrError(_ message: String) {
        if let snapshot = lastSuccessfulResetCreditsSnapshot
            ?? (try? resetCreditsCacheStore.load())?.snapshot {
            lastSuccessfulResetCreditsSnapshot = snapshot
            resetCreditsState = .ready(snapshot)
            resetCreditsRefreshFailure = message
        } else {
            resetCreditsState = .error(message)
        }
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
            var groups: [[String]] = []
            if case let .ready(snapshot, _) = quotaState {
                groups.append(MenuBarQuotaPresentation.codexTitles(
                    items: settings.sanitized.codexMenuBarQuotaItems, snapshot: snapshot,
                    showsWindowLabel: settings.codexMenuBarShowsQuotaLabels
                ))
            }
            if case let .ready(snapshot, _) = claudeQuotaState {
                let currentDate = now()
                groups.append(MenuBarQuotaPresentation.claudeTitles(
                    items: settings.sanitized.claudeMenuBarQuotaItems, snapshot: snapshot, now: currentDate
                ))
            }
            if settings.grokMenuBarShowsQuota,
               case let .ready(snapshot, _) = grokQuotaState {
                groups.append([grokMenuBarPart(snapshot: snapshot)])
            }
            if settings.codexMenuBarShowsLocalUsage {
                groups.append([labeledLocalUsageMenuBarTitle])
            }
            let title = MenuBarQuotaPresentation.title(groups: groups)
            guard !title.isEmpty else {
                if case .ready = quotaState { return localUsageMenuBarTitle }
                return "--"
            }
            return title
        }
    }

    var menuBarTooltip: String {
        let currentDate = now()
        let copy = AgentBarCopy(language: settings.language)
        let todayModel = usageSummary.todayTopModel?.model ?? copy.noModel
        var lines = codexTooltipLines(now: currentDate)
        lines.append(contentsOf: grokTooltipLines(now: currentDate))
        if case let .ready(snapshot, isStale) = claudeQuotaState {
            lines.append(snapshot.displayPlan)
            for window in snapshot.windows {
                let reset = window.resetsAt.map { AgentBarFormatters.relativeReset(from: currentDate, to: $0, language: settings.language) } ?? "--"
                lines.append("\(window.key.label): \(AgentBarFormatters.percent(window.usedPercent)) \(copy.used) · \(reset)")
            }
            if isStale { lines.append(copy.stale) }
            if let failure = claudeQuotaRefreshFailure { lines.append(copy.claudeMessage(failure)) }
        } else if case let .error(message) = claudeQuotaState {
            lines.append("Claude: \(copy.claudeMessage(message))")
        }
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

    private var labeledLocalUsageMenuBarTitle: String {
        let copy = AgentBarCopy(language: settings.language)
        switch settings.menuBarMetric {
        case .usedTokens, .usedCost:
            return localUsageMenuBarTitle
        case .remainingPercent:
            return "\(copy.metricTitle(.remainingPercent)) \(localUsageMenuBarTitle)"
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

    private func grokTooltipLines(now currentDate: Date) -> [String] {
        let copy = AgentBarCopy(language: settings.language)
        switch grokQuotaState {
        case let .ready(snapshot, isStale):
            let percent = grokQuotaPercent(snapshot)
            let basis = copy.quotaBasisTitle(settings.grokQuotaPercentBasis).lowercased()
            var lines = [
                "Grok \(snapshot.periodLabel):  \(AgentBarFormatters.percent(percent)) \(basis) · \(AgentBarFormatters.relativeReset(from: currentDate, to: snapshot.resetsAt, language: settings.language))"
            ]
            if isStale {
                let age = AgentBarFormatters.relativeAge(from: currentDate, to: snapshot.fetchedAt)
                lines.append(settings.language == .simplifiedChinese ? "Grok 已过期 · 获取于 \(age)" : "Grok stale · fetched \(age)")
            }
            if let grokQuotaRefreshFailure { lines.append(grokQuotaRefreshFailure) }
            return lines
        case .unsupportedAPIKey:
            return [settings.language == .simplifiedChinese ? "Grok: API key 模式不支持订阅余量查询" : "Grok: API key mode does not expose subscription quota"]
        case .notConfigured:
            return [settings.language == .simplifiedChinese ? "Grok: 未配置" : "Grok: Not configured"]
        case .notLoggedIn:
            return [settings.language == .simplifiedChinese ? "Grok: 未登录，请运行 grok login" : "Grok: Not signed in. Run grok login"]
        case let .error(message):
            return ["Grok: \(message)"]
        case .loading:
            return [settings.language == .simplifiedChinese ? "Grok: 正在刷新额度" : "Grok: Refreshing quota"]
        }
    }

    private func grokMenuBarPart(snapshot: GrokQuotaSnapshot) -> String {
        settings.grokMenuBarDisplayStyle.title(provider: "Grok", percent: grokQuotaPercent(snapshot))
    }

    private func grokQuotaPercent(_ snapshot: GrokQuotaSnapshot) -> Double {
        switch settings.grokQuotaPercentBasis {
        case .used:
            return snapshot.usedPercent
        case .remaining:
            return snapshot.remainingPercent
        }
    }
}

private struct CodexQuotaRefreshError: LocalizedError {
    let attempts: Int
    let message: String

    var errorDescription: String? {
        "Codex 额度刷新连续 \(attempts) 次失败: \(message)"
    }
}
