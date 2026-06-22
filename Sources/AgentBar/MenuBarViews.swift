import AgentBarCore
import AppKit
import SwiftUI

@MainActor
private final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?

    @discardableResult
    func show(model: AgentBarModel) -> NSWindow {
        if let window, window.isVisible {
            window.title = AgentBarCopy(language: model.settings.language).settingsWindowTitle
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return window
        }

        let copy = AgentBarCopy(language: model.settings.language)
        let hostingView = NSHostingView(rootView: SettingsView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = copy.settingsWindowTitle
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}

struct MenuBarLabelView: View {
    @ObservedObject var model: AgentBarModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.xaxis")
                .symbolRenderingMode(.monochrome)
            if !model.menuBarTitle.isEmpty {
                Text(model.menuBarTitle)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .help(model.menuBarTooltip)
    }
}

struct MenuBarPanelView: View {
    @ObservedObject var model: AgentBarModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var openingAnimationID = 0
    @State private var showsUsageRangeControl = false
    @State private var selectedUsageRange: UsagePanelRange = .sevenDays
    @State private var usageDetailsMode: UsageDetailsMode = .models
    @State private var topModelLimit: TopModelLimit = .three
    @State private var customStartDate = Date().addingTimeInterval(-29 * 86_400)
    @State private var customEndDate = Date()

    private static let panelWidth: CGFloat = 500
    private static let panelPadding: CGFloat = 16
    private static let panelOuterWidth = panelWidth + panelPadding * 2
    private static let contentMinHeight: CGFloat = 520
    private var copy: AgentBarCopy {
        AgentBarCopy(language: model.settings.language)
    }

    var body: some View {
        let usageWindow = selectedUsageWindow
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(width: Self.panelWidth, alignment: .leading)
                .padding(.horizontal, Self.panelPadding)
                .padding(.top, Self.panelPadding)
                .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                panelContent(usageWindow: usageWindow)
                    .frame(width: Self.panelWidth, alignment: .leading)
                    .padding(.horizontal, Self.panelPadding)
                    .padding(.bottom, 14)
            }
            .layoutPriority(1)
            .frame(minHeight: Self.contentMinHeight, alignment: .top)

            footer
                .frame(width: Self.panelWidth, alignment: .leading)
                .padding(.horizontal, Self.panelPadding)
                .padding(.top, 10)
                .padding(.bottom, Self.panelPadding)
        }
        .frame(width: Self.panelOuterWidth, alignment: .top)
        .frame(maxHeight: panelMaxHeight, alignment: .top)
        .agentBarPanelBackground()
        .onAppear {
            replayOpeningEffects()
            model.popoverOpened()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            replayOpeningEffects()
        }
    }

    private var panelMaxHeight: CGFloat {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        let visibleHeight = screen?.visibleFrame.height ?? 760
        return max(420, visibleHeight - 72)
    }

    private func panelContent(usageWindow: UsageWindowSnapshot) -> some View {
        let modules = visiblePanelModules
        return VStack(alignment: .leading, spacing: 14) {
            if showsUsageRangeControl {
                UsageRangeControlView(
                    selection: $selectedUsageRange,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate,
                    language: model.settings.language
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if modules.isEmpty {
                noVisibleModulesCard
            } else {
                if modules.contains(.summary) {
                    UsageWindowSummaryView(window: usageWindow, language: model.settings.language)
                }

                if modules.contains(.details) {
                    ModelUsageDetailsView(
                        window: usageWindow,
                        mode: $usageDetailsMode,
                        topLimit: $topModelLimit,
                        language: model.settings.language
                    )
                }

                if modules.contains(.trend) {
                    UsageThirtyDayBarChartView(days: recentThirtyDayUsage, language: model.settings.language)
                        .zIndex(2)
                }

                if modules.contains(.codexQuota) {
                    CodexQuotaCardView(
                        state: model.quotaState,
                        quotaItems: model.settings.sanitized.codexMenuBarQuotaItems,
                        refreshFailureMessage: model.codexQuotaRefreshFailure,
                        now: Date(),
                        language: model.settings.language
                    )
                }

                if modules.contains(.heatmap) {
                    UsageHeatmapView(
                        days: model.usageSummary.heatmapDays,
                        language: model.settings.language,
                        animationID: openingAnimationID
                    )
                }
            }
        }
    }

    private var visiblePanelModules: Set<PanelModule> {
        Set(model.settings.sanitized.visiblePanelModules)
    }

    private var noVisibleModulesCard: some View {
        Text(copy.noVisibleModules)
            .font(.callout)
            .agentBarSecondaryText()
            .frame(maxWidth: .infinity, alignment: .leading)
            .agentBarCard()
    }

    private func replayOpeningEffects() {
        openingAnimationID += 1
    }

    private var selectedUsageWindow: UsageWindowSnapshot {
        let calendar = Calendar.agentBarCalendar(timeZone: model.settings.timeZone)
        let today = calendar.startOfDay(for: Date())
        if selectedUsageRange == .all {
            return UsageWindowSnapshot(
                range: selectedUsageRange,
                startDate: allUsageStartDate(calendar: calendar, fallback: today),
                endDate: today,
                days: model.usageSummary.dailyUsageDays,
                modelDays: model.usageSummary.dailyModelUsageDays,
                sourceDays: model.usageSummary.dailySourceUsageDays
            )
        }
        let range = selectedUsageRange.dateRange(
            today: today,
            calendar: calendar,
            customStart: customStartDate,
            customEnd: customEndDate
        )
        return UsageWindowSnapshot(
            range: selectedUsageRange,
            startDate: range.start,
            endDate: range.end,
            days: denseUsageDays(start: range.start, end: range.end, calendar: calendar),
            modelDays: filteredModelUsage(start: range.start, end: range.end, calendar: calendar),
            sourceDays: filteredSourceUsage(start: range.start, end: range.end, calendar: calendar)
        )
    }

    private func allUsageStartDate(calendar: Calendar, fallback: Date) -> Date {
        let firstDay = model.usageSummary.dailyUsageDays.first?.day
            ?? model.usageSummary.dailyModelUsageDays.first?.day
            ?? model.usageSummary.dailySourceUsageDays.first?.day
        guard let firstDay,
              let date = UsageAggregator.date(fromDayString: firstDay, timeZone: calendar.timeZone) else {
            return fallback
        }
        return date
    }

    private var recentThirtyDayUsage: [DailyUsage] {
        let calendar = Calendar.agentBarCalendar(timeZone: model.settings.timeZone)
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        return denseUsageDays(start: start, end: today, calendar: calendar)
    }

    private func denseUsageDays(start: Date, end: Date, calendar: Calendar) -> [DailyUsage] {
        var byDay: [String: DailyUsage] = [:]
        for day in model.usageSummary.dailyUsageDays {
            byDay[day.day] = (byDay[day.day] ?? DailyUsage(day: day.day)).merging(day)
        }
        let dayCount = max(1, min(366, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1))
        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = UsageAggregator.dayString(for: date, timeZone: calendar.timeZone)
            return byDay[key] ?? DailyUsage(day: key)
        }
    }

    private func filteredModelUsage(start: Date, end: Date, calendar: Calendar) -> [DailyModelUsage] {
        model.usageSummary.dailyModelUsageDays.filter { usage in
            guard let date = UsageAggregator.date(fromDayString: usage.day, timeZone: calendar.timeZone) else {
                return false
            }
            return date >= start && date <= end
        }
    }

    private func filteredSourceUsage(start: Date, end: Date, calendar: Calendar) -> [DailySourceUsage] {
        model.usageSummary.dailySourceUsageDays.filter { usage in
            guard let date = UsageAggregator.date(fromDayString: usage.day, timeZone: calendar.timeZone) else {
                return false
            }
            return date >= start && date <= end
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AgentBar")
                    .font(.headline)
                Text(copy.statusMessage(model.statusMessage))
                    .font(.caption)
                    .foregroundStyle(model.errorMessage == nil ? AgentBarStyle.secondaryText(colorScheme) : AgentBarStyle.red)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    showsUsageRangeControl.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(selectedUsageRange.title(copy: copy))
                        .monospacedDigit()
                    Image(systemName: showsUsageRangeControl ? "chevron.up" : "chevron.down")
                        .imageScale(.small)
                }
            }
            .buttonStyle(AgentBarCommandButtonStyle())
            .help(showsUsageRangeControl ? copy.collapseRange : copy.expandRange)

            Button {
                Task { await model.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(AgentBarIconButtonStyle())
            .help(copy.refresh)
            .disabled(model.isRefreshing)

            Button {
                let menuBarWindow = NSApp.keyWindow
                let settingsWindow = SettingsWindowManager.shared.show(model: model)
                if menuBarWindow !== settingsWindow {
                    menuBarWindow?.orderOut(nil)
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(AgentBarIconButtonStyle())
            .help(copy.settings)
        }
    }

    private var footer: some View {
        HStack {
            Text(lastRefreshText)
                .font(.caption)
                .agentBarSecondaryText()
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(AgentBarIconButtonStyle())
            .help(copy.quit)
        }
    }

    private var lastRefreshText: String {
        guard let lastRefresh = model.lastRefresh else {
            return copy.notRefreshed
        }
        return copy.updated(at: lastRefresh)
    }
}

struct CodexQuotaCardView: View {
    let state: CodexQuotaCardState
    let quotaItems: [CodexMenuBarQuotaItem]
    let refreshFailureMessage: String?
    let now: Date
    let language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme

    @State private var redactsAccountEmail = false
    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        switch state {
        case .loading:
            statusCard(
                title: "Codex",
                message: copy.refreshingQuota,
                severity: .ok,
                systemImage: "arrow.triangle.2.circlepath"
            )
        case let .ready(snapshot, isStale):
            readyCard(snapshot: snapshot, isStale: isStale)
        case .unsupportedAPIKey:
            statusCard(
                title: "Codex",
                message: copy.unsupportedAPIKey,
                severity: .ok,
                systemImage: "key.slash"
            )
        case .notConfigured:
            statusCard(
                title: "Codex",
                message: copy.codexNotConfigured,
                severity: .ok,
                systemImage: "terminal"
            )
        case .notLoggedIn:
            statusCard(
                title: "Codex",
                message: copy.codexNotLoggedIn,
                severity: .ok,
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
        case let .error(message):
            statusCard(
                title: "Codex",
                message: message,
                severity: .critical,
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    private func readyCard(snapshot: CodexQuotaSnapshot, isStale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        statusDot(snapshot.severity)
                        Text(snapshot.displayPlan)
                            .font(.headline)
                    }
                    Text(refreshStatusText(snapshot: snapshot, isStale: isStale))
                        .font(.caption)
                        .foregroundStyle(refreshFailureMessage == nil ? AgentBarStyle.secondaryText(colorScheme) : AgentBarStyle.red)
                }

                Spacer()

                Text(AgentBarFormatters.percent(headerPercent(in: snapshot)))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(for: visibleSeverity(in: snapshot)))
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(CodexMenuBarQuotaItem.supportedKeys) { key in
                    MeterRowView(
                        window: snapshot.window(for: key),
                        key: key,
                        basis: quotaItem(for: key).basis,
                        now: now,
                        language: language
                    )
                }
            }

            if let accountDisplayName = snapshot.accountDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !accountDisplayName.isEmpty {
                HStack(spacing: 8) {
                    Label(displayAccountName(accountDisplayName), systemImage: "person.crop.circle")
                        .lineLimit(1)
                    Spacer()
                    staleText(isStale: isStale, snapshot: snapshot)
                    Button {
                        redactsAccountEmail.toggle()
                    } label: {
                        Image(systemName: redactsAccountEmail ? "eye" : "eye.slash")
                            .imageScale(.small)
                    }
                    .buttonStyle(AgentBarIconButtonStyle())
                    .help(redactsAccountEmail ? copy.showEmail : copy.hideEmail)
                }
                .font(.caption)
                .foregroundStyle(isStale ? AgentBarStyle.secondaryText(colorScheme) : AgentBarStyle.primaryText(colorScheme))
            } else if isStale {
                HStack {
                    Spacer()
                    staleText(isStale: isStale, snapshot: snapshot)
                }
                .font(.caption)
                .agentBarSecondaryText()
            }

            if let refreshFailureMessage {
                Label(refreshFailureMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AgentBarStyle.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .agentBarCard(padding: 12)
    }

    @ViewBuilder
    private func staleText(isStale: Bool, snapshot: CodexQuotaSnapshot) -> some View {
        if isStale {
            Text(AgentBarFormatters.relativeAge(from: now, to: snapshot.fetchedAt))
                .agentBarSecondaryText()
        }
    }

    private func refreshStatusText(snapshot: CodexQuotaSnapshot, isStale: Bool) -> String {
        copy.refreshStatus(snapshot: snapshot, isStale: isStale, failed: refreshFailureMessage != nil)
    }

    private func statusCard(
        title: String,
        message: String,
        severity: CodexQuotaSeverity,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                statusDot(severity)
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: systemImage)
                    .foregroundStyle(color(for: severity))
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(severity == .critical ? AgentBarStyle.red : AgentBarStyle.secondaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .agentBarCard(padding: 12)
    }

    private func statusDot(_ severity: CodexQuotaSeverity) -> some View {
        Circle()
            .fill(color(for: severity))
            .frame(width: 8, height: 8)
    }

    private func color(for severity: CodexQuotaSeverity) -> Color {
        switch severity {
        case .ok:
            return AgentBarStyle.green
        case .warning:
            return AgentBarStyle.yellow
        case .critical:
            return AgentBarStyle.red
        }
    }

    private var normalizedQuotaItems: [CodexMenuBarQuotaItem] {
        CodexMenuBarQuotaItem.normalized(quotaItems)
    }

    private var headerQuotaItems: [CodexMenuBarQuotaItem] {
        let enabled = normalizedQuotaItems.filter(\.isEnabled)
        return enabled.isEmpty ? normalizedQuotaItems : enabled
    }

    private func quotaItem(for key: CodexQuotaKey) -> CodexMenuBarQuotaItem {
        normalizedQuotaItems.first { $0.key == key } ?? CodexMenuBarQuotaItem(key: key)
    }

    private func headerPercent(in snapshot: CodexQuotaSnapshot) -> Double? {
        let availableItems = headerQuotaItems.filter { snapshot.window(for: $0.key) != nil }
        guard let firstItem = availableItems.first else { return nil }

        if availableItems.allSatisfy({ $0.basis == firstItem.basis }) {
            switch firstItem.basis {
            case .used:
                return availableItems
                    .compactMap { snapshot.window(for: $0.key)?.usedPercent }
                    .max()
            case .remaining:
                return availableItems
                    .compactMap { snapshot.window(for: $0.key)?.remainingPercent }
                    .min()
            }
        }

        guard let window = snapshot.window(for: firstItem.key) else { return nil }
        return percent(for: window, basis: firstItem.basis)
    }

    private func visibleHighestUsedPercent(in snapshot: CodexQuotaSnapshot) -> Double? {
        headerQuotaItems
            .compactMap { snapshot.window(for: $0.key)?.usedPercent }
            .max()
    }

    private func visibleSeverity(in snapshot: CodexQuotaSnapshot) -> CodexQuotaSeverity {
        visibleHighestUsedPercent(in: snapshot).map(CodexQuotaSeverity.severity(for:)) ?? .ok
    }

    private func displayAccountName(_ value: String) -> String {
        redactsAccountEmail ? redactedEmail(value) : value
    }

    private func redactedEmail(_ value: String) -> String {
        let parts = value.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return value }
        let local = parts[0]
        let first = local.first.map(String.init) ?? ""
        return "\(first)***@\(parts[1])"
    }
}

private func percent(for window: CodexQuotaWindow, basis: CodexQuotaPercentBasis) -> Double {
    switch basis {
    case .used:
        return window.usedPercent
    case .remaining:
        return window.remainingPercent
    }
}

struct MeterRowView: View {
    let window: CodexQuotaWindow?
    let key: CodexQuotaKey
    let basis: CodexQuotaPercentBasis
    let now: Date
    let language: AppLanguage

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(key.label)
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, alignment: .leading)
                Text(copy.quotaMeaning(key))
                    .font(.caption)
                    .agentBarSecondaryText()
                    .lineLimit(1)
                Spacer()
                Text(percentText)
                    .font(.caption.monospacedDigit().weight(.semibold))
            }

            AgentBarProgressBar(value: progressValue, tint: tint)

            HStack {
                Text(resetText)
                Spacer()
                Text(resetTimeText)
                    .monospacedDigit()
            }
            .font(.caption2)
            .agentBarSecondaryText()
        }
    }

    private var percentText: String {
        AgentBarFormatters.percent(window.map { percent(for: $0, basis: basis) })
    }

    private var progressValue: Double {
        guard let window else { return 0 }
        return max(0, min(1, percent(for: window, basis: basis) / 100))
    }

    private var tint: Color {
        guard let window else { return .secondary }
        switch window.severity {
        case .ok:
            return AgentBarStyle.green
        case .warning:
            return AgentBarStyle.yellow
        case .critical:
            return AgentBarStyle.red
        }
    }

    private var resetText: String {
        guard let window else { return copy.unavailable }
        if window.stale {
            return copy.stale
        }
        return AgentBarFormatters.relativeReset(from: now, to: window.resetsAt, language: language)
    }

    private var resetTimeText: String {
        guard let window, !window.stale else { return "" }
        if Calendar.current.isDate(window.resetsAt, inSameDayAs: now) {
            return window.resetsAt.formatted(date: .omitted, time: .shortened)
        }
        return window.resetsAt.formatted(date: .abbreviated, time: .shortened)
    }
}

