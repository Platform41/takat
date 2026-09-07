import Foundation

enum ClaudeSessionParser {
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

    static func parse(lines: some Sequence<String>) -> [(Date, Int)] {
        let decoder = JSONDecoder()
        var deltas: [(Date, Int)] = []

        for line in lines {
            guard !line.isEmpty else { continue }
            guard let entry = try? decoder.decode(ClaudeEntry.self, from: Data(line.utf8)) else {
                continue
            }
            guard entry.type == "assistant", let usage = entry.message?.usage else { continue }
            guard let date = fractionalTimestamp.date(from: entry.timestamp) ?? plainTimestamp.date(from: entry.timestamp) else {
                continue
            }
            deltas.append((date, newTokens(usage)))
        }

        return deltas
    }

    static func newTokens(_ usage: ClaudeTokenUsage) -> Int {
        (usage.input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0) + (usage.output_tokens ?? 0)
    }
}

struct ClaudeEntry: Decodable {
    let type: String
    let timestamp: String
    let message: ClaudeMessage?
}

struct ClaudeMessage: Decodable {
    let usage: ClaudeTokenUsage?
}

struct ClaudeTokenUsage: Decodable {
    let input_tokens: Int?
    let cache_creation_input_tokens: Int?
    let output_tokens: Int?
}
