import XCTest
@testable import AgentBarCore

final class GrokSupportTests: XCTestCase {
    func testGrokDisplaySettingsMigrateAndRoundTrip() throws {
        let migrated = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(migrated.grokQuotaPercentBasis, .used)
        XCTAssertFalse(migrated.grokMenuBarShowsQuota)

        let settings = AppSettings(
            grokQuotaPercentBasis: .remaining,
            grokMenuBarShowsQuota: true
        )
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.grokQuotaPercentBasis, .remaining)
        XCTAssertTrue(decoded.grokMenuBarShowsQuota)
    }

    func testGrokBuildParserReadsTurnUsageAndSplitsOverlappingBuckets() throws {
        let home = temporaryDirectory()
        let sessionDirectory = home
            .appendingPathComponent(".grok/sessions/%2Ftmp%2Fwork%2Fagentbar/session-1", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        try Data(#"{"info":{"id":"session-1","cwd":"/tmp/work/agentbar"},"current_model_id":"grok-4.5"}"#.utf8)
            .write(to: sessionDirectory.appendingPathComponent("summary.json"))
        let update = #"{"timestamp":1785482400,"method":"_x.ai/session/update","params":{"sessionId":"session-1","update":{"sessionUpdate":"turn_completed","prompt_id":"prompt-1","stop_reason":"end_turn","usage":{"inputTokens":100,"outputTokens":50,"cachedReadTokens":30,"cacheCreationTokens":10,"reasoningTokens":20,"modelCalls":1,"modelUsage":{"grok-4.5":{"inputTokens":100,"outputTokens":50,"cachedReadTokens":30,"cacheCreationTokens":10,"reasoningTokens":20,"modelCalls":1}}}}}}"#
        let updatesURL = sessionDirectory.appendingPathComponent("updates.jsonl")
        try Data((update + "\n").utf8).write(to: updatesURL)

        let parser = GrokBuildParser(environment: { [:] }, homeDirectory: home)
        let entries = try parser.parseFile(at: updatesURL, fromOffset: nil)

        XCTAssertTrue(parser.shouldParseFile(updatesURL))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].source, "grok-build")
        XCTAssertEqual(entries[0].model, "grok-4.5")
        XCTAssertEqual(entries[0].project, "agentbar")
        XCTAssertEqual(entries[0].inputTokens, 60)
        XCTAssertEqual(entries[0].cachedInputTokens, 30)
        XCTAssertEqual(entries[0].cacheCreationInputTokens, 10)
        XCTAssertEqual(entries[0].outputTokens, 30)
        XCTAssertEqual(entries[0].reasoningOutputTokens, 20)
        XCTAssertEqual(entries[0].totalTokens, 150)
    }

    func testGrokBuildParserExcludesNestedSubagentSessions() throws {
        let home = temporaryDirectory()
        let child = home.appendingPathComponent(".grok/sessions/cwd/session/subagents/child/updates.jsonl")
        try FileManager.default.createDirectory(at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: child)

        let parser = GrokBuildParser(environment: { [:] }, homeDirectory: home)
        XCTAssertFalse(parser.shouldParseFile(child))
    }

    func testGrokAuthLoaderUsesGrokHomeAndSelectsFirstPartySession() throws {
        let home = temporaryDirectory()
        let grokHome = home.appendingPathComponent("custom-grok", isDirectory: true)
        try FileManager.default.createDirectory(at: grokHome, withIntermediateDirectories: true)
        let auth = #"{"xai::api_key":{"key":"api-secret","auth_mode":"api_key","create_time":"2026-01-01T00:00:00Z","user_id":"api"},"https://auth.x.ai::client":{"key":"oauth-secret","auth_mode":"oidc","create_time":"2026-07-31T00:00:00Z","user_id":"user-42","email":"person@example.com","oidc_issuer":"https://auth.x.ai"}}"#
        try Data(auth.utf8).write(to: grokHome.appendingPathComponent("auth.json"))

        let loader = GrokAuthLoader(
            environment: { ["GROK_HOME": grokHome.path] },
            homeDirectory: { home }
        )

        XCTAssertEqual(loader.authURL(), grokHome.appendingPathComponent("auth.json"))
        XCTAssertEqual(
            loader.load(),
            .credentials(GrokCredentials(accessToken: "oauth-secret", userID: "user-42", displayName: "person@example.com"))
        )
    }

    func testGrokAuthLoaderReportsAPIKeyOnlyAsUnsupported() throws {
        let home = temporaryDirectory()
        let grokHome = home.appendingPathComponent(".grok", isDirectory: true)
        try FileManager.default.createDirectory(at: grokHome, withIntermediateDirectories: true)
        let auth = #"{"xai::api_key":{"key":"api-secret","auth_mode":"api_key","create_time":"2026-01-01T00:00:00Z","user_id":"api"}}"#
        try Data(auth.utf8).write(to: grokHome.appendingPathComponent("auth.json"))

        let loader = GrokAuthLoader(environment: { [:] }, homeDirectory: { home })
        XCTAssertEqual(loader.load(), .unsupportedAPIKey)
    }

    func testGrokQuotaParserSupportsCurrentWeeklyCreditsShape() throws {
        let now = fixedDate("2026-07-31T10:00:00Z")
        let body = #"{"config":{"creditUsagePercent":42.5,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-27T00:00:00Z","end":"2026-08-03T00:00:00Z"},"monthlyLimit":{"val":2000},"used":{"val":850},"prepaidBalance":{"val":100},"productUsage":[{"product":"PRODUCT_CHAT","usagePercent":12.5},{"product":"PRODUCT_GROK_BUILD","usagePercent":30}]}}"#

        let snapshot = try GrokQuotaParser.parse(
            Data(body.utf8),
            now: now,
            source: "test",
            accountDisplayName: "person@example.com"
        )

        XCTAssertEqual(snapshot.periodLabel, "Weekly")
        XCTAssertEqual(snapshot.usedPercent, 42.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.remainingPercent, 57.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.includedCents, 2000)
        XCTAssertEqual(snapshot.usedCents, 850)
        XCTAssertEqual(snapshot.prepaidBalanceCents, 100)
        XCTAssertEqual(
            snapshot.productUsage,
            [
                GrokQuotaProductUsage(product: "PRODUCT_GROK_BUILD", usagePercent: 30),
                GrokQuotaProductUsage(product: "PRODUCT_CHAT", usagePercent: 12.5)
            ]
        )
        XCTAssertEqual(snapshot.accountDisplayName, "person@example.com")
    }

    func testGrokQuotaParserFallsBackToProductUsageTotal() throws {
        let body = #"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-03T00:00:00Z"},"productUsage":[{"product":"PRODUCT_API","usagePercent":9},{"product":"PRODUCT_GROK_BUILD","usagePercent":21}]}}"#
        let snapshot = try GrokQuotaParser.parse(
            Data(body.utf8),
            now: fixedDate("2026-07-31T10:00:00Z"),
            source: "test",
            accountDisplayName: nil
        )

        XCTAssertEqual(snapshot.usedPercent, 30, accuracy: 0.001)
        XCTAssertEqual(snapshot.productUsage.count, 2)
    }

    func testGrokQuotaParserFallsBackToLegacyMonthlyFields() throws {
        let body = #"{"config":{"monthlyLimit":{"val":2000},"used":{"val":500},"billingPeriodEnd":"2026-08-31T00:00:00Z"}}"#
        let snapshot = try GrokQuotaParser.parse(
            Data(body.utf8),
            now: fixedDate("2026-07-31T10:00:00Z"),
            source: "test",
            accountDisplayName: nil
        )
        XCTAssertEqual(snapshot.periodLabel, "Monthly")
        XCTAssertEqual(snapshot.usedPercent, 25, accuracy: 0.001)
    }

    func testGrokQuotaClientBuildsOfficialBillingRequest() async throws {
        let body = #"{"config":{"creditUsagePercent":10,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-03T00:00:00Z"}}}"#
        let transport = MockGrokQuotaTransport(body: body, status: 200)
        let client = GrokQuotaClient(
            transport: transport,
            now: { self.fixedDate("2026-07-31T10:00:00Z") }
        )

        _ = try await client.fetch(
            credentials: GrokCredentials(accessToken: "secret-token", userID: "user-42", displayName: nil)
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url, GrokQuotaClient.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-XAI-Token-Auth"), "xai-grok-cli")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-userid"), "user-42")
    }

    func testGrokQuotaCacheRoundTrips() throws {
        let fileURL = temporaryDirectory().appendingPathComponent("grok-quota.json")
        let snapshot = GrokQuotaSnapshot(
            periodType: "USAGE_PERIOD_TYPE_WEEKLY",
            usedPercent: 30,
            resetsAt: fixedDate("2026-08-03T00:00:00Z"),
            includedCents: nil,
            usedCents: nil,
            prepaidBalanceCents: nil,
            productUsage: [GrokQuotaProductUsage(product: "PRODUCT_GROK_BUILD", usagePercent: 30)],
            accountDisplayName: nil,
            fetchedAt: fixedDate("2026-07-31T10:00:00Z"),
            source: "test"
        )
        let store = GrokQuotaCacheStore(fileURL: fileURL)
        let record = GrokQuotaCacheRecord(snapshot: snapshot, lastNetworkAttemptAt: snapshot.fetchedAt)
        try store.save(record)
        XCTAssertEqual(try store.load()?.snapshot, snapshot)
    }

    func testGrokQuotaSnapshotDecodesCacheWithoutProductUsage() throws {
        let snapshot = GrokQuotaSnapshot(
            periodType: "USAGE_PERIOD_TYPE_WEEKLY",
            usedPercent: 30,
            resetsAt: fixedDate("2026-08-03T00:00:00Z"),
            includedCents: nil,
            usedCents: nil,
            prepaidBalanceCents: nil,
            accountDisplayName: nil,
            fetchedAt: fixedDate("2026-07-31T10:00:00Z"),
            source: "test"
        )
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        )
        legacy.removeValue(forKey: "productUsage")

        let decoded = try JSONDecoder().decode(
            GrokQuotaSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertTrue(decoded.productUsage.isEmpty)
        XCTAssertEqual(decoded.usedPercent, 30, accuracy: 0.001)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func fixedDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private final class MockGrokQuotaTransport: GrokQuotaHTTPTransport, @unchecked Sendable {
    private let body: String
    private let status: Int
    private(set) var requests: [URLRequest] = []

    init(body: String, status: Int) {
        self.body = body
        self.status = status
    }

    func data(for request: URLRequest, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}
