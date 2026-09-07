import Foundation

enum RefreshPolicy {
    static let staleThreshold: TimeInterval = 15 * 60
    static let refreshInterval: TimeInterval = 60

    static func isStale(
        _ date: Date,
        at now: Date = Date(),
        threshold: TimeInterval = staleThreshold
    ) -> Bool {
        now.timeIntervalSince(date) > threshold
    }
}
