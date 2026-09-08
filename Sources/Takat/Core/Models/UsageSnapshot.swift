import Foundation

public struct UsageSnapshot: Equatable, Sendable, Codable {
    public let provider: ProviderID
    public let planName: String
    public let sessionPercent: Double?
    public let weeklyPercent: Double?
    public let resetDate: Date?
    public let dailyTokenUsage: [DailyTokenUsage]
    public let balance: Balance?

    public init(
        provider: ProviderID,
        planName: String,
        sessionPercent: Double? = nil,
        weeklyPercent: Double? = nil,
        resetDate: Date? = nil,
        dailyTokenUsage: [DailyTokenUsage] = [],
        balance: Balance? = nil
    ) {
        self.provider = provider
        self.planName = planName
        self.sessionPercent = sessionPercent
        self.weeklyPercent = weeklyPercent
        self.resetDate = resetDate
        self.dailyTokenUsage = dailyTokenUsage
        self.balance = balance
    }
}

public struct Balance: Equatable, Sendable, Codable {
    public let amount: Decimal
    public let currency: String
    public let isAvailable: Bool

    public init(amount: Decimal, currency: String, isAvailable: Bool) {
        self.amount = amount
        self.currency = currency
        self.isAvailable = isAvailable
    }
}

public enum ProviderID: String, CaseIterable, Sendable, Codable {
    case claude
    case codex
    case gemini
    case deepseek

    public static let displayOrder: [ProviderID] = [.claude, .codex, .gemini, .deepseek]
}

public struct DailyTokenUsage: Equatable, Sendable, Codable {
    public let day: Date
    /// Non-cached tokens processed that day: new input + cache writes + output + reasoning.
    /// Excludes cached-context reads, which dominate raw per-turn totals.
    public let tokenCount: Int

    public init(day: Date, tokenCount: Int) {
        self.day = day
        self.tokenCount = tokenCount
    }
}
