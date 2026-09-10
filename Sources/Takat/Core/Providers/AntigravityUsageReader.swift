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
/// its structured payload. No shell. Takat never reads OAuth credentials and
/// never calls Google's Code Assist backend itself — but `agy` may refresh its
/// quota over the network using its own existing authentication.
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
        let cancelled = CancelFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(
                        returning: Self.runBlocking(executable, timeout: timeout, isCancelled: { cancelled.isSet })
                    )
                }
            }
        } onCancel: {
            cancelled.set()
        }
    }

    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        var isSet: Bool { lock.withLock { flag } }
        func set() { lock.withLock { flag = true } }
    }

    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Data()
        func append(_ data: Data) { lock.withLock { value.append(data) } }
        var data: Data { lock.withLock { value } }
    }

    /// Reads a handle to EOF. Stores at most `cap` bytes (when `box` is given);
    /// keeps reading past the cap so the pipe never back-pressures the child.
    private static func drain(_ handle: FileHandle, into box: OutputBox?, cap: Int) {
        var stored = 0
        while let chunk = try? handle.read(upToCount: 64 << 10), !chunk.isEmpty {
            guard let box else { continue }
            let room = cap - stored
            guard room > 0 else { continue }
            let slice = chunk.prefix(room)
            box.append(Data(slice))
            stored += slice.count
        }
    }

    private static func runBlocking(
        _ executable: URL,
        timeout: TimeInterval,
        isCancelled: @escaping () -> Bool
    ) -> Data? {
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

        // Drain BOTH pipes concurrently from launch. A child that fills the
        // stderr buffer must never block before it can exit.
        let outBox = OutputBox()
        let readers = DispatchGroup()
        let queue = DispatchQueue(label: "antigravity.usage.read", attributes: .concurrent)
        queue.async(group: readers) { drain(stdout.fileHandleForReading, into: outBox, cap: maxOutputBytes) }
        queue.async(group: readers) { drain(stderr.fileHandleForReading, into: nil, cap: 0) }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        let deadline = Date().addingTimeInterval(timeout)
        var abandoned = false
        while true {
            if finished.wait(timeout: .now() + .milliseconds(50)) == .success { break }
            if Date() >= deadline || isCancelled() {
                abandoned = true
                process.terminate()
                if finished.wait(timeout: .now() + .milliseconds(300)) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                _ = finished.wait(timeout: .now() + .seconds(2))
                break
            }
        }

        process.waitUntilExit()          // ensure the child is reaped
        readers.wait()                    // both pipes drained / closed

        if abandoned { return nil }
        guard process.terminationStatus == 0 else { return nil }
        return outBox.data
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
