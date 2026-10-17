<p align="center">
  <img src="docs/assets/agentbar-icon.png" alt="AgentBar 图标" width="96" height="96">
</p>

<h1 align="center">AgentBar</h1>

<p align="center">
  <a href="README.md">English</a>
</p>

AgentBar 是一个本地优先的 macOS 菜单栏应用，用来查看 AI 编程助手的使用量。它会扫描你 Mac 上的本地使用记录，估算 token 和费用，并把本地使用量与 Codex 配额进度显示在菜单栏里。

<img src="docs/assets/agentbar-dashboard.png" alt="AgentBar 主界面" width="420">

## 为什么用 AgentBar

- 不打开网页，也能看到今日、近 7 天和全部 AI 编程使用量。
- 在菜单栏追踪 Codex 5 小时和 7 天滚动配额窗口。
- 基于本地 token 记录估算费用，并支持配置预算。
- 数据本地优先。AgentBar 会把归一化后的记录存到你 Mac 上的 SQLite 数据库。
- 支持 Homebrew 安装、下载 Release 包，或从源码构建。

## 安装

### Homebrew

```bash
brew tap varenyzc1/agentbar
brew install --cask agentbar
```

升级到最新版本：

```bash
brew update && brew upgrade --cask agentbar
```

AgentBar 可以识别 Homebrew 安装方式。检查到新版本时，设置页可以打开一个基于 Terminal 的 Homebrew 更新流程。

### GitHub Release

1. 打开项目的 **Releases** 页面。
2. 下载最新版本里的 `AgentBar-macos.zip`。
3. 解压后把 `AgentBar.app` 移到 `/Applications`。
4. 启动 AgentBar。

如果 macOS 提示应用已损坏，或设置窗口无法打开，可以移除隔离标记后重新启动：

```bash
xattr -cr /Applications/AgentBar.app
```

### 从源码构建

环境要求：

- macOS 14 或更新版本
- Xcode Command Line Tools
- Swift 5.9 或更新版本

```bash
git clone https://github.com/varenyzc1/agentbar.git
cd agentbar
./build.sh
open .build/AgentBar.app
```

## 功能

<img src="docs/assets/agentbar-menu-bar.png" alt="AgentBar 菜单栏" width="220">

- 支持配额、提醒、本地使用量等菜单栏显示模式。
- 显示 Codex 5 小时和 7 天滚动窗口配额。
- 汇总今日、近 7 天和全部使用量。
- 在用量摘要卡片底层显示折线趋势，用来观察时间和用量变化。
- 按来源展示使用量，例如 Codex、Claude Code。
- 365 天活动热力图，并带有 GitHub 风格的错峰打开动画。
- 可在设置页切换英文和简体中文界面。
- 基于价格表估算费用，并支持预算设置。
- 支持手动扫描、费用重算、价格重置和开机启动。
- 显示当前版本，并可检查 GitHub Releases 中的新版本。

## 设置

设置页可以配置菜单栏显示内容、界面语言、刷新行为、开机启动、token 与费用预算、维护操作和更新检查。

<img src="docs/assets/agentbar-settings.png" alt="AgentBar 设置" width="560">

## 工作原理

AgentBar 会读取支持的编程助手在本地生成的使用记录，从中解析 provider、model、token 和时间信息，然后把归一化后的记录写入本地 SQLite 数据库。应用基于这些记录计算汇总区间和滚动窗口，再结合模型价格表估算费用，最后通过轻量的 SwiftUI 菜单栏界面展示。

配额信息和本地使用量是分开的。可用时，AgentBar 会通过网络刷新配额状态并缓存在本地，这样菜单栏在两次刷新之间也能保持可用。

在“设置 → 菜单栏”中，Codex 和 Claude 的 **5h**、**7d** 额度均可独立选择是否显示、已用／剩余和**详细／精简**。详细包含服务名称（如 `Claude 5h 25%`），精简省略名称（`5h 25%`）；Grok 也支持详细／精简。旧版 Claude 的显示设置会迁移到两个额度窗口。

同一服务的名称只在第一个可见的“详细”项目中显示一次。同一服务的额度窗口用空格分隔，不同服务之间用 `·` 分隔，例如 `Codex 5h 25% 7d 40% · Claude 5h 25% 7d 40%`。

### Claude 订阅额度

默认从 Claude Code 的官方 `statusLine` 数据获取 5 小时和每周额度。在“设置 → Claude 额度”点击“启用采集”，再正常使用 Claude Code；订阅额度字段通常在收到 API 响应后出现。AgentBar 会包装现有状态栏命令，保留其输入、输出和其他配置；点击“停用采集”可恢复原设置。采集程序随应用打包，也可用 `swift run AgentBarStatusline install` 安装。

采集仅保存额度、重置时间、采集时间及用于隔离会话／账号的摘要，文件位于 Claude 配置目录的 `agentbar-statusline/`。AgentBar 每 5 秒检查本地数据，不发起 Claude 额度请求、不读取钥匙串。无新响应时显示缓存；状态栏重复重绘不会延长数据的新鲜度，过期窗口不会假定恢复满额。

需要主动获取最新数据或 Sonnet／Opus 专属周额度时，点击“网络补查”。只有此操作会读取 Claude Code 的 OAuth 凭据并访问额度接口，可能需要钥匙串授权，并遵守已有的 429 冷却策略。应用不会轮换或覆盖凭据；登录过期时运行 `claude auth login`。普通扫描、刷新和保存代理均不会触发网络补查。