enum UsagePanelRange: String, CaseIterable, Identifiable, Hashable {
    case today
    case sevenDays
    case thirtyDays
    case all
    case custom

    var id: String { rawValue }

    func title(copy: AgentBarCopy) -> String {
        switch self {
        case .today:
            return copy.today
        case .sevenDays:
            return copy.sevenDaysShort
        case .thirtyDays:
            return copy.thirtyDays
        case .all:
            return copy.all
        case .custom:
            return copy.custom
        }
    }

    func dateRange(today: Date, calendar: Calendar, customStart: Date, customEnd: Date) -> (start: Date, end: Date) {
        switch self {
        case .today:
            return (today, today)
        case .sevenDays:
            return (calendar.date(byAdding: .day, value: -6, to: today) ?? today, today)
        case .thirtyDays:
            return (calendar.date(byAdding: .day, value: -29, to: today) ?? today, today)
        case .all:
            return (.distantPast, today)
        case .custom:
            let start = calendar.startOfDay(for: customStart)
            let end = calendar.startOfDay(for: customEnd)
            return start <= end ? (start, end) : (end, start)
        }
    }
}

enum TopModelLimit: String, CaseIterable, Identifiable, Hashable {
    case three
    case five

    var id: String { rawValue }
    var count: Int { self == .three ? 3 : 5 }

