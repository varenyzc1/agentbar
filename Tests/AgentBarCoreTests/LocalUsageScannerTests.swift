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

    func testScannerBackfillsCodexModelForAppendOnlyTokenRows() throws {
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
                #"{"type":"session_config","payload":{"model":"gpt-5.5"}}"#,
                codexTokenLine(model: nil, input: 100, output: 40, cached: 20, cacheCreate: 0, reasoning: 10, total: 140)
            ]
        )

        _ = try scanner.scan()
        appendLine(
            codexTokenLine(model: nil, input: 120, output: 50, cached: 40, cacheCreate: 0, reasoning: 10, total: 170),
            to: session
        )
        _ = try scanner.scan()
        let summary = try database.usageSummary(
            now: fixedDate("2026-06-13T12:00:00Z"),
            settings: AppSettings(timeZoneIdentifier: TimeZone.current.identifier)
        )

        XCTAssertEqual(summary.today.totalTokens, 310)
        XCTAssertEqual(summary.dailyModelUsageDays.map(\.model), ["gpt-5.5"])
    }

    func testScannerRebuildsCachedBucketsWhenParserCacheVersionChanges() throws {
        let home = temporaryDirectory()
        let database = try UsageDatabase(dbURL: home.appendingPathComponent("agentbar.db"))
        let parser = CodexSessionParser(environment: { [:] }, homeDirectory: home)
        let timestamp = fixedDate("2026-06-13T10:00:00Z")
        let session = try writeCodexSession(
            home: home,
            lines: [
                codexMeta(cwd: "/tmp/work/agentbar"),
                #"{"type":"session_config","payload":{"model":"gpt-5.5"}}"#,
                codexTokenLine(model: nil, input: 100, output: 40, cached: 20, cacheCreate: 0, reasoning: 10, total: 140)
            ]
        )
        let attrs = try FileManager.default.attributesOfItem(atPath: session.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = (attrs[.modificationDate] as? Date) ?? timestamp
        let mtimeNS = Int64(modifiedAt.timeIntervalSince1970 * 1_000_000_000)

        _ = try database.ingest(
            entries: [
                TokenEntry(source: "codex", model: "unknown", project: "agentbar", timestamp: timestamp, inputTokens: 80, outputTokens: 30, cachedInputTokens: 20, reasoningOutputTokens: 10, dedupKey: "old-unknown")
            ],
            strategy: .addDelta,
            syncedAt: timestamp
        )
        try database.upsertScanFile(path: session.path, source: "codex", size: size, mtimeNS: mtimeNS, parserStateJSON: #"{"parsedSize":1}"#)

        let scanner = UsageScanner(
            database: database,
            parsers: [parser],
            logger: UsageScannerLogger(logURL: home.appendingPathComponent("scanner.log"))
        )

        let result = try scanner.scan()
        let summary = try database.usageSummary(
            now: fixedDate("2026-06-13T12:00:00Z"),
            settings: AppSettings(timeZoneIdentifier: TimeZone.current.identifier)
        )

        XCTAssertEqual(result.scannedFiles, 1)
        XCTAssertEqual(result.skippedFiles, 0)
        XCTAssertEqual(summary.today.totalTokens, 140)
        XCTAssertEqual(summary.dailyModelUsageDays.map(\.model), ["gpt-5.5"])
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
        XCTAssertEqual(summary.dailyUsageDays.last?.day, "2026-06-13")
        XCTAssertEqual(summary.dailyUsageDays.last?.totalTokens, 4_000_000)
        XCTAssertEqual(summary.dailyModelUsageDays.count, 1)
        XCTAssertEqual(summary.dailyModelUsageDays[0].model, "gpt-5-codex-2026-06")
        XCTAssertEqual(summary.dailyModelUsageDays[0].inputTokens, 1_000_000)
        XCTAssertEqual(summary.dailyModelUsageDays[0].outputTokens, 1_000_000)
        XCTAssertEqual(summary.dailyModelUsageDays[0].cachedInputTokens, 1_000_000)
        XCTAssertEqual(summary.dailyModelUsageDays[0].reasoningOutputTokens, 1_000_000)
    }

    func testSummaryIncludesDailySourceUsageForRangeFiltering() throws {
        let home = temporaryDirectory()
        let database = try UsageDatabase(dbURL: home.appendingPathComponent("agentbar.db"))
        let dayOne = fixedDate("2026-06-12T10:00:00Z")
        let dayTwo = fixedDate("2026-06-13T10:00:00Z")
        let entries = [
            TokenEntry(source: "codex", model: "gpt-5-codex", project: "agentbar", timestamp: dayOne, inputTokens: 100, outputTokens: 50, dedupKey: "codex-1"),
            TokenEntry(source: "claude-code", model: "claude-sonnet-4-5", project: "agentbar", timestamp: dayOne, inputTokens: 30, outputTokens: 20, dedupKey: "claude-1"),
            TokenEntry(source: "codex", model: "gpt-5-codex", project: "agentbar", timestamp: dayTwo, inputTokens: 200, outputTokens: 100, cachedInputTokens: 40, dedupKey: "codex-2")
        ]

        _ = try database.ingest(entries: entries, strategy: .addDelta, syncedAt: dayTwo)
        let summary = try database.usageSummary(
            now: fixedDate("2026-06-13T12:00:00Z"),
            settings: AppSettings(timeZoneIdentifier: TimeZone.current.identifier)
        )

        XCTAssertEqual(summary.dailySourceUsageDays.map { "\($0.day):\($0.source):\($0.totalTokens)" }, [
            "2026-06-12:claude-code:50",
            "2026-06-12:codex:150",
            "2026-06-13:codex:340"
        ])
    }

    func testDailyModelUsageKeepsUnknownModelSoTotalsMatchSourceBreakdown() throws {
        let home = temporaryDirectory()
        let database = try UsageDatabase(dbURL: home.appendingPathComponent("agentbar.db"))
        let timestamp = fixedDate("2026-06-13T10:00:00Z")
        let entries = [
            TokenEntry(source: "codex", model: "gpt-5.5", project: "agentbar", timestamp: timestamp, inputTokens: 100, outputTokens: 50, dedupKey: "known"),
            TokenEntry(source: "codex", model: "unknown", project: "agentbar", timestamp: timestamp, inputTokens: 200, outputTokens: 20, cachedInputTokens: 500, dedupKey: "unknown")
        ]

        _ = try database.ingest(entries: entries, strategy: .addDelta, syncedAt: timestamp)
        let summary = try database.usageSummary(
            now: fixedDate("2026-06-13T12:00:00Z"),
            settings: AppSettings(timeZoneIdentifier: TimeZone.current.identifier)
        )

        XCTAssertEqual(summary.dailySourceUsageDays.map(\.totalTokens).reduce(0, +), 870)
        XCTAssertEqual(summary.dailyModelUsageDays.map(\.totalTokens).reduce(0, +), 870)
        XCTAssertEqual(summary.dailyModelUsageDays.map(\.model), ["gpt-5.5", "unknown"])
    }

    func testSummaryDailyUsageIncludesOlderHistoryForAllRange() throws {
        let home = temporaryDirectory()
        let database = try UsageDatabase(dbURL: home.appendingPathComponent("agentbar.db"))
        let oldDay = fixedDate("2025-05-01T10:00:00Z")
        let recentDay = fixedDate("2026-06-13T10:00:00Z")
        let entries = [
            TokenEntry(source: "codex", model: "gpt-5-codex", project: "agentbar", timestamp: oldDay, inputTokens: 70, outputTokens: 30, dedupKey: "old-codex"),
            TokenEntry(source: "claude-code", model: "claude-sonnet-4-5", project: "agentbar", timestamp: recentDay, inputTokens: 100, outputTokens: 50, dedupKey: "recent-claude")
        ]

        _ = try database.ingest(entries: entries, strategy: .addDelta, syncedAt: recentDay)
        let summary = try database.usageSummary(
            now: fixedDate("2026-06-13T12:00:00Z"),
            settings: AppSettings(timeZoneIdentifier: TimeZone.current.identifier)
        )

        XCTAssertEqual(summary.dailyUsageDays.first?.day, "2025-05-01")
        XCTAssertEqual(summary.dailyUsageDays.map(\.totalTokens).reduce(0, +), 250)
        XCTAssertEqual(summary.dailyModelUsageDays.map(\.totalTokens).reduce(0, +), 250)
        XCTAssertEqual(summary.dailySourceUsageDays.map(\.totalTokens).reduce(0, +), 250)
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
