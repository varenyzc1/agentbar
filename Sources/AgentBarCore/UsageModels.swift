import Foundation

public struct DailyUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { day }

    public var day: String
    public var inputTokens: Int64
    public var outputTokens: Int64
    public var cachedInputTokens: Int64
    public var cacheCreationInputTokens: Int64
    public var reasoningOutputTokens: Int64
    public var requestCount: Int
    public var costUSD: Double?

    public init(
        day: String,
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        cachedInputTokens: Int64 = 0,
        cacheCreationInputTokens: Int64 = 0,
        reasoningOutputTokens: Int64 = 0,
        requestCount: Int = 0,
        costUSD: Double? = nil
    ) {
        self.day = day
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.requestCount = requestCount
        self.costUSD = costUSD
    }

    public var totalTokens: Int64 {
        inputTokens
            + outputTokens
            + cachedInputTokens
            + cacheCreationInputTokens
            + reasoningOutputTokens
    }

    public func merging(_ other: DailyUsage) -> DailyUsage {
        DailyUsage(
            day: day,
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens + other.cacheCreationInputTokens,
            reasoningOutputTokens: reasoningOutputTokens + other.reasoningOutputTokens,
            requestCount: requestCount + other.requestCount,
            costUSD: UsageMath.addOptional(costUSD, other.costUSD)
        )
    }

    public func replacingCost(_ costUSD: Double?) -> DailyUsage {
        DailyUsage(
            day: day,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedInputTokens: cachedInputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens,
            reasoningOutputTokens: reasoningOutputTokens,
            requestCount: requestCount,
            costUSD: costUSD
        )
    }
}

public struct HeatmapDay: Codable, Equatable, Identifiable, Sendable {
    public var id: String { day }
    public let day: String
    public let tokens: Int64
    public let costUSD: Double
    public let topModel: String?
    public let level: Int

    public init(day: String, tokens: Int64, costUSD: Double = 0, topModel: String? = nil, level: Int) {
        self.day = day
        self.tokens = tokens
        self.costUSD = costUSD
        self.topModel = topModel
        self.level = level
    }
}

public struct TokenEntry: Codable, Equatable, Sendable {
    public let source: String
    public let model: String
    public let project: String
    public let timestamp: Date
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cachedInputTokens: Int64
    public let cacheCreationInputTokens: Int64
    public let reasoningOutputTokens: Int64
    public let dedupKey: String

    public init(
        source: String,
        model: String,
        project: String,
        timestamp: Date,
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        cachedInputTokens: Int64 = 0,
        cacheCreationInputTokens: Int64 = 0,
        reasoningOutputTokens: Int64 = 0,
        dedupKey: String
    ) {
        self.source = source
        self.model = model.isEmpty ? "unknown" : model
        self.project = project.isEmpty ? "unknown" : project
        self.timestamp = timestamp
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cachedInputTokens = max(0, cachedInputTokens)
        self.cacheCreationInputTokens = max(0, cacheCreationInputTokens)
        self.reasoningOutputTokens = max(0, reasoningOutputTokens)
        self.dedupKey = dedupKey
    }

    public var totalTokens: Int64 {
        inputTokens
            + outputTokens
            + cachedInputTokens
            + cacheCreationInputTokens
            + reasoningOutputTokens
    }
}

public struct ModelPricing: Codable, Equatable, Sendable {
    public let pattern: String
    public let displayName: String
    public let family: String
    public let inputPerMTok: Double
    public let outputPerMTok: Double
    public let cacheReadPerMTok: Double
    public let cacheCreationPerMTok: Double
    public let reasoningPerMTok: Double

    public init(
        pattern: String,
        displayName: String? = nil,
        family: String,
        inputPerMTok: Double,
        outputPerMTok: Double,
        cacheReadPerMTok: Double = 0,
        cacheCreationPerMTok: Double = 0,
        reasoningPerMTok: Double = 0
    ) {
        self.pattern = pattern
        self.displayName = displayName ?? pattern
        self.family = family
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
        self.cacheReadPerMTok = cacheReadPerMTok
        self.cacheCreationPerMTok = cacheCreationPerMTok
        self.reasoningPerMTok = reasoningPerMTok
    }
}

public struct ModelUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { model }

    public let model: String
    public let tokens: Int64
    public let costUSD: Double

    public init(model: String, tokens: Int64, costUSD: Double) {
        self.model = model
        self.tokens = tokens
        self.costUSD = costUSD
    }
}

