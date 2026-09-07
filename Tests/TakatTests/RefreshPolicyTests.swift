import XCTest
@testable import Takat

final class RefreshPolicyTests: XCTestCase {
    func testStaleThresholdBoundary() {
        let now = Date(timeIntervalSince1970: 100_000)
        let threshold = RefreshPolicy.staleThreshold

        let justUnder = now.addingTimeInterval(-threshold + 1)
        let exactly = now.addingTimeInterval(-threshold)
        let justOver = now.addingTimeInterval(-threshold - 1)

        XCTAssertFalse(RefreshPolicy.isStale(justUnder, at: now))
        XCTAssertFalse(RefreshPolicy.isStale(exactly, at: now))
        XCTAssertTrue(RefreshPolicy.isStale(justOver, at: now))
    }
}
