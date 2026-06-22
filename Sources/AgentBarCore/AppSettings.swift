import Foundation

public enum MenuBarMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case usedTokens
    case usedCost
    case remainingPercent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .usedTokens:
            return "Used tokens"
        case .usedCost:
            return "Used cost"
        case .remainingPercent:
            return "Remaining"
        }
    }
}

public enum CodexMenuBarMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case plan
    case alerts
    case iconOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plan:
            return "Plan"
        case .alerts:
            return "Alerts"
        case .iconOnly:
            return "Usage"
        }
    }
}

public enum CodexQuotaPercentBasis: String, Codable, CaseIterable, Identifiable, Sendable {
    case used
    case remaining

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .used:
            return "Used"
        case .remaining:
            return "Remaining"
        }
    }
}

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "中文"
        }
    }
}

public enum PanelModule: String, Codable, CaseIterable, Identifiable, Sendable {
    case summary
    case details
    case trend
    case codexQuota
    case heatmap

    public var id: String { rawValue }

    public static let defaults: [PanelModule] = allCases

    public static func normalized(_ modules: [PanelModule]) -> [PanelModule] {
        let selected = Set(modules)
        return allCases.filter { selected.contains($0) }
    }
}

public struct CodexMenuBarQuotaItem: Codable, Equatable, Identifiable, Sendable {
    public var id: CodexQuotaKey { key }

    public var key: CodexQuotaKey
    public var basis: CodexQuotaPercentBasis
    public var isEnabled: Bool

    public init(
        key: CodexQuotaKey,
        basis: CodexQuotaPercentBasis = .used,
        isEnabled: Bool = true
    ) {
        self.key = key
        self.basis = basis
        self.isEnabled = isEnabled
    }

    public static let supportedKeys: [CodexQuotaKey] = [.fiveHour, .sevenDay]

    public static let defaults: [CodexMenuBarQuotaItem] = [
        CodexMenuBarQuotaItem(key: .fiveHour),
        CodexMenuBarQuotaItem(key: .sevenDay)
    ]

