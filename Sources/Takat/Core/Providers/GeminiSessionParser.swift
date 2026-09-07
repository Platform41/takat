import Foundation

enum GeminiSessionParser {
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

    static func parse(data: Data) -> [(Date, Int)] {
        guard let session = decode(data) else { return [] }
        return deltas(from: session)
    }

    static func decode(_ data: Data) -> GeminiSession? {
        try? JSONDecoder().decode(GeminiSession.self, from: data)
    }

    static func deltas(from session: GeminiSession) -> [(Date, Int)] {
        var deltas: [(Date, Int)] = []
        for message in session.messages {
            guard message.type == "gemini", let tokens = message.tokens else { continue }
            guard let timestamp = message.timestamp,
                  let date = fractionalTimestamp.date(from: timestamp) ?? plainTimestamp.date(from: timestamp) else {
                continue
            }
            deltas.append((date, newTokens(tokens)))
        }
        return deltas
    }

    static func newTokens(_ tokens: GeminiTokens) -> Int {
        let input = tokens.input ?? 0
        let cached = tokens.cached ?? 0
        let output = tokens.output ?? 0
        let thoughts = tokens.thoughts ?? 0
        return max(0, input - cached) + output + thoughts
    }
}

struct GeminiSession: Decodable {
    let messages: [GeminiMessage]
}

struct GeminiMessage: Decodable {
    let type: String?
    let timestamp: String?
    let model: String?
    let tokens: GeminiTokens?
}

struct GeminiTokens: Decodable {
    let input: Int?
    let output: Int?
    let cached: Int?
    let thoughts: Int?
}
