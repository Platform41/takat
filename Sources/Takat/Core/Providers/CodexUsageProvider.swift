import Foundation

public struct CodexUsageProvider: UsageProvider {
    public let providerID: ProviderID = .codex

    private let sessionsDirectory: URL
    private let clock: @Sendable () -> Date

    public init(
        sessionsDirectory: URL = CodexUsageProvider.defaultSessionsDirectory,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.clock = now
    }

    public static var defaultSessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sessionsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw UsageProviderError.notConfigured
        }

        let files = sessionFiles(in: sessionsDirectory)
        guard !files.isEmpty else {
            throw UsageProviderError.notConfigured
        }

        guard let rateLimits = latestRateLimits(in: files) else {
            throw UsageProviderError.unavailable
        }

        let calendar = Calendar.current
        let now = clock()
        let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now

        var deltas: [(Date, Int)] = []
        for file in files {
            guard modificationDate(of: file) >= cutoff else { continue }
            deltas.append(contentsOf: CodexSessionParser.parse(lines: lines(of: file)).tokenDeltas)
        }

        let daily = DailyUsageBucketing.dailyUsage(
            tokenDeltas: deltas,
            referenceDate: now,
            calendar: calendar
        )

        return UsageSnapshot(
            provider: .codex,
            planName: CodexSessionParser.planName(from: rateLimits.plan_type),
            sessionPercent: livePercent(rateLimits.primary, at: now),
            weeklyPercent: livePercent(rateLimits.secondary, at: now),
            resetDate: liveReset(rateLimits.secondary, at: now),
            dailyTokenUsage: daily
        )
    }

    /// `used_percent` is only meaningful while its window is still open. A cached
    /// `rate_limits` block from an older session can name a window that has since
    /// reset — in that case the percentage is stale and we report `nil` (unknown),
    /// not `0` (a real fresh-window value the guard still passes through).
    private func livePercent(_ window: CodexWindow?, at now: Date) -> Double? {
        guard let window, isOpen(window, at: now) else { return nil }
        return window.used_percent
    }

    private func liveReset(_ window: CodexWindow?, at now: Date) -> Date? {
        guard let window, let resetsAt = window.resets_at, isOpen(window, at: now) else { return nil }
        return Date(timeIntervalSince1970: resetsAt)
    }

    private func isOpen(_ window: CodexWindow, at now: Date) -> Bool {
        guard let resetsAt = window.resets_at else { return false }
        return Date(timeIntervalSince1970: resetsAt) > now
    }

    private func latestRateLimits(in files: [URL]) -> CodexRateLimits? {
        for file in files.prefix(3) {
            if let rateLimits = CodexSessionParser.parseRateLimitsOnly(lines: lines(of: file)) {
                return rateLimits
            }
        }
        return nil
    }

    private func sessionFiles(in root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let name = url.lastPathComponent
            guard name.hasPrefix("rollout-"), url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                files.append(url)
            }
        }
        return files.sorted { $0.path > $1.path }
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private func lines(of url: URL) -> JSONLLines {
        JSONLLines(data: (try? Data(contentsOf: url)) ?? Data())
    }
}