    func title(copy: AgentBarCopy) -> String {
        self == .three ? copy.top3 : copy.top5
    }
}

enum UsageDetailsMode: String, CaseIterable, Identifiable, Hashable {
    case models
    case agents

    var id: String { rawValue }

    func title(copy: AgentBarCopy) -> String {
        switch self {
        case .models:
            return copy.model
        case .agents:
            return copy.agent
        }
    }
}

struct UsageWindowSnapshot {
    let range: UsagePanelRange
    let startDate: Date
    let endDate: Date
    let days: [DailyUsage]
    let modelDays: [DailyModelUsage]
    let sourceDays: [DailySourceUsage]

    var total: DailyUsage {
        days.reduce(DailyUsage(day: "range")) { $0.merging($1) }
    }

    var costUSD: Double? {
        let totalCost = days.compactMap(\.costUSD).reduce(0, +)
        return days.contains { $0.costUSD != nil } ? totalCost : nil
    }

    func topModels(limit: Int) -> [ModelUsageBreakdown] {
        var byModel: [String: ModelUsageBreakdown] = [:]
        for day in modelDays {
            byModel[day.model, default: ModelUsageBreakdown(model: day.model)].add(day)
        }
        return byModel.values
            .sorted { left, right in
                if left.totalTokens == right.totalTokens {
                    return left.model < right.model
                }
                return left.totalTokens > right.totalTokens
            }
            .prefix(limit)
            .map { $0 }
    }

