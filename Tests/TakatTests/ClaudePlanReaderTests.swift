import XCTest
@testable import Takat

final class ClaudePlanReaderTests: XCTestCase {
    private func config(_ organizationType: String) -> Data {
        Data(#"{"oauthAccount":{"organizationType":"\#(organizationType)"}}"#.utf8)
    }

    func testMappings() {
        XCTAssertEqual(ClaudePlanReader.planName(fromConfig: config("claude_pro")), "Pro")
        XCTAssertEqual(ClaudePlanReader.planName(fromConfig: config("claude_max")), "Max")
        XCTAssertEqual(ClaudePlanReader.planName(fromConfig: config("claude_team")), "Team")
        XCTAssertEqual(ClaudePlanReader.planName(fromConfig: config("claude_enterprise")), "Enterprise")
        XCTAssertEqual(ClaudePlanReader.planName(fromConfig: config("claude_free")), "Free")
    }

    func testUnknownOrganizationTypeFallsBack() {
        XCTAssertEqual(ClaudePlanReader.planName(fromConfig: config("claude_startup")), "Claude")
    }

    func testMissingOauthAccountFallsBack() {
        XCTAssertEqual(ClaudePlanReader.planName(fromConfig: Data(#"{"other":1}"#.utf8)), "Claude")
    }

    func testMalformedAndEmptyFallBack() {
        XCTAssertEqual(ClaudePlanReader.planName(fromConfig: Data("not json".utf8)), "Claude")
        XCTAssertEqual(ClaudePlanReader.planName(fromConfig: Data()), "Claude")
    }

    func testPrivacySentinelNeverReachesPlanName() {
        let data = Data(#"{"oauthAccount":{"organizationType":"claude_pro","emailAddress":"SECRET-SENTINEL"},"mcpServers":{"x":{"env":{"API_KEY":"SECRET-SENTINEL"}}}}"#.utf8)

        let planName = ClaudePlanReader.planName(fromConfig: data)

        XCTAssertEqual(planName, "Pro")
        XCTAssertFalse(planName.contains("SECRET-SENTINEL"))
    }

    func testParsesCommittedFixture() {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/claude-config/claude.json")

        let data = (try? Data(contentsOf: fixture)) ?? Data()
        let planName = ClaudePlanReader.planName(fromConfig: data)

        XCTAssertEqual(planName, "Pro")
        XCTAssertFalse(planName.contains("SECRET-SENTINEL"))
    }
}
