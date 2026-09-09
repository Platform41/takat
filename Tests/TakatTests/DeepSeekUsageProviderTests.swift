import XCTest
@testable import Takat

final class DeepSeekUsageProviderTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session = nil
        super.tearDown()
    }

    func testNoKeyThrowsNotConfigured() async {
        let provider = DeepSeekUsageProvider(apiKey: { nil }, session: session)
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .notConfigured error")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmptyKeyThrowsNotConfigured() async {
        let provider = DeepSeekUsageProvider(apiKey: { "   " }, session: session)
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .notConfigured error")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSuccessfulBalanceResponseUSD() async throws {
        let json = """
        {
            "is_available": true,
            "balance_infos": [
                {
                    "currency": "USD",
                    "total_balance": "12.34",
                    "granted_balance": "0.00",
                    "topped_up_balance": "12.34"
                }
            ]
        }
        """
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let provider = DeepSeekUsageProvider(apiKey: { "test-api-key" }, session: session)
        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.provider, .deepseek)
        XCTAssertEqual(snapshot.planName, "API")
        XCTAssertNil(snapshot.sessionPercent)
        XCTAssertNil(snapshot.weeklyPercent)
        XCTAssertNil(snapshot.resetDate)
        XCTAssertTrue(snapshot.dailyTokenUsage.isEmpty)

        guard let balance = snapshot.balance else {
            return XCTFail("Expected non-nil balance")
        }
        XCTAssertEqual(balance.amount, Decimal(string: "12.34"))
        XCTAssertEqual(balance.currency, "USD")
        XCTAssertTrue(balance.isAvailable)
    }

    func testSuccessfulBalancePrefersUSDOverOtherCurrencies() async throws {
        let json = """
        {
            "is_available": true,
            "balance_infos": [
                {
                    "currency": "CNY",
                    "total_balance": "88.00"
                },
                {
                    "currency": "USD",
                    "total_balance": "15.50"
                }
            ]
        }
        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let provider = DeepSeekUsageProvider(apiKey: { "test-key" }, session: session)
        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.balance?.currency, "USD")
        XCTAssertEqual(snapshot.balance?.amount, Decimal(string: "15.50"))
    }

    func testCNYOnlyFallback() async throws {
        let json = """
        {
            "is_available": false,
            "balance_infos": [
                {
                    "currency": "CNY",
                    "total_balance": "50.25"
                }
            ]
        }
        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let provider = DeepSeekUsageProvider(apiKey: { "test-key" }, session: session)
        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.balance?.currency, "CNY")
        XCTAssertEqual(snapshot.balance?.amount, Decimal(string: "50.25"))
        XCTAssertFalse(snapshot.balance?.isAvailable ?? true)
    }

    func testEmptyBalanceInfosThrowsUnavailable() async {
        let json = """
        {
            "is_available": true,
            "balance_infos": []
        }
        """
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let provider = DeepSeekUsageProvider(apiKey: { "test-key" }, session: session)
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .unavailable")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnauthorizedStatusCode401() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let provider = DeepSeekUsageProvider(apiKey: { "bad-key" }, session: session)
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .unauthorized")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnauthorizedStatusCode403() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let provider = DeepSeekUsageProvider(apiKey: { "forbidden-key" }, session: session)
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .unauthorized")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerErrorStatusCode500ThrowsUnavailable() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let provider = DeepSeekUsageProvider(apiKey: { "test-key" }, session: session)
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .unavailable")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedBodyThrowsUnavailable() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("not-json".utf8))
        }

        let provider = DeepSeekUsageProvider(apiKey: { "test-key" }, session: session)
        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected .unavailable")
        } catch let error as UsageProviderError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCachingWithinTTLHitsNetworkOnce() async throws {
        nonisolated(unsafe) var requestCount = 0
        let json = """
        {
            "is_available": true,
            "balance_infos": [
                { "currency": "USD", "total_balance": "10.00" }
            ]
        }
        """
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let provider = DeepSeekUsageProvider(apiKey: { "test-key" }, session: session, ttl: 600)
        let first = try await provider.fetchUsage()
        let second = try await provider.fetchUsage()

        XCTAssertEqual(first, second)
        XCTAssertEqual(requestCount, 1)
    }

    func testBalanceCodableRoundTrip() throws {
        let balance = Balance(amount: Decimal(string: "42.99")!, currency: "USD", isAvailable: true)
        let data = try JSONEncoder().encode(balance)
        let decoded = try JSONDecoder().decode(Balance.self, from: data)
        XCTAssertEqual(decoded, balance)
    }

    func testUsageSnapshotWithBalanceCodableRoundTrip() throws {
        let snapshot = UsageSnapshot(
            provider: .deepseek,
            planName: "API",
            balance: Balance(amount: Decimal(string: "9.99")!, currency: "USD", isAvailable: true)
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.balance?.amount, Decimal(string: "9.99"))
    }

    func testOldSnapshotWithoutBalanceDecodesWithNilBalance() throws {
        let json = """
        {
            "provider": "claude",
            "planName": "Pro",
            "sessionPercent": 42.0,
            "weeklyPercent": 68.0,
            "dailyTokenUsage": []
        }
        """
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.provider, .claude)
        XCTAssertEqual(decoded.planName, "Pro")
        XCTAssertNil(decoded.balance)
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
