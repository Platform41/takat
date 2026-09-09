import XCTest
@testable import Takat

final class GeminiSessionParserTests: XCTestCase {
    private let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func geminiMessage(
        type: String,
        timestamp: String,
        input: Int = 0,
        cached: Int = 0,
        output: Int = 0,
        thoughts: Int = 0,
        content: String? = nil,
        thoughtsArray: String? = nil
    ) -> String {
        let tokens = #"{"input":\#(input),"output":\#(output),"cached":\#(cached),"thoughts":\#(thoughts)}"#
        let contentField = content.map { #","content":"\#($0)""# } ?? ""
        let thoughtsField = thoughtsArray.map { #","thoughts":\#($0)"# } ?? ""
        return #"{"id":"fake","timestamp":"\#(timestamp)","type":"\#(type)","model":"gemini-3-flash-preview","tokens":\#(tokens)\#(contentField)\#(thoughtsField)}"#
    }

    private func geminiFile(_ messages: [String]) -> String {
        #"{"sessionId":"fake","projectHash":"fake","messages":[\#(messages.joined(separator: ","))]}"#
    }

    func testNewTokensMath() {
        XCTAssertEqual(
            GeminiSessionParser.newTokens(GeminiTokens(input: 1000, output: 200, cached: 900, thoughts: 50)),
            350
        )
        XCTAssertEqual(
            GeminiSessionParser.newTokens(GeminiTokens(input: 900, output: 0, cached: 900, thoughts: 0)),
            0
        )
    }

    func testUserMessagesSkipped() {
        let file = geminiFile([
            geminiMessage(type: "user", timestamp: "2026-09-06T14:11:57.880Z", input: 100),
            geminiMessage(type: "gemini", timestamp: "2026-09-06T14:12:00.000Z", input: 7, output: 3)
        ])

        let deltas = GeminiSessionParser.parse(data: Data(file.utf8))

        XCTAssertEqual(deltas.map(\.1), [10])
    }

    func testMalformedFileReturnsEmpty() {
        XCTAssertEqual(GeminiSessionParser.parse(data: Data("not json".utf8)).count, 0)
    }

    func testPrivacySentinelNeverReachesSnapshot() {
        let file = geminiFile([
            geminiMessage(
                type: "gemini",
                timestamp: "2026-09-06T14:12:00.000Z",
                input: 7,
                output: 3,
                content: "SECRET-SENTINEL",
                thoughtsArray: #"[{"subject":"x","description":"SECRET-SENTINEL"}]"#
            )
        ])

        let deltas = GeminiSessionParser.parse(data: Data(file.utf8))

        XCTAssertEqual(deltas.map(\.1), [10])

        let daily = DailyUsageBucketing.dailyUsage(tokenDeltas: deltas, referenceDate: Date(), calendar: .current)
        let snapshot = UsageSnapshot(provider: .gemini, planName: "Gemini", dailyTokenUsage: daily)

        XCTAssertFalse(String(describing: snapshot).contains("SECRET-SENTINEL"))
    }

    func testParseAndBucketIntoCalendarDays() {
        let calendar = Calendar(identifier: .gregorian)
        let ref = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: ref))!

        let file = geminiFile([
            geminiMessage(type: "gemini", timestamp: iso.string(from: calendar.date(byAdding: .hour, value: 1, to: threeDaysAgo)!), input: 100),
            geminiMessage(type: "gemini", timestamp: iso.string(from: calendar.date(byAdding: .hour, value: 2, to: threeDaysAgo)!), output: 50)
        ])

        let deltas = GeminiSessionParser.parse(data: Data(file.utf8))
        let usage = DailyUsageBucketing.dailyUsage(tokenDeltas: deltas, referenceDate: ref, calendar: calendar)

        XCTAssertEqual(usage.map(\.tokenCount), [0, 0, 0, 150, 0, 0, 0])
    }

