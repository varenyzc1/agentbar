import CryptoKit
import Darwin
import Foundation

public struct ClaudeStatuslineStore: Sendable {
    public let configDirectory: URL
    public let homeDirectory: URL
    public var directory: URL { configDirectory.appendingPathComponent("agentbar-statusline") }
    public var snapshotsDirectory: URL { directory.appendingPathComponent("snapshots") }

    public init(configDirectory: URL? = nil, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
        self.configDirectory = configDirectory ?? ClaudeAuthLoader(homeDirectory: homeDirectory).configDirectory
    }

    /// Only a digest leaves the Claude settings file; no credential or account data is stored.
    public var accountIdentity: String? {
        let isDefault = configDirectory.standardizedFileURL == homeDirectory.appendingPathComponent(".claude").standardizedFileURL
        let file = isDefault ? homeDirectory.appendingPathComponent(".claude.json") : configDirectory.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any],
              let id = account["accountUuid"] as? String, !id.isEmpty else { return nil }
        return Self.digest(configDirectory.standardizedFileURL.path + "\n" + id + "\n" + (account["organizationUuid"] as? String ?? ""))
    }

    /// Capture only the documented quota fields. Repainting an unchanged status line does not refresh its age.
    @discardableResult
    public func capture(_ data: Data, now: Date = Date()) throws -> Bool {
        guard data.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let session = root["session_id"] as? String, !session.isEmpty,
              let limits = root["rate_limits"] as? [String: Any] else { return false }
        var windows: [ClaudeQuotaWindow] = []
        for key in ClaudeMenuBarQuotaItem.supportedKeys {
            guard let row = limits[key.rawValue] as? [String: Any],
                  let used = Self.number(row["used_percentage"]), (0...100).contains(used),
                  let reset = Self.number(row["resets_at"]), reset > now.timeIntervalSince1970 else { continue }
            windows.append(.init(key: key, usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset)))
        }
        guard !windows.isEmpty else { return false }
        let snapshot = ClaudeQuotaSnapshot(windows: windows, plan: nil, fetchedAt: now, source: .statusline)
        let cost = root["cost"] as? [String: Any] ?? [:]
        let context = root["context_window"] as? [String: Any] ?? [:]
        let revision = Self.digest([cost["total_api_duration_ms"], context["total_input_tokens"], context["total_output_tokens"]]
            .map { Self.number($0).map { String($0) } ?? "" }.joined(separator: ":"))
        let file = snapshotsDirectory.appendingPathComponent(Self.digest(session) + ".json")
        try FileManager.default.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let lock = open(directory.appendingPathComponent("capture.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { throw ClaudeStatuslineError.storage }
        defer { close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw ClaudeStatuslineError.storage }
        defer { flock(lock, LOCK_UN) }
        let identity = accountIdentity
        if let previousData = try? Data(contentsOf: file), let previous = try? JSONDecoder().decode(Record.self, from: previousData) {
            // A running session must not relabel its old account's values after a login switch.
            guard previous.accountIdentity == identity else { return false }
            if previous.revision == revision && previous.snapshot.windows == windows { return false }
        }
        let record = Record(accountIdentity: identity, revision: revision, snapshot: snapshot)
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        prune(now: now)
        return true
    }

    public func loadLatest(now: Date = Date()) -> ClaudeQuotaSnapshot? {
        let identity = accountIdentity
        return records().filter {
            $0.accountIdentity == identity && $0.snapshot.source == .statusline && $0.snapshot.fetchedAt <= now.addingTimeInterval(5)
        }.map(\.snapshot).max { $0.fetchedAt < $1.fetchedAt }
    }

    private func records() -> [Record] {
        let files = (try? FileManager.default.contentsOfDirectory(at: snapshotsDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap {
            guard let data = try? Data(contentsOf: $0), data.count <= 16_384 else { return nil }
            return try? JSONDecoder().decode(Record.self, from: data)
        }
    }

    private func prune(now: Date) {
        let files = (try? FileManager.default.contentsOfDirectory(at: snapshotsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let sorted = files.filter { $0.pathExtension == "json" }.compactMap { file -> (URL, Date)? in
            guard let data = try? Data(contentsOf: file), let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
            return (file, record.snapshot.fetchedAt)
        }.sorted { $0.1 > $1.1 }
        for (index, entry) in sorted.enumerated() {
            if index >= 32 || now.timeIntervalSince(entry.1) > 7 * 86400 { try? FileManager.default.removeItem(at: entry.0) }
        }
    }

    private struct Record: Codable {
        let accountIdentity: String?
        let revision: String
        let snapshot: ClaudeQuotaSnapshot
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum ClaudeStatuslineError: LocalizedError {
    case storage, invalidSettings, changedSettings, missingHelper
    public var errorDescription: String? {
        switch self {
        case .storage: return "Could not save Claude local quota data."
        case .invalidSettings: return "Could not read Claude status line settings."
        case .changedSettings: return "Claude status line settings changed. Re-enable local collection."
        case .missingHelper: return "Claude local collector is missing. Rebuild or reinstall AgentBar."
        }
    }
}