    func topAgents(limit: Int) -> [AgentUsageBreakdown] {
        var bySource: [String: AgentUsageBreakdown] = [:]
        for day in sourceDays {
            bySource[day.source, default: AgentUsageBreakdown(source: day.source)].add(day)
        }
        return bySource.values
            .sorted { left, right in
                if left.totalTokens == right.totalTokens {
                    return left.source < right.source
                }
                return left.totalTokens > right.totalTokens
            }
            .prefix(limit)
            .map { $0 }
    }
}

struct ModelUsageBreakdown: Identifiable {
    var id: String { model }

    let model: String
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var cacheCreationInputTokens: Int64 = 0
    var reasoningOutputTokens: Int64 = 0
    var costUSD: Double = 0

    var cachedTokens: Int64 {
        cachedInputTokens + cacheCreationInputTokens
    }

    var totalTokens: Int64 {
        inputTokens + outputTokens + cachedTokens + reasoningOutputTokens
    }

    mutating func add(_ usage: DailyModelUsage) {
        inputTokens += usage.inputTokens
        outputTokens += usage.outputTokens
        cachedInputTokens += usage.cachedInputTokens
        cacheCreationInputTokens += usage.cacheCreationInputTokens
        reasoningOutputTokens += usage.reasoningOutputTokens
        costUSD += usage.costUSD
    }
}

struct AgentUsageBreakdown: Identifiable {
    var id: String { source }

    let source: String
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var cacheCreationInputTokens: Int64 = 0
    var reasoningOutputTokens: Int64 = 0
    var costUSD: Double = 0

    var cachedTokens: Int64 {
        cachedInputTokens + cacheCreationInputTokens
    }

    var totalTokens: Int64 {
        inputTokens + outputTokens + cachedTokens + reasoningOutputTokens
    }

    mutating func add(_ usage: DailySourceUsage) {
        inputTokens += usage.inputTokens
        outputTokens += usage.outputTokens
        cachedInputTokens += usage.cachedInputTokens
        cacheCreationInputTokens += usage.cacheCreationInputTokens
        reasoningOutputTokens += usage.reasoningOutputTokens
        costUSD += usage.costUSD
    }
}

private extension Calendar {
    static func agentBarCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

struct UsageRangeControlView: View {
    @Binding var selection: UsagePanelRange
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    let language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingDateField: CustomDateField?

    private enum CustomDateField: Hashable {
        case start
        case end
    }

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(copy.range)
                    .font(.caption.weight(.semibold))
                    .agentBarSecondaryText()
                    .frame(width: 42, alignment: .leading)
                AgentBarSegmentedPicker(
                    options: UsagePanelRange.allCases,
                    selection: $selection,
                    title: { $0.title(copy: copy) }
                )
                .frame(maxWidth: 380, alignment: .leading)
                Spacer(minLength: 0)
            }

