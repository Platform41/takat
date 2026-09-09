import SwiftUI

extension ProviderID {
    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .deepseek: "DeepSeek"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude: .orange
        case .codex: .teal
        case .gemini: .blue
        case .deepseek: .indigo
        }
    }
}
