import XCTest
@testable import AgentBarCore

final class ClaudeEgressIPTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDetectsIPv4AndIPv6AtClaudeHostWithoutCredentials() async throws {
        for ip in ["203.0.113.42", "2001:db8::1234", "2001:db8:1234:5678:abcd:ef01:2345:6789"] {
            let transport = EgressTestTransport(body: "fl=test\nh=api.anthropic.com\nip=\(ip)\nloc=US\n")
            let now = now
            let snapshot = try await ClaudeEgressIPClient(transport: transport, now: { now }).fetch()
            XCTAssertEqual(snapshot, ClaudeEgressIPSnapshot(ipAddress: ip, checkedAt: now))
            let (request, proxy, bodyLimit) = await transport.captured()
            XCTAssertEqual(request?.url?.host, ClaudeQuotaClient.endpoint.host)
            XCTAssertEqual(request?.url?.path, "/cdn-cgi/trace")
            XCTAssertEqual(request?.httpMethod, "GET")
            XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request?.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request?.value(forHTTPHeaderField: "anthropic-beta"))
            XCTAssertNil(request?.httpBody)
            XCTAssertEqual(request?.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request?.timeoutInterval, ClaudeQuotaClient.requestTimeout)
            XCTAssertEqual(proxy, NetworkProxySettings())
            XCTAssertEqual(bodyLimit, ClaudeEgressIPClient.bodyLimit)
        }
    }

    func testUsesSelectedManualProxyForEverySupportedScheme() async throws {
        for scheme in ["http", "https", "socks5"] {
            let transport = EgressTestTransport(body: "h=api.anthropic.com\nip=203.0.113.42\n")
            let proxy = NetworkProxySettings(mode: .manual, address: "\(scheme)://127.0.0.1:7890")
            _ = try await ClaudeEgressIPClient(transport: transport).fetch(proxy: proxy)
            let (_, capturedProxy, _) = await transport.captured()
            XCTAssertEqual(capturedProxy, proxy)
        }
    }

    func testRejectsMalformedOrAmbiguousTraceWithoutEchoingPayload() async {
        let invalidBodies = [
            "h=api.anthropic.com\nip=secret-payload",
            "h=api.anthropic.com\nip=999.2.3.4",
            "h=api.anthropic.com\nip=example.com",
            "h=api.anthropic.com\nip=fe80::1%en0",
            "h=api.anthropic.com\nip=203.0.113.42\nip=203.0.113.43",
            "h=api.anthropic.com\nh=api.anthropic.com\nip=203.0.113.42",
            "h=another.example\nip=203.0.113.42",
            "ip=203.0.113.42",
            "h=api.anthropic.com",
            "<html>secret-payload</html>",
            "h=api.anthropic.com\nip=203.0.113.42\n" + String(repeating: "x", count: ClaudeEgressIPClient.bodyLimit)
        ]
        for body in invalidBodies {
            do {
                _ = try await ClaudeEgressIPClient(transport: EgressTestTransport(body: body)).fetch()
                XCTFail("Expected invalid response")
            } catch {
                XCTAssertEqual(error as? ClaudeEgressIPError, .invalidResponse)
                XCTAssertFalse(error.localizedDescription.contains("secret-payload"))
            }
        }
    }

    func testAcceptsCRLFTrace() async throws {
        let transport = EgressTestTransport(body: "h=api.anthropic.com\r\nip=203.0.113.42\r\n")
        let snapshot = try await ClaudeEgressIPClient(transport: transport).fetch()
        XCTAssertEqual(snapshot.ipAddress, "203.0.113.42")
    }

    func testRejectsRedirectsAndHTTPFailures() async {
        for status in [302, 403, 429, 503] {
            let transport = EgressTestTransport(body: "secret-payload", status: status)
            do {
                _ = try await ClaudeEgressIPClient(transport: transport).fetch()
                XCTFail("Expected HTTP failure")
            } catch {
                XCTAssertEqual(error as? ClaudeEgressIPError, .httpStatus(status))
                XCTAssertFalse(error.localizedDescription.contains("secret-payload"))
            }
        }
    }

    func testRejectsResponseFromDifferentURL() async {
        let transport = EgressTestTransport(body: "h=api.anthropic.com\nip=203.0.113.42", responseURL: URL(string: "https://other.example/cdn-cgi/trace")!)
        do {
            _ = try await ClaudeEgressIPClient(transport: transport).fetch()
            XCTFail("Expected URL validation failure")
        } catch {
            XCTAssertEqual(error as? ClaudeEgressIPError, .invalidResponse)
        }
    }

    func testInvalidProxyDoesNotMakeRequest() async {
        let transport = EgressTestTransport(body: "")
        do {
            _ = try await ClaudeEgressIPClient(transport: transport).fetch(proxy: .init(mode: .manual, address: "http://user:secret@127.0.0.1:7890"))
            XCTFail("Expected proxy validation failure")
        } catch {
            XCTAssertEqual(error as? NetworkProxyError, .credentialsNotSupported)
        }
        let (request, _, _) = await transport.captured()
        XCTAssertNil(request)
    }

    func testTransportErrorsAreSafeAndOversizedResponsesAreInvalid() async {
        let failures: [(Error, ClaudeEgressIPError)] = [
            (NSError(domain: NSURLErrorDomain, code: -1004, userInfo: [NSLocalizedDescriptionKey: "http://user:secret@proxy.example:8080"]), .network),
            (ClaudeQuotaClientError.responseTooLarge, .invalidResponse),
            (ClaudeQuotaClientError.invalidResponse, .invalidResponse)
        ]
        for (failure, expected) in failures {
            do {
                _ = try await ClaudeEgressIPClient(transport: EgressTestTransport(error: failure)).fetch()
                XCTFail("Expected transport failure")
            } catch {
                XCTAssertEqual(error as? ClaudeEgressIPError, expected)
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
        }
    }

    func testCancellationIsPreserved() async {
        do {
            _ = try await ClaudeEgressIPClient(transport: EgressTestTransport(error: CancellationError())).fetch()
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}

private actor EgressTestTransport: ClaudeQuotaHTTPTransport {
    let body: String
    let status: Int
    let responseURL: URL?
    let error: Error?
    private var request: URLRequest?
    private var proxy: NetworkProxySettings?
    private var bodyLimit: Int?

    init(body: String = "", status: Int = 200, responseURL: URL? = nil, error: Error? = nil) {
        self.body = body
        self.status = status
        self.responseURL = responseURL
        self.error = error
    }

    func data(for request: URLRequest, proxy: NetworkProxySettings, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        self.proxy = proxy
        self.bodyLimit = bodyLimit
        if let error { throw error }
        return (Data(body.utf8), HTTPURLResponse(url: responseURL ?? request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func captured() -> (URLRequest?, NetworkProxySettings?, Int?) { (request, proxy, bodyLimit) }
}
