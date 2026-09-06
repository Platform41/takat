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

        for provider in providers {
            do {
                snapshots[provider.providerID] = try await provider.fetchUsage()
            } catch {
                errors[provider.providerID] = (error as? UsageProviderError) ?? .unavailable
            }
        }
    }
}
