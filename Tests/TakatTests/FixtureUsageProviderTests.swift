import XCTest
@testable import Takat

final class FixtureUsageProviderTests: XCTestCase {
    private let fixedDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 6
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    func testClaudeFixtureIsStable() {
        let snapshot = FixtureUsageProvider.fixture(for: .claude, now: fixedDate)

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(snapshot.sessionPercent, 42)
        XCTAssertEqual(snapshot.weeklyPercent, 68)
        XCTAssertEqual(snapshot.dailyTokenUsage.count, 7)
        XCTAssertNotNil(snapshot.resetDate)
    }

    func testCodexFixtureIsStable() {
        let snapshot = FixtureUsageProvider.fixture(for: .codex, now: fixedDate)

        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.planName, "Enterprise")
        XCTAssertEqual(snapshot.sessionPercent, 17.5)
        XCTAssertEqual(snapshot.weeklyPercent, 54)
        XCTAssertEqual(snapshot.dailyTokenUsage.count, 7)
        XCTAssertNotNil(snapshot.resetDate)
    }

    func testDeepSeekFixtureIsStable() {
        let snapshot = FixtureUsageProvider.fixture(for: .deepseek, now: fixedDate)

        XCTAssertEqual(snapshot.provider, .deepseek)
        XCTAssertEqual(snapshot.planName, "API")
        XCTAssertNil(snapshot.sessionPercent)
        XCTAssertNil(snapshot.weeklyPercent)
        XCTAssertNil(snapshot.resetDate)
        XCTAssertEqual(snapshot.dailyTokenUsage.count, 0)
        XCTAssertEqual(snapshot.balance, Balance(amount: 4.20, currency: "USD", isAvailable: true))
    }

    func testDailyUsageIsOrderedChronologically() {
        let snapshot = FixtureUsageProvider.fixture(for: .claude, now: fixedDate)
        let days = snapshot.dailyTokenUsage.map(\.day)

        XCTAssertEqual(days, days.sorted(by: <))
    }
}
