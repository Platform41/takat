# Step 5.8 — Claude session/weekly/reset from `cachedUsageUtilization`: Handoff to DeepSeek

**Spec owner:** One
**Implementer:** DeepSeek (Three)
**Branch:** `feat/claude-usage-utilization` off `main` → PR (expected #28)
**Depends on:** PR #17 merged (`c3403cf`) — Claude adapter + `ClaudePlanReader` already reads `~/.claude.json`
**Source:** `docs/research/provider-data-sources.md` § "Correction 2"

## Why

The shipped Claude adapter leaves `sessionPercent` / `weeklyPercent` / `resetDate` `nil`, so the card shows *"Session and weekly limits aren't reported by Claude."* They **are** reported — Claude Code caches the server figures in `~/.claude.json` → `cachedUsageUtilization` (the same file the adapter already opens for `planName`). Reading it is a **local file read, no OAuth, no Keychain, no network, no ToS question.** This brings the Claude card to full parity with Codex.

## Data

`~/.claude.json` → `cachedUsageUtilization`:

```jsonc
{
  "fetchedAtMs": 1788791249199,
  "accountUuid": "871ccbac-…",           // == oauthAccount.accountUuid
  "utilization": {
    "five_hour": { "utilization": 21, "resets_at": "2026-09-07T15:39:59.661643+00:00", "locked_reason": null },
    "seven_day": { "utilization": 32, "resets_at": "2026-09-07T21:59:59.661667+00:00", "locked_reason": null }
  }
}
```

- `five_hour` → **session**; `seven_day` → **weekly**. `utilization` is an integer percent (0–100+).
- `resets_at` is ISO8601 with **microseconds** (`.661643`) and an explicit `+00:00` offset.
- `fetchedAtMs` — epoch ms; refreshed on ~every CLI interaction (observed 2 min old on an active machine).
- There is also a `utilization.limits[]` array carrying the same `percent`/`resets_at` keyed by `kind` (`"session"`, `"weekly_all"`) — use `five_hour`/`seven_day` as primary; `limits[]` is a fallback if those are ever missing.

## Change

### 1. Extend the config reader

`ClaudePlanReader.swift` already decodes `~/.claude.json` for `organizationType`. Add the utilization decode — either a sibling `static func usage(fromConfig:) -> ClaudeUsage?` or fold both into one `ClaudeConfigReader.read(_:) -> (planName: String, usage: ClaudeUsage?)` so the file is parsed once.

```swift
struct ClaudeUsage {
    var sessionPercent: Double?
    var weeklyPercent: Double?
    var resetDate: Date?          // seven_day.resets_at — mirror Codex (weekly reset on the card's single line)
}
```

Decode target — model **only** these fields (privacy boundary; the file also holds `accountUuid`, `spend`, email, MCP configs):

```swift
struct ClaudeConfig: Decodable {
    let oauthAccount: ClaudeOAuthAccount?
    let cachedUsageUtilization: ClaudeCachedUtilization?
}
struct ClaudeCachedUtilization: Decodable {
    let fetchedAtMs: Double?
    let utilization: ClaudeUtilizationWindows?
}
struct ClaudeUtilizationWindows: Decodable {
    let five_hour: ClaudeWindow?
    let seven_day: ClaudeWindow?
}
struct ClaudeWindow: Decodable {
    let utilization: Double?
    let resets_at: String?
}
```

### 2. Validity rules (a stale cache must not show wrong numbers)

For each window:

- Parse `resets_at`. **Truncate the fractional seconds to ≤3 digits before parsing** (`ISO8601DateFormatter(.withFractionalSeconds)` rejects microseconds); a regex like `\.\d+` → `.\(first 3 digits)`, or drop the fraction entirely — sub-second precision on a reset time is irrelevant. Reuse the parser's existing `fractionalTimestamp` / `plainTimestamp` fallback after truncation.
- **If `resets_at` is in the past** (`< Date()`), the window has rolled over since the cache was written → the cached `utilization` is from the previous window → that field is **`nil`** (unknown, not 0 — we don't actually know the new window's usage).
- If `resets_at` parses and is in the future → use `utilization` as the percent.
- If `cachedUsageUtilization` is absent, or `utilization` / a window is missing → that field is `nil` (current behavior; caption still shows only when **both** percents are nil).
- Optional extra guard: if `fetchedAtMs` is older than ~24 h even with a future `resets_at`, still show it (the window is structurally valid) but you may log it. Don't over-engineer — the past-`resets_at` check is the important one.

### 3. Wire into the provider

`ClaudeUsageProvider.fetchUsage()` — after `planName()` and `daily`, read the same config data for `ClaudeUsage`, and populate the snapshot:

```swift
return UsageSnapshot(
    provider: .claude,
    planName: planName,
    sessionPercent: usage?.sessionPercent,
    weeklyPercent: usage?.weeklyPercent,
    resetDate: usage?.resetDate,
    dailyTokenUsage: daily
)
```

Read `~/.claude.json` **once** per `fetchUsage()` (not twice) — refactor `readConfig()` to return the parsed data.

### 4. No UI / model changes

- `UsageSnapshot` fields already exist and are optional.
- `ProviderCardView` already renders the bars when a percent is non-nil, and the caption only when **both** are nil — so a Claude card with live data now shows the Session/Weekly bars + "Resets …" line automatically, and the caption disappears. Nothing to touch.
- Codex / Gemini untouched.

## Out of scope

- Option B / the `/usage` server endpoint — **dropped**, don't build it.
- `extra_usage` credits / `spend` — future, when the DeepSeek `balance` model lands.
- Per-model weekly breakdowns (`seven_day_opus`, etc. — all `null` on this machine anyway).
- Showing `fetchedAtMs` staleness in the UI (the existing per-card "Updated N ago" already covers freshness of the whole snapshot).

## Tests

Extend `ClaudePlanReaderTests` / add `ClaudeUsageReaderTests`, and `ClaudeUsageProviderTests`:

- Fixture config with `cachedUsageUtilization`, both `resets_at` in the **future** → `sessionPercent == 21`, `weeklyPercent == 32`, `resetDate` == the `seven_day` timestamp.
- `resets_at` in the **past** → that field `nil`, the other still populated.
- Microsecond `resets_at` (`…661643+00:00`) parses correctly after truncation.
- `cachedUsageUtilization` absent → all three `nil`, `planName` still resolved.
- Malformed / partial `utilization` → `nil`, no throw.
- Privacy: fixture with `cachedUsageUtilization.accountUuid` = `"SECRET-SENTINEL"` and a `spend` block → snapshot has no sentinel (extends the existing step-5.6 privacy test).
- Provider: fixture `configFile` with future-reset utilization + project fixtures → snapshot has bars **and** chart.

Keep all 72 tests green. `swift build && swift test` locally (CI paused — state result in the PR). `Package.swift` dependency-free. No version bump.

## Handoff back

Push, open the PR. **Screenshot the Claude card** showing real Session/Weekly bars + "Resets …" (the caption should be gone). Report the live values and whether they match `/status` → Usage. One re-reviews from remote.
