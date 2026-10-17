import Foundation

public enum ClaudeQuotaKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
    case sevenDaySonnet = "seven_day_sonnet"
    case sevenDayOpus = "seven_day_opus"

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .fiveHour: return "5h"
        case .sevenDay: return "7d"
        case .sevenDaySonnet: return "Sonnet · 7d"
        case .sevenDayOpus: return "Opus · 7d"
        }
    }
}

public struct ClaudeQuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: ClaudeQuotaKey { key }
    public let key: ClaudeQuotaKey
    public let usedPercent: Double
    public let resetsAt: Date?
    public var remainingPercent: Double { 100 - usedPercent }
    public var severity: CodexQuotaSeverity { .severity(for: usedPercent) }

    public init(key: ClaudeQuotaKey, usedPercent: Double, resetsAt: Date?) {
        self.key = key
        self.usedPercent = max(0, min(100, usedPercent))
        self.resetsAt = resetsAt
    }

    public func isExpired(at date: Date) -> Bool {
        resetsAt.map { date >= $0 } ?? false
    }
}

public enum ClaudeQuotaSource: String, Codable, Sendable {
    case oauth
    case statusline
}

public struct ClaudeQuotaSnapshot: Codable, Equatable, Sendable {
    public let windows: [ClaudeQuotaWindow]
    public let plan: String?
    public let fetchedAt: Date
    public let source: ClaudeQuotaSource

    public init(windows: [ClaudeQuotaWindow], plan: String?, fetchedAt: Date, source: ClaudeQuotaSource = .oauth) {
        self.windows = windows
        self.plan = plan
        self.fetchedAt = fetchedAt
        self.source = source
    }

    enum CodingKeys: String, CodingKey { case windows, plan, fetchedAt, source }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(windows: try container.decode([ClaudeQuotaWindow].self, forKey: .windows),
                  plan: try container.decodeIfPresent(String.self, forKey: .plan),
                  fetchedAt: try container.decode(Date.self, forKey: .fetchedAt),
                  source: try container.decodeIfPresent(ClaudeQuotaSource.self, forKey: .source) ?? .oauth)
    }

    public var displayPlan: String {
        guard let plan, ["pro", "max", "team", "enterprise"].contains(plan.lowercased()) else { return "Claude" }
        return "Claude \(plan.capitalized)"
    }

    public func isStale(at date: Date, interval: TimeInterval) -> Bool {
        date.timeIntervalSince(fetchedAt) > interval || windows.contains { $0.isExpired(at: date) }
    }
}

public enum ClaudeQuotaParser {
    public static func parse(_ data: Data, now: Date, plan: String?) throws -> ClaudeQuotaSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeQuotaClientError.invalidResponse
        }
        var windows: [ClaudeQuotaWindow] = []
        for key in ClaudeQuotaKey.allCases {
            guard let row = root[key.rawValue] as? [String: Any],
                  let number = row["utilization"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { continue }
            let resetsAt: Date?
            if let raw = row["resets_at"] as? String {
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { continue }
                resetsAt = date
            } else if row["resets_at"] == nil || row["resets_at"] is NSNull {
                resetsAt = nil
            } else {
                continue
            }
            windows.append(ClaudeQuotaWindow(key: key, usedPercent: number.doubleValue, resetsAt: resetsAt))
        }
        guard !windows.isEmpty else { throw ClaudeQuotaClientError.noQuotaWindows }
        return ClaudeQuotaSnapshot(windows: windows, plan: plan, fetchedAt: now)
    }
}
