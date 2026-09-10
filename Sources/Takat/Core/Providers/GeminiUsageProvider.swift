import Foundation

public struct GeminiUsageProvider: UsageProvider {
    public let providerID: ProviderID = .gemini

    /// Shown on the Gemini card when Antigravity is the active tool but its
    /// `/usage` quota couldn't be read this refresh (CLI missing, not
    /// authenticated, timed out). It's a transient read failure, not a
    /// statement that quota is unavailable in principle.
    public static let antigravityNote = "Antigravity usage couldn't be read right now."

    private let chatsRoot: URL
    private let antigravityRoot: URL
    private let clock: @Sendable () -> Date
    private let quotaSource: AntigravityQuotaSource

    public init(
        chatsRoot: URL = GeminiUsageProvider.defaultChatsRoot,
        antigravityRoot: URL = GeminiUsageProvider.defaultAntigravityRoot,
        now: @escaping @Sendable () -> Date = { Date() },
        quotaSource: AntigravityQuotaSource = AntigravityUsageReader()
    ) {
        self.chatsRoot = chatsRoot
        self.antigravityRoot = antigravityRoot
        self.clock = now
        self.quotaSource = quotaSource
    }

    public static var defaultChatsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
    }

    public static var defaultAntigravityRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("antigravity-cli", isDirectory: true)
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let calendar = Calendar.current
        let now = clock()
        let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now

        let files = chatFiles(in: chatsRoot)
        let antigravityRootExists = directoryExists(antigravityRoot)
        let antigravityActive = antigravityRootExists && antigravityActive(since: cutoff)

        // 1. Live Antigravity quota. It's the currently supported client, so it
        //    wins over legacy chat files whenever it can be read — the two would
        //    otherwise describe different tools.
        if antigravityRootExists, let groups = await quotaSource.fetchQuotaGroups(), !groups.isEmpty {
            return UsageSnapshot(
                provider: .gemini,
                planName: "Antigravity",
                dailyTokenUsage: [],
                quotaGroups: groups
            )
        }

        // No legacy Gemini CLI data at all.
        guard !files.isEmpty else {
            if antigravityActive { return antigravityNoticeSnapshot }
            throw UsageProviderError.notConfigured
        }

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

        // A legacy file can be recently touched (mtime in window) while carrying
        // only old messages — filter by each message's own timestamp so it
        // doesn't count as "real recent usage".
        let recentDeltas = deltas.filter { $0.0 >= cutoff }

        // Legacy CLI has real recent usage — the normal token-chart snapshot.
        if !recentDeltas.isEmpty {
            let daily = DailyUsageBucketing.dailyUsage(
                tokenDeltas: recentDeltas,
                referenceDate: now,
                calendar: calendar
            )
            return UsageSnapshot(
                provider: .gemini,
                planName: "Gemini",
                dailyTokenUsage: daily
            )
        }

        // Legacy CLI is present but idle. If the user has since moved to
        // Antigravity, say so; otherwise the honest "no recent usage" chart.
        if antigravityActive {
            return antigravityNoticeSnapshot
        }

        return UsageSnapshot(
            provider: .gemini,
            planName: "Gemini",
            dailyTokenUsage: DailyUsageBucketing.dailyUsage(
                tokenDeltas: [],
                referenceDate: now,
                calendar: calendar
            )
        )
    }

    private var antigravityNoticeSnapshot: UsageSnapshot {
        UsageSnapshot(
            provider: .gemini,
            planName: "Gemini",
            dailyTokenUsage: [],
            note: Self.antigravityNote
        )
    }

    /// `true` when `~/.gemini/antigravity-cli/` exists and shows conversation
    /// activity on or after `cutoff` — mtime of `history.jsonl` or the newest
    /// entry under `conversations/`. No SQLite parsing (there are no token
    /// counts in there anyway).
    private func antigravityActive(since cutoff: Date) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: antigravityRoot.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        let history = antigravityRoot.appendingPathComponent("history.jsonl", isDirectory: false)
        if modificationDate(of: history) >= cutoff { return true }

        let conversations = antigravityRoot.appendingPathComponent("conversations", isDirectory: true)
        if let entries = try? fm.contentsOfDirectory(
            at: conversations,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries where modificationDate(of: entry) >= cutoff {
                return true
            }
        }

        return false
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

    private func directoryExists(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
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
