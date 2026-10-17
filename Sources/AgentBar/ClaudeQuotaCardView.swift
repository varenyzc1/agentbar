import AgentBarCore
import SwiftUI

struct ClaudeQuotaCardView: View {
    let state: ClaudeQuotaCardState
    let basis: CodexQuotaPercentBasis
    var quotaItems: [ClaudeMenuBarQuotaItem] = []
    let refreshFailureMessage: String?
    let isRefreshing: Bool
    let language: AppLanguage
    let onRefresh: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var copy: AgentBarCopy { AgentBarCopy(language: language) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(title).font(.headline)
                    Spacer()
                    Button(action: onRefresh) {
                        Image(systemName: "network")
                    }
                    .buttonStyle(AgentBarIconButtonStyle())
                    .help(copy.refreshClaudeQuota)
                    .accessibilityLabel(copy.refreshClaudeQuota)
                    .disabled(isRefreshing)
                }
                switch state {
                case .loading:
                    Text(copy.refreshingQuota).font(.callout).agentBarSecondaryText()
                case .waitingForLocal:
                    Text(copy.waitingForClaudeLocal).font(.callout).agentBarSecondaryText()
                case let .error(message):
                    Text(copy.claudeMessage(message))
                        .font(.callout)
                        .agentBarSecondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                case let .ready(snapshot, isStale):
                    ForEach(snapshot.windows) { window in
                        windowRow(window, now: context.date)
                    }
                    let expired = snapshot.windows.contains { $0.isExpired(at: context.date) }
                    Text((snapshot.source == .statusline ? text("Local · ", "本地 · ") : text("Online · ", "网络 · "))
                        + (isStale || expired ? text("Cached", "缓存于") : text("Updated", "采集于"))
                        + " " + snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .agentBarSecondaryText()
                    if let refreshFailureMessage {
                        Text(copy.claudeMessage(refreshFailureMessage))
                            .font(.caption)
                            .foregroundStyle(AgentBarStyle.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .agentBarCard(padding: 12)
        }
    }

    private var title: String {
        if case let .ready(snapshot, _) = state { return snapshot.displayPlan }
        return "Claude"
    }

    private var statusColor: Color {
        switch state {
        case .loading, .waitingForLocal: return AgentBarStyle.secondaryText(colorScheme)
        case .error: return AgentBarStyle.yellow
        case let .ready(snapshot, isStale):
            if isStale { return AgentBarStyle.secondaryText(colorScheme) }
            return color(.severity(for: snapshot.windows.map(\.usedPercent).max() ?? 0))
        }
    }

    private func windowRow(_ window: ClaudeQuotaWindow, now: Date) -> some View {
        let basis = quotaItems.first(where: { $0.key == window.key })?.basis ?? basis
        let expired = window.isExpired(at: now)
        let percent = basis == .used ? window.usedPercent : window.remainingPercent
        let tint = expired ? AgentBarStyle.secondaryText(colorScheme) : color(window.severity)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.key.label).font(.caption.weight(.semibold))
                Spacer()
                Text(expired ? "--" : "\(AgentBarFormatters.percent(percent)) \(copy.quotaBasisTitle(basis))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(tint)
            }
            AgentBarProgressBar(value: expired ? 0 : percent / 100, tint: tint)
                .accessibilityLabel(window.key.label)
                .accessibilityValue(expired ? copy.stale : "\(AgentBarFormatters.percent(percent)) \(copy.quotaBasisTitle(basis))")
            HStack {
                Text(expired ? text("Waiting for refresh", "等待刷新") : text("Resets", "重置"))
                Spacer()
                if let date = window.resetsAt, !expired {
                    Text(AgentBarFormatters.relativeReset(from: now, to: date, language: language)).monospacedDigit()
                } else if !expired {
                    Text("--")
                }
            }
            .font(.caption2)
            .agentBarSecondaryText()
        }
    }

    private func color(_ severity: CodexQuotaSeverity) -> Color {
        switch severity {
        case .ok: return AgentBarStyle.green
        case .warning: return AgentBarStyle.yellow
        case .critical: return AgentBarStyle.red
        }
    }

    private func text(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}
