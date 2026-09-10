import Foundation

/// Supplies Antigravity's `/usage` quota groups. Injected into `GeminiUsageProvider`
/// so provider tests never launch the real `agy` CLI.
public protocol AntigravityQuotaSource: Sendable {
    /// The quota groups from `agy /usage`, or `nil` when Antigravity / `agy`
    /// isn't available or the payload can't be trusted. A non-nil result always
    /// has at least one group with at least one window.
    func fetchQuotaGroups() async -> [UsageQuotaGroup]?
}

/// Runs the installed `agy` executable's local `/usage` slash command and decodes
/// its structured payload. No shell, no network, no OAuth files — the official
/// executable owns authentication.
public struct AntigravityUsageReader: AntigravityQuotaSource {
    /// Overrides executable resolution in tests.
    private let executableOverride: URL?
    private let processTimeout: TimeInterval

    public init(executableOverride: URL? = nil, processTimeout: TimeInterval = 45) {
        self.executableOverride = executableOverride
        self.processTimeout = processTimeout
    }

    static let arguments = ["--print", "/usage", "--output-format", "json", "--print-timeout", "30s"]
    static let maxOutputBytes = 1 << 20  // 1 MiB

    public func fetchQuotaGroups() async -> [UsageQuotaGroup]? {
        guard let executable = resolveExecutable() else { return nil }
        guard let data = await run(executable) else { return nil }
        return Self.decode(data)
    }

    // MARK: Executable resolution

    private func resolveExecutable() -> URL? {
        if let executableOverride {
            return isRunnable(executableOverride) ? executableOverride : nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/agy", isDirectory: false),
            URL(fileURLWithPath: "/opt/homebrew/bin/agy"),
            URL(fileURLWithPath: "/usr/local/bin/agy"),
        ]
        return candidates.first(where: isRunnable)
    }

    /// A GUI app has no interactive shell `PATH`, so `command -v` is useless here.
    /// Require a real executable file (following one level of symlink).
    private func isRunnable(_ url: URL) -> Bool {
        let fm = FileManager.default
        let resolved = url.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return fm.isExecutableFile(atPath: resolved.path)
    }

    // MARK: Process

    private func run(_ executable: URL) async -> Data? {
        let timeout = processTimeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.runBlocking(executable, timeout: timeout))
            }
        }
    }

    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Data()
        func append(_ data: Data) { lock.withLock { value.append(data) } }
        var data: Data { lock.withLock { value } }
    }

    private static func runBlocking(_ executable: URL, timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }

        // Read stdout on its own thread so a silent child (no output, no exit)
        // can't wedge us — the outer timeout stays in control.
        let box = OutputBox()
        let reader = DispatchQueue(label: "antigravity.usage.read")
        reader.async {
            let handle = stdout.fileHandleForReading
            var collected = Data()
            while let chunk = try? handle.read(upToCount: 64 << 10), !chunk.isEmpty {
                collected.append(chunk)
                if collected.count >= maxOutputBytes { break }
            }
            box.append(collected)
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            return nil
        }

        // Process exited: its pipe write-ends are closed, so the reader loop
        // ends on its own. Wait for it, then drain stderr and discard.
        reader.sync {}
        _ = try? stderr.fileHandleForReading.readToEnd()

        guard process.terminationStatus == 0 else { return nil }
        return box.data
    }

    // MARK: Decoding

    /// Pure JSON → quota groups. Models only the fields it needs — the free-form
    /// `response`, `description`, and `usage` blocks are never decoded, so nothing
    /// from them can reach a persisted snapshot.
    public static func decode(_ data: Data) -> [UsageQuotaGroup]? {
        guard let root = try? JSONDecoder().decode(AgyResponse.self, from: data) else { return nil }
        guard root.status == "SUCCESS",
              root.command?.name == "usage",
              let rawGroups = root.command?.data?.groups else {
            return nil
        }

        var groups: [UsageQuotaGroup] = []
        for rawGroup in rawGroups {
            let windows: [UsageQuotaWindow] = (rawGroup.buckets ?? []).compactMap { bucket in
                guard let id = bucket.id,
                      let fraction = bucket.remaining_fraction,
                      fraction.isFinite else {
                    return nil
                }
                let used = min(max((1 - fraction) * 100, 0), 100)
                return UsageQuotaWindow(
                    id: id,
                    name: windowLabel(bucketID: id, window: bucket.window),
                    usedPercent: used,
                    resetDate: parseTimestamp(bucket.reset_time)
                )
            }
            guard !windows.isEmpty else { continue }
            let bucketIDs = windows.map(\.id)
            groups.append(
                UsageQuotaGroup(
                    id: bucketIDs.sorted().joined(separator: "+"),
                    name: groupLabel(bucketIDs: bucketIDs, fallback: rawGroup.name),
                    windows: windows
                )
            )
        }
        return groups.isEmpty ? nil : groups
    }

    static func groupLabel(bucketIDs: [String], fallback: String?) -> String {
        if bucketIDs.contains(where: { $0.hasPrefix("gemini") }) { return "Gemini models" }
        if bucketIDs.contains(where: { $0.hasPrefix("3p") }) { return "Claude and GPT models" }
        return sanitizedLabel(fallback) ?? "Usage"
    }

    static func windowLabel(bucketID: String, window: String?) -> String {
        if window == "weekly" || bucketID.hasSuffix("-weekly") { return "Weekly" }
        if window == "daily" || bucketID.hasSuffix("-daily") { return "Daily" }
        return sanitizedLabel(window) ?? "Limit"
    }

    /// Length-bounded, character-filtered — for unknown future IDs only.
    static func sanitizedLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.prefix(40).filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw)
    }

    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

// MARK: - Decode targets (only the trusted fields)

struct AgyResponse: Decodable {
    let status: String?
    let command: AgyCommand?
}

struct AgyCommand: Decodable {
    let name: String?
    let data: AgyCommandData?
}

struct AgyCommandData: Decodable {
    let groups: [AgyGroup]?
}

struct AgyGroup: Decodable {
    let name: String?
    let buckets: [AgyBucket]?
}

struct AgyBucket: Decodable {
    let id: String?
    let window: String?
    let remaining_fraction: Double?
    let reset_time: String?
}
