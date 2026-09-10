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

    func testGrokAuthLoaderRefreshesExpiredTokenAndPersistsRotation() async throws {
        let home = temporaryDirectory()
        let grokHome = home.appendingPathComponent(".grok", isDirectory: true)
        try FileManager.default.createDirectory(at: grokHome, withIntermediateDirectories: true)
        let authURL = grokHome.appendingPathComponent("auth.json")
        let auth = #"{"https://auth.x.ai::client":{"key":"expired-token","auth_mode":"oidc","create_time":"2026-07-31T00:00:00Z","expires_at":"2026-07-31T09:00:00Z","user_id":"user-42","email":"person@example.com","oidc_issuer":"https://auth.x.ai","oidc_client_id":"grok-client","refresh_token":"old-refresh","preserved":"value"}}"#
        try Data(auth.utf8).write(to: authURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)

        let loader = GrokAuthLoader(
            environment: { [:] },
            homeDirectory: { home },
            now: { self.fixedDate("2026-07-31T10:00:00Z") },
            refreshCredentials: { issuer, clientID, refreshToken in
                XCTAssertEqual(issuer, URL(string: "https://auth.x.ai"))
                XCTAssertEqual(clientID, "grok-client")
                XCTAssertEqual(refreshToken, "old-refresh")
                return GrokTokenRefreshResult(
                    accessToken: "fresh-token",
                    refreshToken: "rotated-refresh",
                    expiresIn: 6 * 60 * 60
                )
            }
        )

        let state = await loader.loadRefreshingIfNeeded()

        XCTAssertEqual(
            state,
            .credentials(
                GrokCredentials(
                    accessToken: "fresh-token",
                    userID: "user-42",
                    displayName: "person@example.com"
                )
            )
        )
        let store = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: authURL)) as? [String: Any]
        )
        let record = try XCTUnwrap(store["https://auth.x.ai::client"] as? [String: Any])
        XCTAssertEqual(record["key"] as? String, "fresh-token")
        XCTAssertEqual(record["refresh_token"] as? String, "rotated-refresh")
        XCTAssertEqual(record["expires_at"] as? String, "2026-07-31T16:00:00.000Z")
        XCTAssertEqual(record["preserved"] as? String, "value")
        let attributes = try FileManager.default.attributesOfItem(atPath: authURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testGrokAuthLoaderKeepsFreshTokenWithoutRefresh() async throws {
        let home = temporaryDirectory()
        let grokHome = home.appendingPathComponent(".grok", isDirectory: true)
        try FileManager.default.createDirectory(at: grokHome, withIntermediateDirectories: true)
        let auth = #"{"https://auth.x.ai::client":{"key":"fresh-token","auth_mode":"oidc","create_time":"2026-07-31T00:00:00Z","expires_at":"2026-07-31T16:00:00Z","user_id":"user-42","oidc_issuer":"https://auth.x.ai","oidc_client_id":"grok-client","refresh_token":"refresh"}}"#
        try Data(auth.utf8).write(to: grokHome.appendingPathComponent("auth.json"))

        let loader = GrokAuthLoader(
            environment: { [:] },
            homeDirectory: { home },
            now: { self.fixedDate("2026-07-31T10:00:00Z") },
            refreshCredentials: { _, _, _ in
                XCTFail("A fresh token should not be refreshed")
                return GrokTokenRefreshResult(accessToken: "unused", refreshToken: nil, expiresIn: nil)
            }
        )

        let state = await loader.loadRefreshingIfNeeded()
        XCTAssertEqual(
            state,
            .credentials(GrokCredentials(accessToken: "fresh-token", userID: "user-42", displayName: nil))
        )
    }

    func testGrokAuthLoaderReportsExpiredTokenWhenRefreshFails() async throws {
        let home = temporaryDirectory()
        let grokHome = home.appendingPathComponent(".grok", isDirectory: true)
        try FileManager.default.createDirectory(at: grokHome, withIntermediateDirectories: true)
        let auth = #"{"https://auth.x.ai::client":{"key":"expired-token","auth_mode":"oidc","create_time":"2026-07-31T00:00:00Z","expires_at":"2026-07-31T09:00:00Z","user_id":"user-42","oidc_issuer":"https://auth.x.ai","oidc_client_id":"grok-client","refresh_token":"super-secret-refresh"}}"#
        try Data(auth.utf8).write(to: grokHome.appendingPathComponent("auth.json"))

        let loader = GrokAuthLoader(
            environment: { [:] },
            homeDirectory: { home },
            now: { self.fixedDate("2026-07-31T10:00:00Z") },
            refreshCredentials: { _, _, _ in throw GrokOIDCClientError.requestFailed(400, "invalid_grant") }
        )

        guard case let .invalid(message) = await loader.loadRefreshingIfNeeded() else {
            return XCTFail("Expected an invalid auth state")
        }
        XCTAssertTrue(message.contains("invalid_grant"))
        XCTAssertFalse(message.contains("expired-token"))
        XCTAssertFalse(message.contains("super-secret-refresh"))
    }

    func testGrokOIDCClientDiscoversEndpointAndRefreshesToken() async throws {
        let transport = MockGrokOIDCTransport(responses: [
            (200, #"{"issuer":"https://auth.x.ai","token_endpoint":"https://auth.x.ai/oauth2/token"}"#),
            (200, #"{"access_token":"fresh-token","refresh_token":"rotated-refresh","expires_in":21600}"#)
        ])
        let client = GrokOIDCClient(transport: transport)

        let result = try await client.refresh(
            issuer: URL(string: "https://auth.x.ai")!,
            clientID: "grok-client",
            refreshToken: "old-refresh"
        )

        XCTAssertEqual(
            result,
            GrokTokenRefreshResult(
                accessToken: "fresh-token",
                refreshToken: "rotated-refresh",
                expiresIn: 21_600
            )
        )
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].httpMethod, "GET")
        XCTAssertEqual(transport.requests[0].url?.path, "/.well-known/openid-configuration")
        XCTAssertEqual(transport.requests[1].httpMethod, "POST")
        XCTAssertEqual(transport.requests[1].url?.path, "/oauth2/token")
        let body = try XCTUnwrap(transport.requests[1].httpBody)
        let form = URLComponents(string: "?" + String(decoding: body, as: UTF8.self))
        let values = Dictionary(uniqueKeysWithValues: (form?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(values["grant_type"], "refresh_token")
        XCTAssertEqual(values["client_id"], "grok-client")
        XCTAssertEqual(values["refresh_token"], "old-refresh")
    }

    func testGrokOIDCClientRejectsCrossOriginTokenEndpoint() async throws {
        let transport = MockGrokOIDCTransport(responses: [
            (200, #"{"token_endpoint":"https://example.com/token"}"#)
        ])
        let client = GrokOIDCClient(transport: transport)

        do {
            _ = try await client.refresh(
                issuer: URL(string: "https://auth.x.ai")!,
                clientID: "grok-client",
                refreshToken: "refresh"
            )
            XCTFail("Expected an unsafe endpoint error")
        } catch {
            XCTAssertEqual(error as? GrokOIDCClientError, .unsafeTokenEndpoint)
        }
        XCTAssertEqual(transport.requests.count, 1)
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

private final class MockGrokOIDCTransport: GrokOIDCHTTPTransport, @unchecked Sendable {
    private let responses: [(status: Int, body: String)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Int, String)]) {
        self.responses = responses
    }

    func data(for request: URLRequest, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses[requests.count - 1]
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(response.body.utf8), http)
    }
}
