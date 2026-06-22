import AgentBarCore
import Foundation

struct AgentBarCopy {
    let language: AppLanguage

    var settingsWindowTitle: String { text("AgentBar Settings", "AgentBar 设置") }
    var menuBar: String { text("Menu Bar", "菜单栏") }
    var refresh: String { text("Refresh", "刷新") }
    var budgets: String { text("Budgets", "预算") }
    var maintenance: String { text("Maintenance", "维护") }
    var updates: String { text("Updates", "更新") }
    var display: String { text("Display", "显示") }
    var metric: String { text("Metric", "指标") }
    var labels: String { text("Labels", "标签") }
    var languageLabel: String { text("Language", "语言") }
    var login: String { text("Login", "登录项") }
    var tokenBudget: String { text("Tokens", "Tokens") }
    var tokens: String { text("tokens", "tokens") }
    var cost: String { text("Cost", "费用") }
    var save: String { text("Save", "保存") }
    var scan: String { text("Scan", "扫描") }
    var recalculate: String { text("Recalculate", "重算") }
    var resetPricing: String { text("Reset pricing", "重置价格") }
    var database: String { text("Database", "数据库") }
    var check: String { text("Check", "检查") }
    var update: String { text("Update", "更新") }
    var open: String { text("Open", "打开") }
    var settings: String { text("Settings", "设置") }
    var quit: String { text("Quit", "退出") }
    var notRefreshed: String { text("Not refreshed", "尚未刷新") }
    var refreshingQuota: String { text("Refreshing quota", "正在刷新额度") }
    var unsupportedAPIKey: String { text("API key mode does not support subscription quota. Sign in with a ChatGPT subscription.", "API key 模式不支持订阅额度，请使用 ChatGPT 订阅登录。") }
    var codexNotConfigured: String { text("Codex is not configured\ncodex login", "Codex 未配置\ncodex login") }
    var codexNotLoggedIn: String { text("Not signed in. Run codex login", "未登录，请运行 codex login") }
    var hideEmail: String { text("Hide email", "隐藏邮箱") }
    var showEmail: String { text("Show email", "显示邮箱") }
    var unavailable: String { text("unavailable", "不可用") }
    var stale: String { text("stale", "已过期") }
    var today: String { text("Today", "今日") }
    var sevenDaysShort: String { text("7D", "7 天") }
    var all: String { text("All", "全部") }
    var topModel: String { text("Top Model", "主要模型") }
    var noLocalUsageYet: String { text("No local usage yet", "暂无本地使用记录") }
    var days365: String { text("365 Days", "365 天") }
    var less: String { text("Less", "少") }
    var more: String { text("More", "多") }
    var sources: String { text("Sources", "来源") }
    var byline: String { text("By varenyzc", "作者 varenyzc") }
    var contributorByline: String { text("By ZengWenJian123", "协作 ZengWenJian123") }
    var openGitHubRepository: String { text("Open GitHub repository", "打开 GitHub 仓库") }
    var invalidSettings: String { text("Invalid settings", "设置无效") }
    var noBudget: String { text("No budget", "未设置预算") }
    var noModel: String { text("no model", "无模型") }
    var used: String { text("used", "已用") }
    var custom: String { text("Custom", "自定义") }
    var thirtyDays: String { text("30D", "30 天") }
    var range: String { text("Range", "范围") }
    var total: String { text("Total", "总计") }
    var input: String { text("Input", "输入") }
    var output: String { text("Output", "输出") }
    var cached: String { text("Cached", "缓存") }
    var topModels: String { text("Top Models", "模型用量明细") }
    var trend30Days: String { text("30 Day Trend", "近 30 天趋势") }
    var top3: String { text("Top 3", "Top 3") }
    var top5: String { text("Top 5", "Top 5") }
    var start: String { text("Start", "开始") }
    var end: String { text("End", "结束") }

    func menuModeTitle(_ mode: CodexMenuBarMode) -> String {
        switch mode {
        case .plan:
            return text("Plan", "计划")
        case .alerts:
            return text("Alerts", "提醒")
        case .iconOnly:
            return text("Usage", "用量")
        }
    }

    func metricTitle(_ metric: MenuBarMetric) -> String {
        switch metric {
        case .usedTokens:
            return text("Used tokens", "已用 tokens")
        case .usedCost:
            return text("Used cost", "已用费用")
        case .remainingPercent:
            return text("Remaining", "剩余")
        }
    }

    func quotaBasisTitle(_ basis: CodexQuotaPercentBasis) -> String {
        switch basis {
        case .used:
            return text("Used", "已用")
        case .remaining:
            return text("Remaining", "剩余")
        }
    }

