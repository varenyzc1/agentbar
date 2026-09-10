import XCTest
@testable import AgentBarCore

final class CodexResetCreditsTests: XCTestCase {
    func testClientBuildsCodexDesktopHeadersAndDerivesAccountIDFromAccessToken() async throws {
        let now = Date(timeIntervalSince1970: 1_783_801_904)
        let accessToken = try jwt(payload: [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct_from_jwt"
            ]
        ])
        let body = """
        {
          "available_count": 1,
          "credits": [
            {
              "id": "reset_credit_12345678",
              "status": "available",
              "reset_type": "codex_rate_limits",
              "expires_at": "2026-07-16T07:51:44Z"
            }
          ]
        }
        """
        let transport = MockResetCreditsTransport(responses: [
            response(status: 200, body: body)
        ])
        let client = CodexResetCreditsClient(transport: transport, now: { now })

        let snapshot = try await client.fetch(
            credentials: CodexCredentials(accessToken: accessToken, accountID: nil, displayName: nil)
        )

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url?.path, "/backend-api/wham/rate-limit-reset-credits")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer \(accessToken)")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "originator"), "Codex Desktop")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "OAI-Product-Sku"), "CODEX")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct_from_jwt")
        XCTAssertEqual(transport.requests[0].timeoutInterval, 20)
        XCTAssertEqual(snapshot.availableCount, 1)
        XCTAssertEqual(snapshot.availableCredits.first?.resetType, "codex_rate_limits")
        XCTAssertEqual(snapshot.availableCredits.first?.expiresAt, Date(timeIntervalSince1970: 1_784_188_304))
    }

    func testParserHandlesSnakeAndCamelCaseAndSortsAvailableCreditsByExpiration() throws {
        let now = Date(timeIntervalSince1970: 1_783_801_904)
        let body = """
        {
          "availableCount": 2,
          "credits": [
            {
              "status": "available",
              "resetType": "later",
              "expiresAt": 1789549304000
            },
            {
              "status": "redeemed",
              "reset_type": "old",
              "expires_at": "2026-07-10T07:51:44Z"
            },
            {
              "status": "available",
              "reset_type": "earlier",
              "expires_at": "2026-07-16T07:51:44Z"
            }
          ]
        }
        """

        let snapshot = try CodexResetCreditsParser.parse(Data(body.utf8), now: now, source: "test")

        XCTAssertEqual(snapshot.availableCount, 2)
        XCTAssertEqual(snapshot.allCreditCount, 3)
        XCTAssertEqual(snapshot.availableCredits.map(\.resetType), ["earlier", "later"])
        XCTAssertEqual(snapshot.allCredits.map(\.resetType), ["old", "earlier", "later"])
        XCTAssertEqual(snapshot.allCredits.map(\.status), ["redeemed", "available", "available"])
        XCTAssertEqual(snapshot.earliestExpiration, Date(timeIntervalSince1970: 1_784_188_304))
    }

    func testClientMapsAuthAndRateLimitErrors() async throws {
        let authTransport = MockResetCreditsTransport(responses: [
            response(status: 401, body: "{}")
        ])
        let authClient = CodexResetCreditsClient(transport: authTransport)

        do {
            _ = try await authClient.fetch(credentials: CodexCredentials(accessToken: "token", accountID: nil, displayName: nil))
            XCTFail("Expected token error")
        } catch let error as CodexResetCreditsClientError {
            XCTAssertEqual(error, .tokenExpired)
        }

        let rateLimitTransport = MockResetCreditsTransport(responses: [
            response(status: 429, body: #"{"message":"slow down"}"#, headers: ["Retry-After": "30"])
        ])
        let rateLimitClient = CodexResetCreditsClient(transport: rateLimitTransport)

        do {
            _ = try await rateLimitClient.fetch(credentials: CodexCredentials(accessToken: "token", accountID: nil, displayName: nil))
            XCTFail("Expected rate limit error")
        } catch let error as CodexResetCreditsClientError {
            XCTAssertEqual(error, .rateLimited("30"))
        }
    }

    func testCacheStoreRoundTripsSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("reset-credits-cache.json")
        let now = Date(timeIntervalSince1970: 1_783_801_904)
        let snapshot = CodexResetCreditsSnapshot(
            availableCount: 1,
            availableCredits: [],
            allCredits: [],
            fetchedAt: now,
            source: "test"
        )
        let record = CodexResetCreditsCacheRecord(snapshot: snapshot, cachedAt: now)
        let store = CodexResetCreditsCacheStore(fileURL: fileURL)

        try store.save(record)

        XCTAssertEqual(try store.load(), record)
    }

    private func jwt(payload: [String: Any]) throws -> String {
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

    private func response(
        status: Int,
        body: String,
        headers: [String: String]? = nil
    ) -> MockResetCreditsTransport.Response {
        let url = URL(string: "https://chatgpt.com/test")!
        return MockResetCreditsTransport.Response(
            data: Data(body.utf8),
            response: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        )
    }
}

private final class MockResetCreditsTransport: CodexResetCreditsHTTPTransport, @unchecked Sendable {
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
            throw CodexResetCreditsClientError.responseTooLarge
        }
        return (response.data, response.response)
    }
}
