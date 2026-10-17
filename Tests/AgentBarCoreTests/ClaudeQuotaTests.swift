import Foundation
import Network
import XCTest
@testable import AgentBarCore

final class ClaudeQuotaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let credentials = ClaudeCredentials(accessToken: "fake-oauth-token", plan: "max")
    private let quotaJSON = #"{"five_hour":{"utilization":24.5,"resets_at":"2030-01-01T08:00:00.123Z"},"seven_day":{"utilization":71,"resets_at":"2030-01-07T08:00:00Z"},"seven_day_sonnet":null}"#

    func testSettingsMigrationAndRoundTripPreserveProxyAndHiddenModule() throws {
        let legacy = Data(#"{"panelModuleLayoutVersion":1,"visiblePanelModules":["summary","codexQuota","heatmap"]}"#.utf8)
        var settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(settings.claudeProxy, NetworkProxySettings())
        XCTAssertEqual(settings.claudeQuotaPercentBasis, .used)
        XCTAssertTrue(settings.claudeMenuBarQuotaItems.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(settings.visiblePanelModules, [.summary, .codexQuota, .claudeQuota, .heatmap])
        settings.visiblePanelModules.removeAll { $0 == .claudeQuota }
        settings.claudeProxy = NetworkProxySettings(mode: .manual, address: "socks5://127.0.0.1:1080")
        settings.claudeMenuBarQuotaItems[0].isEnabled = true
        settings.claudeQuotaPercentBasis = .remaining
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
        XCTAssertFalse(decoded.visiblePanelModules.contains(.claudeQuota))
    }

    func testSettingsStoreRejectsProxySecretsBeforeWriting() throws {
        let file = temporaryDirectory().appendingPathComponent("settings.json")
        let store = AppSettingsStore(fileURL: file)
        let settings = AppSettings(claudeProxy: NetworkProxySettings(mode: .manual, address: "http://name:secret@localhost:8080"))
        XCTAssertThrowsError(try store.save(settings))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testAuthReadsKeychainAndUsesMillisecondsForExpiry() {
        let payload = Data(#"{"claudeAiOauth":{"accessToken":"oauth-test","expiresAt":2000000,"scopes":["user:profile"],"subscriptionType":"pro"}}"#.utf8)
        let loader = ClaudeAuthLoader(environment: { [:] }, now: { Date(timeIntervalSince1970: 1000) }, readKeychain: { service, interaction in
            XCTAssertEqual(service, "Claude Code-credentials")
            XCTAssertFalse(interaction)
            return payload
        })
        XCTAssertEqual(loader.load(), .credentials(ClaudeCredentials(accessToken: "oauth-test", expiresAt: Date(timeIntervalSince1970: 2000), plan: "pro")))
    }

    func testAuthMissingScopeExpiredAndMalformedPayload() {
        let cases: [(String, ClaudeAuthState)] = [
            (#"{"claudeAiOauth":{"accessToken":"fake","scopes":["user:inference"]}}"#, .missingScope),
            (#"{"claudeAiOauth":{"accessToken":"fake","expiresAt":999000}}"#, .expired),
            (#"{"mcpOAuth":{}}"#, .notLoggedIn),
            (#"{"claudeAiOauth":{"accessToken":"bad\nheader"}}"#, .notLoggedIn),
            ("malformed secret", .invalid)
        ]
        for (json, expected) in cases {
            let data = Data(json.utf8)
            let loader = ClaudeAuthLoader(environment: { [:] }, now: { Date(timeIntervalSince1970: 1000) }, readKeychain: { _, _ in data })
            XCTAssertEqual(loader.load(), expected)
        }
    }

    func testAuthFileFallbackAndCustomProfileIsolation() throws {
        let home = temporaryDirectory()
        let profile = home.appendingPathComponent("custom")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let file = profile.appendingPathComponent(".credentials.json")
        let data = Data(#"{"claudeAiOauth":{"accessToken":"custom-account","scopes":["user:profile"]}}"#.utf8)
        try data.write(to: file)
        let loader = ClaudeAuthLoader(environment: { ["CLAUDE_CONFIG_DIR": profile.path] }, homeDirectory: home, readKeychain: { service, interaction in
            XCTAssertTrue(service.hasPrefix("Claude Code-credentials-"))
            XCTAssertEqual(service.count, "Claude Code-credentials-".count + 8)
            XCTAssertTrue(interaction)
            return nil
        })
        XCTAssertEqual(loader.load(allowInteraction: true), .credentials(ClaudeCredentials(accessToken: "custom-account")))
        XCTAssertEqual(try Data(contentsOf: file), data, "Reading credentials must not rotate or overwrite them")
    }

    func testDeniedKeychainDoesNotReadStaleFileOrPromptInBackground() throws {
        let home = temporaryDirectory()
        let config = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try Data(#"{"claudeAiOauth":{"accessToken":"old-account"}}"#.utf8).write(to: config.appendingPathComponent(".credentials.json"))
        let loader = ClaudeAuthLoader(environment: { [:] }, homeDirectory: home, readKeychain: { _, interaction in
            XCTAssertFalse(interaction)
            throw ClaudeKeychainError.accessDenied
        })
        XCTAssertEqual(loader.load(), .keychainAccessRequired)
    }

    func testPresentKeychainDoesNotFallBackToAnotherAccount() throws {
        let home = temporaryDirectory()
        let config = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try Data(#"{"claudeAiOauth":{"accessToken":"old-account"}}"#.utf8).write(to: config.appendingPathComponent(".credentials.json"))
        let loader = ClaudeAuthLoader(environment: { [:] }, homeDirectory: home, readKeychain: { _, _ in Data(#"{"mcpOAuth":{}}"#.utf8) })
        XCTAssertEqual(loader.load(), .notLoggedIn)
    }

    func testParserReadsWindowsWithoutInventingMissingQuota() throws {
        let snapshot = try ClaudeQuotaParser.parse(Data(quotaJSON.utf8), now: now, plan: "max")
        XCTAssertEqual(snapshot.windows.map(\.key), [.fiveHour, .sevenDay])
        XCTAssertEqual(snapshot.windows[0].usedPercent, 24.5)
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 75.5)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertEqual(snapshot.displayPlan, "Claude Max")
        XCTAssertFalse(snapshot.isStale(at: now, interval: 300))
        XCTAssertTrue(snapshot.isStale(at: now.addingTimeInterval(301), interval: 300))
    }

    func testParserHandlesNullResetsAndRejectsInvalidWindowValues() throws {
        let json = #"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":true},"seven_day_opus":{"utilization":150,"resets_at":"bad-date"},"seven_day_sonnet":{"utilization":150}}"#
        let snapshot = try ClaudeQuotaParser.parse(Data(json.utf8), now: now, plan: nil)
        XCTAssertEqual(snapshot.windows.map(\.key), [.fiveHour, .sevenDaySonnet])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [0, 100])
        XCTAssertNil(snapshot.windows[0].resetsAt)
        for invalid in ["{}", #"{"five_hour":null}"#, #"{"five_hour":{"utilization":"unknown"}}"#] {
            XCTAssertThrowsError(try ClaudeQuotaParser.parse(Data(invalid.utf8), now: now, plan: nil))
        }
    }

    func testExpiredWindowsAreStaleWithoutResettingTheirMeasurement() {
        let window = ClaudeQuotaWindow(key: .fiveHour, usedPercent: 90, resetsAt: now)
        XCTAssertTrue(window.isExpired(at: now))
        XCTAssertEqual(window.usedPercent, 90)
        XCTAssertEqual(window.remainingPercent, 10)
        let snapshot = ClaudeQuotaSnapshot(windows: [window], plan: nil, fetchedAt: now)
        XCTAssertTrue(snapshot.isStale(at: now, interval: 300))
    }

    func testClientUsesOAuthHeadersAndPassesManualProxy() async throws {
        let transport = ClaudeTestTransport(status: 200, body: quotaJSON)
        let client = ClaudeQuotaClient(transport: transport, now: { Date(timeIntervalSince1970: 1000) })
        let proxy = NetworkProxySettings(mode: .manual, address: "http://127.0.0.1:7890")
        let result = try await client.fetch(credentials: credentials, proxy: proxy)
        let captured = await transport.captured()
        XCTAssertEqual(captured.0?.url, ClaudeQuotaClient.endpoint)
        XCTAssertEqual(captured.0?.httpMethod, "GET")
        XCTAssertEqual(captured.0?.value(forHTTPHeaderField: "Authorization"), "Bearer fake-oauth-token")
        XCTAssertEqual(captured.0?.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(captured.0?.timeoutInterval, 8)
        XCTAssertEqual(captured.1, proxy)
        XCTAssertEqual(captured.2, ClaudeQuotaClient.bodyLimit)
        XCTAssertEqual(result.fetchedAt, now)
    }

    func testClientRejectsInvalidProxyBeforeSendingCredentials() async {
        let transport = ClaudeTestTransport(status: 200, body: quotaJSON)
        do {
            _ = try await ClaudeQuotaClient(transport: transport).fetch(credentials: credentials, proxy: .init(mode: .manual, address: "bad"))
            XCTFail("Invalid proxy must not send a request")
        } catch { XCTAssertEqual(error as? NetworkProxyError, .invalidAddress) }
        let captured = await transport.captured()
        XCTAssertNil(captured.0)
    }

    func testHTTPFailuresNeverExposeResponsePayload() async {
        for (status, expected) in [(401, ClaudeQuotaClientError.tokenExpired), (403, .forbidden), (500, .httpStatus(500))] {
            let transport = ClaudeTestTransport(status: status, body: #"{"error":"accessToken=secret account_id=private email=private@example.com"}"#)
            do {
                _ = try await ClaudeQuotaClient(transport: transport).fetch(credentials: credentials)
                XCTFail("Expected failure")
            } catch {
                XCTAssertEqual(error as? ClaudeQuotaClientError, expected)
                XCTAssertFalse(error.localizedDescription.contains("secret"))
                XCTAssertFalse(error.localizedDescription.contains("private"))
            }
        }
    }

    func testTransportErrorsDoNotExposeProxyCredentials() async {
        do {
            _ = try await ClaudeQuotaClient(transport: ClaudeFailingTransport()).fetch(credentials: credentials)
            XCTFail("Expected network failure")
        } catch {
            XCTAssertEqual(error as? ClaudeQuotaClientError, .network)
            XCTAssertFalse(error.localizedDescription.contains("proxy-secret"))
        }
    }

    func testRedirectsCannotForwardOAuthCredentials() throws {
        let request = URLRequest(url: URL(string: "https://unexpected.example/usage")!)
        let response = HTTPURLResponse(url: ClaudeQuotaClient.endpoint, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: ClaudeQuotaClient.endpoint)
        var completionCalled = false
        ClaudeQuotaRedirectGuard().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { redirected in
            completionCalled = true
            XCTAssertNil(redirected)
        }
        XCTAssertTrue(completionCalled)
    }

    func testRateLimitResponseRespectsRetryAfterSecondsAndDates() async {
        let transport = ClaudeTestTransport(status: 429, body: "", headers: ["Retry-After": "600"])
        let client = ClaudeQuotaClient(transport: transport, now: { Date(timeIntervalSince1970: 1000) })
        do {
            _ = try await client.fetch(credentials: credentials)
            XCTFail("Expected rate limit")
        } catch {
            XCTAssertEqual(error as? ClaudeQuotaClientError, .rateLimited(retryAfter: now.addingTimeInterval(600)))
        }
        XCTAssertEqual(ClaudeQuotaClient.retryAfter("Thu, 01 Jan 1970 01:00:00 GMT", now: now), Date(timeIntervalSince1970: 3600))
        XCTAssertNil(ClaudeQuotaClient.retryAfter("invalid", now: now))
        XCTAssertNil(ClaudeQuotaClient.retryAfter("nan", now: now))
    }

    func testRefreshScheduleThrottlesAutoRefreshAndCannotForcePast429() throws {
        var schedule = ClaudeQuotaRefreshSchedule()
        XCTAssertTrue(schedule.allowsRequest(at: now, interval: 300, force: false))
        schedule.recordAttempt(at: now)
        XCTAssertFalse(schedule.allowsRequest(at: now.addingTimeInterval(59), interval: 30, force: false))
        XCTAssertTrue(schedule.allowsRequest(at: now.addingTimeInterval(60), interval: 30, force: false))
        schedule.recordRateLimit(at: now, serverRetryAfter: now.addingTimeInterval(1200))
        XCTAssertFalse(schedule.allowsRequest(at: now.addingTimeInterval(1199), interval: 60, force: true))
        XCTAssertTrue(schedule.allowsRequest(at: now.addingTimeInterval(1200), interval: 60, force: true))
        let decoded = try JSONDecoder().decode(ClaudeQuotaRefreshSchedule.self, from: JSONEncoder().encode(schedule))
        XCTAssertEqual(decoded, schedule)
        schedule.recordSuccess()
        XCTAssertNil(schedule.retryAfter)
        XCTAssertEqual(schedule.rateLimitCount, 0)
    }

    func testRateLimitWithoutRetryAfterUsesExponentialBackoff() {
        var schedule = ClaudeQuotaRefreshSchedule()
        schedule.recordRateLimit(at: now, serverRetryAfter: now)
        XCTAssertEqual(schedule.retryAfter, now.addingTimeInterval(300))
        schedule.recordRateLimit(at: now, serverRetryAfter: nil)
        XCTAssertEqual(schedule.retryAfter, now.addingTimeInterval(600))
    }

    func testCachePersistsCooldownAndRejectsOtherCredentials() throws {
        let file = temporaryDirectory().appendingPathComponent("quota.json")
        let store = ClaudeQuotaCacheStore(fileURL: file)
        let snapshot = try ClaudeQuotaParser.parse(Data(quotaJSON.utf8), now: now, plan: "max")
        var schedule = ClaudeQuotaRefreshSchedule()
        schedule.recordRateLimit(at: now, serverRetryAfter: nil)
        let record = ClaudeQuotaCacheRecord(credentialIdentity: credentials.cacheIdentity, snapshot: snapshot, schedule: schedule)
        try store.save(record)
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored, record)
        XCTAssertTrue(restored.belongs(to: credentials))
        XCTAssertFalse(restored.belongs(to: ClaudeCredentials(accessToken: "another-account")))
        XCTAssertFalse(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains(credentials.accessToken))
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testSystemProxyIsUntouchedAndManualProxyDisallowsFailover() throws {
        let system = try URLSessionClaudeQuotaTransport.makeConfiguration()
        XCTAssertNil(system.connectionProxyDictionary)
        XCTAssertTrue(system.proxyConfigurations.isEmpty)
        for address in ["http://127.0.0.1:7890", "https://proxy.example:443", "socks5://127.0.0.1:1080", "127.0.0.1:7890", "http://[::1]:7890"] {
            let config = try URLSessionClaudeQuotaTransport.makeConfiguration(proxy: .init(mode: .manual, address: address))
            XCTAssertEqual(config.proxyConfigurations.count, 1)
            XCTAssertFalse(try XCTUnwrap(config.proxyConfigurations.first).allowFailover)
        }
    }

    func testInvalidProxyAddressesAreRejectedWithoutEchoingSecrets() {
        for address in ["", "localhost", "ftp://localhost:20", "http://localhost:0", "http://localhost:65536", "http://localhost:8080/path", "http://localhost:8080?q=secret", "http://user:secret@localhost:8080", "http://localhost:8080#secret"] {
            XCTAssertThrowsError(try NetworkProxySettings(mode: .manual, address: address).validate()) { error in
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
        }
    }

    func testManualHTTPProxyReceivesConnectWithoutOAuthHeader() async throws {
        let ready = expectation(description: "Local proxy ready")
        let received = expectation(description: "CONNECT received")
        let listener = try NWListener(using: .tcp, on: .any)
        let captured = ClaudeTestCapture()
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                captured.set(data.map { String(decoding: $0, as: UTF8.self) } ?? "")
                received.fulfill()
                connection.send(content: Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .global())
        defer { listener.cancel() }
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        var request = URLRequest(url: URL(string: "https://quota.invalid/api/oauth/usage")!)
        request.setValue("Bearer proxy-test-secret", forHTTPHeaderField: "Authorization")
        do {
            _ = try await URLSessionClaudeQuotaTransport().data(for: request, proxy: .init(mode: .manual, address: "http://127.0.0.1:\(port.rawValue)"), bodyLimit: 1024)
        } catch { /* The local proxy deliberately rejects the tunnel; no external server is contacted. */ }
        await fulfillment(of: [received], timeout: 5)
        XCTAssertTrue(captured.get().hasPrefix("CONNECT quota.invalid:443 HTTP/1.1"))
        XCTAssertFalse(captured.get().contains("proxy-test-secret"))
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private actor ClaudeTestTransport: ClaudeQuotaHTTPTransport {
    let status: Int
    let body: String
    let headers: [String: String]
    private var request: URLRequest?
    private var proxy: NetworkProxySettings?
    private var bodyLimit: Int?

    init(status: Int, body: String, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }

    func data(for request: URLRequest, proxy: NetworkProxySettings, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        self.proxy = proxy
        self.bodyLimit = bodyLimit
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }

    func captured() -> (URLRequest?, NetworkProxySettings?, Int?) { (request, proxy, bodyLimit) }
}

private struct ClaudeFailingTransport: ClaudeQuotaHTTPTransport {
    func data(for request: URLRequest, proxy: NetworkProxySettings, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        throw NSError(domain: NSURLErrorDomain, code: -1004, userInfo: [NSLocalizedDescriptionKey: "Cannot connect to http://user:proxy-secret@proxy.example:8080"])
    }
}

private final class ClaudeTestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    func set(_ value: String) { lock.lock(); defer { lock.unlock() }; self.value = value }
    func get() -> String { lock.lock(); defer { lock.unlock() }; return value }
}
