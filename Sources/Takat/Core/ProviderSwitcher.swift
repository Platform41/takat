import Foundation

enum ProviderSwitcher {
    enum Mode: Equatable {
        case empty
        case single
        case multiple
    }

    static func switcherProviders(snapshots: Set<ProviderID>) -> [ProviderID] {
        ProviderID.displayOrder.filter { snapshots.contains($0) }
    }

    static func mode(snapshots: Set<ProviderID>) -> Mode {
        switch switcherProviders(snapshots: snapshots).count {
        case 0: return .empty
        case 1: return .single
        default: return .multiple
        }
    }

    static func selectedProvider(stored: String?, available: [ProviderID]) -> ProviderID? {
        if let stored, let provider = ProviderID(rawValue: stored), available.contains(provider) {
            return provider
        }
        return available.first
    }
}
