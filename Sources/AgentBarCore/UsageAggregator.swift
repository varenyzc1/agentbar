import Foundation

public enum UsageAggregator {
    public static func summarize(
        days: [DailyUsage],
        now: Date,
        settings: AppSettings
    ) -> UsageSummary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = settings.timeZone

        let todayDate = calendar.startOfDay(for: now)
        let todayKey = dayString(for: todayDate, calendar: calendar)
        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0) })

        let rawToday = byDay[todayKey] ?? DailyUsage(day: todayKey)
        let today = rawToday.costUSD == nil
            ? rawToday.replacingCost(estimatedCost(for: rawToday, settings: settings))
            : rawToday
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: todayDate) ?? todayDate
        let monthInterval = calendar.dateInterval(of: .month, for: todayDate)
        let monthStart = monthInterval?.start ?? todayDate

        let sevenDayItems = days.filter { day in
            guard let date = date(fromDayString: day.day, calendar: calendar) else { return false }
            return date >= sevenDayStart && date <= todayDate
        }

        let monthItems = days.filter { day in
            guard let date = date(fromDayString: day.day, calendar: calendar) else { return false }
            return date >= monthStart && date <= todayDate
        }

        let sevenDayCost = sumCost(sevenDayItems, settings: settings)
        let monthCost = sumCost(monthItems, settings: settings)
        let monthTokens = monthItems.reduce(Int64(0)) { $0 + $1.totalTokens }
        let allTimeCost = sumCost(days, settings: settings)
        let allTimeTokens = days.reduce(Int64(0)) { $0 + $1.totalTokens }

        let quota = QuotaSnapshot(
            tokenBudget: settings.monthlyTokenBudget,
            costBudgetUSD: settings.monthlyCostBudgetUSD,
            monthTokens: Int(clamping: monthTokens),
            monthCostUSD: monthCost,
            tokenRemainingPercent: remainingPercent(used: Double(monthTokens), budget: settings.monthlyTokenBudget.map(Double.init)),
            costRemainingPercent: remainingPercent(used: monthCost, budget: settings.monthlyCostBudgetUSD)
        )

        return UsageSummary(
            today: today,
            sevenDayTokens: sevenDayItems.reduce(Int64(0)) { $0 + $1.totalTokens },
            sevenDayCostUSD: sevenDayCost,
            allTimeTokens: allTimeTokens,
            allTimeCostUSD: allTimeCost,
            monthTokens: monthTokens,
            monthCostUSD: monthCost,
            quota: quota,
            heatmapDays: heatmap(daysByKey: byDay, today: todayDate, calendar: calendar),
            dailyUsageDays: days.sorted { $0.day < $1.day }
        )
    }

    public static func dayString(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return dayString(for: date, calendar: calendar)
    }

    public static func date(fromDayString day: String, timeZone: TimeZone = .current) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return date(fromDayString: day, calendar: calendar)
    }

    public static func estimatedCost(for usage: DailyUsage, settings: AppSettings) -> Double? {
        guard settings.estimatedInputCostPerMillion > 0 || settings.estimatedOutputCostPerMillion > 0 else {
            return nil
        }

        let inputCost = Double(usage.inputTokens) / 1_000_000 * settings.estimatedInputCostPerMillion
        let outputCost = Double(usage.outputTokens) / 1_000_000 * settings.estimatedOutputCostPerMillion
        return inputCost + outputCost
    }

    static func dayString(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func date(fromDayString day: String, calendar: Calendar) -> Date? {
        let pieces = day.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2]))
    }

    private static func sumCost(_ days: [DailyUsage], settings: AppSettings) -> Double? {
        var hasCost = false
        let total = days.reduce(0.0) { partial, day in
            if let cost = day.costUSD ?? estimatedCost(for: day, settings: settings) {
                hasCost = true
                return partial + cost
            }
            return partial
        }
        return hasCost ? total : nil
    }

    private static func remainingPercent(used: Double?, budget: Double?) -> Double? {
        guard let used, let budget, budget > 0 else { return nil }
        return max(0, min(100, (1 - used / budget) * 100))
    }

    private static func heatmap(
        daysByKey: [String: DailyUsage],
        today: Date,
        calendar: Calendar
    ) -> [HeatmapDay] {
        let dates = (0..<365).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - 364, to: today)
        }
        let maxTokens = max(dates.map { date -> Int64 in
            let key = dayString(for: date, calendar: calendar)
            return daysByKey[key]?.totalTokens ?? 0
        }.max() ?? Int64(0), Int64(0))

        return dates.map { date in
            let key = dayString(for: date, calendar: calendar)
            let tokens = daysByKey[key]?.totalTokens ?? 0
            return HeatmapDay(day: key, tokens: tokens, level: heatmapLevel(tokens: tokens, maxTokens: maxTokens))
        }
    }

    private static func heatmapLevel(tokens: Int64, maxTokens: Int64) -> Int {
        guard tokens > 0, maxTokens > 0 else { return 0 }
        let ratio = Double(tokens) / Double(maxTokens)
        switch ratio {
        case 0..<0.25:
            return 1
        case 0.25..<0.5:
            return 2
        case 0.5..<0.75:
            return 3
        default:
            return 4
        }
    }
}