            if selection == .custom {
                HStack(spacing: 8) {
                    compactDateField(copy.start, field: .start, date: $customStartDate)
                    compactDateField(copy.end, field: .end, date: $customEndDate)
                    Spacer(minLength: 0)
                }
            }
        }
        .agentBarCard()
    }

    private func compactDateField(_ title: String, field: CustomDateField, date: Binding<Date>) -> some View {
        Button {
            editingDateField = field
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .agentBarSecondaryText()
                Text(dateText(date.wrappedValue))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .agentBarPrimaryText()
                Spacer(minLength: 0)
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .agentBarSecondaryText()
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .circular)
                    .fill(AgentBarStyle.fieldBackground(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .circular)
                    .stroke(AgentBarStyle.stroke(colorScheme), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .frame(width: 154, height: 28)
        .popover(isPresented: datePopoverBinding(for: field), arrowEdge: .bottom) {
            AgentBarCalendarPicker(
                title: title,
                date: date,
                language: language,
                onSelect: { editingDateField = nil }
            )
        }
    }

    private func datePopoverBinding(for field: CustomDateField) -> Binding<Bool> {
        Binding(
            get: { editingDateField == field },
            set: { isPresented in
                editingDateField = isPresented ? field : nil
            }
        )
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct AgentBarCalendarPicker: View {
    let title: String
    @Binding var date: Date
    let language: AppLanguage
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var visibleMonth: Date

    init(
        title: String,
        date: Binding<Date>,
        language: AppLanguage,
        onSelect: @escaping () -> Void
    ) {
        self.title = title
        self._date = date
        self.language = language
        self.onSelect = onSelect

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let month = calendar.dateInterval(of: .month, for: date.wrappedValue)?.start ?? date.wrappedValue
        self._visibleMonth = State(initialValue: month)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .agentBarSecondaryText()
                Spacer()
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(AgentBarIconButtonStyle())

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(AgentBarIconButtonStyle())
            }

            Text(monthTitle)
                .font(.callout.weight(.semibold))
                .agentBarPrimaryText()

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .agentBarSecondaryText()
                        .frame(width: 26, height: 18)
                }

                ForEach(calendarCells.indices, id: \.self) { index in
                    if let day = calendarCells[index] {
                        Button {
                            date = day
                            onSelect()
                        } label: {
                            Text(dayNumber(day))
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .frame(width: 26, height: 24)
                                .foregroundStyle(isSelected(day) ? Color.white : AgentBarStyle.primaryText(colorScheme))
                                .background(dayBackground(day))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(width: 26, height: 24)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 238)
        .agentBarPanelBackground()
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(26), spacing: 5), count: 7)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = language == .simplifiedChinese ? Locale(identifier: "zh_Hans") : Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = language == .simplifiedChinese ? "yyyy 年 M 月" : "MMM yyyy"
        return formatter.string(from: visibleMonth)
    }

    private var weekdayTitles: [String] {
        language == .simplifiedChinese
            ? ["日", "一", "二", "三", "四", "五", "六"]
            : ["S", "M", "T", "W", "T", "F", "S"]
    }

    private var calendarCells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingEmptyDays = max(0, firstWeekday - 1)
        let dayCount = calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 0
        var cells = Array<Date?>(repeating: nil, count: leadingEmptyDays)
        cells.append(contentsOf: (0..<dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        })

        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private func moveMonth(by offset: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonth) ?? visibleMonth
    }

    private func dayNumber(_ day: Date) -> String {
        String(calendar.component(.day, from: day))
    }

    private func isSelected(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: date)
    }

    private func dayBackground(_ day: Date) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .circular)
            .fill(isSelected(day) ? AgentBarStyle.green : AgentBarStyle.fieldBackground(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .circular)
                    .stroke(isToday(day) && !isSelected(day) ? AgentBarStyle.green.opacity(0.55) : Color.clear, lineWidth: 0.8)
            )
    }

    private func isToday(_ day: Date) -> Bool {
        calendar.isDateInToday(day)
    }
}

struct UsageWindowSummaryView: View {
    let window: UsageWindowSnapshot
    let language: AppLanguage

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        HStack(spacing: 8) {
            metricTile(title: copy.total, value: AgentBarFormatters.compactTokens(window.total.totalTokens), footnote: AgentBarFormatters.usd(window.costUSD))
            metricTile(title: copy.input, value: AgentBarFormatters.compactTokens(window.total.inputTokens), footnote: nil)
            metricTile(title: copy.output, value: AgentBarFormatters.compactTokens(outputTokens), footnote: nil)
            metricTile(title: copy.cached, value: AgentBarFormatters.compactTokens(cachedTokens), footnote: cacheRateText)
        }
    }

    private var outputTokens: Int64 {
        window.total.outputTokens + window.total.reasoningOutputTokens
    }

    private var cachedTokens: Int64 {
        window.total.cachedInputTokens + window.total.cacheCreationInputTokens
    }

    private var cacheRateText: String? {
        guard window.total.totalTokens > 0 else { return nil }
        return AgentBarFormatters.percent(Double(cachedTokens) / Double(window.total.totalTokens) * 100)
    }

    private func metricTile(title: String, value: String, footnote: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .agentBarSecondaryText()
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(footnote ?? " ")
                .font(.caption2.monospacedDigit())
                .agentBarSecondaryText()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentBarCard()
    }
}

struct ModelUsageDetailsView: View {
    let window: UsageWindowSnapshot
    @Binding var mode: UsageDetailsMode
    @Binding var topLimit: TopModelLimit
    let language: AppLanguage

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(mode == .models ? copy.topModels : copy.agentUsage)
                    .font(.caption.weight(.semibold))
                    .agentBarSecondaryText()
                Spacer()
                AgentBarSegmentedPicker(
                    options: UsageDetailsMode.allCases,
                    selection: $mode,
                    title: { $0.title(copy: copy) }
                )
                .frame(width: 126)
                AgentBarSegmentedPicker(
                    options: TopModelLimit.allCases,
                    selection: $topLimit,
                    title: { $0.title(copy: copy) }
                )
                .frame(width: 112)
            }

            if visibleRowsAreEmpty {
                Text(copy.noLocalUsageYet)
                    .font(.callout)
                    .agentBarSecondaryText()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                switch mode {
                case .models:
                    ForEach(models) { model in
                        ModelUsageDetailRow(model: model, maxTokens: modelMaxTokens, language: language)
                    }
                case .agents:
                    ForEach(agents) { agent in
                        AgentUsageDetailRow(agent: agent, maxTokens: agentMaxTokens, language: language)
                    }
                }
            }
        }
        .agentBarCard()
    }

    private var models: [ModelUsageBreakdown] {
        window.topModels(limit: topLimit.count)
    }

    private var agents: [AgentUsageBreakdown] {
        window.topAgents(limit: topLimit.count)
    }

    private var visibleRowsAreEmpty: Bool {
        switch mode {
        case .models:
            return models.isEmpty
        case .agents:
            return agents.isEmpty
        }
    }

    private var modelMaxTokens: Int64 {
        max(models.map(\.totalTokens).max() ?? 0, 1)
    }

    private var agentMaxTokens: Int64 {
        max(agents.map(\.totalTokens).max() ?? 0, 1)
    }
}

private struct ModelUsageDetailRow: View {
    let model: ModelUsageBreakdown
    let maxTokens: Int64
    let language: AppLanguage

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(model.model)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(AgentBarFormatters.compactTokens(model.totalTokens)) · \(AgentBarFormatters.usd(model.costUSD))")
                    .font(.caption.monospacedDigit())
                    .agentBarSecondaryText()
            }

            AgentBarProgressBar(value: Double(model.totalTokens) / Double(maxTokens), tint: AgentBarStyle.green)

            HStack(spacing: 10) {
                tokenPart(copy.input, model.inputTokens)
                tokenPart(copy.output, model.outputTokens + model.reasoningOutputTokens)
                tokenPart(copy.cached, model.cachedTokens)
                Spacer(minLength: 0)
            }
        }
    }

    private func tokenPart(_ title: String, _ value: Int64) -> some View {
        Text("\(title) \(AgentBarFormatters.compactTokens(value))")
            .font(.caption2.monospacedDigit())
            .agentBarSecondaryText()
            .lineLimit(1)
    }
}

