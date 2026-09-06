import Foundation

public struct FixtureUsageProvider: UsageProvider {
    public let providerID: ProviderID

    public init(providerID: ProviderID) {
        self.providerID = providerID
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        try? await Task.sleep(nanoseconds: 150_000_000)
        return Self.fixture(for: providerID)
    }

    public static func fixture(for providerID: ProviderID, now: Date = Date()) -> UsageSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let startOfToday = calendar.startOfDay(for: now)

        let tokenPattern: [Int]
        let planName: String
        let sessionPercent: Double
        let weeklyPercent: Double
        let resetDate: Date?

        switch providerID {
        case .claude:
            tokenPattern = [1200, 850, 2000, 640, 3100, 90, 2400]
            planName = "Pro"
            sessionPercent = 42
            weeklyPercent = 68
            resetDate = calendar.nextDate(
                after: now,
                matching: DateComponents(weekday: 2),
                matchingPolicy: .nextTime
            )
        case .codex:
            tokenPattern = [800, 1200, 450, 1800, 990, 1500, 700]
            planName = "Enterprise"
            sessionPercent = 17.5
            weeklyPercent = 54
            resetDate = calendar.nextDate(
                after: now,
                matching: DateComponents(day: 1),
                matchingPolicy: .nextTime
            )
        }

        let daily: [DailyTokenUsage] = (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) ?? startOfToday
            let index = (tokenPattern.count - 1 - offset) % tokenPattern.count
            return DailyTokenUsage(day: day, tokenCount: tokenPattern[index])
        }

        return UsageSnapshot(
            provider: providerID,
            planName: planName,
            sessionPercent: sessionPercent,
            weeklyPercent: weeklyPercent,
            resetDate: resetDate,
            dailyTokenUsage: daily
        )
    }
}
