import XCTest
@testable import Takat

final class ClaudeUsageReaderTests: XCTestCase {
    func testFutureResetPopulatesPercentages() {
        let json = #"""
        {
          "oauthAccount": { "organizationType": "claude_pro" },
          "cachedUsageUtilization": {
            "utilization": {
              "five_hour": { "utilization": 21, "resets_at": "2099-09-07T15:39:59.661643+00:00" },
              "seven_day": { "utilization": 32, "resets_at": "2099-09-07T21:59:59.661667+00:00" }
            }
          }
        }
        """#
        let usage = ClaudePlanReader.usage(fromConfig: Data(json.utf8))

        XCTAssertEqual(usage?.sessionPercent, 21)
        XCTAssertEqual(usage?.weeklyPercent, 32)
        XCTAssertNotNil(usage?.resetDate)
    }

    func testPastResetYieldsNilForThatWindow() {
        let json = #"""
        {
          "cachedUsageUtilization": {
            "utilization": {
              "five_hour": { "utilization": 21, "resets_at": "2020-01-01T00:00:00.000+00:00" },
              "seven_day": { "utilization": 32, "resets_at": "2099-09-07T21:59:59.000+00:00" }
            }
          }
        }
        """#
        let usage = ClaudePlanReader.usage(fromConfig: Data(json.utf8))

        XCTAssertNil(usage?.sessionPercent)
        XCTAssertEqual(usage?.weeklyPercent, 32)
        XCTAssertNotNil(usage?.resetDate)
    }

    func testMicrosecondResetParsesAfterTruncation() {
        let json = #"""
        {
          "cachedUsageUtilization": {
            "utilization": {
              "five_hour": { "utilization": 21, "resets_at": "2099-09-07T15:39:59.661643+00:00" },
              "seven_day": { "utilization": 32, "resets_at": "2099-09-07T21:59:59.661667+00:00" }
            }
          }
        }
        """#
        let usage = ClaudePlanReader.usage(fromConfig: Data(json.utf8))

        XCTAssertEqual(usage?.sessionPercent, 21)
        XCTAssertEqual(usage?.weeklyPercent, 32)
        XCTAssertNotNil(usage?.resetDate)
    }

    func testMissingUtilizationYieldsNilButResolvesPlanName() {
        let json = #"{"oauthAccount":{"organizationType":"claude_pro"}}"#
        let result = ClaudePlanReader.read(Data(json.utf8))

        XCTAssertEqual(result.planName, "Pro")
        XCTAssertNil(result.usage)
    }

    func testMalformedUtilizationYieldsNilNoThrow() {
        let json = #"{"cachedUsageUtilization":{"utilization":{"five_hour":"garbage"}}}"#
        XCTAssertNil(ClaudePlanReader.usage(fromConfig: Data(json.utf8)))
    }

    func testPrivacySentinelNeverReachesSnapshot() {
        let json = #"""
        {
          "oauthAccount": { "organizationType": "claude_pro", "accountUuid": "SECRET-SENTINEL" },
          "cachedUsageUtilization": {
            "accountUuid": "SECRET-SENTINEL",
            "utilization": {
              "five_hour": { "utilization": 21, "resets_at": "2099-09-07T15:39:59.661+00:00" },
              "seven_day": { "utilization": 32, "resets_at": "2099-09-07T21:59:59.661+00:00" }
            }
          },
          "spend": { "total_spend_usd": "SECRET-SENTINEL" }
        }
        """#

        let result = ClaudePlanReader.read(Data(json.utf8))
        let snapshot = UsageSnapshot(
            provider: .claude,
            planName: result.planName,
            sessionPercent: result.usage?.sessionPercent,
            weeklyPercent: result.usage?.weeklyPercent,
            resetDate: result.usage?.resetDate,
            dailyTokenUsage: []
        )

        XCTAssertEqual(snapshot.sessionPercent, 21)
        XCTAssertFalse(String(describing: snapshot).contains("SECRET-SENTINEL"))
    }
}
