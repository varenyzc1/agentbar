import Foundation

public struct ClaudeQuotaRefreshSchedule: Codable, Equatable, Sendable {
    public private(set) var lastAttemptAt: Date?
    public private(set) var retryAfter: Date?
    public private(set) var rateLimitCount = 0

    public init() {}

    public func allowsRequest(at now: Date, interval: TimeInterval, force: Bool) -> Bool {
        if let retryAfter, now < retryAfter { return false }
        return force || lastAttemptAt.map { now.timeIntervalSince($0) >= max(60, interval) } ?? true
    }

    public mutating func recordAttempt(at now: Date) { lastAttemptAt = now }

    public mutating func recordSuccess() {
        retryAfter = nil
        rateLimitCount = 0
    }

    public mutating func recordRateLimit(at now: Date, serverRetryAfter: Date?) {
        rateLimitCount = min(5, rateLimitCount + 1)
        let backoff = min(3600, 300 * pow(2, Double(rateLimitCount - 1)))
        retryAfter = max(now.addingTimeInterval(backoff), serverRetryAfter ?? now)
    }
}

public struct ClaudeQuotaCacheRecord: Codable, Equatable, Sendable {
    public let credentialIdentity: String
    public var snapshot: ClaudeQuotaSnapshot?
    public var schedule: ClaudeQuotaRefreshSchedule

    public init(credentialIdentity: String, snapshot: ClaudeQuotaSnapshot? = nil, schedule: ClaudeQuotaRefreshSchedule = .init()) {
        self.credentialIdentity = credentialIdentity
        self.snapshot = snapshot
        self.schedule = schedule
    }

    public func belongs(to credentials: ClaudeCredentials) -> Bool {
        credentialIdentity == credentials.cacheIdentity
    }
}

public struct ClaudeQuotaCacheStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        self.fileURL = fileURL ?? support.appendingPathComponent("AgentBar/claude-quota-cache.json")
    }

    public func load() throws -> ClaudeQuotaCacheRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(ClaudeQuotaCacheRecord.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ record: ClaudeQuotaCacheRecord) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
