import Foundation

public struct CodexUsageProvider: UsageProvider {
    public let providerID: ProviderID = .codex

    private let sessionsDirectory: URL

    public init(sessionsDirectory: URL = CodexUsageProvider.defaultSessionsDirectory) {
        self.sessionsDirectory = sessionsDirectory
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
        let now = Date()
        let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now

        var deltas: [(Date, Int)] = []
        for file in files {
            guard modificationDate(of: file) >= cutoff else { continue }
            deltas.append(contentsOf: CodexSessionParser.parse(lines: lines(of: file)).tokenDeltas)
        }

        let daily = CodexSessionParser.dailyUsage(
            tokenDeltas: deltas,
            referenceDate: now,
            calendar: calendar
        )

        return UsageSnapshot(
            provider: .codex,
            planName: CodexSessionParser.planName(from: rateLimits.plan_type),
            sessionPercent: rateLimits.primary?.used_percent,
            weeklyPercent: rateLimits.secondary?.used_percent,
            resetDate: rateLimits.secondary?.resets_at.map { Date(timeIntervalSince1970: $0) },
            dailyTokenUsage: daily
        )
    }

    private func latestRateLimits(in files: [URL]) -> CodexRateLimits? {
        for file in files.prefix(3) {
            let data = CodexSessionParser.parse(lines: lines(of: file))
            if let rateLimits = data.rateLimits {
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

struct JSONLLines: Sequence {
    let data: Data

    func makeIterator() -> Iterator {
        Iterator(data: data)
    }

    struct Iterator: IteratorProtocol {
        let data: Data
        var start: Data.Index

        init(data: Data) {
            self.data = data
            self.start = data.startIndex
        }

        mutating func next() -> String? {
            guard start < data.endIndex else { return nil }
            var end = start
            while end < data.endIndex, data[end] != 0x0A {
                data.formIndex(after: &end)
            }
            defer { start = end < data.endIndex ? data.index(after: end) : end }
            return String(decoding: data[start..<end], as: UTF8.self)
        }
    }
}
