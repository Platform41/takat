import XCTest
@testable import Takat

final class AntigravityUsageReaderDecodeTests: XCTestCase {
    private func payload(_ groups: String, status: String = "SUCCESS", command: String = "usage") -> Data {
        Data(#"""
        {
          "conversation_id": "",
          "status": "\#(status)",
          "response": "human readable bars — SECRET-SENTINEL",
          "duration_seconds": 0,
          "num_turns": 0,
          "usage": { "input_tokens": 0, "output_tokens": 0, "total_tokens": 0 },
          "command": {
            "name": "\#(command)",
            "data": {
              "description": "Within each group, models share a weekly limit. SECRET-SENTINEL",
              "groups": [\#(groups)]
            }
          }
        }
        """#.utf8)
    }

    private let twoGroups = #"""
    {
      "name": "Gemini Models",
      "description": "Models within this group: Gemini Flash, Gemini Pro",
      "buckets": [
        { "id": "gemini-weekly", "name": "Weekly Limit Remaining",
          "description": "You have hit your weekly limit. SECRET-SENTINEL",
          "window": "weekly", "remaining_fraction": 0.84, "reset_time": "2099-09-14T04:48:31Z" }
      ]
    },
    {
      "name": "Claude and GPT models",
      "buckets": [
        { "id": "3p-weekly", "name": "Weekly Limit Remaining",
          "window": "weekly", "remaining_fraction": 0.25, "reset_time": "2099-09-15T17:41:12.123456Z" }
      ]
    }
    """#

    func testDecodesTheTwoGroupPayload() throws {
        let groups = try XCTUnwrap(AntigravityUsageReader.decode(payload(twoGroups)))
        XCTAssertEqual(groups.count, 2)

        XCTAssertEqual(groups[0].id, "gemini-weekly")
        XCTAssertEqual(groups[0].name, "Gemini models")
        XCTAssertEqual(groups[0].windows.count, 1)
        XCTAssertEqual(groups[0].windows[0].id, "gemini-weekly")
        XCTAssertEqual(groups[0].windows[0].name, "Weekly")
        XCTAssertEqual(groups[0].windows[0].usedPercent, 16, accuracy: 0.0001)
        XCTAssertNotNil(groups[0].windows[0].resetDate)

        XCTAssertEqual(groups[1].name, "Claude and GPT models")
        XCTAssertEqual(groups[1].windows[0].usedPercent, 75, accuracy: 0.0001)
        XCTAssertNotNil(groups[1].windows[0].resetDate, "fractional ISO-8601 must parse")
    }

    func testRemainingFractionConversion() throws {
        for (remaining, used) in [(0.0, 100.0), (0.25, 75.0), (0.84, 16.0), (1.0, 0.0)] {
            let json = #"{"buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":\#(remaining)}]}"#
            let groups = try XCTUnwrap(AntigravityUsageReader.decode(payload(json)))
            XCTAssertEqual(groups[0].windows[0].usedPercent, used, accuracy: 0.0001)
        }
    }

    func testClampsOutOfRangeFractions() throws {
        let below = #"{"buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":1.5}]}"#
        XCTAssertEqual(try XCTUnwrap(AntigravityUsageReader.decode(payload(below)))[0].windows[0].usedPercent, 0)

        let above = #"{"buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":-0.5}]}"#
        XCTAssertEqual(try XCTUnwrap(AntigravityUsageReader.decode(payload(above)))[0].windows[0].usedPercent, 100)
    }

    func testRejectsNonFinitePercentage() {
        // JSON has no NaN literal; a missing fraction must drop the bucket, not crash.
        let json = #"{"name":"X","buckets":[{"id":"gemini-weekly","window":"weekly"}]}"#
        XCTAssertNil(AntigravityUsageReader.decode(payload(json)))
    }

    func testPlainAndFractionalTimestamps() throws {
        let plain = #"{"buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.5,"reset_time":"2099-01-02T03:04:05Z"}]}"#
        let frac = #"{"buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.5,"reset_time":"2099-01-02T03:04:05.987Z"}]}"#
        XCTAssertNotNil(try XCTUnwrap(AntigravityUsageReader.decode(payload(plain)))[0].windows[0].resetDate)
        XCTAssertNotNil(try XCTUnwrap(AntigravityUsageReader.decode(payload(frac)))[0].windows[0].resetDate)
    }

    func testIgnoresUnknownFields() throws {
        let json = #"{"name":"Gemini Models","surprise":true,"buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.9,"future_field":42}]}"#
        XCTAssertNotNil(AntigravityUsageReader.decode(payload(json)))
    }

    func testSkipsOneMalformedBucketKeepsValidOne() throws {
        let json = #"""
        {
          "name": "Gemini Models",
          "buckets": [
            { "id": null, "window": "weekly", "remaining_fraction": 0.1 },
            { "id": "gemini-weekly", "window": "weekly", "remaining_fraction": 0.4 }
          ]
        }
        """#
        let groups = try XCTUnwrap(AntigravityUsageReader.decode(payload(json)))
        XCTAssertEqual(groups[0].windows.count, 1)
        XCTAssertEqual(groups[0].windows[0].usedPercent, 60, accuracy: 0.0001)
    }

    func testRejectsUnsuccessfulStatus() {
        XCTAssertNil(AntigravityUsageReader.decode(payload(twoGroups, status: "ERROR")))
    }

    func testRejectsWrongCommandName() {
        XCTAssertNil(AntigravityUsageReader.decode(payload(twoGroups, command: "help")))
    }

    func testRejectsEmptyGroups() {
        XCTAssertNil(AntigravityUsageReader.decode(payload("")))
    }

    func testRejectsInvalidJSON() {
        XCTAssertNil(AntigravityUsageReader.decode(Data("{not json".utf8)))
    }

    func testUnknownBucketIDGetsGenericBoundedLabel() throws {
        let json = #"{"name":"Some New Pool <script>","buckets":[{"id":"quantum-hourly","window":"hourly","remaining_fraction":0.7}]}"#
        let groups = try XCTUnwrap(AntigravityUsageReader.decode(payload(json)))
        XCTAssertEqual(groups[0].name, "Some New Pool script")            // sanitized, no angle brackets
        XCTAssertEqual(groups[0].windows[0].name, "hourly")               // sanitized window label
        XCTAssertLessThanOrEqual(groups[0].name.count, 40)
    }

    func testDecodedSnapshotContainsNoSentinel() throws {
        let groups = try XCTUnwrap(AntigravityUsageReader.decode(payload(twoGroups)))
        let snapshot = UsageSnapshot(provider: .gemini, planName: "Antigravity", quotaGroups: groups)
        let described = String(describing: snapshot)
        XCTAssertFalse(described.contains("SECRET-SENTINEL"))
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("SECRET-SENTINEL"))
    }
}

final class AntigravityUsageReaderProcessTests: XCTestCase {
    /// Writes a tiny executable that prints `output` and exits `exitCode`.
    private func fakeExecutable(printing output: String, exitCode: Int = 0) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agy-fake-\(UUID().uuidString)")
        let script = "#!/bin/sh\ncat <<'AGYEOF'\n\(output)\nAGYEOF\nexit \(exitCode)\n"
        try script.data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func validPayload() -> String {
        #"""
        {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[
          {"name":"Gemini Models","buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.6,"reset_time":"2099-09-14T04:48:31Z"}]}
        ]}}}
        """#
    }

    func testRunsExecutableDirectlyAndDecodes() async throws {
        let exe = try fakeExecutable(printing: validPayload())
        defer { try? FileManager.default.removeItem(at: exe) }

        let reader = AntigravityUsageReader(executableOverride: exe)
        let result = await reader.fetchQuotaGroups()
        let groups = try XCTUnwrap(result)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.windows.first?.usedPercent ?? -1, 40, accuracy: 0.0001)
    }

    func testNonZeroExitYieldsNil() async throws {
        let exe = try fakeExecutable(printing: validPayload(), exitCode: 3)
        defer { try? FileManager.default.removeItem(at: exe) }
        let groups = await AntigravityUsageReader(executableOverride: exe).fetchQuotaGroups()
        XCTAssertNil(groups)
    }

    func testGarbageOutputYieldsNil() async throws {
        let exe = try fakeExecutable(printing: "not json at all")
        defer { try? FileManager.default.removeItem(at: exe) }
        let groups = await AntigravityUsageReader(executableOverride: exe).fetchQuotaGroups()
        XCTAssertNil(groups)
    }

    func testMissingExecutableYieldsNil() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-agy")
        let groups = await AntigravityUsageReader(executableOverride: missing).fetchQuotaGroups()
        XCTAssertNil(groups)
    }

    func testNonExecutableFileYieldsNil() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agy-plain-\(UUID().uuidString)")
        try "echo hi".data(using: .utf8)!.write(to: url)  // no +x
        defer { try? FileManager.default.removeItem(at: url) }
        let groups = await AntigravityUsageReader(executableOverride: url).fetchQuotaGroups()
        XCTAssertNil(groups)
    }

    func testHangingExecutableIsBoundedByTimeout() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agy-hang-\(UUID().uuidString)")
        try "#!/bin/sh\nsleep 30\n".data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        defer { try? FileManager.default.removeItem(at: url) }

        let start = Date()
        let groups = await AntigravityUsageReader(executableOverride: url, processTimeout: 1).fetchQuotaGroups()
        XCTAssertNil(groups)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "timeout must terminate the child")
    }
}
