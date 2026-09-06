import Foundation
import Observation

@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshots: [ProviderID: UsageSnapshot] = [:]
    public private(set) var isRefreshing = false
    public private(set) var errors: [ProviderID: UsageProviderError] = [:]

    private let providers: [any UsageProvider]

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public func snapshot(for providerID: ProviderID) -> UsageSnapshot? {
        snapshots[providerID]
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

        for (id, result) in results {
            switch result {
            case .success(let snapshot):
                snapshots[id] = snapshot
            case .failure(let error):
                errors[id] = error
            }
        }
    }
}
