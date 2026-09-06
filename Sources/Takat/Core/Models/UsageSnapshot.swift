import Foundation

public struct UsageSnapshot: Equatable, Sendable {
    public let provider: ProviderID
    public let planName: String
    public let sessionPercent: Double?
    public let weeklyPercent: Double?
    public let resetDate: Date?
    public let dailyTokenUsage: [DailyTokenUsage]

    public init(
        provider: ProviderID,
        planName: String,
        sessionPercent: Double? = nil,
        weeklyPercent: Double? = nil,
        resetDate: Date? = nil,
        dailyTokenUsage: [DailyTokenUsage] = []
    ) {
        self.provider = provider
        self.planName = planName
        self.sessionPercent = sessionPercent
        self.weeklyPercent = weeklyPercent
        self.resetDate = resetDate
        self.dailyTokenUsage = dailyTokenUsage
    }
}

public enum ProviderID: String, CaseIterable, Sendable {
    case claude
    case codex
}

public struct DailyTokenUsage: Equatable, Sendable {
    public let day: Date
    public let tokenCount: Int

    public init(day: Date, tokenCount: Int) {
        self.day = day
        self.tokenCount = tokenCount
    }
}
