import XCTest
@testable import Takat

final class ClaudeSessionParserTests: XCTestCase {
    private let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func claudeLine(
        type: String,
        timestamp: String,
        input: Int = 0,
        cacheCreation: Int = 0,
        cacheRead: Int = 0,
        output: Int = 0,
        isSidechain: Bool = false,
        content: String? = nil
    ) -> String {
        let usageJSON = #"{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheCreation),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output)}"#
        let contentField = content.map { #","content":"\#($0)""# } ?? ""
        let message = #"{"role":"assistant","usage":\#(usageJSON)\#(contentField)}"#
        return #"{"type":"\#(type)","timestamp":"\#(timestamp)","isSidechain":\#(isSidechain),"message":\#(message)}"#
    }

    func testNewTokensMath() {
        XCTAssertEqual(
            ClaudeSessionParser.newTokens(ClaudeTokenUsage(input_tokens: 10, cache_creation_input_tokens: 20, output_tokens: 30)),
            60
        )
        XCTAssertEqual(
            ClaudeSessionParser.newTokens(ClaudeTokenUsage(input_tokens: nil, cache_creation_input_tokens: nil, output_tokens: nil)),
            0
        )
    }

    func testCacheReadExcluded() {
        let line = claudeLine(type: "assistant", timestamp: "2026-09-06T14:11:57.880Z", input: 5, cacheRead: 1000, output: 5)
        let deltas = ClaudeSessionParser.parse(lines: [line])

        XCTAssertEqual(deltas.map(\.1), [10])
    }

    func testIgnoresUserAndUnknownLines() {
        let lines = [
            #"{"type":"user","timestamp":"2026-09-06T14:10:00.000Z","message":{"role":"user","content":"hello"}}"#,
            #"{"type":"system","timestamp":"2026-09-06T14:10:00.000Z"}"#,
            claudeLine(type: "assistant", timestamp: "2026-09-06T14:11:57.880Z", input: 7, output: 3)
        ]

        let deltas = ClaudeSessionParser.parse(lines: lines)

        XCTAssertEqual(deltas.map(\.1), [10])
    }

    func testToleratesMalformedFinalLine() {
        let lines = [
            claudeLine(type: "assistant", timestamp: "2026-09-06T14:11:57.880Z", input: 7, output: 3),
            "{truncated garbage"
        ]

        let deltas = ClaudeSessionParser.parse(lines: lines)

        XCTAssertEqual(deltas.map(\.1), [10])
    }

    func testCountsSidechainLines() {
        let line = claudeLine(type: "assistant", timestamp: "2026-09-06T14:12:00.000Z", input: 10, output: 20, isSidechain: true)
        let deltas = ClaudeSessionParser.parse(lines: [line])

        XCTAssertEqual(deltas.map(\.1), [30])
    }

    func testPrivacySentinelNeverReachesSnapshot() {
        let line = claudeLine(type: "assistant", timestamp: "2026-09-06T14:11:57.880Z", input: 7, output: 3, content: "SECRET-SENTINEL")
        let deltas = ClaudeSessionParser.parse(lines: [line])

        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(deltas.first?.1, 10)

        let daily = DailyUsageBucketing.dailyUsage(tokenDeltas: deltas, referenceDate: Date(), calendar: .current)
        let snapshot = UsageSnapshot(provider: .claude, planName: "Claude", dailyTokenUsage: daily)

        XCTAssertFalse(String(describing: snapshot).contains("SECRET-SENTINEL"))
    }

    func testParseAndBucketIntoCalendarDays() {
        let calendar = Calendar(identifier: .gregorian)
        let ref = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: ref))!

        let line1 = claudeLine(type: "assistant", timestamp: iso.string(from: calendar.date(byAdding: .hour, value: 1, to: threeDaysAgo)!), input: 100)
        let line2 = claudeLine(type: "assistant", timestamp: iso.string(from: calendar.date(byAdding: .hour, value: 2, to: threeDaysAgo)!), output: 50)

        let deltas = ClaudeSessionParser.parse(lines: [line1, line2])
        let usage = DailyUsageBucketing.dailyUsage(tokenDeltas: deltas, referenceDate: ref, calendar: calendar)

        XCTAssertEqual(usage.map(\.tokenCount), [0, 0, 0, 150, 0, 0, 0])
    }

    func testParsesCommittedFixture() {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/claude-projects/-fake-project/aaaaaaaa-0000-0000-0000-000000000001.jsonl")

        let data = (try? Data(contentsOf: fixture)) ?? Data()
        let deltas = ClaudeSessionParser.parse(lines: JSONLLines(data: data))

        XCTAssertEqual(deltas.map(\.1), [11873, 30])
    }
}