private struct AgentUsageDetailRow: View {
    let agent: AgentUsageBreakdown
    let maxTokens: Int64
    let language: AppLanguage

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(displayName(for: agent.source))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(AgentBarFormatters.compactTokens(agent.totalTokens)) · \(AgentBarFormatters.usd(agent.costUSD))")
                    .font(.caption.monospacedDigit())
                    .agentBarSecondaryText()
            }

            AgentBarProgressBar(value: Double(agent.totalTokens) / Double(maxTokens), tint: AgentBarStyle.green)

            HStack(spacing: 10) {
                tokenPart(copy.input, agent.inputTokens)
                tokenPart(copy.output, agent.outputTokens + agent.reasoningOutputTokens)
                tokenPart(copy.cached, agent.cachedTokens)
                Spacer(minLength: 0)
            }
        }
    }

    private func tokenPart(_ title: String, _ value: Int64) -> some View {
        Text("\(title) \(AgentBarFormatters.compactTokens(value))")
            .font(.caption2.monospacedDigit())
            .agentBarSecondaryText()
            .lineLimit(1)
    }

    private func displayName(for source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return copy.agent
        }
        switch trimmed.lowercased() {
        case "codex":
            return "Codex Agent"
        case "claude-code":
            return "Claude Code Agent"
        default:
            return "\(titleCased(trimmed)) Agent"
        }
    }

    private func titleCased(_ value: String) -> String {
        value
            .split { $0 == "-" || $0 == "_" || $0 == " " }
            .map { part in
                let lowercased = part.lowercased()
                return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
            }
            .joined(separator: " ")
    }
}

struct UsageThirtyDayBarChartView: View {
    let days: [DailyUsage]
    let language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredDay: DailyUsage?

    private let inputColor = Color(red: 0.32, green: 0.60, blue: 0.95)
    private let outputColor = Color(red: 0.95, green: 0.47, blue: 0.64)
    private let cachedColor = AgentBarStyle.green
    private let hoverCardWidth: CGFloat = 180

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .circular)
                .fill(AgentBarStyle.cardBackground(colorScheme))
            RoundedRectangle(cornerRadius: 8, style: .circular)
                .stroke(AgentBarStyle.stroke(colorScheme), lineWidth: 0.8)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(copy.trend30Days)
                        .font(.caption.weight(.semibold))
                        .agentBarSecondaryText()
                    Spacer()
                    Text("\(AgentBarFormatters.compactTokens(totalTokens)) · \(AgentBarFormatters.usd(totalCost))")
                        .font(.caption.monospacedDigit())
                        .agentBarSecondaryText()
                }

                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(days) { day in
                                stackedBar(day: day, maxTokens: maxTokens, isHovered: hoveredDay?.day == day.day)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                    .onHover { isHovering in
                                        if isHovering {
                                            hoveredDay = day
                                        } else if hoveredDay?.day == day.day {
                                            hoveredDay = nil
                                        }
                                    }
                                    .help("\(displayDay(day.day)) · \(AgentBarFormatters.compactTokens(day.totalTokens)) · \(AgentBarFormatters.usd(day.costUSD))")
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)

                        if let hoveredDay {
                            UsageDayHoverCard(
                                day: hoveredDay,
                                language: language,
                                inputColor: inputColor,
                                outputColor: outputColor,
                                cachedColor: cachedColor
                            )
                            .zIndex(10)
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                            .offset(x: hoverCardX(for: hoveredDay, chartWidth: proxy.size.width), y: 2)
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: hoveredDay?.day)
                }
                .frame(height: 56)
            }
            .padding(8)
        }
    }

    private var totalTokens: Int64 {
        days.reduce(Int64(0)) { $0 + $1.totalTokens }
    }

    private var totalCost: Double? {
        let values = days.compactMap(\.costUSD)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    private var maxTokens: Int64 {
        max(days.map(\.totalTokens).max() ?? 0, 1)
    }

    private func stackedBar(day: DailyUsage, maxTokens: Int64, isHovered: Bool) -> some View {
        let heightRatio = max(0.02, Double(day.totalTokens) / Double(maxTokens))
        return GeometryReader { proxy in
            let barHeight = max(2, proxy.size.height * heightRatio)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    segment(tokens: day.outputTokens + day.reasoningOutputTokens, total: day.totalTokens, barHeight: barHeight, color: outputColor)
                    segment(tokens: day.inputTokens, total: day.totalTokens, barHeight: barHeight, color: inputColor)
                    segment(tokens: day.cachedInputTokens + day.cacheCreationInputTokens, total: day.totalTokens, barHeight: barHeight, color: cachedColor)
                }
                .frame(height: barHeight)
                .frame(maxWidth: .infinity)
                .background(AgentBarStyle.track(colorScheme).opacity(day.totalTokens > 0 ? 0.18 : 0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .circular)
                        .stroke(isHovered ? AgentBarStyle.primaryText(colorScheme).opacity(0.78) : Color.clear, lineWidth: 1.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .circular))
                .scaleEffect(x: isHovered ? 1.25 : 1, y: isHovered ? 1.04 : 1, anchor: .bottom)
                .shadow(color: isHovered ? AgentBarStyle.primaryText(colorScheme).opacity(0.18) : .clear, radius: 5, y: 1)
            }
        }
    }

    private func segment(tokens: Int64, total: Int64, barHeight: CGFloat, color: Color) -> some View {
        let ratio = total > 0 ? Double(tokens) / Double(total) : 0
        return Rectangle()
            .fill(color)
            .frame(height: max(0, barHeight * ratio))
    }

    private func hoverCardX(for day: DailyUsage, chartWidth: CGFloat) -> CGFloat {
        guard chartWidth > hoverCardWidth else { return 0 }
        let dayCount = max(days.count, 1)
        let index = days.firstIndex { $0.day == day.day } ?? dayCount - 1
        let columnWidth = chartWidth / CGFloat(dayCount)
        let selectedCenterX = (CGFloat(index) + 0.5) * columnWidth
        if selectedCenterX < chartWidth / 2 {
            let x = selectedCenterX + columnWidth * 1.5
            return min(max(2, x), chartWidth - hoverCardWidth - 2)
        }
        return 2
    }

    private func displayDay(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let dayOfMonth = Int(parts[2]) else {
            return day
        }
        if language == .simplifiedChinese {
            return "\(month)月\(dayOfMonth)日"
        }
        return "\(month)/\(dayOfMonth)"
    }
}

