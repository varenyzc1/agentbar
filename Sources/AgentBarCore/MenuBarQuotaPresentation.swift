import Foundation

public enum MenuBarQuotaPresentation {
    public static func title(groups: [[String]]) -> String {
        groups.map { $0.filter { !$0.isEmpty }.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    public static func codexTitles(
        items: [CodexMenuBarQuotaItem], snapshot: CodexQuotaSnapshot, showsWindowLabel: Bool
    ) -> [String] {
        titles(items: items, displayStyle: \.displayStyle) {
            $0.menuBarTitle(snapshot: snapshot, showsWindowLabel: showsWindowLabel)
        }
    }

    public static func claudeTitles(
        items: [ClaudeMenuBarQuotaItem], snapshot: ClaudeQuotaSnapshot, now: Date
    ) -> [String] {
        titles(items: items, displayStyle: \.displayStyle) {
            $0.menuBarTitle(snapshot: snapshot, now: now)
        }
    }

    private static func titles<Item>(
        items: [Item], displayStyle: WritableKeyPath<Item, MenuBarQuotaDisplayStyle>,
        title: (Item) -> String?
    ) -> [String] {
        var providerShown = false
        return items.compactMap { item in
            var displayedItem = item
            if providerShown { displayedItem[keyPath: displayStyle] = .compact }
            guard let result = title(displayedItem) else { return nil }
            // A hidden, missing or expired window must not consume the provider label.
            if displayedItem[keyPath: displayStyle] == .detailed { providerShown = true }
            return result
        }
    }
}

public extension MenuBarQuotaDisplayStyle {
    func title(provider: String, windowLabel: String? = nil, percent: Double) -> String {
        var parts = self == .detailed ? [provider] : []
        if let windowLabel { parts.append(windowLabel) }
        parts.append(AgentBarFormatters.percent(percent))
        return parts.joined(separator: " ")
    }
}

public extension CodexMenuBarQuotaItem {
    func menuBarTitle(snapshot: CodexQuotaSnapshot, showsWindowLabel: Bool) -> String? {
        guard isEnabled, Self.supportedKeys.contains(key), let window = snapshot.window(for: key) else { return nil }
        return displayStyle.title(
            provider: "Codex", windowLabel: showsWindowLabel ? key.label : nil,
            percent: basis == .used ? window.usedPercent : window.remainingPercent
        )
    }
}

public extension ClaudeMenuBarQuotaItem {
    func menuBarTitle(snapshot: ClaudeQuotaSnapshot, now: Date) -> String? {
        guard isEnabled, Self.supportedKeys.contains(key),
              let window = snapshot.windows.first(where: { $0.key == key }),
              !window.isExpired(at: now) else { return nil }
        return displayStyle.title(
            provider: "Claude", windowLabel: key.label,
            percent: basis == .used ? window.usedPercent : window.remainingPercent
        )
    }
}
