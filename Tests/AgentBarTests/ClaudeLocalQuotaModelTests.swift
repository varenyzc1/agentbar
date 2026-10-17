import Foundation
import XCTest
import AgentBarCore
@testable import AgentBar

final class ClaudeLocalQuotaModelTests: XCTestCase {
    @MainActor
    func testOrdinaryAndForcedRefreshDoNotReadClaudeCredentialsOrCallNetwork() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        await model.refreshClaudeQuotaLocally()
        XCTAssertEqual(model.claudeQuotaState, .waitingForLocal)
        await model.refresh(force: true)
        XCTAssertEqual(fixture.reads.count, 0)
        let requests = await fixture.transport.calls
        XCTAssertEqual(requests, 0)
    }

    @MainActor
    func testLocalQuotaWinsOverMissingAuthAndRetainsDataAfterManual429() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.capture()
        let model = fixture.model()
        await model.refreshClaudeQuotaLocally()
        guard case let .ready(snapshot, _) = model.claudeQuotaState else { return XCTFail("Expected local quota") }
        XCTAssertEqual(snapshot.source, .statusline)
        XCTAssertEqual(fixture.reads.count, 0)
        await model.queryClaudeQuotaOnline()
        guard case let .ready(cached, _) = model.claudeQuotaState else { return XCTFail("Manual failure lost local data") }
        XCTAssertEqual(cached, snapshot)
        XCTAssertNotNil(model.claudeQuotaRefreshFailure)
        let firstRequests = await fixture.transport.calls
        XCTAssertEqual(firstRequests, 1)
        await model.refreshClaudeQuotaLocally()
        await model.queryClaudeQuotaOnline()
        let secondRequests = await fixture.transport.calls
        XCTAssertEqual(secondRequests, 1, "Manual retry must respect 429 cooldown")
    }

    @MainActor
    func testAccountChangeClearsLocalDataWithoutNetwork() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.capture()
        let model = fixture.model()
        await model.refreshClaudeQuotaLocally()
        try Data(#"{"oauthAccount":{"accountUuid":"different-account"}}"#.utf8).write(to: fixture.home.appendingPathComponent(".claude.json"))
        await model.refreshClaudeQuotaLocally()
        XCTAssertEqual(model.claudeQuotaState, .waitingForLocal)
        XCTAssertEqual(fixture.reads.count, 0)
        let requests = await fixture.transport.calls
        XCTAssertEqual(requests, 0)
    }
}

private struct Fixture {
    let home: URL
    let store: ClaudeStatuslineStore
    let reads = ReadCounter()
    let transport = CountingTransport()
    let now = Date()

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        store = ClaudeStatuslineStore(configDirectory: config, homeDirectory: home)
    }

    func remove() { try? FileManager.default.removeItem(at: home) }

    func capture() throws {
        let body = """
        {"session_id":"test-session","rate_limits":{"five_hour":{"used_percentage":25,"resets_at":\(now.addingTimeInterval(3600).timeIntervalSince1970)}}}
        """
        _ = try store.capture(Data(body.utf8), now: now)
    }

    @MainActor func model() -> AgentBarModel {
        let home = home, now = now, reads = reads
        return AgentBarModel(
            settingsStore: .init(fileURL: home.appendingPathComponent("settings.json"), legacyKey: UUID().uuidString),
            authLoader: .init(environment: { [:] }, homeDirectory: { home }),
            quotaCacheStore: .init(fileURL: home.appendingPathComponent("codex-cache.json")),
            resetCreditsCacheStore: .init(fileURL: home.appendingPathComponent("reset-cache.json")),
            grokAuthLoader: .init(environment: { [:] }, homeDirectory: { home }),
            grokQuotaCacheStore: .init(fileURL: home.appendingPathComponent("grok-cache.json")),
            claudeAuthLoader: .init(environment: { [:] }, homeDirectory: home, readKeychain: { _, _ in
                reads.increment()
                return Data(#"{"claudeAiOauth":{"accessToken":"test-token","scopes":["user:profile"]}}"#.utf8)
            }),
            claudeQuotaClient: .init(transport: transport),
            claudeQuotaCacheStore: .init(fileURL: home.appendingPathComponent("claude-cache.json")),
            claudeStatuslineStore: store,
            database: nil, startsBackgroundTasks: false, now: { now }
        )
    }
}

private final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
}

private actor CountingTransport: ClaudeQuotaHTTPTransport {
    private(set) var calls = 0
    func data(for request: URLRequest, proxy: NetworkProxySettings, bodyLimit: Int) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "600"])!)
    }
}
