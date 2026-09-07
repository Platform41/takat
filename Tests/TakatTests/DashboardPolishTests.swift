import XCTest
@testable import Takat

final class DashboardPolishTests: XCTestCase {
    func testAllZero() {
        XCTAssertTrue(allZero([]))
        XCTAssertTrue(allZero([
            DailyTokenUsage(day: Date(), tokenCount: 0),
            DailyTokenUsage(day: Date(), tokenCount: 0),
            DailyTokenUsage(day: Date(), tokenCount: 0)
        ]))
        XCTAssertFalse(allZero([
            DailyTokenUsage(day: Date(), tokenCount: 0),
            DailyTokenUsage(day: Date(), tokenCount: 5),
            DailyTokenUsage(day: Date(), tokenCount: 0)
        ]))
    }
}
