import XCTest
@testable import AgentBarCore

final class LocalUsageScannerTests: XCTestCase {
    func testCodexParserClampsOverlappingTokenFields() throws {
        let home = temporaryDirectory()
        let session = try writeCodexSession(
            home: home,
            lines: [
                codexMeta(cwd: "/tmp/work/agentbar"),
                codexTokenLine(
                    model: "gpt-5-codex",
                    input: 100,
                    output: 40,
                    cached: 30,
                    cacheCreate: 90,
                    reasoning: 10,
                    total: 140
                )
            ]
        )

        let parser = CodexSessionParser(environment: { [:] }, homeDirectory: home)
        let entries = try parser.parseFile(at: session, fromOffset: nil)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].project, "agentbar")
        XCTAssertEqual(entries[0].inputTokens, 0)
        XCTAssertEqual(entries[0].cachedInputTokens, 30)
        XCTAssertEqual(entries[0].cacheCreationInputTokens, 70)
        XCTAssertEqual(entries[0].outputTokens, 30)
        XCTAssertEqual(entries[0].reasoningOutputTokens, 10)
        XCTAssertEqual(entries[0].totalTokens, 140)
    }

    func testCodexParserBackfillsModelFromSessionRows() throws {
        let home = temporaryDirectory()
        let session = try writeCodexSession(
            home: home,
            lines: [
                codexMeta(cwd: "/tmp/work/agentbar"),
                #"{"type":"session_config","payload":{"model":"gpt-5-codex"}}"#,
                codexTokenLine(
                    model: nil,
                    input: 100,
                    output: 40,
                    cached: 0,
                    cacheCreate: 0,
                    reasoning: 0,
                    total: 140
                )
            ]
        )

        let parser = CodexSessionParser(environment: { [:] }, homeDirectory: home)
        let entries = try parser.parseFile(at: session, fromOffset: nil)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].model, "gpt-5-codex")
    }

    func testClaudeParserSplitsThinkingFromOutputWhenReasoningMissing() throws {
        let home = temporaryDirectory()
        let project = home.appendingPathComponent(".claude/projects/-tmp-work-agentbar", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let session = project.appendingPathComponent("session.jsonl")
        let line = """
        {"type":"assistant","timestamp":"2026-06-13T10:00:00Z","message":{"id":"msg_01","model":"claude-sonnet-4-6-20251001","usage":{"input_tokens":100,"output_tokens":100,"cache_read_input_tokens":10,"cache_creation_input_tokens":5},"content":[{"type":"thinking","text":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"type":"text","text":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}}
        """
        try Data((line + "\n").utf8).write(to: session)

        let entries = try ClaudeCodeParser(homeDirectory: home).parseFile(at: session, fromOffset: nil)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].project, "agentbar")
        XCTAssertEqual(entries[0].outputTokens, 50)
        XCTAssertEqual(entries[0].reasoningOutputTokens, 50)
        XCTAssertEqual(entries[0].totalTokens, 215)
    }

    func testGeminiParserSupportsUsageMetadataSchema() throws {
        let home = temporaryDirectory()
        let chats = home.appendingPathComponent(".gemini/tmp/session-123/chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        let session = chats.appendingPathComponent("session-1.json")
        let json = """
        {
          "model": "gemini-2.5-pro",
          "timestamp": "2026-06-13T10:00:00Z",
          "turns": [
            {
              "usageMetadata": {
                "promptTokenCount": 100,
                "candidatesTokenCount": 50,
                "cachedContentTokenCount": 20,
                "thoughtsTokenCount": 10
              }
            }
          ]
        }
        """
        try Data(json.utf8).write(to: session)

        let entries = try GeminiCLIParser(homeDirectory: home).parseFile(at: session, fromOffset: nil)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].project, "session-123")
        XCTAssertEqual(entries[0].inputTokens, 80)
        XCTAssertEqual(entries[0].cachedInputTokens, 20)
        XCTAssertEqual(entries[0].outputTokens, 40)
        XCTAssertEqual(entries[0].reasoningOutputTokens, 10)
        XCTAssertEqual(entries[0].totalTokens, 150)
    }

    func testScannerUsesScanFileCacheAndAppendDeltaWithoutDuplicatingBuckets() throws {
        let home = temporaryDirectory()
        let database = try UsageDatabase(dbURL: home.appendingPathComponent("agentbar.db"))
        let parser = CodexSessionParser(environment: { [:] }, homeDirectory: home)
        let scanner = UsageScanner(
            database: database,
            parsers: [parser],
            logger: UsageScannerLogger(logURL: home.appendingPathComponent("scanner.log"))
        )
        let session = try writeCodexSession(
            home: home,
            lines: [
                codexMeta(cwd: "/tmp/work/agentbar"),
                codexTokenLine(model: "gpt-5-codex", input: 100, output: 40, cached: 20, cacheCreate: 0, reasoning: 10, total: 140)
            ]
        )

        let first = try scanner.scan()
        let second = try scanner.scan()
        appendLine(
            codexTokenLine(model: "gpt-5-codex", input: 120, output: 50, cached: 20, cacheCreate: 0, reasoning: 10, total: 170),
            to: session
        )
        let third = try scanner.scan()
        let summary = try database.usageSummary(
            now: fixedDate("2026-06-13T12:00:00Z"),
            settings: AppSettings(timeZoneIdentifier: TimeZone.current.identifier)
        )

        XCTAssertEqual(first.scannedFiles, 1)
        XCTAssertEqual(second.skippedFiles, 1)
        XCTAssertEqual(second.parsedEntries, 0)
        XCTAssertEqual(third.scannedFiles, 1)
        XCTAssertEqual(summary.today.totalTokens, 310)
        XCTAssertEqual(summary.topModel7Days?.model, "gpt-5-codex")
        XCTAssertEqual(summary.sourceBreakdown7Days.first?.source, "codex")
    }

    func testDatabaseUsesLongestPricingMatchAndFiveDimensionalTotals() throws {
        let home = temporaryDirectory()
        let database = try UsageDatabase(dbURL: home.appendingPathComponent("agentbar.db"))
        let timestamp = fixedDate("2026-06-13T10:00:00Z")
        let entry = TokenEntry(
            source: "codex",
            model: "gpt-5-codex-2026-06",
            project: "agentbar",
            timestamp: timestamp,
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cachedInputTokens: 1_000_000,
            cacheCreationInputTokens: 0,
            reasoningOutputTokens: 1_000_000,
            dedupKey: "entry-1"
        )

        _ = try database.ingest(entries: [entry], strategy: .addDelta, syncedAt: timestamp)
        let summary = try database.usageSummary(
            now: fixedDate("2026-06-13T12:00:00Z"),
            settings: AppSettings(timeZoneIdentifier: TimeZone.current.identifier)
        )

        XCTAssertEqual(summary.today.totalTokens, 4_000_000)
        XCTAssertEqual(summary.today.inputTokens + summary.today.outputTokens + summary.today.cachedInputTokens + summary.today.cacheCreationInputTokens + summary.today.reasoningOutputTokens, summary.today.totalTokens)
        XCTAssertEqual(summary.today.costUSD ?? 0, 21.375, accuracy: 0.000_001)
        XCTAssertEqual(summary.heatmapDays.count, 365)
        XCTAssertEqual(summary.heatmapDays.last?.level, 4)
    }

    func testSettingsStoreWritesSettingsJSON() throws {
        let home = temporaryDirectory()
        let settingsURL = home.appendingPathComponent("Application Support/AgentBar/settings.json")
        let store = AppSettingsStore(fileURL: settingsURL)

        try store.save(AppSettings(menuBarMetric: .usedCost, codexRefreshIntervalSeconds: 120, language: .simplifiedChinese))
        let loaded = store.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertEqual(loaded.menuBarMetric, .usedCost)
        XCTAssertEqual(loaded.codexRefreshIntervalSeconds, 120)
        XCTAssertEqual(loaded.language, .simplifiedChinese)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func writeCodexSession(home: URL, lines: [String]) throws -> URL {
        let root = home.appendingPathComponent(".codex/sessions/2026/06/13", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = root.appendingPathComponent("session.jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: session)
        return session
    }

    private func appendLine(_ line: String, to url: URL) {
        let handle = try! FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
    }

    private func codexMeta(cwd: String) -> String {
        #"{"type":"session_meta","payload":{"cwd":"\#(cwd)"}}"#
    }

    private func codexTokenLine(
        model: String?,
        input: Int,
        output: Int,
        cached: Int,
        cacheCreate: Int,
        reasoning: Int,
        total: Int
    ) -> String {
        let modelJSON = model.map { #""model":"\#($0)","# } ?? ""
        return """
        {"type":"event_msg","timestamp":"2026-06-13T10:00:00Z","payload":{"type":"token_count","info":{\(modelJSON)"last_token_usage":{"input_tokens":\(input),"output_tokens":\(output),"cached_input_tokens":\(cached),"cache_creation_input_tokens":\(cacheCreate),"reasoning_output_tokens":\(reasoning),"total_tokens":\(total)}}}}
        """
    }

    private func fixedDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
