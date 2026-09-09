import XCTest
@testable import Takat

final class ProviderSwitcherTests: XCTestCase {
    func testSwitcherProvidersInDisplayOrder() {
        let providers = ProviderSwitcher.switcherProviders(snapshots: [.gemini, .claude])
        XCTAssertEqual(providers, [.claude, .gemini])
    }

    func testSwitcherProvidersIncludesDeepSeekInDisplayOrder() {
        let providers = ProviderSwitcher.switcherProviders(snapshots: [.deepseek, .claude])
        XCTAssertEqual(providers, [.claude, .deepseek])
        XCTAssertEqual(ProviderID.displayOrder, [.claude, .codex, .gemini, .deepseek])
    }

    func testSwitcherProvidersIgnoresUnavailable() {
        XCTAssertEqual(ProviderSwitcher.switcherProviders(snapshots: [.codex]), [.codex])
        XCTAssertEqual(ProviderSwitcher.switcherProviders(snapshots: []), [])
    }

    func testModeBranching() {
        XCTAssertEqual(ProviderSwitcher.mode(snapshots: []), .empty)
        XCTAssertEqual(ProviderSwitcher.mode(snapshots: [.codex]), .single)
        XCTAssertEqual(ProviderSwitcher.mode(snapshots: [.claude, .codex]), .multiple)
        XCTAssertEqual(ProviderSwitcher.mode(snapshots: [.claude, .codex, .gemini]), .multiple)
    }

    func testSelectedProviderStoredPresent() {
        let selected = ProviderSwitcher.selectedProvider(stored: "codex", available: [.claude, .codex, .gemini])
        XCTAssertEqual(selected, .codex)
    }

    func testSelectedProviderStoredAbsentFallsBackToFirst() {
        XCTAssertEqual(
            ProviderSwitcher.selectedProvider(stored: "codex", available: [.claude, .gemini]),
            .claude
        )
    }

    func testSelectedProviderInvalidRawFallsBack() {
        XCTAssertEqual(
            ProviderSwitcher.selectedProvider(stored: "not-a-provider", available: [.claude, .gemini]),
            .claude
        )
    }

    func testSelectedProviderNilStoredFallsBack() {
        XCTAssertEqual(
            ProviderSwitcher.selectedProvider(stored: nil, available: [.gemini]),
            .gemini
        )
    }

    func testSelectedProviderEmptyAvailableReturnsNil() {
        XCTAssertNil(ProviderSwitcher.selectedProvider(stored: "codex", available: []))
    }
}
