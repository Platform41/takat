import Foundation

public protocol UsageProvider: Sendable {
    var providerID: ProviderID { get }
    func fetchUsage() async throws -> UsageSnapshot
}

public enum UsageProviderError: Error, Equatable {
    case notConfigured
    case unavailable
    case unauthorized
}