struct UsageDayHoverCard: View {
    let day: DailyUsage
    let language: AppLanguage
    let inputColor: Color
    let outputColor: Color
    let cachedColor: Color
    @Environment(\.colorScheme) private var colorScheme

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayDay(day.day))
                    .font(.caption.weight(.semibold))
                    .agentBarPrimaryText()
                Spacer(minLength: 10)
                Text(AgentBarFormatters.usd(day.costUSD))
                    .font(.caption2.monospacedDigit())
                    .agentBarSecondaryText()
            }

            miniStack
                .frame(height: 7)

            VStack(alignment: .leading, spacing: 4) {
                metricRow(title: copy.total, value: day.totalTokens, color: AgentBarStyle.primaryText(colorScheme))
                metricRow(title: copy.input, value: day.inputTokens, color: inputColor)
                metricRow(title: copy.output, value: day.outputTokens + day.reasoningOutputTokens, color: outputColor)
                metricRow(title: copy.cached, value: day.cachedInputTokens + day.cacheCreationInputTokens, color: cachedColor)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .circular)
                .fill(AgentBarStyle.cardBackground(colorScheme))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.36 : 0.14), radius: 12, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .circular)
                .stroke(AgentBarStyle.stroke(colorScheme), lineWidth: 0.8)
        )
    }

    private var miniStack: some View {
        GeometryReader { proxy in
            let total = max(day.totalTokens, 1)
            let cachedWidth = proxy.size.width * CGFloat(Double(day.cachedInputTokens + day.cacheCreationInputTokens) / Double(total))
            let inputWidth = proxy.size.width * CGFloat(Double(day.inputTokens) / Double(total))
            let outputWidth = proxy.size.width * CGFloat(Double(day.outputTokens + day.reasoningOutputTokens) / Double(total))
            HStack(spacing: 0) {
                cachedColor.frame(width: cachedWidth)
                inputColor.frame(width: inputWidth)
                outputColor.frame(width: outputWidth)
                AgentBarStyle.track(colorScheme)
                    .frame(width: max(0, proxy.size.width - cachedWidth - inputWidth - outputWidth))
            }
            .clipShape(Capsule())
        }
    }

    private func metricRow(title: String, value: Int64, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption2.weight(.semibold))
                .agentBarSecondaryText()
            Spacer(minLength: 8)
            Text(AgentBarFormatters.compactTokens(value))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .agentBarPrimaryText()
                .frame(minWidth: 46, alignment: .trailing)
        }
    }

    private func displayDay(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let dayOfMonth = Int(parts[2]) else {
            return day
        }
        if language == .simplifiedChinese {
            return "\(month)月\(dayOfMonth)日"
        }
        return "\(month)/\(dayOfMonth)"
    }
}

struct UsageTotalsView: View {
    let summary: UsageSummary
    let language: AppLanguage

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        HStack(spacing: 8) {
            UsageTotalTile(
                title: copy.today,
                tokens: summary.today.totalTokens,
                cost: summary.today.costUSD,
                trend: trend(days: Array(summary.heatmapDays.suffix(7)))
            )
            UsageTotalTile(
                title: copy.sevenDaysShort,
                tokens: summary.sevenDayTokens,
                cost: summary.sevenDayCostUSD,
                trend: trend(days: Array(summary.heatmapDays.suffix(14)))
            )
            UsageTotalTile(
                title: copy.all,
                tokens: summary.allTimeTokens,
                cost: summary.allTimeCostUSD,
                trend: trend(days: sampledAllTimeDays)
            )
        }
    }

    private var sampledAllTimeDays: [HeatmapDay] {
        let days = summary.heatmapDays
        guard days.count > 18 else { return days }
        return (0..<18).map { index in
            let sourceIndex = Int((Double(index) / 17.0) * Double(days.count - 1))
            return days[sourceIndex]
        }
    }

    private func trend(days: [HeatmapDay]) -> UsageTileTrend {
        UsageTileTrend(
            tokens: days.map { Double($0.tokens) },
            costs: days.map(\.costUSD)
        )
    }
}

struct UsageTotalTile: View {
    let title: String
    let tokens: Int64
    let cost: Double?
    let trend: UsageTileTrend
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .leading) {
            UsageTileSparkline(trend: trend)
                .padding(.top, 26)
                .padding(.horizontal, 4)
                .opacity(colorScheme == .dark ? 0.44 : 0.34)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .agentBarSecondaryText()
                Text(AgentBarFormatters.compactTokens(tokens))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(AgentBarFormatters.usd(cost))
                    .font(.caption.monospacedDigit())
                    .agentBarSecondaryText()
            }
            .shadow(color: AgentBarStyle.cardBackground(colorScheme).opacity(0.76), radius: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 72, alignment: .leading)
        .agentBarCard()
    }
}

struct UsageTileTrend {
    let tokens: [Double]
    let costs: [Double]
}

private struct UsageTileSparkline: View {
    let trend: UsageTileTrend

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                sparkline(values: trend.costs, in: proxy.size, verticalOffset: 12)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.96, green: 0.48, blue: 0.68),
                                Color(red: 0.98, green: 0.64, blue: 0.22)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round)
                    )
                sparkline(values: trend.tokens, in: proxy.size, verticalOffset: 0)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.30, green: 0.66, blue: 0.88),
                                AgentBarStyle.green
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func sparkline(values: [Double], in size: CGSize, verticalOffset: CGFloat) -> Path {
        let normalized = normalizedValues(values)
        guard normalized.count > 1, size.width > 0, size.height > 0 else { return Path() }

        let chartHeight = max(8, size.height - 10)
        let step = size.width / CGFloat(normalized.count - 1)
        var path = Path()

        for index in normalized.indices {
            let x = CGFloat(index) * step
            let y = 6 + (1 - CGFloat(normalized[index])) * chartHeight * 0.72 + verticalOffset
            let point = CGPoint(x: x, y: min(size.height - 2, max(2, y)))
            if index == normalized.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func normalizedValues(_ values: [Double]) -> [Double] {
        guard values.count > 1 else { return [] }
        let maxValue = values.max() ?? 0
        let minValue = values.min() ?? 0
        guard maxValue > 0, maxValue > minValue else {
            return values.map { _ in maxValue > 0 ? 0.5 : 0 }
        }
        return values.map { ($0 - minValue) / (maxValue - minValue) }
    }
}

struct TopModelView: View {
    let modelUsage: ModelUsage?
    let language: AppLanguage

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkline")
                .foregroundStyle(AgentBarStyle.green)
            VStack(alignment: .leading, spacing: 3) {
                Text(copy.topModel)
                    .font(.caption.weight(.semibold))
                    .agentBarSecondaryText()
                Text(modelUsage?.model ?? copy.noLocalUsageYet)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(AgentBarFormatters.compactTokens(modelUsage?.tokens ?? 0))
                    .font(.callout.monospacedDigit().weight(.semibold))
                Text(AgentBarFormatters.usd(modelUsage?.costUSD))
                    .font(.caption.monospacedDigit())
                    .agentBarSecondaryText()
            }
        }
        .agentBarCard()
    }
}

