# Step 5.5 — Gemini CLI Usage Adapter: Handoff to DeepSeek

**Spec owner:** One
**Implementer:** DeepSeek (Three)
**Branch:** `feat/gemini-adapter` off `main` → PR (expected #13)
**Depends on:** PR #11 merged (`f8afe35`) — Claude adapter + shared `Core/` helpers
**Source of truth for data shapes:** `docs/research/provider-data-sources.md` (§ Gemini CLI)

## Goal

Add a third real provider. The Gemini CLI writes per-message token counts locally — structurally a near-copy of the Claude adapter (local files, tokens only, no session/weekly %/reset). Also folds in the one review nit deferred from PR #11 and adds a scroll container now that there are three cards.

---

## Where the data is

```
~/.gemini/tmp/<dir>/chats/session-<ISO8601>.json
```

**One JSON object per file** (not JSONL). `sessionRetention` defaults to 30 days.

- `tmp/` also holds `logs.json` (flat prompt log, **no tokens** — ignore) and `antigravity-*` dirs. Touch **only** `tmp/*/chats/session-*.json`.
- `<dir>` names are a mix of sha-hashes and plain slugs — just glob, don't resolve them.

### File shape

```json
{
  "sessionId": "…", "projectHash": "…",
  "startTime": "2026-03-05T02:41:53.926Z", "lastUpdated": "…",
  "messages": [
    {
      "id": "…", "timestamp": "2026-03-05T02:42:00.053Z",
      "type": "gemini",                       // or "user"
      "model": "gemini-3-flash-preview",
      "tokens": { "input": 7201, "output": 122, "cached": 3005, "thoughts": 338, "tool": 0, "total": 7661 }
    }
  ]
}
```

- `total == input + output + thoughts` (verified). `cached` ⊆ `input` (cheap re-reads).
- `thoughts` is **separate from `output`** (Gemini bills reasoning separately) → **add** it, don't subtract.
- `type: "user"` messages carry a zeroed `tokens` block — skip; only `type: "gemini"` counts.

---

## Mapping to `UsageSnapshot`

| Field | Value |
|---|---|
| `provider` | `.gemini` (new `ProviderID` case) |
| `planName` | `"Gemini"` — fixed. No plan string exists; `model` per message is only a model id. |
| `sessionPercent` / `weeklyPercent` / `resetDate` | `nil` |
| `dailyTokenUsage` | per-day sum of `newTokens`, bucketed by each `gemini` message's `timestamp` via the shared `DailyUsageBucketing.dailyUsage` |

```swift
static func newTokens(_ t: GeminiTokens) -> Int {
    let input = t.input ?? 0
    let cached = t.cached ?? 0
    let output = t.output ?? 0
    let thoughts = t.thoughts ?? 0
    return max(0, input - cached) + output + thoughts
}
```

---

## Structure (mirror Claude)

- `Sources/Takat/Core/Providers/GeminiSessionParser.swift`
  - pure `enum GeminiSessionParser` — `static func parse(data: Data) -> [(Date, Int)]` (one file's worth of deltas), `static func newTokens(_:)`.
  - **Cannot** reuse `JSONLLines` — this is a single JSON object. Decode the whole file into a small `Decodable` struct, iterate `messages`.
  - `Decodable` models **only**: `messages: [{ type, timestamp, model, tokens: { input, output, cached, thoughts } }]`. Nothing else — privacy boundary. In particular **do not** model `content` or the top-level `thoughts` array on a message (that's a list of reasoning summaries — sensitive prose; the token count you want is the `tokens.thoughts` Int).
- `Sources/Takat/Core/Providers/GeminiUsageProvider.swift`
  - `public struct GeminiUsageProvider: UsageProvider`, `providerID = .gemini`
  - `public init(chatsRoot: URL = GeminiUsageProvider.defaultChatsRoot)` where default = `~/.gemini/tmp`
  - Enumerate `*/chats/*.json` under that root, mtime within last 7 local days, skip files > ~50 MB (Gemini chat files are small; guard anyway), decode+parse each, concatenate deltas, bucket.
  - A file that fails to decode → skip it (don't fail the provider).
- Reuse `DailyUsageBucketing`. Do not add a parser-local copy.

### Error mapping (same rules as Claude/Codex)

| Condition | Result |
|---|---|
| `~/.gemini` or `~/.gemini/tmp` missing | `throw .notConfigured` |
| No `chats/*.json` anywhere under `tmp/` | `throw .notConfigured` |
| Files exist, none in the 7-day window / no `gemini` messages | valid snapshot, 7 zero entries — **not** an error |
| Directory readable but every file failed to decode | `throw .unavailable` |

(That last row is the fix for the gap One flagged in the Claude adapter — apply it here **and** retrofit the Claude provider in this PR: track successful reads, throw `.unavailable` only if `files` was non-empty and zero were read.)

---

## `ProviderID` + `ProviderStyle`

`Sources/Takat/Core/Models/UsageSnapshot.swift` — add `case gemini` to the enum (keep it `Codable`/`CaseIterable`). This flows automatically into `DashboardView`/`SettingsView` (`ForEach(ProviderID.allCases)`) and the cache.

`Sources/Takat/DesignSystem/ProviderStyle.swift` — the three switches are exhaustive, so add:
```swift
case .gemini: "Gemini"                              // displayName
case .gemini: "diamond"                             // symbolName — or another distinct SF Symbol
case .gemini: .blue                                 // accentColor (Claude=orange, Codex=teal)
```
Pick the symbol/colour with taste; those are suggestions.

---

## Folded-in fixes (do these here)

1. **PR #11 nit** — `Sources/Takat/Features/Dashboard/DashboardView.swift`, the nil-percent caption currently hardcodes "Claude":
   ```swift
   Text("Session and weekly limits aren't reported by \(snapshot.provider.displayName).")
   ```
2. **PR #11 minor** — retrofit `ClaudeUsageProvider` (and match in `GeminiUsageProvider`) to `throw .unavailable` when it has files but reads none.
3. **Three cards now** — wrap the provider-card list in `DashboardView.content` in a `ScrollView` with a sensible `.frame(maxHeight:)` (start ~480) so the menu-bar panel can't grow unbounded. Keep header + refresh button outside the scroll. This is a functional stopgap; a proper compact/collapsible card mode is a separate Two task — note it in the PR, don't build it.

---

## Wire-up

`Sources/Takat/App/TakatApp.swift`:
```swift
let providers: [any UsageProvider] = [
    ClaudeUsageProvider(),
    CodexUsageProvider(),
    GeminiUsageProvider()
]
```

---

## Out of scope

- Gemini paid Code Assist / Vertex rate-limit data (not observed; only `oauth-personal` free tier here).
- Showing the per-message `model` anywhere (future subtitle idea, not now).
- DeepSeek / any network adapter.
- The compact-card redesign (Two's task).
- Cost calc, backfill > 7 days.

---

## Tests

Sanitized hand-crafted fixtures under `Tests/TakatTests/Fixtures/gemini-chats/<dir>/chats/session-x.json` — no real content. Cover:

- Parser: `newTokens` math including `thoughts` **added** (`input 1000, cached 900, output 200, thoughts 50` → `350`); all-cached message (`input 900, cached 900`) → `0`.
- Parser: `type: "user"` messages skipped.
- Parser: a malformed file → `parse` returns `[]` (provider skips it).
- Privacy: a fixture message carrying `content: "SECRET-SENTINEL"` and a `thoughts: [{description: "SECRET-SENTINEL"}]` array → resulting snapshot contains no sentinel.
- Parser: bucketing by calendar day with an injected reference date (via `DailyUsageBucketing`, already covered — just the Gemini parse feeding it).
- Provider: aggregates across two different `<dir>/chats/` directories.
- Provider: mtime filter excludes an old file.
- Provider: missing `tmp/` → `.notConfigured`; `tmp/` with no `chats/*.json` → `.notConfigured`.
- Provider: files present, none in window → 7 zero entries, `planName == "Gemini"`, percents `nil`.
- Provider: all files un-decodable → `.unavailable`.
- Regression: existing Claude provider test for the new `.unavailable` behaviour.

Keep all 42 existing tests green. `swift build` + `swift test` before every push. `Package.swift` stays dependency-free.

---

## Handoff back

- Push, open the PR, fill test-evidence.
- Run the provider against live `~/.gemini/tmp` and report the 7-day bar values (same order-of-magnitude sanity check).
- **Desktop screenshot** of the panel with all three cards, showing the Gemini card (header "Gemini", the caption in place of bars, 7-day chart) and that the scroll container behaves.
- One re-reviews from remote.
