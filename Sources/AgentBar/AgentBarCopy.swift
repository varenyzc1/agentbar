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
    var grokQuota: String { text("Grok quota", "Grok 额度") }
    var claudeQuota: String { text("Claude quota", "Claude 额度") }
    var refreshClaudeQuota: String { text("Query Claude quota online", "网络补查 Claude 额度") }
    var waitingForClaudeLocal: String { text("Waiting for local quota data. Use Claude Code to update it.", "等待本地额度数据，使用 Claude Code 后自动更新。") }
    var claudeLocalCollection: String { text("Local collection", "本地采集") }
    var claudeLocalMode: String { text("Local first · Online queries are manual", "本地优先 · 网络仅手动补查") }
    var showClaudeQuotaInMenuBar: String { text("Show Claude quota in the menu bar", "在菜单栏显示 Claude 额度") }
    var claudeProxy: String { text("Claude proxy", "Claude 代理") }
    var proxyAddress: String { text("Address", "代理地址") }
    var applyAndRefresh: String { text("Apply proxy", "应用代理") }
    var detectClaudeIP: String { text("Check outbound IP", "检测出口 IP") }
    var detectingClaudeIP: String { text("Checking…", "检测中…") }
    var claudeOutboundIP: String { text("Outbound IP", "出口 IP") }
    var claudeIPCheckHint: String { text("Checks api.anthropic.com using the proxy selected above", "使用上方代理检测 api.anthropic.com") }
    var showGrokQuotaInMenuBar: String { text("Show Grok quota in the menu bar", "在菜单栏显示 Grok 额度") }
    var panelModules: String { text("Modules", "模块") }
    var moveUp: String { text("Move up", "上移") }
    var moveDown: String { text("Move down", "下移") }
    var dragToReorder: String { text("Drag to reorder", "拖动排序") }
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
    var collapseRange: String { text("Hide range", "收起时间范围") }
    var expandRange: String { text("Show range", "选择时间范围") }
    var notRefreshed: String { text("Not refreshed", "尚未刷新") }
    var refreshingQuota: String { text("Refreshing quota", "正在刷新额度") }
    var resetCredits: String { text("Reset credits", "重置卡") }
    var queryResetCredits: String { text("Refresh reset credits", "刷新重置卡") }
    var queryingResetCredits: String { text("Querying reset credits", "正在查询重置卡") }
    var hideResetCredits: String { text("Hide reset credits", "隐藏重置卡") }
    var showResetCredits: String { text("Show reset credits", "显示重置卡") }
    var resetCreditsHidden: String { text("Reset credits hidden", "重置卡已隐藏") }
    var availableResetCredits: String { text("available", "可用") }
    var earliestExpiration: String { text("Earliest", "最早到期") }
    var allResetCredits: String { text("All reset credits", "全部重置卡") }
    var noResetCredits: String { text("No reset credits returned", "没有返回重置卡") }
    var expires: String { text("Expires", "到期") }
    var unsupportedAPIKey: String { text("API key mode does not support subscription quota. Sign in with a ChatGPT subscription.", "API key 模式不支持订阅额度，请使用 ChatGPT 订阅登录。") }
    var codexNotConfigured: String { text("Codex is not configured\ncodex login", "Codex 未配置\ncodex login") }
    var codexNotLoggedIn: String { text("Not signed in. Run codex login", "未登录，请运行 codex login") }
    var hideEmail: String { text("Hide email", "隐藏邮箱") }
    var showEmail: String { text("Show email", "显示邮箱") }
    var unavailable: String { text("unavailable", "不可用") }
    var stale: String { text("stale", "已过期") }
    var today: String { text("Today", "今日") }
    var usage: String { text("Usage", "用量") }
    var sevenDaysShort: String { text("7D", "7 天") }
    var all: String { text("All", "全部") }
    var topModel: String { text("Top Model", "主要模型") }
    var noLocalUsageYet: String { text("No local usage yet", "暂无本地使用记录") }
    var noVisibleModules: String { text("No visible modules", "未显示模块") }
    var days365: String { text("365 Days", "365 天") }
    var less: String { text("Less", "少") }
    var more: String { text("More", "多") }
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
    var model: String { text("Model", "模型") }
    var agent: String { text("Agent", "Agent") }
    var agentUsage: String { text("Agent Usage", "Agent 使用") }
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

    func quotaDisplayStyleTitle(_ style: MenuBarQuotaDisplayStyle) -> String {
        style == .detailed ? text("Detailed", "详细") : text("Compact", "精简")
    }

    var quotaDisplayStyleHelp: String {
        text("Detailed shows the service name in the menu bar; Compact omits it.", "详细在菜单栏显示服务名称，精简省略名称。")
    }

    func languageTitle(_ language: AppLanguage) -> String {
        switch language {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "中文"
        }
    }

    func panelModuleTitle(_ module: PanelModule) -> String {
        switch module {
        case .summary:
            return text("Range summary", "范围摘要")
        case .details:
            return text("Usage details", "用量明细")
        case .trend:
            return text("30 day trend", "30 天趋势")
        case .yearlyTrend:
            return text("Monthly usage this year", "今年各月用量")
        case .codexQuota:
            return text("Codex quota", "Codex 额度")
        case .claudeQuota:
            return claudeQuota
        case .grokQuota:
            return text("Grok quota", "Grok 额度")
        case .heatmap:
            return text("365 day heatmap", "365 天热力图")
        }
    }

    func yearlyTrendTitle(_ year: Int) -> String {
        text("Monthly Usage · \(year)", "\(year) 年各月用量")
    }

    func proxyModeTitle(_ mode: NetworkProxyMode) -> String {
        mode == .system ? text("System", "跟随系统") : text("Manual", "手动代理")
    }

    func claudeMessage(_ message: String) -> String {
        guard language == .simplifiedChinese else { return message }
        switch message {
        case "Sign in to Claude Code with claude auth login.": return "请运行 claude auth login 登录 Claude Code。"
        case "Claude login expired. Open Claude Code or run claude auth login.": return "Claude 登录已过期，请打开 Claude Code 或运行 claude auth login。"
        case "Claude login lacks usage access. Run claude auth login; setup-token is not sufficient.": return "当前登录缺少额度权限，请运行 claude auth login；setup-token 不提供额度权限。"
        case "Allow Keychain access by clicking Refresh Claude quota.": return "请点击网络补查，并允许访问钥匙串。"
        case "Could not configure Claude local collection.": return "无法设置 Claude 本地采集。"
        case "Could not read Claude status line settings.": return "无法读取 Claude 状态栏设置。"
        case "Claude status line settings changed. Re-enable local collection.": return "Claude 状态栏设置已变更，请重新启用本地采集。"
        case "Claude local collector is missing. Rebuild or reinstall AgentBar.": return "缺少本地采集程序，请重新构建或安装 AgentBar。"
        case "Could not read Claude login. Run claude auth login.": return "无法读取 Claude 登录，请运行 claude auth login。"
        case "Claude login changed. Refresh Claude quota.": return "Claude 登录已变更，请刷新额度。"
        case "Waiting for the next Claude quota refresh.": return "等待下一次 Claude 额度刷新。"
        case "Invalid Claude quota response.": return "Claude 额度响应无效。"
        case "This Claude account did not return subscription quota windows.": return "当前 Claude 账号未返回订阅额度窗口。"
        case "Claude quota access denied. Sign in to Claude Code with subscription usage access.": return "Claude 额度访问被拒绝，请使用有订阅额度权限的账号登录 Claude Code。"
        case "Claude quota refresh was rate limited. Waiting before retrying.": return "Claude 额度查询已被限流，正在等待重试。"
        case "Claude quota response was too large.": return "Claude 额度响应过大。"
        case "Could not connect to Claude. Check the network and proxy settings.": return "无法连接 Claude，请检查网络和代理设置。"
        case "Claude IP check did not return a valid IP address.": return "Claude 出口检测未返回有效 IP 地址。"
        case "Could not check Claude's outbound IP. Check the network and proxy settings.": return "无法检测 Claude 出口 IP，请检查网络和代理设置。"
        case "Enter an HTTP, HTTPS or SOCKS5 proxy address with a valid host and port.": return "请输入含主机和有效端口的 HTTP、HTTPS 或 SOCKS5 代理地址。"
        case "Proxy addresses with usernames or passwords are not supported.": return "暂不支持含用户名或密码的代理地址。"
        default:
            if message.hasPrefix("Claude quota request failed (HTTP ") {
                return message.replacingOccurrences(of: "Claude quota request failed", with: "Claude 额度请求失败")
            }
            if message.hasPrefix("Claude IP check failed (HTTP ") {
                return message.replacingOccurrences(of: "Claude IP check failed", with: "Claude 出口 IP 检测失败")
            }
            return message
        }
    }

    func quotaLabel(_ key: CodexQuotaKey) -> String {
        text("Codex \(key.label) quota", "Codex \(key.label) 额度")
    }

    func claudeQuotaLabel(_ key: ClaudeQuotaKey) -> String {
        text("Claude \(key.label) quota", "Claude \(key.label) 额度")
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

    func resetCreditStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "available":
            return text("Available", "可用")
        case "redeemed":
            return text("Redeemed", "已使用")
        case "expired":
            return text("Expired", "已过期")
        default:
            return status
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
        case "Reset credits updated":
            return "重置卡已更新"
        case "Reset credits failed":
            return "重置卡查询失败"
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
