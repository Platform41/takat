import Foundation
import Observation

@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshots: [ProviderID: UsageSnapshot] = [:]
    public private(set) var lastUpdated: [ProviderID: Date] = [:]
    public private(set) var isRefreshing = false
    public private(set) var errors: [ProviderID: UsageProviderError] = [:]

    private let providers: [any UsageProvider]
    private let cacheDirectory: URL?
    private var hasLoadedCache = false

    public static var defaultCacheDirectory: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Takat", isDirectory: true)
    }

    public init(
        providers: [any UsageProvider],
        cacheDirectory: URL? = UsageStore.defaultCacheDirectory
    ) {
        self.providers = providers
        self.cacheDirectory = cacheDirectory
    }

    public func snapshot(for providerID: ProviderID) -> UsageSnapshot? {
        snapshots[providerID]
    }

    public func lastUpdated(for providerID: ProviderID) -> Date? {
        lastUpdated[providerID]
    }

    var needsRefreshOnOpen: Bool {
        if snapshots.isEmpty { return true }
        guard let newest = lastUpdated.values.max() else { return true }
        return RefreshPolicy.isStale(newest)
    }

    public func loadPersistedSnapshots() async {
        guard !hasLoadedCache, let cacheDirectory else { return }
        hasLoadedCache = true

        let directory = cacheDirectory
        let payload = await Task.detached(priority: .userInitiated) {
            UsageCache.load(from: directory)
        }.value

        guard let payload, snapshots.isEmpty else { return }
        snapshots = payload.snapshots
        lastUpdated = payload.lastUpdated
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errors = [:]
        defer { isRefreshing = false }

        let providers = self.providers
        let results = await withTaskGroup(of: (ProviderID, Result<UsageSnapshot, UsageProviderError>).self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let snapshot = try await provider.fetchUsage()
                        return (provider.providerID, .success(snapshot))
                    } catch {
                        let mapped = (error as? UsageProviderError) ?? .unavailable
                        return (provider.providerID, .failure(mapped))
                    }
                }
            }

            var collected: [(ProviderID, Result<UsageSnapshot, UsageProviderError>)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        let now = Date()
        for (id, result) in results {
            switch result {
            case .success(let snapshot):
                snapshots[id] = snapshot
                lastUpdated[id] = now
            case .failure(let error):
                errors[id] = error
                if error == .notConfigured {
                    snapshots.removeValue(forKey: id)
                    lastUpdated.removeValue(forKey: id)
                }
            }
        }

        await persistSnapshots()
    }

    private func persistSnapshots() async {
        guard let cacheDirectory else { return }
        let payload = UsageCache.Payload(
            schema: UsageCache.schemaVersion,
            snapshots: snapshots,
            lastUpdated: lastUpdated
        )
        let directory = cacheDirectory
        await Task.detached(priority: .utility) {
            UsageCache.save(payload, to: directory)
        }.value
    }
}
