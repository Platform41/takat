import XCTest
@testable import Takat

final class DashboardPolishTests: XCTestCase {
    func testAllZero() {
        XCTAssertTrue(ChartData.allZero([]))
        XCTAssertTrue(ChartData.allZero([
            DailyTokenUsage(day: Date(), tokenCount: 0),
            DailyTokenUsage(day: Date(), tokenCount: 0),
            DailyTokenUsage(day: Date(), tokenCount: 0)
        ]))
        XCTAssertFalse(ChartData.allZero([
            DailyTokenUsage(day: Date(), tokenCount: 0),
            DailyTokenUsage(day: Date(), tokenCount: 5),
            DailyTokenUsage(day: Date(), tokenCount: 0)
        ]))
    }
}
