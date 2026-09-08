import Foundation

public actor DeepSeekUsageProvider: UsageProvider {
    public nonisolated let providerID: ProviderID = .deepseek

    private let apiKey: @Sendable () -> String?
    private let session: URLSession
    private let ttl: TimeInterval
    private var cached: (key: String, snapshot: UsageSnapshot, at: Date)?

    public init(
        apiKey: @escaping @Sendable () -> String? = { KeychainStore.get("deepseek") },
        session: URLSession = DeepSeekUsageProvider.defaultSession,
        ttl: TimeInterval = 600
    ) {
        self.apiKey = apiKey
        self.session = session
        self.ttl = ttl
    }

    public static var defaultSession: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        guard let key = apiKey(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cached = nil
            throw UsageProviderError.notConfigured
        }

        let now = Date()
        if let cached = cached, cached.key == key, now.timeIntervalSince(cached.at) < ttl {
            return cached.snapshot
        }

        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
            throw UsageProviderError.unavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageProviderError.unavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageProviderError.unavailable
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageProviderError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            throw UsageProviderError.unavailable
        }

        guard let balanceResponse = try? JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data) else {
            throw UsageProviderError.unavailable
        }

        guard !balanceResponse.balanceInfos.isEmpty else {
            throw UsageProviderError.unavailable
        }

        let chosenInfo = balanceResponse.balanceInfos.first(where: { $0.currency == "USD" }) ?? balanceResponse.balanceInfos[0]
        let amount = Decimal(string: chosenInfo.totalBalance) ?? 0

        let snapshot = UsageSnapshot(
            provider: .deepseek,
            planName: "API",
            sessionPercent: nil,
            weeklyPercent: nil,
            resetDate: nil,
            dailyTokenUsage: [],
            balance: Balance(
                amount: amount,
                currency: chosenInfo.currency,
                isAvailable: balanceResponse.isAvailable
            )
        )

        self.cached = (key: key, snapshot: snapshot, at: now)
        return snapshot
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

private struct DeepSeekBalanceInfo: Decodable {
    let currency: String
    let totalBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
    }
}
