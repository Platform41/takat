import XCTest
@testable import Takat

@MainActor
final class UsageStoreTests: XCTestCase {
    func testRefreshPopulatesSnapshots() async {
        let providers: [any UsageProvider] = [
            FixtureUsageProvider(providerID: .claude),
            FixtureUsageProvider(providerID: .codex)
        ]
        let store = UsageStore(providers: providers)

        XCTAssertTrue(store.snapshots.isEmpty)

        await store.refresh()

        XCTAssertEqual(store.snapshots.count, 2)
        XCTAssertEqual(store.snapshot(for: .claude)?.provider, .claude)
        XCTAssertEqual(store.snapshot(for: .codex)?.planName, "Enterprise")
        XCTAssertTrue(store.errors.isEmpty)
        XCTAssertFalse(store.isRefreshing)
    }

    func testFailingProviderRecordsError() async {
        let store = UsageStore(providers: [ThrowingProvider()])

        await store.refresh()

        XCTAssertNil(store.snapshot(for: .codex))
        XCTAssertEqual(store.errors[.codex], .unauthorized)
    }
}

private struct ThrowingProvider: UsageProvider {
    var providerID: ProviderID { .codex }

    func fetchUsage() async throws -> UsageSnapshot {
        throw UsageProviderError.unauthorized
    }
}
