import XCTest
@testable import Takat

@MainActor
final class UsageStorePersistenceTests: XCTestCase {
    private func tempCacheDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TakatTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testPersistenceRoundTrip() async {
        let dir = tempCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store1 = UsageStore(
            providers: [FixtureUsageProvider(providerID: .claude)],
            cacheDirectory: dir
        )
        await store1.refresh()

        let store2 = UsageStore(providers: [], cacheDirectory: dir)
        await store2.loadPersistedSnapshots()

        XCTAssertEqual(store2.snapshot(for: .claude)?.planName, "Pro")
        XCTAssertNotNil(store2.lastUpdated(for: .claude))
    }

    func testCorruptCacheStartsEmpty() async {
        let dir = tempCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data("not json".utf8).write(to: dir.appendingPathComponent("usage-cache.json"))

        let store = UsageStore(providers: [], cacheDirectory: dir)
        await store.loadPersistedSnapshots()

        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertTrue(store.lastUpdated.isEmpty)
    }

    func testSchemaMismatchStartsEmpty() async {
        let dir = tempCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{"schema": 999, "snapshots": [], "lastUpdated": []}"#
        try? Data(json.utf8).write(to: dir.appendingPathComponent("usage-cache.json"))

        let store = UsageStore(providers: [], cacheDirectory: dir)
        await store.loadPersistedSnapshots()

        XCTAssertTrue(store.snapshots.isEmpty)
    }

    func testLastUpdatedNilBeforeRefresh() async {
        let store = UsageStore(
            providers: [FixtureUsageProvider(providerID: .claude)],
            cacheDirectory: nil
        )

        XCTAssertNil(store.lastUpdated(for: .claude))

        await store.refresh()

        XCTAssertNotNil(store.lastUpdated(for: .claude))
    }

    func testErrorsClearedAfterFailThenSucceed() async {
        let store = UsageStore(providers: [FlakyProvider()], cacheDirectory: nil)

        await store.refresh()
        XCTAssertEqual(store.errors[.codex], .unauthorized)

        await store.refresh()
        XCTAssertNil(store.errors[.codex])
        XCTAssertNotNil(store.snapshot(for: .codex))
    }
}

private final class FlakyProvider: UsageProvider, @unchecked Sendable {
    var providerID: ProviderID { .codex }

    private let lock = NSLock()
    private var calls = 0

    func fetchUsage() async throws -> UsageSnapshot {
        let call = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        if call == 1 {
            throw UsageProviderError.unauthorized
        }
        return FixtureUsageProvider.fixture(for: .codex)
    }
}
