# Step 5.6 — Claude plan name from `~/.claude.json`: Handoff to DeepSeek

**Spec owner:** One
**Implementer:** DeepSeek (Three)
**Branch:** `feat/claude-plan-name` off `main` → PR (expected #16)
**Depends on:** PR #11 merged (`f8afe35`) — Claude adapter. Independent of PR #13/#14.
**Type:** small enhancement to the shipped Claude adapter — no new provider, no network.

## Why

The Claude card hardcodes `planName = "Claude"`. The real plan **is** on disk — `~/.claude.json` → `oauthAccount.organizationType` (`"claude_pro"` on the maintainer's machine). Reading it makes the Claude card show "Pro" like the Codex card shows "Plus". No auth, no Keychain, no network. (Session/weekly bars are a separate, later milestone — see `docs/research/provider-data-sources.md` § "network adapters".)

## Data

`~/.claude.json` — a single JSON object (~112 KB on this machine, whole CLI config). Relevant slice:

```json
{
  "oauthAccount": {
    "organizationType": "claude_pro",
    "billingType": "stripe_subscription",
    "hasExtraUsageEnabled": true,
    "seatTier": null,
    "organizationRateLimitTier": "default_claude_ai"
  }
}
```

## Change

### 1. Pure plan-name mapper

`Sources/Takat/Core/Providers/ClaudePlanReader.swift` (or fold into `ClaudeSessionParser` — your call, keep it pure and testable):

```swift
enum ClaudePlanReader {
    /// Decodes only `oauthAccount.organizationType` from ~/.claude.json content.
    static func planName(fromConfig data: Data) -> String {
        guard let cfg = try? JSONDecoder().decode(ClaudeConfig.self, from: data),
              let type = cfg.oauthAccount?.organizationType else {
            return "Claude"
        }
        switch type {
        case "claude_pro":        return "Pro"
        case "claude_max":        return "Max"
        case "claude_team":       return "Team"
        case "claude_enterprise": return "Enterprise"
        case "claude_free":       return "Free"
        default:                  return "Claude"   // unknown → safe fallback
        }
    }
}

struct ClaudeConfig: Decodable { let oauthAccount: ClaudeOAuthAccount? }
struct ClaudeOAuthAccount: Decodable { let organizationType: String? }
```

**Privacy:** model **only** `oauthAccount.organizationType`. `~/.claude.json` also holds `emailAddress`, `accountUuid`, project paths, and MCP server configs (which can contain API keys in env blocks) — none of that must be decoded, read, or logged. The `Decodable` boundary enforces it; keep it that way.

### 2. Wire into the provider

`ClaudeUsageProvider`:
- New injectable: `public init(projectsDirectory: URL = …, configFile: URL = ClaudeUsageProvider.defaultConfigFile)` where `defaultConfigFile = ~/.claude.json`.
- In `fetchUsage()`, after building `daily`: read `configFile` (guard size ≤ ~10 MB; `try?`), pass to `ClaudePlanReader.planName(fromConfig:)`. If the file is missing/unreadable/oversize → `"Claude"`. **Do not fail the provider** — the token chart still works without a plan name.
- Use the result as `planName:` in the returned `UsageSnapshot`.

### 3. No other changes

- No UI change — `ProviderCardView` already renders `snapshot.planName` in the pill.
- No `TakatApp` change (default arg).
- Codex/Gemini untouched.
- No model change.

## Out of scope

- Session/weekly/reset bars (`/usage` endpoint — network-adapters milestone).
- `seatTier` / `organizationRateLimitTier` / Max 5x-vs-20x distinction — note as a possible refinement in a code comment, don't build.
- `hasExtraUsageEnabled` ("Pro + extra usage") — skip.
- Reading anything else from `~/.claude.json`.

## Tests

`Tests/TakatTests/ClaudeUsageProviderTests.swift` (or a new `ClaudePlanReaderTests`):

- Mapper: `claude_pro`→"Pro", `claude_max`→"Max", `claude_team`→"Team", `claude_enterprise`→"Enterprise", `claude_free`→"Free".
- Mapper: unknown `organizationType` (e.g. `"claude_startup"`) → "Claude".
- Mapper: missing `oauthAccount` → "Claude"; malformed JSON → "Claude"; empty data → "Claude".
- Privacy: a config fixture with `oauthAccount.emailAddress: "SECRET-SENTINEL"` and an `mcpServers` block with `"apiKey": "SECRET-SENTINEL"` → resulting `UsageSnapshot` contains no sentinel.
- Provider: with a fixture `configFile` containing `claude_pro` → `snapshot.planName == "Pro"`, chart still populated from the project fixtures.
- Provider: `configFile` pointing at a nonexistent path → `snapshot.planName == "Claude"` (no throw), chart unaffected.
- Keep all 55 existing tests green.

Sanitized fixture: `Tests/TakatTests/Fixtures/claude-config/claude.json` (hand-crafted — only `oauthAccount.organizationType` plus a couple of sentinel-bearing fields for the privacy test).

`swift build` + `swift test` before every push. `Package.swift` stays dependency-free. No version bump.

## Handoff back

Push, open the PR, fill test-evidence. Run against the live `~/.claude.json` and report the resolved `planName`. Screenshot the Claude card showing the plan pill (bundle with the still-pending three-card eyeball if convenient). One re-reviews from remote.

> Note: CI (GitHub Actions) is currently failing to start due to a repo billing issue — One is verifying locally until that's resolved.