    func languageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "中文"
        }
    }

    func quotaLabel(_ key: CodexQuotaKey) -> String {
        text("\(key.label) quota", "\(key.label) 额度")
    }

    func quotaMeaning(_ key: CodexQuotaKey) -> String {
        switch key {
        case .fiveHour:
            return text("5 hour rolling window", "5 小时滚动窗口")
        case .sevenDay:
            return text("7 day rolling window", "7 天滚动窗口")
        case .codeReview:
            return text("Code Review limit", "Code Review 限额")
        }
    }

    func updated(at date: Date) -> String {
        text(
            "Updated \(date.formatted(date: .omitted, time: .shortened))",
            "更新于 \(date.formatted(date: .omitted, time: .shortened))"
        )
    }

    func refreshStatus(snapshot: CodexQuotaSnapshot, isStale: Bool, failed: Bool) -> String {
        let time = snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)
        if failed {
            return text("Refresh failed · cached \(time)", "刷新失败 · 缓存于 \(time)")
        }
        if isStale {
            return text("Cached \(time)", "缓存于 \(time)")
        }
        return text("Updated \(time)", "更新于 \(time)")
    }

    func installMethod(_ method: AppInstallMethod) -> String {
        switch method {
        case .unknown:
            return text("Checking install method...", "正在检查安装方式...")
        case .homebrew:
            return text("Installed with Homebrew.", "通过 Homebrew 安装。")
        case .manual:
            return text("Manual install or DMG install.", "手动安装或 DMG 安装。")
        }
    }

    func updateStatus(_ state: AppUpdateState, installMethod: AppInstallMethod) -> String {
        switch state {
        case .idle:
            return text(
                "\(self.installMethod(installMethod)) Check GitHub Releases for a newer version.",
                "\(self.installMethod(installMethod)) 可检查 GitHub Releases 是否有新版本。"
            )
        case .checking:
            return text("Checking for updates...", "正在检查更新...")
        case let .upToDate(version):
            return text(
                "You are up to date on \(version). \(self.installMethod(installMethod))",
                "当前已是最新版本 \(version)。\(self.installMethod(installMethod))"
            )
        case let .available(version, _):
            if installMethod == .homebrew {
                return text(
                    "AgentBar \(version) is available. Update with Homebrew.",
                    "AgentBar \(version) 可用。请使用 Homebrew 更新。"
                )
            }
            return text(
                "AgentBar \(version) is available. Open the release page to install it.",
                "AgentBar \(version) 可用。打开发布页安装。"
            )
        case let .failed(message):
            return message
        }
    }

    func statusMessage(_ message: String) -> String {
        guard language == .simplifiedChinese else { return message }

        if message.hasPrefix("Scanned "), message.hasSuffix(" files") {
            let count = message
                .dropFirst("Scanned ".count)
                .dropLast(" files".count)
            return "已扫描 \(count) 个文件"
        }

        if message.hasSuffix(" · showing cached quota") {
            let prefix = message.dropLast(" · showing cached quota".count)
            return "\(prefix) · 显示缓存额度"
        }

        switch message {
        case "Ready":
            return "就绪"
        case "Database error":
            return "数据库错误"
        case "Unable to open local database":
            return "无法打开本地数据库"
        case "Settings saved":
            return "设置已保存"
        case "Scanning":
            return "正在扫描"
        case "Refreshing":
            return "正在刷新"
        case "Up to date":
            return "已是最新"
        case "Scan failed":
            return "扫描失败"
        case "Updated":
            return "已更新"
        case "Unable to refresh Codex quota":
            return "无法刷新 Codex 额度"
        case "Pricing reset":
            return "价格已重置"
        case "Pricing reset failed":
            return "价格重置失败"
        case "Costs recalculated":
            return "费用已重算"
        case "Recalculate failed":
            return "重算失败"
        case "Launch at login enabled":
            return "已启用登录时启动"
        case "Launch at login disabled":
            return "已关闭登录时启动"
        case "Login item update failed":
            return "登录项更新失败"
        case "Update available":
            return "有可用更新"
        case "AgentBar is up to date":
            return "AgentBar 已是最新"
        case "Update check failed":
            return "检查更新失败"
        case "Homebrew update started":
            return "已启动 Homebrew 更新"
        case "Update failed":
            return "更新失败"
        case "Invalid settings":
            return invalidSettings
        default:
            return message
        }
    }

    func tooltipTokens(day: String, tokens: Int64, cost: Double, model: String?) -> String {
        let base = text(
            "\(day) · \(AgentBarFormatters.compactTokens(tokens)) tokens · \(AgentBarFormatters.usd(cost))",
            "\(day) · \(AgentBarFormatters.compactTokens(tokens)) tokens · \(AgentBarFormatters.usd(cost))"
        )
        guard let model else { return base }
        return "\(base) · \(model)"
    }

    private func text(_ english: String, _ simplifiedChinese: String) -> String {
        language == .simplifiedChinese ? simplifiedChinese : english
    }
}
