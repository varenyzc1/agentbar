import XCTest
@testable import AgentBarCore

final class UsageAggregatorTests: XCTestCase {
    func testSummarizesTodaySevenDayMonthAndQuota() {
        let now = fixedDate("2026-06-13T12:00:00Z")
        let settings = AppSettings(
            monthlyTokenBudget: 10_000,
            monthlyCostBudgetUSD: 25,
            timeZoneIdentifier: "UTC"
        )

        let days = [
            DailyUsage(day: "2026-06-13", inputTokens: 1_000, outputTokens: 500, requestCount: 4, costUSD: 4),
            DailyUsage(day: "2026-06-12", inputTokens: 2_000, outputTokens: 0, requestCount: 2, costUSD: 2),
            DailyUsage(day: "2026-06-07", inputTokens: 100, outputTokens: 100, requestCount: 1, costUSD: 1),
            DailyUsage(day: "2026-05-31", inputTokens: 5_000, outputTokens: 0, requestCount: 1, costUSD: 5)
        ]

        let summary = UsageAggregator.summarize(days: days, now: now, settings: settings)

        XCTAssertEqual(summary.today.totalTokens, 1_500)
        XCTAssertEqual(summary.sevenDayTokens, 3_700)
        XCTAssertEqual(summary.sevenDayCostUSD, 7)
        XCTAssertEqual(summary.monthTokens, 3_700)
        XCTAssertEqual(summary.monthCostUSD, 7)
        XCTAssertEqual(summary.quota.tokenRemainingPercent, 63)
        XCTAssertEqual(summary.quota.costRemainingPercent, 72)
    }

    func testUsesEstimatedCostWhenActualCostIsMissing() {
        let now = fixedDate("2026-06-13T12:00:00Z")
        let settings = AppSettings(
            monthlyCostBudgetUSD: 10,
            timeZoneIdentifier: "UTC",
            estimatedInputCostPerMillion: 2,
            estimatedOutputCostPerMillion: 8
        )

        let days = [
            DailyUsage(day: "2026-06-13", inputTokens: 1_000_000, outputTokens: 500_000)
        ]

        let summary = UsageAggregator.summarize(days: days, now: now, settings: settings)
        XCTAssertEqual(summary.today.costUSD, 6)
        XCTAssertEqual(summary.monthCostUSD, 6)
        XCTAssertEqual(summary.quota.costRemainingPercent, 40)
    }

    func testHeatmapContains365DaysAndLevels() {
        let now = fixedDate("2026-06-13T12:00:00Z")
        let settings = AppSettings(timeZoneIdentifier: "UTC")
        let days = [
            DailyUsage(day: "2026-06-11", inputTokens: 25),
            DailyUsage(day: "2026-06-12", inputTokens: 50),
            DailyUsage(day: "2026-06-13", inputTokens: 100)
        ]

        let summary = UsageAggregator.summarize(days: days, now: now, settings: settings)
        XCTAssertEqual(summary.heatmapDays.count, 365)
        XCTAssertEqual(summary.heatmapDays.last?.day, "2026-06-13")
        XCTAssertEqual(summary.heatmapDays.last?.level, 4)
        XCTAssertEqual(summary.heatmapDays.first?.level, 0)
    }

    func testMonthlyUsageForYearBuildsTwelveDetailedBuckets() {
        let days = [
            DailyUsage(day: "2025-12-31", inputTokens: 999, costUSD: 9),
            DailyUsage(day: "2026-01-02", inputTokens: 100, cachedInputTokens: 30, costUSD: 1),
            DailyUsage(day: "2026-01-20", outputTokens: 40, reasoningOutputTokens: 10, costUSD: 2),
            DailyUsage(day: "2026-02-03", cacheCreationInputTokens: 25),
            DailyUsage(day: "2027-01-01", inputTokens: 888, costUSD: 8)
        ]

        let months = UsageAggregator.monthlyUsageForYear(
            days: days,
            containing: fixedDate("2026-08-01T00:00:00Z"),
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.map(\.day), (1...12).map { String(format: "2026-%02d-01", $0) })
        XCTAssertEqual(months[0].inputTokens, 100)
        XCTAssertEqual(months[0].outputTokens, 40)
        XCTAssertEqual(months[0].cachedInputTokens, 30)
        XCTAssertEqual(months[0].reasoningOutputTokens, 10)
        XCTAssertEqual(months[0].costUSD, 3)
        XCTAssertEqual(months[1].cacheCreationInputTokens, 25)
        XCTAssertNil(months[1].costUSD)
        XCTAssertEqual(months[11].totalTokens, 0)
    }

    private func fixedDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
