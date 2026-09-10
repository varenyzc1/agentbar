import Foundation

public enum CodexQuotaKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
    case codeReview = "code_review"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fiveHour:
            return "5h"
        case .sevenDay:
            return "7d"
        case .codeReview:
            return "R"
        }
    }

    public var meaning: String {
        switch self {
        case .fiveHour:
            return "5 hour rolling window"
        case .sevenDay:
            return "7 day rolling window"
        case .codeReview:
            return "Code Review limit"
        }
    }
}

public enum CodexQuotaSeverity: String, Codable, Sendable {
    case ok
    case warning
    case critical

    public static func severity(for usedPercent: Double) -> CodexQuotaSeverity {
        switch usedPercent {
        case 90...:
            return .critical
        case 70..<90:
            return .warning
        default:
            return .ok
        }
    }
}

public struct CodexQuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: CodexQuotaKey { key }

    public let key: CodexQuotaKey
    public let usedPercent: Double
    public let remainingPercent: Double
    public let resetsAt: Date
    public let limitWindowSeconds: Int?
    public let stale: Bool

    public init(
        key: CodexQuotaKey,
        usedPercent: Double,
        resetsAt: Date,
        limitWindowSeconds: Int?,
        now: Date
    ) {
        let clamped = max(0, min(100, usedPercent))
        self.key = key
        self.usedPercent = clamped
        self.remainingPercent = 100 - clamped
        self.resetsAt = resetsAt
        self.limitWindowSeconds = limitWindowSeconds
        self.stale = now > resetsAt.addingTimeInterval(60)
    }

    private init(
        key: CodexQuotaKey,
        usedPercent: Double,
        remainingPercent: Double,
        resetsAt: Date,
        limitWindowSeconds: Int?,
        stale: Bool
    ) {
        self.key = key
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.limitWindowSeconds = limitWindowSeconds
        self.stale = stale
    }

    public var severity: CodexQuotaSeverity {
        CodexQuotaSeverity.severity(for: usedPercent)
    }

    public func refreshed(now: Date) -> CodexQuotaWindow {
        CodexQuotaWindow(
            key: key,
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
            resetsAt: resetsAt,
            limitWindowSeconds: limitWindowSeconds,
            stale: now > resetsAt.addingTimeInterval(60)
        )
    }
}

public struct CodexQuotaSnapshot: Codable, Equatable, Sendable {
    public let planType: String
    public let windows: [CodexQuotaWindow]
    public let accountDisplayName: String?
    public let fetchedAt: Date
    public let source: String

    public init(
        planType: String,
        windows: [CodexQuotaWindow],
        accountDisplayName: String?,
        fetchedAt: Date,
        source: String
    ) {
        self.planType = planType
        self.windows = windows.sorted { $0.key.rawValue < $1.key.rawValue }
        self.accountDisplayName = accountDisplayName
        self.fetchedAt = fetchedAt
        self.source = source
    }

    public var displayPlan: String {
        guard let displayPlanType else { return "Codex" }
        return "Codex \(displayPlanType)"
    }

    public var displayPlanType: String? {
        let trimmed = planType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let words = trimmed
            .split { $0 == "_" || $0 == "-" || $0.isWhitespace }
            .map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    public var highestUsedPercent: Double? {
        windows.map(\.usedPercent).max()
    }

    public var highestWindow: CodexQuotaWindow? {
        windows.max { $0.usedPercent < $1.usedPercent }
    }

    public var severity: CodexQuotaSeverity {
        highestUsedPercent.map(CodexQuotaSeverity.severity(for:)) ?? .ok
    }

    public var warningCount: Int {
        windows.filter { $0.usedPercent >= 70 }.count
    }

    public func window(for key: CodexQuotaKey) -> CodexQuotaWindow? {
        windows.first { $0.key == key }
    }

    public func refreshed(now: Date) -> CodexQuotaSnapshot {
        CodexQuotaSnapshot(
            planType: planType,
            windows: windows.map { $0.refreshed(now: now) },
            accountDisplayName: accountDisplayName,
            fetchedAt: fetchedAt,
            source: source
        )
    }

    public func droppingExpiredWindows(now: Date) -> CodexQuotaSnapshot? {
        let currentWindows = windows
            .map { $0.refreshed(now: now) }
            .filter { !$0.stale }
        guard !currentWindows.isEmpty else { return nil }
        return CodexQuotaSnapshot(
            planType: planType,
            windows: currentWindows,
            accountDisplayName: accountDisplayName,
            fetchedAt: fetchedAt,
            source: source
        )
    }
}

public enum CodexQuotaParser {
    public static func parse(
        _ data: Data,
        now: Date,
        source: String,
        accountDisplayName: String?
    ) throws -> CodexQuotaSnapshot {
        do {
            let response = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            var windows: [CodexQuotaWindow] = []
            if let primary = response.rateLimit?.primaryWindow {
                windows.append(primary.window(key: .fiveHour, now: now))
            }
            if let secondary = response.rateLimit?.secondaryWindow {
                windows.append(secondary.window(key: .sevenDay, now: now))
            }
            if let review = response.codeReviewRateLimit?.primaryWindow {
                windows.append(review.window(key: .codeReview, now: now))
            }
            return CodexQuotaSnapshot(
                planType: response.planType ?? "",
                windows: windows,
                accountDisplayName: accountDisplayName,
                fetchedAt: now,
                source: source
            )
        } catch {
            throw CodexQuotaClientError.decoding(PrivacyScrubber.scrub(error.localizedDescription))
        }
    }
}

private struct CodexUsageResponse: Decodable {
    let planType: String?
    let rateLimit: CodexRateLimit?
    let codeReviewRateLimit: CodexCodeReviewRateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case codeReviewRateLimit = "code_review_rate_limit"
    }
}

private struct CodexRateLimit: Decodable {
    let primaryWindow: CodexRawWindow?
    let secondaryWindow: CodexRawWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexCodeReviewRateLimit: Decodable {
    let primaryWindow: CodexRawWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
    }
}

private struct CodexRawWindow: Decodable {
    let usedPercent: Double
    let resetAt: TimeInterval
    let limitWindowSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }

    func window(key: CodexQuotaKey, now: Date) -> CodexQuotaWindow {
        CodexQuotaWindow(
            key: key,
            usedPercent: usedPercent,
            resetsAt: Date(timeIntervalSince1970: resetAt),
            limitWindowSeconds: limitWindowSeconds,
            now: now
        )
    }
}
