import Foundation

public struct ClaudeUsageProvider: UsageProvider {
    public let providerID: ProviderID = .claude

    private let projectsDirectory: URL

    public init(projectsDirectory: URL = ClaudeUsageProvider.defaultProjectsDirectory) {
        self.projectsDirectory = projectsDirectory
    }

    public static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: projectsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw UsageProviderError.notConfigured
        }

        let files = projectFiles(in: projectsDirectory)
        guard !files.isEmpty else {
            throw UsageProviderError.notConfigured
        }

        let calendar = Calendar.current
        let now = Date()
        let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now

        var deltas: [(Date, Int)] = []
        var inWindowCount = 0
        var successfulReads = 0
        for file in files {
            guard modificationDate(of: file) >= cutoff else { continue }
            inWindowCount += 1
            guard let data = readData(of: file) else { continue }
            successfulReads += 1
            deltas.append(contentsOf: ClaudeSessionParser.parse(lines: JSONLLines(data: data)))
        }

        if inWindowCount > 0 && successfulReads == 0 {
            throw UsageProviderError.unavailable
        }

        let daily = DailyUsageBucketing.dailyUsage(
            tokenDeltas: deltas,
            referenceDate: now,
            calendar: calendar
        )

        return UsageSnapshot(
            provider: .claude,
            planName: "Claude",
            sessionPercent: nil,
            weeklyPercent: nil,
            resetDate: nil,
            dailyTokenUsage: daily
        )
    }

    private func projectFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let slugDirs = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for slugDir in slugDirs {
            guard (try? slugDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let contents = try? fm.contentsOfDirectory(
                at: slugDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for url in contents {
                guard url.pathExtension == "jsonl" else { continue }
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    files.append(url)
                }
            }
        }
        return files
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private func readData(of url: URL) -> Data? {
        let maxBytes: Int64 = 200 * 1024 * 1024
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxBytes else { return nil }
        return try? Data(contentsOf: url)
    }
}
