# AgentBar 开发指南

这份文档供 AI coding agent 使用。`AGENTS.md` 和 `CLAUDE.md` 内容保持一致，避免维护两套规则。

## 项目概览

AgentBar 是一个本地优先的 macOS 菜单栏应用，使用 Swift 和 SwiftUI 编写。它会扫描本地 AI 编程助手的使用记录，将归一化后的数据存入 SQLite，估算 token 与费用，显示 Codex 配额状态，并支持 GitHub/Homebrew 更新检查。

Swift Package targets：

- `AgentBar`：macOS SwiftUI 应用、菜单栏 UI、设置页、安装来源检测和更新 UI。
- `AgentBarCore`：扫描、解析、存储、价格、聚合、Codex 配额和认证逻辑。
- `AgentBarCoreTests`：核心逻辑测试。

最低要求：

- macOS 14
- Swift tools 5.9

## 重要文件

```text
Package.swift
build.sh
debug.sh
release.sh
Scripts/build_app.sh
.github/workflows/release.yml
Sources/AgentBar/
Sources/AgentBarCore/
Tests/AgentBarCoreTests/
docs/assets/
```

## 常用命令

在仓库根目录运行：

```bash
swift test
swift build -c release --product AgentBar
./build.sh
./debug.sh
```

发布新版本：

```bash
./release.sh 0.2.0
```

`release.sh` 只负责创建并推送版本 tag。GitHub Actions 会在 tag 推送后构建 app、上传 release assets，并在配置 `TAP_PAT` 后更新 Homebrew cask。

## 架构边界

- 纯数据逻辑放在 `Sources/AgentBarCore`。
- UI、应用状态、设置页、更新检查和 macOS 集成放在 `Sources/AgentBar`。
- 优先扩展现有类型，例如 `AgentBarModel`、`AppSettings`、`UsageAggregator` 和 parser 实现，不要另起一套平行流程。
- `UsageDatabase` 和相关 store 会写入 Application Support。测试应使用临时目录或可注入 store。
- 网络代码应保持小而明确，使用较短 timeout，并确保错误信息适合展示给用户。

## UI 规则

- AgentBar 是紧凑的 macOS 工具，不是营销页。
- 菜单栏面板应信息密度高、易扫读，并尽量减少不同 macOS 版本带来的视觉差异。
- 复用 `AgentBarStyle.swift` 中的卡片、按钮、输入框、分段控件、开关和进度条。
- 除非用户明确要求原生 macOS 外观，否则不要重新引入系统 material、系统 segmented picker、系统 toggle 或系统 progress 样式。
- 菜单栏面板和设置页应保持同一套视觉语言。
- 不要在应用内加入大段功能说明或使用说明；只有错误、状态或必要提示才适合显示在 UI 里。

## 隐私与安全

- 本地使用日志、账号名、认证文件和配额响应都应视为敏感信息。
- 不要记录 access token、account ID、原始配额 payload 或本地使用文件内容。
- 来自外部响应或异常的用户可见错误，应使用 `PrivacyScrubber` 处理。
- 不要添加遥测或远程分析。
- 更新检查会访问 GitHub Releases。配置了凭据时，Codex 配额刷新可能访问 ChatGPT/Codex 接口。

## 测试要求

修改以下内容时，应添加或更新聚焦测试：

- provider parser
- usage aggregation
- SQLite/database 行为
- settings 序列化
- quota parser/client 行为
- privacy scrubbing

交付前至少运行：

```bash
swift test
```

如果改动涉及 app/UI，也运行：

```bash
swift build -c release --product AgentBar
```

## 发布与打包

- `Scripts/build_app.sh` 是本地 release build 和 CI 共用的 app bundle 构建脚本。
- `build.sh` 是 `Scripts/build_app.sh` 的快捷入口。
- `.github/workflows/release.yml` 负责 release 打包和 Homebrew cask 更新。
- 不要把上传 GitHub Release 或 push Homebrew tap 的逻辑重新加回 `release.sh`；发布动作应集中在 CI。

## Git 与文件卫生

- 不要覆盖用户未提交的改动。
- 聚焦当前任务，避免无关重构。
- 不要提交 `.build/`、本地 `.app`、`.zip`、`.dmg` 或包含敏感信息的日志。
- 修改截图时，更新 `docs/assets/` 下的文件，并保持 README 引用路径稳定。
