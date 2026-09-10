import Foundation

public struct UsageSnapshot: Equatable, Sendable, Codable {
    public let provider: ProviderID
    public let planName: String
    public let sessionPercent: Double?
    public let weeklyPercent: Double?
    public let resetDate: Date?
    public let dailyTokenUsage: [DailyTokenUsage]
    public let balance: Balance?
    /// The provider is present but its usage isn't locally measurable — this
    /// explains why (e.g. an Antigravity quota read that couldn't complete).
    public let note: String?
    /// Independent quota pools reported by a provider that has more than the
    /// single session/weekly pair the flat fields model (e.g. Antigravity's
    /// "Gemini models" and "Claude and GPT models" weekly groups).
    public let quotaGroups: [UsageQuotaGroup]?

    public init(
        provider: ProviderID,
        planName: String,
        sessionPercent: Double? = nil,
        weeklyPercent: Double? = nil,
        resetDate: Date? = nil,
        dailyTokenUsage: [DailyTokenUsage] = [],
        balance: Balance? = nil,
        note: String? = nil,
        quotaGroups: [UsageQuotaGroup]? = nil
    ) {
        self.provider = provider
        self.planName = planName
        self.sessionPercent = sessionPercent
        self.weeklyPercent = weeklyPercent
        self.resetDate = resetDate
        self.dailyTokenUsage = dailyTokenUsage
        self.balance = balance
        self.note = note
        self.quotaGroups = quotaGroups
    }
}

public struct UsageQuotaGroup: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let windows: [UsageQuotaWindow]

    public init(id: String, name: String, windows: [UsageQuotaWindow]) {
        self.id = id
        self.name = name
        self.windows = windows
    }
}

public struct UsageQuotaWindow: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    /// 0–100, already converted from "remaining" to "used".
    public let usedPercent: Double
    public let resetDate: Date?

    public init(id: String, name: String, usedPercent: Double, resetDate: Date?) {
        self.id = id
        self.name = name
        self.usedPercent = usedPercent
        self.resetDate = resetDate
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
