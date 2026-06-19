import Foundation

public enum AgentBarFormatters {
    public static func compactTokens(_ value: Int64) -> String {
        let absolute = abs(value)
        switch absolute {
        case 1_000_000_000...:
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000..<1_000_000:
            return String(format: "%.0fK", Double(value) / 1_000)
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return "\(value)"
        }
    }

    public static func compactTokens(_ value: Int) -> String {
        compactTokens(Int64(value))
    }

    public static func fullTokens(_ value: Int64) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func fullTokens(_ value: Int) -> String {
        fullTokens(Int64(value))
    }

    public static func usd(_ value: Double?) -> String {
        guard let value else { return "--" }
        return currencyFormatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    public static func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f%%", value)
    }

    public static func relativeReset(from now: Date, to date: Date, language: AppLanguage = .english) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded())
        guard seconds > 0 else {
            return language == .simplifiedChinese ? "现在重置" : "reset now"
        }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            if language == .simplifiedChinese {
                return hours > 0 ? "\(days)天 \(hours)小时后重置" : "\(days)天后重置"
            }
            return hours > 0 ? "resets in \(days)d \(hours)h" : "resets in \(days)d"
        }
        if hours > 0 {
            if language == .simplifiedChinese {
                return minutes > 0 ? "\(hours)小时 \(minutes)分钟后重置" : "\(hours)小时后重置"
            }
            return minutes > 0 ? "resets in \(hours)h \(minutes)m" : "resets in \(hours)h"
        }
        if language == .simplifiedChinese {
            return "\(max(1, minutes))分钟后重置"
        }
        return "resets in \(max(1, minutes))m"
    }

    public static func relativeAge(from now: Date, to pastDate: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(pastDate).rounded()))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h ago" : "\(days)d ago"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m ago" : "\(hours)h ago"
        }
        if minutes > 0 {
            return "\(minutes)m ago"
        }
        return "just now"
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()
}
