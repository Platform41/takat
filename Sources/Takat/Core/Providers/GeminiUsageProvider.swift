import Foundation

public struct GeminiUsageProvider: UsageProvider {
    public let providerID: ProviderID = .gemini

    private let chatsRoot: URL

    public init(chatsRoot: URL = GeminiUsageProvider.defaultChatsRoot) {
        self.chatsRoot = chatsRoot
    }

    public static var defaultChatsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: chatsRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw UsageProviderError.notConfigured
        }

        let files = chatFiles(in: chatsRoot)
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
            guard let session = GeminiSessionParser.decode(data) else { continue }
            successfulReads += 1
            deltas.append(contentsOf: GeminiSessionParser.deltas(from: session))
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
            provider: .gemini,
            planName: "Gemini",
            sessionPercent: nil,
            weeklyPercent: nil,
            resetDate: nil,
            dailyTokenUsage: daily
        )
    }

    private func chatFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let chatsDir = dir.appendingPathComponent("chats", isDirectory: true)
            guard let contents = try? fm.contentsOfDirectory(
                at: chatsDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for url in contents {
                guard url.pathExtension == "json" else { continue }
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
        let maxBytes: Int64 = 50 * 1024 * 1024
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxBytes else { return nil }
        return try? Data(contentsOf: url)
    }
}
