import XCTest
@testable import AgentBarCore

final class MenuBarQuotaSettingsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testLegacyClaudeSettingsMigrateBothWindowsAndRetainBasis() throws {
        for enabled in [true, false] {
            let json = """
            {"claudeMenuBarShowsQuota":\(enabled),"claudeQuotaPercentBasis":"remaining",
             "codexMenuBarQuotaItems":[{"key":"five_hour","basis":"remaining","isEnabled":false},
                                       {"key":"seven_day","basis":"used","isEnabled":true}]}
            """
            let settings = try decode(json)
            XCTAssertEqual(settings.claudeMenuBarQuotaItems.map(\.key), [.fiveHour, .sevenDay])
            XCTAssertEqual(settings.claudeMenuBarQuotaItems.map(\.isEnabled), [enabled, enabled])
            XCTAssertEqual(settings.claudeMenuBarQuotaItems.map(\.basis), [.remaining, .remaining])
            XCTAssertEqual(settings.claudeMenuBarQuotaItems.map(\.displayStyle), [.detailed, .detailed])
            XCTAssertEqual(settings.codexMenuBarQuotaItems.map(\.isEnabled), [false, true])
            XCTAssertEqual(settings.codexMenuBarQuotaItems.map(\.basis), [.remaining, .used])
            XCTAssertEqual(settings.codexMenuBarQuotaItems.map(\.displayStyle), [.compact, .compact])
        }
    }

    func testMissingClaudeSettingsStayDisabled() throws {
        let settings = try decode("{}")
        XCTAssertEqual(settings.claudeMenuBarQuotaItems, ClaudeMenuBarQuotaItem.defaults)
        XCTAssertTrue(settings.claudeMenuBarQuotaItems.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(settings.grokMenuBarDisplayStyle, .detailed)
    }

    func testIndependentSettingsSurviveSavingAndLoading() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let settings = AppSettings(
            codexMenuBarQuotaItems: [
                .init(key: .fiveHour, basis: .used, isEnabled: true, displayStyle: .detailed),
                .init(key: .sevenDay, basis: .remaining, isEnabled: false, displayStyle: .compact)
            ],
            grokMenuBarDisplayStyle: .compact,
            claudeMenuBarQuotaItems: [
                .init(key: .fiveHour, basis: .remaining, isEnabled: false, displayStyle: .compact),
                .init(key: .sevenDay, basis: .used, isEnabled: true, displayStyle: .detailed)
            ]
        )
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)
        let saved = try Data(contentsOf: store.fileURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertNil(object["claudeMenuBarShowsQuota"])
    }

    func testNewClaudeItemsTakePrecedenceOverLegacyGlobalSettings() throws {
        let settings = try decode("""
        {"claudeMenuBarShowsQuota":true,"claudeQuotaPercentBasis":"remaining",
         "claudeMenuBarQuotaItems":[{"key":"five_hour","basis":"used","isEnabled":false,"displayStyle":"compact"}]}
        """)
        XCTAssertEqual(settings.claudeMenuBarQuotaItems[0], .init(key: .fiveHour, displayStyle: .compact))
        XCTAssertEqual(settings.claudeMenuBarQuotaItems[1], .init(key: .sevenDay))
        let reloaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(reloaded, settings)
    }

    func testNormalizationHandlesDuplicateUnsupportedAndMissingKeys() {
        let settings = AppSettings(
            codexMenuBarQuotaItems: [
                .init(key: .fiveHour), .init(key: .codeReview),
                .init(key: .fiveHour, basis: .remaining, isEnabled: false, displayStyle: .detailed)
            ],
            claudeMenuBarQuotaItems: [
                .init(key: .sevenDay, isEnabled: true), .init(key: .sevenDayOpus, isEnabled: true),
                .init(key: .sevenDay, basis: .remaining, isEnabled: false, displayStyle: .compact)
            ]
        ).sanitized
        XCTAssertEqual(settings.codexMenuBarQuotaItems.map(\.key), [.fiveHour, .sevenDay])
        XCTAssertEqual(settings.codexMenuBarQuotaItems[0], .init(key: .fiveHour, basis: .remaining, isEnabled: false, displayStyle: .detailed))
        XCTAssertEqual(settings.claudeMenuBarQuotaItems.map(\.key), [.fiveHour, .sevenDay])
        XCTAssertEqual(settings.claudeMenuBarQuotaItems[0], .init(key: .fiveHour))
        XCTAssertEqual(settings.claudeMenuBarQuotaItems[1], .init(key: .sevenDay, basis: .remaining, displayStyle: .compact))
    }

    func testCodexTitleCombinesIndependentStyleBasisAndWindowLabels() {
        let snapshot = CodexQuotaSnapshot(planType: "pro", windows: [
            .init(key: .fiveHour, usedPercent: 25, resetsAt: now.addingTimeInterval(3600), limitWindowSeconds: 18000, now: now),
            .init(key: .sevenDay, usedPercent: 60, resetsAt: now.addingTimeInterval(7200), limitWindowSeconds: 604800, now: now)
        ], accountDisplayName: nil, fetchedAt: now, source: "test")
        var item = CodexMenuBarQuotaItem(key: .fiveHour, displayStyle: .detailed)
        XCTAssertEqual(item.menuBarTitle(snapshot: snapshot, showsWindowLabel: true), "Codex 5h 25%")
        XCTAssertEqual(item.menuBarTitle(snapshot: snapshot, showsWindowLabel: false), "Codex 25%")
        item.displayStyle = .compact
        item.basis = .remaining
        XCTAssertEqual(item.menuBarTitle(snapshot: snapshot, showsWindowLabel: true), "5h 75%")
        XCTAssertEqual(item.menuBarTitle(snapshot: snapshot, showsWindowLabel: false), "75%")
        item.isEnabled = false
        XCTAssertNil(item.menuBarTitle(snapshot: snapshot, showsWindowLabel: true))
        XCTAssertEqual(CodexMenuBarQuotaItem(key: .sevenDay, displayStyle: .detailed).menuBarTitle(snapshot: snapshot, showsWindowLabel: true), "Codex 7d 60%")
    }

    func testClaudeWindowsHaveIndependentVisibilityBasisAndStyle() {
        let snapshot = ClaudeQuotaSnapshot(windows: [
            .init(key: .sevenDay, usedPercent: 60, resetsAt: now.addingTimeInterval(7200)),
            .init(key: .fiveHour, usedPercent: 25, resetsAt: now.addingTimeInterval(3600))
        ], plan: "max", fetchedAt: now)
        var items: [ClaudeMenuBarQuotaItem] = [
            .init(key: .fiveHour, isEnabled: true, displayStyle: .detailed),
            .init(key: .sevenDay, basis: .remaining, isEnabled: true, displayStyle: .compact)
        ]
        XCTAssertEqual(items.compactMap { $0.menuBarTitle(snapshot: snapshot, now: now) }, ["Claude 5h 25%", "7d 40%"])
        items[0].isEnabled = false
        XCTAssertEqual(items.compactMap { $0.menuBarTitle(snapshot: snapshot, now: now) }, ["7d 40%"])
        items[1].displayStyle = .detailed
        XCTAssertEqual(items[1].menuBarTitle(snapshot: snapshot, now: now), "Claude 7d 40%")
    }

    func testClaudeExpiredMissingAndUnsupportedWindowsAreNotShown() {
        let snapshot = ClaudeQuotaSnapshot(windows: [
            .init(key: .fiveHour, usedPercent: 25, resetsAt: now),
            .init(key: .sevenDayOpus, usedPercent: 60, resetsAt: nil)
        ], plan: "max", fetchedAt: now)
        for key in ClaudeQuotaKey.allCases {
            XCTAssertNil(ClaudeMenuBarQuotaItem(key: key, isEnabled: true).menuBarTitle(snapshot: snapshot, now: now))
        }
    }

    func testGrokStyleOnlyChangesProviderName() {
        XCTAssertEqual(MenuBarQuotaDisplayStyle.detailed.title(provider: "Grok", percent: 42), "Grok 42%")
        XCTAssertEqual(MenuBarQuotaDisplayStyle.compact.title(provider: "Grok", percent: 42), "42%")
    }

    func testGroupedTitlesShowEachProviderOnlyOnce() {
        let codexItems = CodexMenuBarQuotaItem.supportedKeys.map {
            CodexMenuBarQuotaItem(key: $0, displayStyle: .detailed)
        }
        let claudeItems = ClaudeMenuBarQuotaItem.supportedKeys.map {
            ClaudeMenuBarQuotaItem(key: $0, isEnabled: true, displayStyle: .detailed)
        }
        let groups = [
            MenuBarQuotaPresentation.codexTitles(items: codexItems, snapshot: codexSnapshot, showsWindowLabel: true),
            MenuBarQuotaPresentation.claudeTitles(items: claudeItems, snapshot: claudeSnapshot, now: now)
        ]
        XCTAssertEqual(MenuBarQuotaPresentation.title(groups: groups), "Codex 5h 25% 7d 60% · Claude 5h 25% 7d 60%")
        XCTAssertEqual(MenuBarQuotaPresentation.codexTitles(items: codexItems, snapshot: codexSnapshot, showsWindowLabel: false), ["Codex 25%", "60%"])
    }

    func testGroupSeparatorsSkipHiddenProvidersAndKeepSingleWindows() {
        XCTAssertEqual(MenuBarQuotaPresentation.title(groups: [[], ["Claude 7d 40%"], []]), "Claude 7d 40%")
        XCTAssertEqual(MenuBarQuotaPresentation.title(groups: [["5h 25%", "7d 40%"], [], ["Grok 60%"]]), "5h 25% 7d 40% · Grok 60%")
        XCTAssertEqual(MenuBarQuotaPresentation.title(groups: [[], [""], []]), "")
    }

    func testGroupedTitlesPreserveMixedStylesAndIndependentPercentBasis() {
        for firstStyle in MenuBarQuotaDisplayStyle.allCases {
            for secondStyle in MenuBarQuotaDisplayStyle.allCases {
                let codexItems: [CodexMenuBarQuotaItem] = [
                    .init(key: .fiveHour, displayStyle: firstStyle),
                    .init(key: .sevenDay, basis: .remaining, displayStyle: secondStyle)
                ]
                let claudeItems: [ClaudeMenuBarQuotaItem] = [
                    .init(key: .fiveHour, isEnabled: true, displayStyle: firstStyle),
                    .init(key: .sevenDay, basis: .remaining, isEnabled: true, displayStyle: secondStyle)
                ]
                for provider in ["Codex", "Claude"] {
                    let expected = [
                        (firstStyle == .detailed ? "\(provider) " : "") + "5h 25%",
                        (firstStyle == .compact && secondStyle == .detailed ? "\(provider) " : "") + "7d 40%"
                    ]
                    let titles = provider == "Codex"
                        ? MenuBarQuotaPresentation.codexTitles(items: codexItems, snapshot: codexSnapshot, showsWindowLabel: true)
                        : MenuBarQuotaPresentation.claudeTitles(items: claudeItems, snapshot: claudeSnapshot, now: now)
                    XCTAssertEqual(titles, expected)
                }
            }
        }
    }

    func testHiddenFirstWindowDoesNotRemoveSecondWindowProviderName() {
        var codexItems: [CodexMenuBarQuotaItem] = [
            .init(key: .fiveHour, isEnabled: false, displayStyle: .detailed),
            .init(key: .sevenDay, displayStyle: .detailed)
        ]
        var claudeItems: [ClaudeMenuBarQuotaItem] = [
            .init(key: .fiveHour, isEnabled: false), .init(key: .sevenDay, isEnabled: true)
        ]
        XCTAssertEqual(MenuBarQuotaPresentation.codexTitles(items: codexItems, snapshot: codexSnapshot, showsWindowLabel: true), ["Codex 7d 60%"])
        XCTAssertEqual(MenuBarQuotaPresentation.claudeTitles(items: claudeItems, snapshot: claudeSnapshot, now: now), ["Claude 7d 60%"])
        codexItems[1].isEnabled = false
        claudeItems[1].isEnabled = false
        XCTAssertEqual(MenuBarQuotaPresentation.codexTitles(items: codexItems, snapshot: codexSnapshot, showsWindowLabel: true), [])
        XCTAssertEqual(MenuBarQuotaPresentation.claudeTitles(items: claudeItems, snapshot: claudeSnapshot, now: now), [])
    }

    func testMissingAndExpiredFirstWindowsDoNotConsumeProviderName() {
        let missingCodex = CodexQuotaSnapshot(
            planType: "pro", windows: codexSnapshot.windows.filter { $0.key == .sevenDay },
            accountDisplayName: nil, fetchedAt: now, source: "test"
        )
        let codexItems = CodexMenuBarQuotaItem.supportedKeys.map { CodexMenuBarQuotaItem(key: $0, displayStyle: .detailed) }
        XCTAssertEqual(MenuBarQuotaPresentation.codexTitles(items: codexItems, snapshot: missingCodex, showsWindowLabel: true), ["Codex 7d 60%"])
        let claudeItems = ClaudeMenuBarQuotaItem.supportedKeys.map { ClaudeMenuBarQuotaItem(key: $0, isEnabled: true) }
        let missingClaude = ClaudeQuotaSnapshot(windows: claudeSnapshot.windows.filter { $0.key == .sevenDay }, plan: "max", fetchedAt: now)
        XCTAssertEqual(MenuBarQuotaPresentation.claudeTitles(items: claudeItems, snapshot: missingClaude, now: now), ["Claude 7d 60%"])
        XCTAssertEqual(MenuBarQuotaPresentation.claudeTitles(items: claudeItems, snapshot: claudeSnapshot, now: now.addingTimeInterval(3600)), ["Claude 7d 60%"])
    }

    private var codexSnapshot: CodexQuotaSnapshot {
        CodexQuotaSnapshot(planType: "pro", windows: [
            .init(key: .fiveHour, usedPercent: 25, resetsAt: now.addingTimeInterval(3600), limitWindowSeconds: 18000, now: now),
            .init(key: .sevenDay, usedPercent: 60, resetsAt: now.addingTimeInterval(7200), limitWindowSeconds: 604800, now: now)
        ], accountDisplayName: nil, fetchedAt: now, source: "test")
    }

    private var claudeSnapshot: ClaudeQuotaSnapshot {
        ClaudeQuotaSnapshot(windows: [
            .init(key: .fiveHour, usedPercent: 25, resetsAt: now.addingTimeInterval(3600)),
            .init(key: .sevenDay, usedPercent: 60, resetsAt: now.addingTimeInterval(7200))
        ], plan: "max", fetchedAt: now)
    }

    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }
}
