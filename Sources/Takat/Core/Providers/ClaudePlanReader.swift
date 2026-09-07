import Foundation

struct ClaudeUsage {
    var sessionPercent: Double?
    var weeklyPercent: Double?
    var resetDate: Date?
}

enum ClaudePlanReader {
    nonisolated(unsafe) private static let fractionalTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Decodes only `oauthAccount.organizationType` + `cachedUsageUtilization` from ~/.claude.json content.
    static func read(_ data: Data) -> (planName: String, usage: ClaudeUsage?) {
        guard let cfg = try? JSONDecoder().decode(ClaudeConfig.self, from: data) else {
            return ("Claude", nil)
        }
        return (planName(from: cfg), usage(from: cfg))
    }

    static func planName(fromConfig data: Data) -> String {
        read(data).planName
    }

    static func usage(fromConfig data: Data) -> ClaudeUsage? {
        read(data).usage
    }

    private static func planName(from cfg: ClaudeConfig) -> String {
        guard let type = cfg.oauthAccount?.organizationType else { return "Claude" }
        switch type {
        case "claude_pro": return "Pro"
        case "claude_max": return "Max"
        case "claude_team": return "Team"
        case "claude_enterprise": return "Enterprise"
        case "claude_free": return "Free"
        default: return "Claude"
        }
    }

    private static func usage(from cfg: ClaudeConfig) -> ClaudeUsage? {
        guard let windows = cfg.cachedUsageUtilization?.utilization else { return nil }

        let now = Date()
        let sessionPercent = windowPercent(windows.five_hour, at: now)
        let weeklyPercent = windowPercent(windows.seven_day, at: now)
        let resetDate = windowReset(windows.seven_day, at: now)

        if sessionPercent == nil && weeklyPercent == nil && resetDate == nil {
            return nil
        }
        return ClaudeUsage(
            sessionPercent: sessionPercent,
            weeklyPercent: weeklyPercent,
            resetDate: resetDate
        )
    }

    private static func windowPercent(_ window: ClaudeWindow?, at now: Date) -> Double? {
        guard let window, let resetsAt = parseResetDate(window.resets_at), resetsAt > now else {
            return nil
        }
        return window.utilization
    }

    private static func windowReset(_ window: ClaudeWindow?, at now: Date) -> Date? {
        guard let window, let resetsAt = parseResetDate(window.resets_at), resetsAt > now else {
            return nil
        }
        return resetsAt
    }

    private static func parseResetDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let truncated = truncateFractionalSeconds(raw)
        return fractionalTimestamp.date(from: truncated) ?? plainTimestamp.date(from: truncated)
    }

    private static func truncateFractionalSeconds(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"(\.\d{3})\d*"#, with: "$1", options: .regularExpression)
    }
}

struct ClaudeConfig: Decodable {
    let oauthAccount: ClaudeOAuthAccount?
    let cachedUsageUtilization: ClaudeCachedUtilization?
}

struct ClaudeOAuthAccount: Decodable {
    let organizationType: String?
}

struct ClaudeCachedUtilization: Decodable {
    let fetchedAtMs: Double?
    let utilization: ClaudeUtilizationWindows?
}

struct ClaudeUtilizationWindows: Decodable {
    let five_hour: ClaudeWindow?
    let seven_day: ClaudeWindow?
}

struct ClaudeWindow: Decodable {
    let utilization: Double?
    let resets_at: String?
}
