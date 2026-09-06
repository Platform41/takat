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

    func testPartialFailureKeepsGoodSnapshotAndRecordsError() async {
        let providers: [any UsageProvider] = [
            FixtureUsageProvider(providerID: .claude),
            ThrowingProvider()
        ]
        let store = UsageStore(providers: providers)

        await store.refresh()

        XCTAssertNotNil(store.snapshot(for: .claude))
        XCTAssertNil(store.snapshot(for: .codex))
        XCTAssertEqual(store.errors[.codex], .unauthorized)
    }

    func testRefreshFansOutConcurrently() async {
        let providers: [any UsageProvider] = [
            DelayedProvider(providerID: .claude, delayNanoseconds: 200_000_000),
            DelayedProvider(providerID: .codex, delayNanoseconds: 200_000_000)
        ]
        let store = UsageStore(providers: providers)

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await store.refresh()
        }

        XCTAssertLessThan(elapsed, .milliseconds(350))
        XCTAssertEqual(store.snapshots.count, 2)
    }

    func testConcurrentRefreshIsGuarded() async {
        let provider = BlockingCountingProvider(providerID: .claude)
        let store = UsageStore(providers: [provider])

        let first = Task { await store.refresh() }

        while provider.fetchCount == 0 {
            await Task.yield()
        }

        await store.refresh()
        XCTAssertEqual(provider.fetchCount, 1)

        provider.release()
        await first.value

        XCTAssertEqual(store.snapshots.count, 1)
    }
}

private struct ThrowingProvider: UsageProvider {
    var providerID: ProviderID { .codex }

    func fetchUsage() async throws -> UsageSnapshot {
        throw UsageProviderError.unauthorized
    }
}

private struct DelayedProvider: UsageProvider {
    let providerID: ProviderID
    let delayNanoseconds: UInt64

    func fetchUsage() async throws -> UsageSnapshot {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return FixtureUsageProvider.fixture(for: providerID)
    }
}

private final class BlockingCountingProvider: UsageProvider, @unchecked Sendable {
    let providerID: ProviderID

    private let lock = NSLock()
    private var _fetchCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(providerID: ProviderID) {
        self.providerID = providerID
    }

    var fetchCount: Int {
        lock.withLock { _fetchCount }
    }

    func fetchUsage() async throws -> UsageSnapshot {
        lock.withLock { _fetchCount += 1 }

        await withCheckedContinuation { continuation in
            lock.withLock { continuations.append(continuation) }
        }

        return FixtureUsageProvider.fixture(for: providerID)
    }

    func release() {
        let pending = lock.withLock {
            defer { continuations.removeAll() }
            return continuations
        }
        for continuation in pending {
            continuation.resume()
        }
    }
}
