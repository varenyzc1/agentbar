import XCTest
@testable import AgentBarCore

final class CodexQuotaTests: XCTestCase {
    func testAuthLoaderUsesCodexHomeAndExtractsDisplayName() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let idToken = try jwt(payload: ["sub": "user@example.com"])
        let auth = """
        {
          "OPENAI_API_KEY": "",
          "tokens": {
            "access_token": "access-token",
            "id_token": "\(idToken)",
            "account_id": "acct_123"
          }
        }
        """
        try Data(auth.utf8).write(to: directory.appendingPathComponent("auth.json"))

        let loader = CodexAuthLoader(
            environment: { ["CODEX_HOME": directory.path] },
            homeDirectory: { URL(fileURLWithPath: "/unused") }
        )

        XCTAssertEqual(
            loader.load(),
            .credentials(
                CodexCredentials(
                    accessToken: "access-token",
                    accountID: "acct_123",
                    displayName: "user@example.com"
                )
            )
        )
    }

    func testAuthLoaderPrefersEmailAndHidesNonEmailSubject() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let idToken = try jwt(payload: ["sub": "auth0|63915027bfd39684bf8794ea", "email": "alice@example.com"])
        let auth = """
        {
          "OPENAI_API_KEY": "",
          "tokens": {
            "access_token": "access-token",
            "id_token": "\(idToken)"
          }
        }
        """
        try Data(auth.utf8).write(to: directory.appendingPathComponent("auth.json"))

        let loader = CodexAuthLoader(
            environment: { ["CODEX_HOME": directory.path] },
            homeDirectory: { URL(fileURLWithPath: "/unused") }
        )

        XCTAssertEqual(
            loader.load(),
            .credentials(
                CodexCredentials(
                    accessToken: "access-token",
                    accountID: nil,
                    displayName: "alice@example.com"
                )
            )
        )

        let noEmailDirectory = temporaryDirectory()
        try FileManager.default.createDirectory(at: noEmailDirectory, withIntermediateDirectories: true)
        let noEmailToken = try jwt(payload: ["sub": "auth0|63915027bfd39684bf8794ea"])
        let noEmailAuth = """
        {
          "OPENAI_API_KEY": "",
          "tokens": {
            "access_token": "access-token",
            "id_token": "\(noEmailToken)"
          }
        }
        """
        try Data(noEmailAuth.utf8).write(to: noEmailDirectory.appendingPathComponent("auth.json"))

        let noEmailLoader = CodexAuthLoader(
            environment: { ["CODEX_HOME": noEmailDirectory.path] },
            homeDirectory: { URL(fileURLWithPath: "/unused") }
        )

        XCTAssertEqual(
            noEmailLoader.load(),
            .credentials(
                CodexCredentials(
                    accessToken: "access-token",
                    accountID: nil,
                    displayName: nil
                )
            )
        )
    }

    func testAuthLoaderReportsUnsupportedAPIKeyModeWithoutToken() throws {
        let home = temporaryDirectory()
        let codex = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try Data(#"{"OPENAI_API_KEY":"sk-test","tokens":{}}"#.utf8)
            .write(to: codex.appendingPathComponent("auth.json"))

        let loader = CodexAuthLoader(
            environment: { [:] },
            homeDirectory: { home }
        )

        XCTAssertEqual(loader.load(), .unsupportedAPIKey)
    }

    func testAuthLoaderReportsNotLoggedInWhenNoCredentialsExist() throws {
        let home = temporaryDirectory()
        let codex = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try Data(#"{"OPENAI_API_KEY":"","tokens":{}}"#.utf8)
            .write(to: codex.appendingPathComponent("auth.json"))

        let loader = CodexAuthLoader(
            environment: { [:] },
            homeDirectory: { home }
        )

        XCTAssertEqual(loader.load(), .notLoggedIn)
    }

    func testClientBuildsHeadersAndFallsBackOn404() async throws {
        let now = Date(timeIntervalSince1970: 1_718_265_600)
        let body = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 23.5,
              "reset_at": 1718269200,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 41.2,
              "reset_at": 1718784000,
              "limit_window_seconds": 604800
            }
          },
          "code_review_rate_limit": {
            "primary_window": {
              "used_percent": 0,
              "reset_at": 1718269200,
              "limit_window_seconds": 18000
            }
          }
        }
        """
        let transport = MockQuotaTransport(responses: [
            response(status: 404, body: "{}"),
            response(status: 200, body: body)
        ])
        let client = CodexQuotaClient(transport: transport, now: { now })

        let snapshot = try await client.fetch(
            credentials: CodexCredentials(
                accessToken: "token",
                accountID: "acct_123",
                displayName: "user"
            ),
            force: true
        )

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "chatgpt.com")
        XCTAssertEqual(transport.requests[0].url?.path, "/backend-api/wham/usage")
        XCTAssertEqual(transport.requests[1].url?.path, "/api/codex/usage")
        XCTAssertEqual(URLComponents(url: transport.requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "force")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-Account-Id"), "acct_123")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct_123")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "ChatClaude-Account-Id"), "acct_123")
        XCTAssertEqual(snapshot.source, "chatgpt.com/api/codex")
        XCTAssertEqual(snapshot.highestUsedPercent, 41.2)
        XCTAssertEqual(snapshot.window(for: .fiveHour)?.remainingPercent, 76.5)
    }

    func testClientMaps401ToLoginMessage() async throws {
        let transport = MockQuotaTransport(responses: [
            response(status: 401, body: "{}")
        ])
        let client = CodexQuotaClient(transport: transport)

        do {
            _ = try await client.fetch(credentials: CodexCredentials(accessToken: "token", accountID: nil, displayName: nil))
            XCTFail("Expected token error")
        } catch let error as CodexQuotaClientError {
            XCTAssertEqual(error, .tokenExpired)
            XCTAssertEqual(error.localizedDescription, "Token 失效,请重新运行 codex login")
        }
    }

    func testClientMapsFallback404ToSanitizedHTTPError() async throws {
        let transport = MockQuotaTransport(responses: [
            response(status: 404, body: "{}"),
            response(status: 404, body: "{}")
        ])
        let client = CodexQuotaClient(transport: transport)

        do {
            _ = try await client.fetch(credentials: CodexCredentials(accessToken: "token", accountID: nil, displayName: nil))
            XCTFail("Expected 404 error")
        } catch let error as CodexQuotaClientError {
            XCTAssertEqual(error, .httpStatus(404, "Not found"))
        }
    }

    func testParserClampsAndMarksStaleWindows() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let body = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 123.4,
              "reset_at": 2000,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": -12,
              "reset_at": 900,
              "limit_window_seconds": 604800
            }
          }
        }
        """

        let snapshot = try CodexQuotaParser.parse(Data(body.utf8), now: now, source: "test", accountDisplayName: nil)

        XCTAssertEqual(snapshot.window(for: .fiveHour)?.usedPercent, 100)
        XCTAssertEqual(snapshot.window(for: .fiveHour)?.remainingPercent, 0)
        XCTAssertEqual(snapshot.window(for: .sevenDay)?.usedPercent, 0)
        XCTAssertEqual(snapshot.window(for: .sevenDay)?.stale, true)
        XCTAssertNil(snapshot.droppingExpiredWindows(now: now)?.window(for: .sevenDay))
    }

    func testPrivacyScrubberRedactsBearerAPIKeyAndSSOQuery() {
        let scrubbed = PrivacyScrubber.scrub(
            "Bearer abc.def sk-abc123 https://x.test?a=1&sso_access_token=secret&sso_client_id=client"
        )

        XCTAssertEqual(
            scrubbed,
            "Bearer [redacted] sk-[redacted] https://x.test?a=1&sso_access_token=[redacted]&sso_client_id=[redacted]"
        )
    }

    func testSettingsDefaultToFiveHourAndSevenDayMenuBarItems() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"codexMenuBarMode":"plan"}"#.utf8))

        XCTAssertEqual(settings.codexMenuBarQuotaItems.map(\.key), [.fiveHour, .sevenDay])
        XCTAssertEqual(settings.codexMenuBarQuotaItems.map(\.basis), [.used, .used])
        XCTAssertEqual(settings.codexMenuBarQuotaItems.map(\.isEnabled), [true, true])
        XCTAssertEqual(settings.codexMenuBarShowsQuotaLabels, true)
        XCTAssertEqual(settings.visiblePanelModules, PanelModule.defaults)
        XCTAssertEqual(settings.language, .english)
    }

    func testSettingsNormalizeVisiblePanelModules() {
        let settings = AppSettings(
            visiblePanelModules: [.heatmap, .summary, .summary, .codexQuota]
        )

        XCTAssertEqual(settings.visiblePanelModules, [.summary, .codexQuota, .heatmap])
    }

    func testSettingsNormalizeMenuBarItemsToSupportedWindows() {
        let settings = AppSettings(
            codexMenuBarQuotaItems: [
                CodexMenuBarQuotaItem(key: .codeReview, basis: .remaining, isEnabled: true),
                CodexMenuBarQuotaItem(key: .sevenDay, basis: .remaining, isEnabled: false)
            ]
        )

        XCTAssertEqual(settings.codexMenuBarQuotaItems.map(\.key), [.fiveHour, .sevenDay])
        XCTAssertEqual(settings.codexMenuBarQuotaItems[0].basis, .used)
        XCTAssertEqual(settings.codexMenuBarQuotaItems[0].isEnabled, true)
        XCTAssertEqual(settings.codexMenuBarQuotaItems[1].basis, .remaining)
        XCTAssertEqual(settings.codexMenuBarQuotaItems[1].isEnabled, false)
    }

    func testSnapshotFormatsPlanTypeForDisplay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = CodexQuotaSnapshot(
            planType: "pro_lite",
            windows: [],
            accountDisplayName: nil,
            fetchedAt: now,
            source: "test"
        )

        XCTAssertEqual(snapshot.displayPlanType, "Pro Lite")
        XCTAssertEqual(snapshot.displayPlan, "Codex Pro Lite")
    }

    func testCodexQuotaCacheStoreRoundTripsSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = CodexQuotaSnapshot(
            planType: "pro",
            windows: [
                CodexQuotaWindow(
                    key: .fiveHour,
                    usedPercent: 42,
                    resetsAt: now.addingTimeInterval(3_600),
                    limitWindowSeconds: 18_000,
                    now: now
                )
            ],
            accountDisplayName: "user",
            fetchedAt: now,
            source: "test"
        )
        let store = CodexQuotaCacheStore(
            fileURL: temporaryDirectory().appendingPathComponent("codex-quota-cache.json")
        )

        try store.save(
            CodexQuotaCacheRecord(
                snapshot: snapshot,
                lastNetworkAttemptAt: now,
                cachedAt: now
            )
        )

        let loaded = try store.load()
        XCTAssertEqual(loaded?.snapshot, snapshot)
        XCTAssertEqual(loaded?.lastNetworkAttemptAt, now)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func jwt(payload: [String: String]) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none"])
        let payload = try JSONSerialization.data(withJSONObject: payload)
        return [
            base64URL(header),
            base64URL(payload),
            "signature"
        ].joined(separator: ".")
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func response(status: Int, body: String) -> MockQuotaTransport.Response {
        let url = URL(string: "https://chatgpt.com/test")!
        return MockQuotaTransport.Response(
            data: Data(body.utf8),
            response: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}

private final class MockQuotaTransport: CodexQuotaHTTPTransport, @unchecked Sendable {
    struct Response {
        let data: Data
        let response: HTTPURLResponse
    }

    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        if response.data.count > bodyLimit {
            throw CodexQuotaClientError.responseTooLarge
        }
        return (response.data, response.response)
    }
}
