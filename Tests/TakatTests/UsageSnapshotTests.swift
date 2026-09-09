import XCTest
@testable import Takat

final class UsageSnapshotTests: XCTestCase {
    func testProviderIDsAreStable() {
        XCTAssertEqual(ProviderID.allCases.map(\.rawValue), ["claude", "codex", "gemini", "deepseek"])
    }

    func testSnapshotWithNoteCodableRoundTrip() throws {
        let snapshot = UsageSnapshot(
            provider: .gemini,
            planName: "Gemini",
            dailyTokenUsage: [],
            note: "Antigravity doesn't record token usage locally."
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.note, snapshot.note)
    }

    func testOldSnapshotWithoutNoteDecodesWithNilNote() throws {
        let json = """
        {
            "provider": "gemini",
            "planName": "Gemini",
            "dailyTokenUsage": []
        }
        """
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.provider, .gemini)
        XCTAssertNil(decoded.note)
        XCTAssertNil(decoded.balance)
    }
}