Claude 请求默认跟随 macOS 系统代理。在“设置 → Claude 代理”中选择“手动代理”，填写含端口的 HTTP、HTTPS 或 SOCKS5 地址（例如 `http://127.0.0.1:7890`），点击“应用代理”。该设置只影响 Claude 额度请求和出口 IP 检测。暂不支持在地址中填写代理用户名或密码；手动代理失败时不会回退为直连。Claude 网络额度查询仅在手动补查时执行。

“检测出口 IP”会使用表单中当前选择的代理，可在应用设置前先测试。检测通过与额度查询相同的网络配置访问 `https://api.anthropic.com/cdn-cgi/trace`，显示该域名在检测时看到的 IPv4 或 IPv6 出口地址。无需登录，不发送 OAuth 凭据，不保存 IP；修改代理后清除旧结果。该诊断接口可能变化，检测成功不代表额度查询已获授权。

OAuth 额度接口不是有公开契约保障的 API，可能发生变化。缓存与当前凭据绑定；额度窗口过期后等待新数据，不会假定额度已恢复到满额。

## 隐私

AgentBar 以本地扫描和本地存储为基础，不需要服务器来计算本地使用量。

会用到网络的场景包括：

- 配置后刷新 Codex 配额。
- 点击“网络补查”时，通过 Claude Code 登录查询 Claude 订阅额度。
- 点击检测按钮时，查询 Claude 出口 IP。
- 检查 GitHub Releases 中的新版本。
- 当你选择更新 Homebrew 安装的应用时，执行 Homebrew 更新。

分享截图时请注意，账号、使用量、配额时间和本地路径可能会出现在界面中。

## 开发

运行测试：

```bash
swift test
```

运行本地调试版本：

```bash
./debug.sh
```

构建 release app bundle：

```bash
./build.sh
```

仓库结构：

```text
.
├── Package.swift                  Swift package manifest
├── build.sh                       本地 release app bundle 快捷入口
├── debug.sh                       本地调试启动脚本
├── release.sh                     创建并推送版本 tag，触发 CI
├── LICENSE
├── README.md
├── README.zh-CN.md
├── .github/
│   └── workflows/
│       └── release.yml            CI、release 打包、Homebrew cask 更新
├── Scripts/
│   └── build_app.sh               本地和 CI 共用的 app bundle 构建脚本
├── Sources/
│   ├── AgentBar/                  SwiftUI 应用、菜单栏界面、设置、更新
│   └── AgentBarCore/              扫描、解析、存储、价格、聚合逻辑
├── Tests/
│   └── AgentBarCoreTests/         核心逻辑测试
└── docs/
    └── assets/                    README 截图
```

## 发布流程

影响 app 或 package 的改动合并到 `main` 后会自动发布。`Auto Release` workflow 会创建下一个 `vX.Y.Z` tag，并启动 release workflow。CI 会运行测试、构建 app bundle、上传 `AgentBar-macos.zip` 和 `AgentBar-macos.dmg` 到 GitHub Releases，并在配置 `TAP_PAT` 后更新 Homebrew cask。

### 日常开发

1. 修改代码后提交并推送：

   ```bash
   git add .
   git commit -m "你的提交信息"
   git push
   ```

   也可以在 VSCode 源代码管理面板操作：暂存更改（⊕）、输入提交信息、提交（✔）、同步（⇄）。

2. 提交前建议先跑测试：

   ```bash
   swift test
   ```

3. 本地调试运行：

   ```bash
   ./debug.sh
   ```

### 发布新版本

1. 合并前运行测试：

   ```bash
   swift test
   ```

2. 将 pull request 合并到 `main`。

   `Auto Release` workflow 会先检查这次合并是否改动了 `Sources/` 或 `Package.swift`。若有相关改动，它会根据最近一个 release tag 之后的提交信息推断版本升级方式：

   - `BREAKING CHANGE:` 或 `feat!:` 这类 `!` 标记会升级 major 版本。
   - `feat:` 会升级 minor 版本。
   - 其他提交默认升级 patch 版本。

   如果要跳过自动发布，在 merge commit 信息里加入 `[skip release]` 或 `[no release]`。

3. CI 自动完成：

   - 运行测试
   - 构建 `.app` bundle
   - 打包 `AgentBar-macos.zip` 和 `AgentBar-macos.dmg`
   - 创建 GitHub Release 并上传产物
   - 更新 Homebrew cask（需配置 `TAP_PAT` secret）

4. 在 GitHub 仓库页面的 **Actions** 查看构建进度。构建完成后，**Releases** 页面会出现可下载的 dmg 和 zip 文件。

如需手动发布，可以创建并推送版本 tag：

```bash
./release.sh 0.2.0
```

这会创建 `v0.2.0` tag 并推送到 GitHub，然后启动同一个 release workflow。

## 参与贡献

欢迎提交 issue 和 pull request。提交 PR 前建议运行：

```bash
swift test
./build.sh
```

如果改动涉及界面，请在 PR 中附上截图，或简单说明菜单栏面板/设置页发生了哪些变化。

## 致谢

- [varenyzc](https://github.com/varenyzc1/agentbar)
- [ZengWenJian123](https://github.com/ZengWenJian123)

## License

Apache License 2.0。详见 [LICENSE](LICENSE)。
