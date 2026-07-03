import Foundation

public struct CodexResetCredit: Codable, Equatable, Identifiable, Sendable {
    public var id: String {
        [
            idSuffix ?? "no-id",
            status,
            resetType,
            expiresAt.map { String(Int($0.timeIntervalSince1970)) } ?? "no-expiry"
        ].joined(separator: ":")
    }

    public let idSuffix: String?
    public let status: String
    public let resetType: String
    public let expiresAt: Date?
    public let grantedAt: Date?
    public let redeemedAt: Date?
    public let redeemStartedAt: Date?

    public init(
        idSuffix: String?,
        status: String,
        resetType: String,
        expiresAt: Date?,
        grantedAt: Date?,
        redeemedAt: Date?,
        redeemStartedAt: Date?
    ) {
        self.idSuffix = idSuffix
        self.status = status
        self.resetType = resetType
        self.expiresAt = expiresAt
        self.grantedAt = grantedAt
        self.redeemedAt = redeemedAt
        self.redeemStartedAt = redeemStartedAt
    }
}

public struct CodexResetCreditsSnapshot: Codable, Equatable, Sendable {
    public let availableCount: Int
    public let availableCredits: [CodexResetCredit]
    public let allCredits: [CodexResetCredit]
    public let allCreditCount: Int
    public let fetchedAt: Date
    public let source: String

    public init(
        availableCount: Int,
        availableCredits: [CodexResetCredit],
        allCredits: [CodexResetCredit],
        fetchedAt: Date,
        source: String
    ) {
        self.availableCount = availableCount
        self.availableCredits = availableCredits.sorted(by: Self.sortCredits)
        self.allCredits = allCredits.sorted(by: Self.sortCredits)
        self.allCreditCount = allCredits.count
        self.fetchedAt = fetchedAt
        self.source = source
    }

    public var earliestExpiration: Date? {
        availableCredits.compactMap(\.expiresAt).min()
    }

    private static func sortCredits(_ lhs: CodexResetCredit, _ rhs: CodexResetCredit) -> Bool {
        switch (lhs.expiresAt, rhs.expiresAt) {
        case let (left?, right?):
            if left != right { return left < right }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return (lhs.idSuffix ?? "") < (rhs.idSuffix ?? "")
    }
}

public enum CodexResetCreditsParser {
    public static func parse(_ data: Data, now: Date, source: String) throws -> CodexResetCreditsSnapshot {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexResetCreditsClientError.invalidResponse
            }

            let rawCredits = object["credits"] as? [[String: Any]] ?? []
            let credits = rawCredits.map(parseCredit)
            let availableCredits = credits.filter { $0.status.lowercased() == "available" }
            let availableCount = parseInt(pick(object, "available_count", "availableCount")) ?? availableCredits.count

            return CodexResetCreditsSnapshot(
                availableCount: availableCount,
                availableCredits: availableCredits,
                allCredits: credits,
                fetchedAt: now,
                source: source
            )
        } catch let error as CodexResetCreditsClientError {
            throw error
        } catch {
            throw CodexResetCreditsClientError.decoding(PrivacyScrubber.scrub(error.localizedDescription))
        }
    }

    private static func parseCredit(_ object: [String: Any]) -> CodexResetCredit {
        let id = pick(object, "id").map { String(describing: $0) }
        return CodexResetCredit(
            idSuffix: id.map { String($0.suffix(8)) },
            status: pick(object, "status").map { String(describing: $0) } ?? "unknown",
            resetType: pick(object, "reset_type", "resetType").map { String(describing: $0) } ?? "unknown",
            expiresAt: parseDate(pick(object, "expires_at", "expiresAt")),
            grantedAt: parseDate(pick(object, "granted_at", "grantedAt")),
            redeemedAt: parseDate(pick(object, "redeemed_at", "redeemedAt")),
            redeemStartedAt: parseDate(pick(object, "redeem_started_at", "redeemStartedAt"))
        )
    }

    private static func pick(_ object: [String: Any], _ keys: String...) -> Any? {
        for key in keys {
            if let value = object[key], !(value is NSNull) {
                if let string = value as? String, string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continue
                }
                return value
            }
        }
        return nil
    }

    private static func parseInt(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let value else { return nil }

        if let number = value as? NSNumber {
            return date(fromTimestamp: number.doubleValue)
        }
        if let double = value as? Double {
            return date(fromTimestamp: double)
        }
        if let int = value as? Int {
            return date(fromTimestamp: Double(int))
        }

        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let double = Double(text) {
            return date(fromTimestamp: double)
        }

        let normalized = text.hasSuffix("Z") ? String(text.dropLast()) + "+00:00" : text
        return ISO8601DateFormatter.agentBarResetCredits.date(from: text)
            ?? ISO8601DateFormatter.agentBarResetCredits.date(from: normalized)
            ?? ISO8601DateFormatter.agentBarResetCreditsWithFractionalSeconds.date(from: text)
            ?? ISO8601DateFormatter.agentBarResetCreditsWithFractionalSeconds.date(from: normalized)
    }

    private static func date(fromTimestamp value: Double) -> Date {
        Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
    }
}

private extension ISO8601DateFormatter {
    static let agentBarResetCredits: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let agentBarResetCreditsWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