public struct SourceUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { source }

    public let source: String
    public let tokens: Int64
    public let costUSD: Double

    public init(source: String, tokens: Int64, costUSD: Double) {
        self.source = source
        self.tokens = tokens
        self.costUSD = costUSD
    }
}

public struct DailyModelUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(day):\(model)" }

    public let day: String
    public let model: String
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cachedInputTokens: Int64
    public let cacheCreationInputTokens: Int64
    public let reasoningOutputTokens: Int64
    public let costUSD: Double

    public init(
        day: String,
        model: String,
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        cachedInputTokens: Int64 = 0,
        cacheCreationInputTokens: Int64 = 0,
        reasoningOutputTokens: Int64 = 0,
        costUSD: Double = 0
    ) {
        self.day = day
        self.model = model.isEmpty ? "unknown" : model
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cachedInputTokens = max(0, cachedInputTokens)
        self.cacheCreationInputTokens = max(0, cacheCreationInputTokens)
        self.reasoningOutputTokens = max(0, reasoningOutputTokens)
        self.costUSD = costUSD
    }

    public var totalTokens: Int64 {
        inputTokens
            + outputTokens
            + cachedInputTokens
            + cacheCreationInputTokens
            + reasoningOutputTokens
    }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let tokenBudget: Int?
    public let costBudgetUSD: Double?
    public let monthTokens: Int
    public let monthCostUSD: Double?
    public let tokenRemainingPercent: Double?
    public let costRemainingPercent: Double?

    public init(
        tokenBudget: Int?,
        costBudgetUSD: Double?,
        monthTokens: Int,
        monthCostUSD: Double?,
        tokenRemainingPercent: Double?,
        costRemainingPercent: Double?
    ) {
        self.tokenBudget = tokenBudget
        self.costBudgetUSD = costBudgetUSD
        self.monthTokens = monthTokens
        self.monthCostUSD = monthCostUSD
        self.tokenRemainingPercent = tokenRemainingPercent
        self.costRemainingPercent = costRemainingPercent
    }

    public var preferredRemainingPercent: Double? {
        costRemainingPercent ?? tokenRemainingPercent
    }
}

public struct UsageSummary: Codable, Equatable, Sendable {
    public let today: DailyUsage
    public let sevenDayTokens: Int64
    public let sevenDayCostUSD: Double?
    public let allTimeTokens: Int64
    public let allTimeCostUSD: Double?
    public let monthTokens: Int64
    public let monthCostUSD: Double?
    public let quota: QuotaSnapshot
    public let heatmapDays: [HeatmapDay]
    public let topModel7Days: ModelUsage?
    public let todayTopModel: ModelUsage?
    public let sourceBreakdown7Days: [SourceUsage]
    public let dailyUsageDays: [DailyUsage]
    public let dailyModelUsageDays: [DailyModelUsage]

    public init(
        today: DailyUsage,
        sevenDayTokens: Int64,
        sevenDayCostUSD: Double?,
        allTimeTokens: Int64 = 0,
        allTimeCostUSD: Double? = nil,
        monthTokens: Int64,
        monthCostUSD: Double?,
        quota: QuotaSnapshot,
        heatmapDays: [HeatmapDay],
        topModel7Days: ModelUsage? = nil,
        todayTopModel: ModelUsage? = nil,
        sourceBreakdown7Days: [SourceUsage] = [],
        dailyUsageDays: [DailyUsage] = [],
        dailyModelUsageDays: [DailyModelUsage] = []
    ) {
        self.today = today
        self.sevenDayTokens = sevenDayTokens
        self.sevenDayCostUSD = sevenDayCostUSD
        self.allTimeTokens = allTimeTokens
        self.allTimeCostUSD = allTimeCostUSD
        self.monthTokens = monthTokens
        self.monthCostUSD = monthCostUSD
        self.quota = quota
        self.heatmapDays = heatmapDays
        self.topModel7Days = topModel7Days
        self.todayTopModel = todayTopModel
        self.sourceBreakdown7Days = sourceBreakdown7Days
        self.dailyUsageDays = dailyUsageDays
        self.dailyModelUsageDays = dailyModelUsageDays
    }

    public static var empty: UsageSummary {
        let settings = AppSettings()
        return UsageAggregator.summarize(days: [], now: Date(), settings: settings)
    }
}

public enum UsageMath {
    static func addOptional(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return left + right
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
        }
    }
}