    public static func normalized(_ items: [CodexMenuBarQuotaItem]) -> [CodexMenuBarQuotaItem] {
        let byKey = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0) })
        return supportedKeys.map { key in
            guard var item = byKey[key] else {
                return CodexMenuBarQuotaItem(key: key)
            }
            item.key = key
            return item
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var menuBarMetric: MenuBarMetric
    public var codexMenuBarMode: CodexMenuBarMode
    public var codexMenuBarQuotaItems: [CodexMenuBarQuotaItem]
    public var codexMenuBarShowsQuotaLabels: Bool
    public var visiblePanelModules: [PanelModule]
    public var refreshIntervalMinutes: Int
    public var codexRefreshIntervalSeconds: Int
    public var monthlyTokenBudget: Int?
    public var monthlyCostBudgetUSD: Double?
    public var timeZoneIdentifier: String
    public var projectIDs: [String]
    public var apiKeyIDs: [String]
    public var modelIDs: [String]
    public var userIDs: [String]
    public var estimatedInputCostPerMillion: Double
    public var estimatedOutputCostPerMillion: Double
    public var launchAtLogin: Bool
    public var language: AppLanguage

    public init(
        menuBarMetric: MenuBarMetric = .usedTokens,
        codexMenuBarMode: CodexMenuBarMode = .plan,
        codexMenuBarQuotaItems: [CodexMenuBarQuotaItem] = CodexMenuBarQuotaItem.defaults,
        codexMenuBarShowsQuotaLabels: Bool = true,
        visiblePanelModules: [PanelModule] = PanelModule.defaults,
        refreshIntervalMinutes: Int = 30,
        codexRefreshIntervalSeconds: Int = 300,
        monthlyTokenBudget: Int? = nil,
        monthlyCostBudgetUSD: Double? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        projectIDs: [String] = [],
        apiKeyIDs: [String] = [],
        modelIDs: [String] = [],
        userIDs: [String] = [],
        estimatedInputCostPerMillion: Double = 0,
        estimatedOutputCostPerMillion: Double = 0,
        launchAtLogin: Bool = false,
        language: AppLanguage = .english
    ) {
        self.menuBarMetric = menuBarMetric
        self.codexMenuBarMode = codexMenuBarMode
        self.codexMenuBarQuotaItems = CodexMenuBarQuotaItem.normalized(codexMenuBarQuotaItems)
        self.codexMenuBarShowsQuotaLabels = codexMenuBarShowsQuotaLabels
        self.visiblePanelModules = PanelModule.normalized(visiblePanelModules)
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.codexRefreshIntervalSeconds = codexRefreshIntervalSeconds
        self.monthlyTokenBudget = monthlyTokenBudget
        self.monthlyCostBudgetUSD = monthlyCostBudgetUSD
        self.timeZoneIdentifier = timeZoneIdentifier
        self.projectIDs = projectIDs
        self.apiKeyIDs = apiKeyIDs
        self.modelIDs = modelIDs
        self.userIDs = userIDs
        self.estimatedInputCostPerMillion = estimatedInputCostPerMillion
        self.estimatedOutputCostPerMillion = estimatedOutputCostPerMillion
        self.launchAtLogin = launchAtLogin
        self.language = language
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    public var sanitized: AppSettings {
        var copy = self
        copy.refreshIntervalMinutes = max(5, min(copy.refreshIntervalMinutes, 24 * 60))
        copy.codexRefreshIntervalSeconds = max(30, min(copy.codexRefreshIntervalSeconds, 24 * 60 * 60))
        copy.codexMenuBarQuotaItems = CodexMenuBarQuotaItem.normalized(copy.codexMenuBarQuotaItems)
        copy.visiblePanelModules = PanelModule.normalized(copy.visiblePanelModules)
        copy.projectIDs = copy.projectIDs.cleanedIdentifiers()
        copy.apiKeyIDs = copy.apiKeyIDs.cleanedIdentifiers()
        copy.modelIDs = copy.modelIDs.cleanedIdentifiers()
        copy.userIDs = copy.userIDs.cleanedIdentifiers()
        copy.estimatedInputCostPerMillion = max(0, copy.estimatedInputCostPerMillion)
        copy.estimatedOutputCostPerMillion = max(0, copy.estimatedOutputCostPerMillion)
        if let tokenBudget = copy.monthlyTokenBudget {
            copy.monthlyTokenBudget = max(0, tokenBudget)
        }
        if let costBudget = copy.monthlyCostBudgetUSD {
            copy.monthlyCostBudgetUSD = max(0, costBudget)
        }
        return copy
    }

    enum CodingKeys: String, CodingKey {
        case menuBarMetric
        case codexMenuBarMode
        case codexMenuBarQuotaItems
        case codexMenuBarShowsQuotaLabels
        case visiblePanelModules
        case refreshIntervalMinutes
        case codexRefreshIntervalSeconds
        case monthlyTokenBudget
        case monthlyCostBudgetUSD
        case timeZoneIdentifier
        case projectIDs
        case apiKeyIDs
        case modelIDs
        case userIDs
        case estimatedInputCostPerMillion
        case estimatedOutputCostPerMillion
        case launchAtLogin
        case language
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            menuBarMetric: try container.decodeIfPresent(MenuBarMetric.self, forKey: .menuBarMetric) ?? .usedTokens,
            codexMenuBarMode: try container.decodeIfPresent(CodexMenuBarMode.self, forKey: .codexMenuBarMode) ?? .plan,
            codexMenuBarQuotaItems: try container.decodeIfPresent([CodexMenuBarQuotaItem].self, forKey: .codexMenuBarQuotaItems) ?? CodexMenuBarQuotaItem.defaults,
            codexMenuBarShowsQuotaLabels: try container.decodeIfPresent(Bool.self, forKey: .codexMenuBarShowsQuotaLabels) ?? true,
            visiblePanelModules: try container.decodeIfPresent([PanelModule].self, forKey: .visiblePanelModules) ?? PanelModule.defaults,
            refreshIntervalMinutes: try container.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? 30,
            codexRefreshIntervalSeconds: try container.decodeIfPresent(Int.self, forKey: .codexRefreshIntervalSeconds) ?? 300,
            monthlyTokenBudget: try container.decodeIfPresent(Int.self, forKey: .monthlyTokenBudget),
            monthlyCostBudgetUSD: try container.decodeIfPresent(Double.self, forKey: .monthlyCostBudgetUSD),
            timeZoneIdentifier: try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) ?? TimeZone.current.identifier,
            projectIDs: try container.decodeIfPresent([String].self, forKey: .projectIDs) ?? [],
            apiKeyIDs: try container.decodeIfPresent([String].self, forKey: .apiKeyIDs) ?? [],
            modelIDs: try container.decodeIfPresent([String].self, forKey: .modelIDs) ?? [],
            userIDs: try container.decodeIfPresent([String].self, forKey: .userIDs) ?? [],
            estimatedInputCostPerMillion: try container.decodeIfPresent(Double.self, forKey: .estimatedInputCostPerMillion) ?? 0,
            estimatedOutputCostPerMillion: try container.decodeIfPresent(Double.self, forKey: .estimatedOutputCostPerMillion) ?? 0,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
            language: try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .english
        )
    }
}

private extension Array where Element == String {
    func cleanedIdentifiers() -> [String] {
        map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public struct AppSettingsStore {
    public let fileURL: URL
    private let legacyKey: String
    private let userDefaults: UserDefaults

    public init(
        fileURL: URL? = nil,
        legacyKey: String = "com.agentbar.settings.v1",
        userDefaults: UserDefaults = .standard
    ) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = support
                .appendingPathComponent("AgentBar", isDirectory: true)
                .appendingPathComponent("settings.json")
        }
        self.legacyKey = legacyKey
        self.userDefaults = userDefaults
    }

    public func load() -> AppSettings {
        if let data = try? Data(contentsOf: fileURL),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data).sanitized {
            return settings
        }

        if let data = userDefaults.data(forKey: legacyKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data).sanitized {
            try? save(settings)
            return settings
        }

        return AppSettings()
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings.sanitized)
        try data.write(to: fileURL, options: .atomic)
    }
}
