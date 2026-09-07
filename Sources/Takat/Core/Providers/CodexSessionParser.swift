import Foundation

struct CodexSessionData {
    var rateLimits: CodexRateLimits?
    var tokenDeltas: [(Date, Int)] = []
}

enum CodexSessionParser {
    static func parse(lines: some Sequence<String>) -> CodexSessionData {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        var data = CodexSessionData()

        for line in lines {
            guard !line.isEmpty else { continue }
            guard let event = try? decoder.decode(CodexEvent.self, from: Data(line.utf8)) else {
                continue
            }
            guard event.payload.type == "token_count" else { continue }

            if let rateLimits = event.payload.rate_limits {
                data.rateLimits = rateLimits
            }

            if let tokens = event.payload.info?.last_token_usage?.total_tokens,
               let date = withFractional.date(from: event.timestamp) ?? plain.date(from: event.timestamp) {
                data.tokenDeltas.append((date, tokens))
            }
        }

        return data
    }

    static func dailyUsage(
        tokenDeltas: [(Date, Int)],
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> [DailyTokenUsage] {
        let startOfToday = calendar.startOfDay(for: referenceDate)

        var buckets: [Date: Int] = [:]
        for (date, tokens) in tokenDeltas {
            let day = calendar.startOfDay(for: date)
            buckets[day, default: 0] += tokens
        }

        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) ?? startOfToday
            return DailyTokenUsage(day: day, tokenCount: buckets[day] ?? 0)
        }
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
    let total_tokens: Int
}

struct CodexRateLimits: Decodable {
    let primary: CodexWindow?
    let secondary: CodexWindow?
    let plan_type: String?
}

struct CodexWindow: Decodable {
    let used_percent: Double?
    let resets_at: Double?
}