final class ClaudeUsageProviderTests: XCTestCase {
    private func makeProjectsDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TakatClaudeTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func missingConfigFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TakatClaudeTests-no-config-\(UUID().uuidString).json")
    }

    private func writeFile(_ name: String, lines: [String], in dir: URL) {
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").data(using: .utf8)!.write(to: url)
    }

    private func claudeLine(
        timestamp: String,
        input: Int = 0,
        cacheCreation: Int = 0,
        cacheRead: Int = 0,
        output: Int = 0
    ) -> String {
        #"{"type":"assistant","timestamp":"\#(timestamp)","isSidechain":false,"message":{"role":"assistant","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheCreation),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output)}}}"#
    }

    private let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func testAggregatesAcrossSlugDirectories() async throws {
        let dir = makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        writeFile("slug-a/a.jsonl", lines: [claudeLine(timestamp: iso.string(from: Date()), input: 100, output: 50)], in: dir)
        writeFile("slug-b/b.jsonl", lines: [claudeLine(timestamp: iso.string(from: Date()), input: 30)], in: dir)

        let snapshot = try await ClaudeUsageProvider(projectsDirectory: dir, configFile: missingConfigFile()).fetchUsage()

        let total = snapshot.dailyTokenUsage.reduce(0) { $0 + $1.tokenCount }
        XCTAssertEqual(total, 180)
        XCTAssertEqual(snapshot.planName, "Claude")
        XCTAssertNil(snapshot.sessionPercent)
        XCTAssertNil(snapshot.weeklyPercent)
    }

    func testMtimeFilterExcludesOldFile() async throws {
        let dir = makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        writeFile("slug/recent.jsonl", lines: [claudeLine(timestamp: iso.string(from: Date()), input: 100)], in: dir)
        writeFile("slug/old.jsonl", lines: [claudeLine(timestamp: iso.string(from: Date()), input: 999)], in: dir)

        let oldURL = dir.appendingPathComponent("slug/old.jsonl")
        let oldDate = Date().addingTimeInterval(-30 * 24 * 3600)
        try? FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldURL.path)

        let snapshot = try await ClaudeUsageProvider(projectsDirectory: dir, configFile: missingConfigFile()).fetchUsage()

        let total = snapshot.dailyTokenUsage.reduce(0) { $0 + $1.tokenCount }
        XCTAssertEqual(total, 100)
    }

    func testMissingDirectoryThrowsNotConfigured() async {
        let dir = makeProjectsDir().appendingPathComponent("does-not-exist", isDirectory: true)
        let provider = ClaudeUsageProvider(projectsDirectory: dir)

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .notConfigured")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDirectoryWithoutJSONLThrowsNotConfigured() async {
        let dir = makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("slug"), withIntermediateDirectories: true)

        let provider = ClaudeUsageProvider(projectsDirectory: dir)

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .notConfigured")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNoRecentUsageReturnsZeroChart() async throws {
        let dir = makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        writeFile("slug/stale.jsonl", lines: [claudeLine(timestamp: iso.string(from: Date()), input: 500)], in: dir)
        let url = dir.appendingPathComponent("slug/stale.jsonl")
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 24 * 3600)], ofItemAtPath: url.path)

        let snapshot = try await ClaudeUsageProvider(projectsDirectory: dir, configFile: missingConfigFile()).fetchUsage()

        XCTAssertEqual(snapshot.planName, "Claude")
        XCTAssertEqual(snapshot.dailyTokenUsage.count, 7)
        XCTAssertTrue(snapshot.dailyTokenUsage.allSatisfy { $0.tokenCount == 0 })
        XCTAssertNil(snapshot.sessionPercent)
        XCTAssertNil(snapshot.weeklyPercent)
    }

    func testUnavailableWhenFilesCannotBeRead() async {
        let dir = makeProjectsDir()
        let unreadable = dir.appendingPathComponent("slug/a.jsonl")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
            try? FileManager.default.removeItem(at: dir)
        }

        writeFile("slug/a.jsonl", lines: [claudeLine(timestamp: iso.string(from: Date()), input: 5, output: 5)], in: dir)
        try? FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)

        let provider = ClaudeUsageProvider(projectsDirectory: dir)

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .unavailable")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPlanNameFromConfigFile() async throws {
        let dir = makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        writeFile("slug/a.jsonl", lines: [claudeLine(timestamp: iso.string(from: Date()), input: 100, output: 50)], in: dir)

        let configFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/claude-config/claude.json")

        let snapshot = try await ClaudeUsageProvider(projectsDirectory: dir, configFile: configFile).fetchUsage()

        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(snapshot.dailyTokenUsage.reduce(0) { $0 + $1.tokenCount }, 150)
    }

    func testMissingConfigFileFallsBackToClaude() async throws {
        let dir = makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        writeFile("slug/a.jsonl", lines: [claudeLine(timestamp: iso.string(from: Date()), input: 100)], in: dir)

        let missing = dir.appendingPathComponent("no-such-config.json")
        let snapshot = try await ClaudeUsageProvider(projectsDirectory: dir, configFile: missing).fetchUsage()

        XCTAssertEqual(snapshot.planName, "Claude")
        XCTAssertEqual(snapshot.dailyTokenUsage.reduce(0) { $0 + $1.tokenCount }, 100)
    }
}