struct UsageHeatmapView: View {
    let days: [HeatmapDay]
    let language: AppLanguage
    let animationID: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredDay: HeatmapDay?
    @State private var revealsGrid = false
    @State private var revealGeneration = 0

    private let cellSize: CGFloat = 10
    private let cellSpacing: CGFloat = 1
    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(copy.days365)
                    .font(.caption.weight(.semibold))
                    .agentBarSecondaryText()
                Spacer()
                legend
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: cellSpacing) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                            VStack(spacing: cellSpacing) {
                                ForEach(0..<7, id: \.self) { index in
                                    if index < week.count, let day = week[index] {
                                        HeatmapCellView(
                                            color: color(for: day.level),
                                            level: day.level,
                                            isRevealed: revealsGrid,
                                            delay: revealDelay(weekIndex: weekIndex, dayIndex: index),
                                            reduceMotion: reduceMotion
                                        )
                                        .frame(width: cellSize, height: cellSize)
                                            .help(tooltip(for: day))
                                            .onHover { isHovering in
                                                hoveredDay = isHovering ? day : nil
                                            }
                                    } else {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.clear)
                                            .frame(width: cellSize, height: cellSize)
                                    }
                                }
                            }
                            .id(weekIndex)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.leading, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    scrollToLatest(proxy)
                    playRevealAnimation()
                }
                .onChange(of: weeks.count) { _, _ in
                    scrollToLatest(proxy)
                    playRevealAnimation()
                }
                .onChange(of: animationID) { _, _ in
                    scrollToLatest(proxy)
                    playRevealAnimation()
                }
            }

            Text(hoveredDay.map(tooltip(for:)) ?? " ")
                .font(.caption2.monospacedDigit())
                .agentBarSecondaryText()
                .lineLimit(1)
        }
        .agentBarCard()
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text(copy.less)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: level))
                    .frame(width: 10, height: 10)
            }
            Text(copy.more)
        }
        .font(.caption2)
        .agentBarSecondaryText()
    }

    private var weeks: [[HeatmapDay?]] {
        guard let first = days.first,
              let firstDate = UsageAggregator.date(fromDayString: first.day, timeZone: .current) else {
            return []
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let leadingEmptyDays = max(0, calendar.component(.weekday, from: firstDate) - 1)
        var cells = Array<HeatmapDay?>(repeating: nil, count: leadingEmptyDays)
        cells.append(contentsOf: days.map(Optional.some))

        var columns: [[HeatmapDay?]] = []
        var index = 0
        while index < cells.count {
            let end = min(index + 7, cells.count)
            var week = Array(cells[index..<end])
            if week.count < 7 {
                week.append(contentsOf: Array<HeatmapDay?>(repeating: nil, count: 7 - week.count))
            }
            columns.append(week)
            index += 7
        }
        return columns
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        let lastWeekIndex = weeks.count - 1
        guard lastWeekIndex >= 0 else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(lastWeekIndex, anchor: .trailing)
        }
    }

    private func playRevealAnimation() {
        guard !reduceMotion else {
            revealsGrid = true
            return
        }

        revealGeneration += 1
        let generation = revealGeneration
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            revealsGrid = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            guard generation == revealGeneration else { return }
            revealsGrid = true
        }
    }

    private func revealDelay(weekIndex: Int, dayIndex: Int) -> Double {
        let latestWeekIndex = max(weeks.count - 1, 0)
        let distanceFromLatest = max(0, latestWeekIndex - weekIndex)
        return min(0.72, Double(distanceFromLatest) * 0.012 + Double(dayIndex) * 0.018)
    }

    private func tooltip(for day: HeatmapDay) -> String {
        copy.tooltipTokens(
            day: day.day,
            tokens: day.tokens,
            cost: day.costUSD,
            model: displayModel(day.topModel)
        )
    }

    private func color(for level: Int) -> Color {
        if colorScheme == .dark {
            switch level {
            case 1: return Color(red: 0.05, green: 0.31, blue: 0.16)
            case 2: return Color(red: 0.05, green: 0.48, blue: 0.24)
            case 3: return Color(red: 0.12, green: 0.64, blue: 0.31)
            case 4: return Color(red: 0.31, green: 0.81, blue: 0.44)
            default: return Color(nsColor: .tertiaryLabelColor).opacity(0.34)
            }
        }

        switch level {
        case 1: return Color(red: 0.61, green: 0.91, blue: 0.66)
        case 2: return Color(red: 0.25, green: 0.77, blue: 0.39)
        case 3: return Color(red: 0.19, green: 0.63, blue: 0.31)
        case 4: return Color(red: 0.13, green: 0.43, blue: 0.22)
        default: return Color(red: 0.78, green: 0.82, blue: 0.84)
        }
    }

    private func displayModel(_ model: String?) -> String? {
        let trimmed = (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "unknown" else {
            return nil
        }
        return trimmed
    }
}

private struct HeatmapCellView: View {
    let color: Color
    let level: Int
    let isRevealed: Bool
    let delay: Double
    let reduceMotion: Bool

    var body: some View {
        let visible = isRevealed || reduceMotion
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(level > 0 ? 0.14 : 0), lineWidth: 0.5)
            )
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.42)
            .brightness(visible || level == 0 ? 0 : 0.16)
            .animation(
                reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78).delay(delay),
                value: isRevealed
            )
    }
}
