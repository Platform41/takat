import XCTest
@testable import Takat

final class CodexSessionParserTests: XCTestCase {
    private func tokenCountLine(
        timestamp: String,
        input: Int,
        cached: Int = 0,
        cacheWrite: Int = 0,
        output: Int = 0,
        reasoning: Int = 0,
        sessionPercent: Double,
        weeklyPercent: Double,
        planType: String
    ) -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":\#(cacheWrite),"output_tokens":\#(output),"reasoning_output_tokens":\#(reasoning)}},"rate_limits":{"primary":{"used_percent":\#(sessionPercent),"window_minutes":300,"resets_at":1788690513},"secondary":{"used_percent":\#(weeklyPercent),"window_minutes":10080,"resets_at":1788748053},"plan_type":"\#(planType)","limit_id":"codex"}}}"#
    }

    private func sessionMetaLine(timestamp: String) -> String {
        #"{"timestamp":"\#(timestamp)","type":"session_meta","payload":{"session_id":"fake","cwd":"/fake","cli_version":"0.153.4","timestamp":"\#(timestamp)","base_instructions":{"text":"FAKE"}}}"#
    }

    func testExtractsLastRateLimits() {
        let lines = [
            tokenCountLine(timestamp: "2026-09-06T06:50:06.843Z", input: 100, sessionPercent: 10, weeklyPercent: 20, planType: "plus"),
            tokenCountLine(timestamp: "2026-09-06T06:51:06.843Z", input: 200, cached: 100, output: 50, sessionPercent: 12, weeklyPercent: 22, planType: "pro")
        ]

        let data = CodexSessionParser.parse(lines: lines)

        XCTAssertEqual(data.rateLimits?.plan_type, "pro")
        XCTAssertEqual(data.rateLimits?.primary?.used_percent, 12)
        XCTAssertEqual(data.rateLimits?.secondary?.used_percent, 22)
        XCTAssertEqual(data.tokenDeltas.count, 2)
        XCTAssertEqual(data.tokenDeltas.last?.1, 150)
    }

    func testNewTokensMath() {
        XCTAssertEqual(
            CodexSessionParser.newTokens(
                CodexTokenUsage(input_tokens: 1000, cached_input_tokens: 900, cache_write_input_tokens: 0, output_tokens: 200, reasoning_output_tokens: 50, total_tokens: nil)
            ),
            350
        )
        XCTAssertEqual(
            CodexSessionParser.newTokens(
                CodexTokenUsage(input_tokens: 900, cached_input_tokens: 900, cache_write_input_tokens: 0, output_tokens: 0, reasoning_output_tokens: 0, total_tokens: nil)
            ),
            0
        )
    }

    func testFullyCachedTurnContributesZeroToBucket() {
        let line = tokenCountLine(timestamp: "2026-09-06T06:50:06.843Z", input: 900, cached: 900, output: 0, sessionPercent: 10, weeklyPercent: 20, planType: "plus")
        let data = CodexSessionParser.parse(lines: [line])

        XCTAssertEqual(data.tokenDeltas.map(\.1), [0])
    }

    func testPlanNameMapping() {
        XCTAssertEqual(CodexSessionParser.planName(from: "plus"), "Plus")
        XCTAssertEqual(CodexSessionParser.planName(from: "pro"), "Pro")
        XCTAssertEqual(CodexSessionParser.planName(from: nil), "Codex")
        XCTAssertEqual(CodexSessionParser.planName(from: "ultra-mega"), "Codex")
        XCTAssertEqual(CodexSessionParser.planName(from: ""), "Codex")
    }

    func testToleratesCorruptFinalLine() {
        let valid = tokenCountLine(timestamp: "2026-09-06T06:50:06.843Z", input: 100, sessionPercent: 10, weeklyPercent: 20, planType: "plus")
        let lines = [
            sessionMetaLine(timestamp: "2026-09-06T06:00:00.000Z"),
            valid,
            "{truncated garbage"
        ]

        let data = CodexSessionParser.parse(lines: lines)

        XCTAssertEqual(data.rateLimits?.plan_type, "plus")
        XCTAssertEqual(data.tokenDeltas.count, 1)
    }

    func testBucketsIntoCalendarDays() {
        let calendar = Calendar(identifier: .gregorian)
        let ref = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
        let startOfToday = calendar.startOfDay(for: ref)
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: startOfToday)!

        let delta1 = calendar.date(byAdding: .hour, value: 1, to: threeDaysAgo)!
        let delta2 = calendar.date(byAdding: .hour, value: 2, to: threeDaysAgo)!

        let usage = CodexSessionParser.dailyUsage(
            tokenDeltas: [(delta1, 100), (delta2, 50)],
            referenceDate: ref,
            calendar: calendar
        )

        XCTAssertEqual(usage.count, 7)
        XCTAssertEqual(usage.map(\.tokenCount), [0, 0, 0, 150, 0, 0, 0])
        XCTAssertEqual(usage.map(\.day), usage.map(\.day).sorted())
    }
}

