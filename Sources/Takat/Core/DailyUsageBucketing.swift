import Foundation

enum DailyUsageBucketing {
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
}
