import Foundation
import XCTest
@testable import AgentBarCore

final class ClaudeStatuslineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCaptureSavesOnlyQuotaDataAndKeepsRepaintAge() throws {
        let store = try fixture()
        XCTAssertTrue(try store.capture(payload(), now: now))
        let first = try XCTUnwrap(store.loadLatest(now: now))
        XCTAssertEqual(first.source, .statusline)
        XCTAssertEqual(first.windows.map(\.usedPercent), [25, 60])
        XCTAssertFalse(try store.capture(payload(), now: now.addingTimeInterval(120)))
        XCTAssertEqual(store.loadLatest(now: now.addingTimeInterval(120))?.fetchedAt, now)
        XCTAssertTrue(try store.capture(payload(revision: 2), now: now.addingTimeInterval(180)))
        XCTAssertEqual(store.loadLatest(now: now.addingTimeInterval(180))?.fetchedAt, now.addingTimeInterval(180))
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: store.snapshotsDirectory, includingPropertiesForKeys: nil).first)
        let text = try String(contentsOf: file)
        for secret in ["private-session", "private-project", "secret-token", "private-account"] { XCTAssertFalse(text.contains(secret)) }
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testInvalidMissingAndExpiredFieldsDoNotInventQuotaOrEraseCache() throws {
        let store = try fixture()
        _ = try store.capture(payload(), now: now)
        for invalid in ["{}", "not json", #"{"session_id":"s","rate_limits":null}"#,
                        #"{"session_id":"s","rate_limits":{"five_hour":{"used_percentage":true,"resets_at":1900000000}}}"#,
                        #"{"session_id":"s","rate_limits":{"five_hour":{"used_percentage":101,"resets_at":1900000000}}}"#,
                        #"{"session_id":"s","rate_limits":{"five_hour":{"used_percentage":0,"resets_at":1700000000}}}"#] {
            XCTAssertFalse(try store.capture(Data(invalid.utf8), now: now))
        }
        XCTAssertEqual(store.loadLatest(now: now)?.windows.count, 2)
        let partial = Data(#"{"session_id":"new","rate_limits":{"seven_day":{"used_percentage":0,"resets_at":1900000000}}}"#.utf8)
        XCTAssertTrue(try store.capture(partial, now: now.addingTimeInterval(1)))
        XCTAssertEqual(store.loadLatest(now: now.addingTimeInterval(1))?.windows.map(\.key), [.sevenDay])
        XCTAssertEqual(store.loadLatest(now: now.addingTimeInterval(1))?.windows.first?.usedPercent, 0)
    }

    func testAccountSwitchRejectsOldSnapshotsAndOldRunningSession() throws {
        let store = try fixture()
        _ = try store.capture(payload(), now: now)
        let originalIdentity = store.accountIdentity
        try setAccount("another-account", home: store.homeDirectory)
        XCTAssertNotEqual(originalIdentity, store.accountIdentity)
        XCTAssertNil(store.loadLatest(now: now))
        XCTAssertFalse(try store.capture(payload(revision: 2), now: now.addingTimeInterval(1)))
        XCTAssertTrue(try store.capture(payload(session: "new-session"), now: now.addingTimeInterval(2)))
        XCTAssertNotNil(store.loadLatest(now: now.addingTimeInterval(2)))
    }

    func testIndependentSessionsCannotRepaintOverNewerObservation() throws {
        let store = try fixture()
        _ = try store.capture(payload(session: "first"), now: now)
        _ = try store.capture(payload(session: "second", used: 35), now: now.addingTimeInterval(2))
        _ = try store.capture(payload(session: "first"), now: now.addingTimeInterval(3))
        XCTAssertEqual(store.loadLatest(now: now.addingTimeInterval(3))?.windows.first?.usedPercent, 35)
    }

    func testLegacyQuotaSnapshotDecodesAsOAuth() throws {
        let data = Data(#"{"windows":[],"fetchedAt":0}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ClaudeQuotaSnapshot.self, from: data).source, .oauth)
    }

    func testInstallerPreservesExistingCommandOptionsAndRestoresThem() throws {
        let store = try fixture()
        let helper = try makeHelper(store: store)
        let settingsURL = store.configDirectory.appendingPathComponent("settings.json")
        let original = #"{"statusLine":{"type":"command","command":"IFS= read -r value; printf '%s\\n' \"$value\"; exit 7","padding":3,"refreshInterval":60000},"env":{"EXISTING_SETTING":"keep-me"}}"#
        try Data(original.utf8).write(to: settingsURL)
        let installer = ClaudeStatuslineInstaller(store: store)
        try installer.install(helper: helper)
        XCTAssertTrue(installer.isInstalled)
        let backup = try Data(contentsOf: store.directory.appendingPathComponent("original-statusline.json"))
        try installer.install(helper: helper)
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("original-statusline.json")), backup)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [store.directory.appendingPathComponent("run.sh").path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data("{\"value\":1}\n".utf8))
        try input.fileHandleForWriting.close()
        let forwarded = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 7)
        XCTAssertEqual(String(data: forwarded, encoding: .utf8), "{\"value\":1}\n")
        try installer.uninstall()
        XCTAssertFalse(installer.isInstalled)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: Data(original.utf8)) as? NSDictionary)
    }

    func testUninstallDoesNotOverwriteNewUserCommandAndMissingSettingsAreSupported() throws {
        let store = try fixture()
        let helper = try makeHelper(store: store)
        let installer = ClaudeStatuslineInstaller(store: store)
        try installer.install(helper: helper)
        try installer.uninstall()
        let file = store.configDirectory.appendingPathComponent("settings.json")
        XCTAssertNil((try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])?["statusLine"])
        try installer.install(helper: helper)
        let edited = Data(#"{"statusLine":{"type":"command","command":"echo custom"}}"#.utf8)
        try edited.write(to: file)
        XCTAssertThrowsError(try installer.uninstall())
        XCTAssertEqual(try Data(contentsOf: file), edited)
    }

    private func fixture() throws -> ClaudeStatuslineStore {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("agentbar ' test " + UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        try setAccount("private-account", home: home)
        return ClaudeStatuslineStore(configDirectory: home.appendingPathComponent(".claude"), homeDirectory: home)
    }

    private func makeHelper(store: ClaudeStatuslineStore) throws -> URL {
        let file = store.homeDirectory.appendingPathComponent("fake-helper")
        try Data("#!/bin/sh\ncat >/dev/null\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return file
    }

    private func setAccount(_ account: String, home: URL) throws {
        try JSONSerialization.data(withJSONObject: ["oauthAccount": ["accountUuid": account]])
            .write(to: home.appendingPathComponent(".claude.json"))
    }

    private func payload(session: String = "private-session", revision: Int = 1, used: Int = 25) -> Data {
        Data("""
        {"session_id":"\(session)","cwd":"private-project","accessToken":"secret-token",
         "cost":{"total_api_duration_ms":\(revision)},
         "rate_limits":{"five_hour":{"used_percentage":\(used),"resets_at":1800003600},
                        "seven_day":{"used_percentage":60,"resets_at":1800604800}}}
        """.utf8)
    }
}
