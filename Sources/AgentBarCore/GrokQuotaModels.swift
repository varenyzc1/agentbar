import Foundation

public struct GrokQuotaProductUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { product }

    public let product: String
    public let usagePercent: Double

    public init(product: String, usagePercent: Double) {
        self.product = product
        self.usagePercent = max(0, min(100, usagePercent.isFinite ? usagePercent : 0))
    }
}

public struct GrokQuotaSnapshot: Codable, Equatable, Sendable {
    public let periodType: String
    public let usedPercent: Double
    public let remainingPercent: Double
    public let resetsAt: Date
    public let includedCents: Int64?
    public let usedCents: Int64?
    public let prepaidBalanceCents: Int64?
    public let productUsage: [GrokQuotaProductUsage]
    public let accountDisplayName: String?
    public let fetchedAt: Date
    public let source: String

    public init(
        periodType: String,
        usedPercent: Double,
        resetsAt: Date,
        includedCents: Int64?,
        usedCents: Int64?,
        prepaidBalanceCents: Int64?,
        productUsage: [GrokQuotaProductUsage] = [],
        accountDisplayName: String?,
        fetchedAt: Date,
        source: String
    ) {
        let clamped = max(0, min(100, usedPercent))
        self.periodType = periodType
        self.usedPercent = clamped
        self.remainingPercent = 100 - clamped
        self.resetsAt = resetsAt
        self.includedCents = includedCents
        self.usedCents = usedCents
        self.prepaidBalanceCents = prepaidBalanceCents
        self.productUsage = productUsage
        self.accountDisplayName = accountDisplayName
        self.fetchedAt = fetchedAt
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case periodType
        case usedPercent
        case remainingPercent
        case resetsAt
        case includedCents
        case usedCents
        case prepaidBalanceCents
        case productUsage
        case accountDisplayName
        case fetchedAt
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            periodType: try container.decode(String.self, forKey: .periodType),
            usedPercent: try container.decode(Double.self, forKey: .usedPercent),
            resetsAt: try container.decode(Date.self, forKey: .resetsAt),
            includedCents: try container.decodeIfPresent(Int64.self, forKey: .includedCents),
            usedCents: try container.decodeIfPresent(Int64.self, forKey: .usedCents),
            prepaidBalanceCents: try container.decodeIfPresent(Int64.self, forKey: .prepaidBalanceCents),
            productUsage: try container.decodeIfPresent([GrokQuotaProductUsage].self, forKey: .productUsage) ?? [],
            accountDisplayName: try container.decodeIfPresent(String.self, forKey: .accountDisplayName),
            fetchedAt: try container.decode(Date.self, forKey: .fetchedAt),
            source: try container.decode(String.self, forKey: .source)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(periodType, forKey: .periodType)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encode(remainingPercent, forKey: .remainingPercent)
        try container.encode(resetsAt, forKey: .resetsAt)
        try container.encodeIfPresent(includedCents, forKey: .includedCents)
        try container.encodeIfPresent(usedCents, forKey: .usedCents)
        try container.encodeIfPresent(prepaidBalanceCents, forKey: .prepaidBalanceCents)
        try container.encode(productUsage, forKey: .productUsage)
        try container.encodeIfPresent(accountDisplayName, forKey: .accountDisplayName)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encode(source, forKey: .source)
    }

    public var periodLabel: String {
        switch periodType.uppercased() {
        case let value where value.contains("WEEKLY"):
            return "Weekly"
        case let value where value.contains("MONTHLY"):
            return "Monthly"
        default:
            return "Usage"
        }
    }

    public var severity: CodexQuotaSeverity {
        CodexQuotaSeverity.severity(for: usedPercent)
    }

}

public enum GrokQuotaParser {
    public static func parse(
        _ data: Data,
        now: Date,
        source: String,
        accountDisplayName: String?
    ) throws -> GrokQuotaSnapshot {
        do {
            guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let config = response["config"] as? [String: Any] else {
                throw GrokQuotaClientError.invalidResponse
            }

            let currentPeriod = config["currentPeriod"] as? [String: Any]
            let periodType = string(currentPeriod?["type"]) ?? "USAGE_PERIOD_TYPE_MONTHLY"
            guard let resetString = string(currentPeriod?["end"])
                    ?? string(config["billingPeriodEnd"]),
                  let resetsAt = date(resetString) else {
                throw GrokQuotaClientError.invalidResponse
            }

            let included = cent(config["monthlyLimit"])
            let used = cent(config["used"])
            let prepaid = cent(config["prepaidBalance"])
            let productUsage = parseProductUsage(config["productUsage"])
            let usedPercent: Double
            if let reported = number(config["creditUsagePercent"]) {
                usedPercent = reported
            } else if let included, included > 0, let used {
                usedPercent = Double(used) / Double(included) * 100
            } else if !productUsage.isEmpty {
                usedPercent = productUsage.reduce(0) { $0 + $1.usagePercent }
            } else {
                throw GrokQuotaClientError.invalidResponse
            }

            return GrokQuotaSnapshot(
                periodType: periodType,
                usedPercent: usedPercent,
                resetsAt: resetsAt,
                includedCents: included,
                usedCents: used,
                prepaidBalanceCents: prepaid,
                productUsage: productUsage,
                accountDisplayName: accountDisplayName,
                fetchedAt: now,
                source: source
            )
        } catch let error as GrokQuotaClientError {
            throw error
        } catch {
            throw GrokQuotaClientError.decoding(PrivacyScrubber.scrub(error.localizedDescription))
        }
    }

    private static func cent(_ value: Any?) -> Int64? {
        guard let object = value as? [String: Any] else { return nil }
        return number(object["val"]).map(Int64.init)
    }

    private static func parseProductUsage(_ value: Any?) -> [GrokQuotaProductUsage] {
        guard let rows = value as? [[String: Any]] else { return [] }
        var percentagesByProduct: [String: Double] = [:]

        for row in rows {
            guard let product = productIdentifier(row["product"]),
                  let usagePercent = number(row["usagePercent"]),
                  usagePercent.isFinite,
                  usagePercent > 0 else {
                continue
            }
            percentagesByProduct[product, default: 0] += usagePercent
        }

        return percentagesByProduct
            .map { GrokQuotaProductUsage(product: $0.key, usagePercent: $0.value) }
            .sorted {
                if $0.usagePercent == $1.usagePercent {
                    return $0.product.localizedCaseInsensitiveCompare($1.product) == .orderedAscending
                }
                return $0.usagePercent > $1.usagePercent
            }
    }

    private static func productIdentifier(_ value: Any?) -> String? {
        if let string = string(value) {
            return string
        }
        if let number = value as? NSNumber {
            return String(number.intValue)
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: value) { return parsed }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