final class CodexUsageProviderTests: XCTestCase {
    private func makeSessionDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TakatCodexTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeSessionFile(_ name: String, lines: [String], in dir: URL) {
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n")
        try? text.data(using: .utf8)!.write(to: url)
    }

    private func codexFixturesDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/codex-sessions", isDirectory: true)
    }

    private func tokenCountLine(
        timestamp: String,
        input: Int,
        cached: Int = 0,
        cacheWrite: Int = 0,
        output: Int = 0,
        reasoning: Int = 0,
        sessionPercent: Double,
        weeklyPercent: Double,
        planType: String
    ) -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":\#(cacheWrite),"output_tokens":\#(output),"reasoning_output_tokens":\#(reasoning)}},"rate_limits":{"primary":{"used_percent":\#(sessionPercent),"window_minutes":300,"resets_at":1788690513},"secondary":{"used_percent":\#(weeklyPercent),"window_minutes":10080,"resets_at":1788748053},"plan_type":"\#(planType)","limit_id":"codex"}}}"#
    }

    private func sessionMetaLine(timestamp: String) -> String {
        #"{"timestamp":"\#(timestamp)","type":"session_meta","payload":{"session_id":"fake","cwd":"/fake","cli_version":"0.153.4","timestamp":"\#(timestamp)","base_instructions":{"text":"FAKE"}}}"#
    }

    func testPicksNewestFileAcrossNestedDirs() async throws {
        let provider = CodexUsageProvider(sessionsDirectory: codexFixturesDir())
        let snapshot = try await provider.fetchUsage()

        // Newest fixture (2026/09/06) carries plan_type "pro".
        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(snapshot.sessionPercent, 15.0)
        XCTAssertEqual(snapshot.weeklyPercent, 88.5)
        XCTAssertNotNil(snapshot.resetDate)
    }

    func testFallsBackToSecondFile() async throws {
        let dir = makeSessionDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Newest file has no token_count lines (brand-new session).
        writeSessionFile(
            "rollout-b.jsonl",
            lines: [sessionMetaLine(timestamp: "2026-09-06T10:00:00.000Z")],
            in: dir
        )
        // Older file has the rate limits.
        writeSessionFile(
            "rollout-a.jsonl",
            lines: [
                sessionMetaLine(timestamp: "2026-09-05T10:00:00.000Z"),
                tokenCountLine(timestamp: "2026-09-05T10:05:00.000Z", input: 200, sessionPercent: 8, weeklyPercent: 40, planType: "plus")
            ],
            in: dir
        )

        let snapshot = try await CodexUsageProvider(sessionsDirectory: dir).fetchUsage()

        XCTAssertEqual(snapshot.planName, "Plus")
        XCTAssertEqual(snapshot.weeklyPercent, 40.0)
    }

    func testMissingDirectoryThrowsNotConfigured() async {
        let dir = makeSessionDir().appendingPathComponent("does-not-exist", isDirectory: true)
        let provider = CodexUsageProvider(sessionsDirectory: dir)

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .notConfigured")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmptyDirectoryThrowsNotConfigured() async {
        let dir = makeSessionDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let provider = CodexUsageProvider(sessionsDirectory: dir)

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .notConfigured")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIgnoresNonRolloutEntries() async throws {
        let dir = makeSessionDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        writeSessionFile(
            "rollout-real.jsonl",
            lines: [
                sessionMetaLine(timestamp: "2026-09-06T10:00:00.000Z"),
                tokenCountLine(timestamp: "2026-09-06T10:05:00.000Z", input: 300, sessionPercent: 15, weeklyPercent: 88, planType: "team")
            ],
            in: dir
        )
        writeSessionFile("history.jsonl", lines: ["{\"not\":\"usage\"}"], in: dir)
        writeSessionFile("notes.txt", lines: ["hello"], in: dir)

        let snapshot = try await CodexUsageProvider(sessionsDirectory: dir).fetchUsage()

        XCTAssertEqual(snapshot.planName, "Team")
    }

    func testDailyTokenUsageAlwaysSevenEntries() async throws {
        let dir = makeSessionDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let todayLine = tokenCountLine(timestamp: iso.string(from: now), input: 200, cached: 100, output: 11, sessionPercent: 5, weeklyPercent: 5, planType: "plus")
        let yesterdayLine = tokenCountLine(timestamp: iso.string(from: yesterday), input: 300, cached: 78, sessionPercent: 5, weeklyPercent: 5, planType: "plus")

        writeSessionFile(
            "rollout-recent.jsonl",
            lines: [sessionMetaLine(timestamp: iso.string(from: now)), todayLine, yesterdayLine],
            in: dir
        )

        let snapshot = try await CodexUsageProvider(sessionsDirectory: dir).fetchUsage()

        XCTAssertEqual(snapshot.dailyTokenUsage.count, 7)
        let days = snapshot.dailyTokenUsage.map(\.day)
        XCTAssertEqual(days, days.sorted())
        XCTAssertEqual(snapshot.dailyTokenUsage.last?.tokenCount, 111)
        XCTAssertEqual(snapshot.dailyTokenUsage[snapshot.dailyTokenUsage.count - 2].tokenCount, 222)
    }
}
