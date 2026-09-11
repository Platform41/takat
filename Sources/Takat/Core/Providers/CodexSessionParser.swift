import Foundation

struct CodexSessionData {
    var rateLimits: CodexRateLimits?
    var tokenDeltas: [(Date, Int)] = []
}

enum CodexSessionParser {
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

    static func parse(lines: some Sequence<String>) -> CodexSessionData {
        let decoder = JSONDecoder()
        var data = CodexSessionData()

        for line in lines {
            guard !line.isEmpty else { continue }
            guard let event = try? decoder.decode(CodexEvent.self, from: Data(line.utf8)) else {
                continue
            }
            guard event.payload.type == "token_count" else { continue }

            if let rateLimits = event.payload.rate_limits, isAccountFamily(rateLimits) {
                data.rateLimits = rateLimits
            }

            if let lastTokenUsage = event.payload.info?.last_token_usage,
               let date = fractionalTimestamp.date(from: event.timestamp) ?? plainTimestamp.date(from: event.timestamp) {
                data.tokenDeltas.append((date, newTokens(lastTokenUsage)))
            }
        }

        return data
    }

    static func newTokens(_ usage: CodexTokenUsage) -> Int {
        let input = usage.input_tokens ?? 0
        let cached = usage.cached_input_tokens ?? 0
        let cacheWrite = usage.cache_write_input_tokens ?? 0
        let output = usage.output_tokens ?? 0
        let reasoning = usage.reasoning_output_tokens ?? 0
        return max(0, input - cached) + cacheWrite + output + reasoning
    }

    static func parseRateLimitsOnly(lines: some Sequence<String>) -> CodexRateLimits? {
        let decoder = JSONDecoder()
        var rateLimits: CodexRateLimits?

        for line in lines {
            guard !line.isEmpty else { continue }
            guard let event = try? decoder.decode(CodexEvent.self, from: Data(line.utf8)) else {
                continue
            }
            guard event.payload.type == "token_count" else { continue }

            if let rl = event.payload.rate_limits, isAccountFamily(rl) {
                rateLimits = rl
            }
        }

        return rateLimits
    }

    /// Codex now interleaves the account-wide "codex" rate-limit family
    /// (5h + weekly, the plan's actual limits) with narrower per-model
    /// families such as "codex_bengalfox" (a preview model's own weekly-only
    /// pool). Only the account family belongs on the Takat card — a
    /// per-model block would silently replace the real session/weekly
    /// numbers with a different, unrelated quota. Older sessions predating
    /// this split have no `limit_id` at all; treat that as the account
    /// family too.
    static func isAccountFamily(_ rateLimits: CodexRateLimits) -> Bool {
        rateLimits.limit_id == nil || rateLimits.limit_id == "codex"
    }

    static func planName(from planType: String?) -> String {
        guard let planType, !planType.isEmpty else { return "Codex" }
        switch planType {
        case "plus", "pro", "team", "enterprise":
            return planType.capitalized
        default:
            return "Codex"
        }
    }
}

struct CodexEvent: Decodable {
    let timestamp: String
    let payload: CodexPayload
}

struct CodexPayload: Decodable {
    let type: String?
    let info: CodexInfo?
    let rate_limits: CodexRateLimits?
}

struct CodexInfo: Decodable {
    let last_token_usage: CodexTokenUsage?
}

struct CodexTokenUsage: Decodable {
    let input_tokens: Int?
    let cached_input_tokens: Int?
    let cache_write_input_tokens: Int?
    let output_tokens: Int?
    let reasoning_output_tokens: Int?
    let total_tokens: Int?
}

struct CodexRateLimits: Decodable {
    let limit_id: String?
    let primary: CodexWindow?
    let secondary: CodexWindow?
    let plan_type: String?

    /// The 5-hour session window, identified by its duration rather than its
    /// position — Codex has been observed putting the weekly window in
    /// `primary` for some limit families, so position alone isn't reliable.
    var sessionWindow: CodexWindow? {
        [primary, secondary].compactMap { $0 }.first { $0.window_minutes == 300 }
    }

    /// The 7-day weekly window, identified by duration.
    var weeklyWindow: CodexWindow? {
        [primary, secondary].compactMap { $0 }.first { $0.window_minutes == 10_080 }
    }
}

struct CodexWindow: Decodable {
    let used_percent: Double?
    let resets_at: Double?
    let window_minutes: Int?
}
