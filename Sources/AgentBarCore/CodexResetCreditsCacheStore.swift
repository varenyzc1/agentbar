import Foundation

public struct CodexResetCreditsCacheRecord: Codable, Equatable, Sendable {
    public let snapshot: CodexResetCreditsSnapshot
    public let cachedAt: Date

    public init(snapshot: CodexResetCreditsSnapshot, cachedAt: Date = Date()) {
        self.snapshot = snapshot
        self.cachedAt = cachedAt
    }
}

public struct CodexResetCreditsCacheStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = support
                .appendingPathComponent("AgentBar", isDirectory: true)
                .appendingPathComponent("codex-reset-credits-cache.json")
        }
    }

    public func load() throws -> CodexResetCreditsCacheRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(CodexResetCreditsCacheRecord.self, from: data)
    }

    public func save(_ record: CodexResetCreditsCacheRecord) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: fileURL, options: .atomic)
    }
}
