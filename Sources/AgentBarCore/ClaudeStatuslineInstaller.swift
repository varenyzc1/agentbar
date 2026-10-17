import Foundation

public struct ClaudeStatuslineInstaller {
    public let store: ClaudeStatuslineStore
    private var settingsURL: URL { store.configDirectory.appendingPathComponent("settings.json") }
    private var runnerURL: URL { store.directory.appendingPathComponent("run.sh") }
    private var helperURL: URL { store.directory.appendingPathComponent("AgentBarStatusline") }
    private var backupURL: URL { store.directory.appendingPathComponent("original-statusline.json") }
    private var previousURL: URL { store.directory.appendingPathComponent("previous-command.sh") }
    private var command: String { "/bin/sh " + Self.quote(runnerURL.path) }

    public init(store: ClaudeStatuslineStore = .init()) { self.store = store }

    public var isInstalled: Bool {
        guard let settings = try? readSettings(), let entry = settings["statusLine"] as? [String: Any] else { return false }
        return entry["command"] as? String == command && FileManager.default.isExecutableFile(atPath: helperURL.path)
            && FileManager.default.fileExists(atPath: runnerURL.path)
    }

    public func install(helper: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw ClaudeStatuslineError.missingHelper }
        let originalData = try? Data(contentsOf: settingsURL)
        var settings = try readSettings()
        var entry = settings["statusLine"] as? [String: Any] ?? [:]
        if let raw = settings["statusLine"], !(raw is [String: Any]) { throw ClaudeStatuslineError.invalidSettings }
        let alreadyManaged = entry["command"] as? String == command
        if alreadyManaged && !FileManager.default.fileExists(atPath: backupURL.path) { throw ClaudeStatuslineError.invalidSettings }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: store.directory.path)
        if !alreadyManaged {
            let previous = entry["command"] as? String ?? "cat >/dev/null"
            try write(JSONSerialization.data(withJSONObject: ["statusLine": settings["statusLine"] ?? NSNull()], options: [.sortedKeys]), to: backupURL, permissions: 0o600)
            try write(Data((previous + "\n").utf8), to: previousURL, permissions: 0o600)
        }
        if helper.standardizedFileURL != helperURL.standardizedFileURL {
            try write(Data(contentsOf: helper), to: helperURL, permissions: 0o700)
        }
        let runner = """
        #!/bin/sh
        # Managed by AgentBar. Keep the original status line's stdin, stdout and exit status.
        agentbar_payload=$(cat)
        printf '%s' "$agentbar_payload" | \(Self.quote(helperURL.path)) capture --config-dir \(Self.quote(store.configDirectory.path)) >/dev/null 2>&1
        printf '%s' "$agentbar_payload" | /bin/sh \(Self.quote(previousURL.path))
        """
        try write(Data((runner + "\n").utf8), to: runnerURL, permissions: 0o700)
        entry["type"] = "command"
        entry["command"] = command
        settings["statusLine"] = entry
        // Refuse to overwrite a concurrent user edit.
        guard (try? Data(contentsOf: settingsURL)) == originalData else { throw ClaudeStatuslineError.changedSettings }
        try write(JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]), to: settingsURL, permissions: 0o600)
    }

    public func uninstall() throws {
        let originalData = try? Data(contentsOf: settingsURL)
        var settings = try readSettings()
        guard (settings["statusLine"] as? [String: Any])?["command"] as? String == command else { throw ClaudeStatuslineError.changedSettings }
        guard let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: backupURL)) as? [String: Any] else { throw ClaudeStatuslineError.invalidSettings }
        if saved["statusLine"] is NSNull { settings.removeValue(forKey: "statusLine") }
        else { settings["statusLine"] = saved["statusLine"] }
        guard (try? Data(contentsOf: settingsURL)) == originalData else { throw ClaudeStatuslineError.changedSettings }
        try write(JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]), to: settingsURL, permissions: 0o600)
        // Retain the managed files so an already-running status line can finish safely.
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClaudeStatuslineError.invalidSettings }
        return settings
    }

    private func write(_ data: Data, to file: URL, permissions: Int) throws {
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
    }

    private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
