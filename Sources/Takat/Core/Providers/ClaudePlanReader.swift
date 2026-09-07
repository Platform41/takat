import Foundation

enum ClaudePlanReader {
    /// Decodes only `oauthAccount.organizationType` from ~/.claude.json content.
    static func planName(fromConfig data: Data) -> String {
        guard let cfg = try? JSONDecoder().decode(ClaudeConfig.self, from: data),
              let type = cfg.oauthAccount?.organizationType else {
            return "Claude"
        }
        switch type {
        case "claude_pro": return "Pro"
        case "claude_max": return "Max"
        case "claude_team": return "Team"
        case "claude_enterprise": return "Enterprise"
        case "claude_free": return "Free"
        default: return "Claude"
        }
    }
}

struct ClaudeConfig: Decodable {
    let oauthAccount: ClaudeOAuthAccount?
}

struct ClaudeOAuthAccount: Decodable {
    let organizationType: String?
}
