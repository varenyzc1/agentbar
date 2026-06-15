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

    private static let panelWidth: CGFloat = 500
    private var copy: AgentBarCopy {
        AgentBarCopy(language: model.settings.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            UsageTotalsView(summary: model.usageSummary, language: model.settings.language)
            TopModelView(modelUsage: model.usageSummary.topModel7Days, language: model.settings.language)
            CodexQuotaCardView(
                state: model.quotaState,
                quotaItems: model.settings.sanitized.codexMenuBarQuotaItems,
                refreshFailureMessage: model.codexQuotaRefreshFailure,
                now: Date(),
                language: model.settings.language
            )
            UsageHeatmapView(days: model.usageSummary.heatmapDays, language: model.settings.language)
            SourceBreakdownView(sources: model.usageSummary.sourceBreakdown7Days, language: model.settings.language)
            footer
        }
        .frame(width: Self.panelWidth, alignment: .leading)
        .padding(16)
        .agentBarPanelBackground()
        .onAppear {
            model.popoverOpened()
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
        return AgentBarFormatters.relativeReset(from: now, to: window.resetsAt)
    }

    private var resetTimeText: String {
        guard let window, !window.stale else { return "" }
        if Calendar.current.isDate(window.resetsAt, inSameDayAs: now) {
            return window.resetsAt.formatted(date: .omitted, time: .shortened)
        }
        return window.resetsAt.formatted(date: .abbreviated, time: .shortened)
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
                cost: summary.today.costUSD
            )
            UsageTotalTile(
                title: copy.sevenDaysShort,
                tokens: summary.sevenDayTokens,
                cost: summary.sevenDayCostUSD
            )
            UsageTotalTile(
                title: copy.all,
                tokens: summary.allTimeTokens,
                cost: summary.allTimeCostUSD
            )
        }
    }
}

struct UsageTotalTile: View {
    let title: String
    let tokens: Int64
    let cost: Double?

    var body: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentBarCard()
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredDay: HeatmapDay?

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
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(color(for: day.level))
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
                }
                .onChange(of: weeks.count) { _, _ in
                    scrollToLatest(proxy)
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

struct SourceBreakdownView: View {
    let sources: [SourceUsage]
    let language: AppLanguage

    private var copy: AgentBarCopy {
        AgentBarCopy(language: language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.sources)
                .font(.caption.weight(.semibold))
                .agentBarSecondaryText()

            if sources.isEmpty {
                Text(copy.noLocalUsageYet)
                    .font(.callout)
                    .agentBarSecondaryText()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(source.source)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(AgentBarFormatters.compactTokens(source.tokens)) · \(AgentBarFormatters.usd(source.costUSD))")
                                .font(.caption.monospacedDigit())
                                .agentBarSecondaryText()
                        }
                        AgentBarProgressBar(value: progress(for: source), tint: AgentBarStyle.green)
                    }
                }
            }
        }
        .agentBarCard()
    }

    private var maxTokens: Int64 {
        max(sources.map(\.tokens).max() ?? 0, 1)
    }

    private func progress(for source: SourceUsage) -> Double {
        Double(source.tokens) / Double(maxTokens)
    }
}
