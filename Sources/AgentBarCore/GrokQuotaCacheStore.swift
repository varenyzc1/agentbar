import Foundation

public struct GrokQuotaCacheRecord: Codable, Equatable, Sendable {
    public let snapshot: GrokQuotaSnapshot
    public let lastNetworkAttemptAt: Date?
    public let cachedAt: Date

    public init(snapshot: GrokQuotaSnapshot, lastNetworkAttemptAt: Date?, cachedAt: Date = Date()) {
        self.snapshot = snapshot
        self.lastNetworkAttemptAt = lastNetworkAttemptAt
        self.cachedAt = cachedAt
    }
}

public struct GrokQuotaCacheStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = support
                .appendingPathComponent("AgentBar", isDirectory: true)
                .appendingPathComponent("grok-quota-cache.json")
        }
    }

    public func load() throws -> GrokQuotaCacheRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(GrokQuotaCacheRecord.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ record: GrokQuotaCacheRecord) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: fileURL, options: .atomic)
    }
}
