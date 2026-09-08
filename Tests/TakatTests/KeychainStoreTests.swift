import XCTest
import Security
@testable import Takat

final class KeychainStoreTests: XCTestCase {
    private let testService = "net.41labs.takat.llm.tests"
    private let testAccount = "test-account-\(UUID().uuidString)"

    override func tearDown() {
        KeychainStore.delete(testAccount, service: testService)
        super.tearDown()
    }

    func testSetGetDeleteRoundTrip() throws {
        // Clean start
        KeychainStore.delete(testAccount, service: testService)
        XCTAssertNil(KeychainStore.get(testAccount, service: testService))

        // Set
        let saved = KeychainStore.set(testAccount, "secret-value-123", service: testService)
        guard saved else {
            // In headless/CI environments without an interactive keychain session, skip
            throw XCTSkip("Keychain set failed (keychain may be unavailable in this environment)")
        }

        // Get
        XCTAssertEqual(KeychainStore.get(testAccount, service: testService), "secret-value-123")

        // Overwrite (set delete-then-add)
        let updated = KeychainStore.set(testAccount, "secret-value-456", service: testService)
        XCTAssertTrue(updated)
        XCTAssertEqual(KeychainStore.get(testAccount, service: testService), "secret-value-456")

        // Delete
        let deleted = KeychainStore.delete(testAccount, service: testService)
        XCTAssertTrue(deleted)
        XCTAssertNil(KeychainStore.get(testAccount, service: testService))
    }
}
