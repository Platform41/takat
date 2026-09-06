import SwiftUI

extension ProviderID {
    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var symbolName: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "terminal"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude: .orange
        case .codex: .teal
        }
    }
}
