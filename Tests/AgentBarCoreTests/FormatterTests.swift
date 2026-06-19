import XCTest
@testable import AgentBarCore

final class FormatterTests: XCTestCase {
    func testRelativeResetUsesSelectedLanguage() {
        let now = Date(timeIntervalSince1970: 0)
        let resetAt = now.addingTimeInterval(3_660)

        XCTAssertEqual(
            AgentBarFormatters.relativeReset(from: now, to: resetAt, language: .english),
            "resets in 1h 1m"
        )
        XCTAssertEqual(
            AgentBarFormatters.relativeReset(from: now, to: resetAt, language: .simplifiedChinese),
            "1小时 1分钟后重置"
        )
    }
}
