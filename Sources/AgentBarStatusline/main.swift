import AgentBarCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let configIndex = arguments.firstIndex(of: "--config-dir")
let directory = configIndex.flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1], isDirectory: true) : nil }
let store = ClaudeStatuslineStore(configDirectory: directory)
do {
    switch arguments.first {
    case "capture":
        var data = Data()
        while data.count <= 1_048_576 {
            let chunk = FileHandle.standardInput.readData(ofLength: 8192)
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        _ = try store.capture(data)
    case "install":
        try ClaudeStatuslineInstaller(store: store).install(helper: URL(fileURLWithPath: CommandLine.arguments[0]))
        print("Claude local collection enabled.")
    case "uninstall":
        try ClaudeStatuslineInstaller(store: store).uninstall()
        print("Claude original status line restored.")
    default:
        print("Usage: AgentBarStatusline capture|install|uninstall [--config-dir path]")
        exit(64)
    }
} catch {
    // Capture errors must never leak session data into Claude Code's footer.
    if arguments.first != "capture" { fputs("Claude local collector setup failed.\n", stderr) }
    exit(1)
}