    func testParsesCommittedFixture() {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/gemini-chats/abc123/chats/session-2026-09-06.json")

        let data = (try? Data(contentsOf: fixture)) ?? Data()
        let deltas = GeminiSessionParser.parse(data: data)

        XCTAssertEqual(deltas.map(\.1), [4656, 160])
    }
}

final class GeminiUsageProviderTests: XCTestCase {
    private func makeChatsRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TakatGeminiTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// A path that does not exist — so `antigravityActive` is false and tests
    /// don't pick up the real `~/.gemini/antigravity-cli` on the dev machine.
    private func inactiveAntigravityRoot() -> URL {
        makeChatsRoot().appendingPathComponent("no-antigravity", isDirectory: true)
    }

    /// Creates `<root>/history.jsonl` with a recent mtime.
    private func makeActiveAntigravityRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TakatAgyTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? "{}\n".data(using: .utf8)!.write(to: root.appendingPathComponent("history.jsonl"))
        return root
    }

    private func writeChatFile(_ relativePath: String, content: String, in root: URL) {
        let url = root.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.data(using: .utf8)!.write(to: url)
    }

    private let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func geminiFile(messages: [String]) -> String {
        #"{"sessionId":"fake","messages":[\#(messages.joined(separator: ","))]}"#
    }

    private func geminiMessage(timestamp: String, input: Int = 0, cached: Int = 0, output: Int = 0, thoughts: Int = 0) -> String {
        #"{"id":"fake","timestamp":"\#(timestamp)","type":"gemini","model":"gemini-3-flash-preview","tokens":{"input":\#(input),"output":\#(output),"cached":\#(cached),"thoughts":\#(thoughts)}}"#
    }

    func testAggregatesAcrossDirectories() async throws {
        let root = makeChatsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        writeChatFile("dir-a/chats/session-1.json", content: geminiFile(messages: [geminiMessage(timestamp: iso.string(from: Date()), input: 100, output: 50)]), in: root)
        writeChatFile("dir-b/chats/session-2.json", content: geminiFile(messages: [geminiMessage(timestamp: iso.string(from: Date()), input: 30)]), in: root)

        let snapshot = try await GeminiUsageProvider(chatsRoot: root, antigravityRoot: inactiveAntigravityRoot()).fetchUsage()

        let total = snapshot.dailyTokenUsage.reduce(0) { $0 + $1.tokenCount }
        XCTAssertEqual(total, 180)
        XCTAssertEqual(snapshot.planName, "Gemini")
        XCTAssertNil(snapshot.sessionPercent)
        XCTAssertNil(snapshot.weeklyPercent)
    }

    func testMtimeFilterExcludesOldFile() async throws {
        let root = makeChatsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        writeChatFile("dir/chats/recent.json", content: geminiFile(messages: [geminiMessage(timestamp: iso.string(from: Date()), input: 100)]), in: root)
        writeChatFile("dir/chats/old.json", content: geminiFile(messages: [geminiMessage(timestamp: iso.string(from: Date()), input: 999)]), in: root)

        let oldURL = root.appendingPathComponent("dir/chats/old.json")
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 24 * 3600)], ofItemAtPath: oldURL.path)

        let snapshot = try await GeminiUsageProvider(chatsRoot: root, antigravityRoot: inactiveAntigravityRoot()).fetchUsage()

        XCTAssertEqual(snapshot.dailyTokenUsage.reduce(0) { $0 + $1.tokenCount }, 100)
    }

    func testMissingDirectoryThrowsNotConfigured() async {
        let root = makeChatsRoot().appendingPathComponent("does-not-exist", isDirectory: true)
        let provider = GeminiUsageProvider(chatsRoot: root, antigravityRoot: inactiveAntigravityRoot())

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .notConfigured")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDirectoryWithoutChatsThrowsNotConfigured() async {
        let root = makeChatsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("dir"), withIntermediateDirectories: true)

        let provider = GeminiUsageProvider(chatsRoot: root, antigravityRoot: inactiveAntigravityRoot())

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
        let root = makeChatsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        writeChatFile("dir/chats/stale.json", content: geminiFile(messages: [geminiMessage(timestamp: iso.string(from: Date()), input: 500)]), in: root)
        let url = root.appendingPathComponent("dir/chats/stale.json")
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 24 * 3600)], ofItemAtPath: url.path)

        let snapshot = try await GeminiUsageProvider(chatsRoot: root, antigravityRoot: inactiveAntigravityRoot()).fetchUsage()

        XCTAssertEqual(snapshot.planName, "Gemini")
        XCTAssertEqual(snapshot.dailyTokenUsage.count, 7)
        XCTAssertTrue(snapshot.dailyTokenUsage.allSatisfy { $0.tokenCount == 0 })
        XCTAssertNil(snapshot.sessionPercent)
        XCTAssertNil(snapshot.weeklyPercent)
    }

    func testAllFilesUndecodableThrowsUnavailable() async {
        let root = makeChatsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        writeChatFile("dir/chats/bad.json", content: "not json", in: root)

        let provider = GeminiUsageProvider(chatsRoot: root, antigravityRoot: inactiveAntigravityRoot())

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .unavailable")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAntigravityActiveWithNoLegacyReturnsNotice() async throws {
        let chats = makeChatsRoot().appendingPathComponent("missing", isDirectory: true)
        let agy = makeActiveAntigravityRoot()
        defer { try? FileManager.default.removeItem(at: agy) }

        let snapshot = try await GeminiUsageProvider(chatsRoot: chats, antigravityRoot: agy).fetchUsage()

        XCTAssertEqual(snapshot.note, GeminiUsageProvider.antigravityNote)
        XCTAssertEqual(snapshot.planName, "Gemini")
        XCTAssertTrue(snapshot.dailyTokenUsage.isEmpty)
        XCTAssertNil(snapshot.sessionPercent)
    }

    func testAntigravityActiveWithStaleLegacyReturnsNotice() async throws {
        let root = makeChatsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let agy = makeActiveAntigravityRoot()
        defer { try? FileManager.default.removeItem(at: agy) }

        writeChatFile("dir/chats/stale.json", content: geminiFile(messages: [geminiMessage(timestamp: iso.string(from: Date()), input: 500)]), in: root)
        let url = root.appendingPathComponent("dir/chats/stale.json")
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 24 * 3600)], ofItemAtPath: url.path)

        let snapshot = try await GeminiUsageProvider(chatsRoot: root, antigravityRoot: agy).fetchUsage()

        XCTAssertEqual(snapshot.note, GeminiUsageProvider.antigravityNote)
        XCTAssertTrue(snapshot.dailyTokenUsage.isEmpty)
    }

    func testLegacyDataTakesPrecedenceOverAntigravity() async throws {
        let root = makeChatsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let agy = makeActiveAntigravityRoot()
        defer { try? FileManager.default.removeItem(at: agy) }

        writeChatFile("dir/chats/recent.json", content: geminiFile(messages: [geminiMessage(timestamp: iso.string(from: Date()), input: 100, output: 20)]), in: root)

        let snapshot = try await GeminiUsageProvider(chatsRoot: root, antigravityRoot: agy).fetchUsage()

        XCTAssertNil(snapshot.note)
        XCTAssertEqual(snapshot.dailyTokenUsage.reduce(0) { $0 + $1.tokenCount }, 120)
    }

    func testAntigravityWithRecentConversationCountsAsActive() async throws {
        let chats = makeChatsRoot().appendingPathComponent("missing", isDirectory: true)
        let agy = FileManager.default.temporaryDirectory
            .appendingPathComponent("TakatAgyConv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: agy) }
        try? FileManager.default.createDirectory(at: agy.appendingPathComponent("conversations"), withIntermediateDirectories: true)
        try? "x".data(using: .utf8)!.write(to: agy.appendingPathComponent("conversations/a.db"))

        let snapshot = try await GeminiUsageProvider(chatsRoot: chats, antigravityRoot: agy).fetchUsage()

        XCTAssertEqual(snapshot.note, GeminiUsageProvider.antigravityNote)
    }
}
