import XCTest
@testable import Takat

final class UsageSnapshotTests: XCTestCase {
    func testProviderIDsAreStable() {
        XCTAssertEqual(ProviderID.allCases.map(\.rawValue), ["claude", "codex", "gemini"])
    }
}
