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
        XCTAssertNil(decoded.quotaGroups)
    }

    func testSnapshotWithQuotaGroupsCodableRoundTrip() throws {
        let snapshot = UsageSnapshot(
            provider: .gemini,
            planName: "Antigravity",
            dailyTokenUsage: [],
            quotaGroups: [
                UsageQuotaGroup(id: "gemini-weekly", name: "Gemini models", windows: [
                    UsageQuotaWindow(id: "gemini-weekly", name: "Weekly", usedPercent: 16, resetDate: Date(timeIntervalSince1970: 4_100_000_000))
                ]),
                UsageQuotaGroup(id: "3p-weekly", name: "Claude and GPT models", windows: [
                    UsageQuotaWindow(id: "3p-weekly", name: "Weekly", usedPercent: 75, resetDate: nil)
                ]),
            ]
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.quotaGroups?.count, 2)
        XCTAssertEqual(decoded.quotaGroups?[0].windows[0].usedPercent, 16)
    }

    func testOldCachedSnapshotWithoutQuotaGroupsDecodes() throws {
        // A snapshot persisted before this change — no quotaGroups key at all.
        let json = """
        {
            "provider": "codex",
            "planName": "Plus",
            "sessionPercent": 10.0,
            "weeklyPercent": 3.0,
            "dailyTokenUsage": []
        }
        """
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.provider, .codex)
        XCTAssertNil(decoded.quotaGroups)
        XCTAssertEqual(decoded.sessionPercent, 10)
    }
}
