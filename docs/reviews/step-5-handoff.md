# Step 5 — Claude Usage Adapter: Handoff to DeepSeek

**Spec owner:** One
**Implementer:** DeepSeek (Three)
**Branch:** `feat/claude-adapter` off `main` → PR (expected #9 or #10)
**Depends on:** PR #8 merged (`ddc2252`) — Codex adapter + chart metric
**Source of truth for data shapes:** `docs/research/provider-data-sources.md` (§ Claude Code)

## Goal

Replace `FixtureUsageProvider(providerID: .claude)` with a real adapter that reads Claude Code's local transcripts for **daily token usage only**. Claude does not persist session/weekly percentages or a reset date anywhere on disk — those bars stay `nil` (Option A in the research doc). No network, no Keychain, no `/usage` endpoint.

After this PR the app uses two real providers; `FixtureUsageProvider` stays for tests and previews.

---

## Where the data is

```
~/.claude/projects/<cwd-slug>/<session-uuid>.jsonl
```

- Newline-delimited JSON, one file per Claude Code session.
- `<cwd-slug>` is a `-`-escaped absolute path; the **same project appears under multiple slugs** (different worktrees). Aggregate across **all** slugs — this is "my Claude usage", not per-project.
- On the maintainer's machine: 75 MB total, 17 files, **4 modified in the last 7 days**. The mtime filter matters.

### Line shape that matters (assistant messages)

```json
{
  "type": "assistant",
  "timestamp": "2026-09-06T14:11:57.880Z",
  "isSidechain": false,
  "message": {
    "role": "assistant",
    "usage": {
      "input_tokens": 2,
      "cache_creation_input_tokens": 11698,
      "cache_read_input_tokens": 24575,
      "output_tokens": 173
    }
  }
}
```

- `input_tokens` = **uncached** new input (Claude splits this out already).
- `cache_creation_input_tokens` = cache writes (new work).
- `cache_read_input_tokens` = cheap cached-context reads — **exclude** (same reasoning as the Codex `newTokens` fix in step 4b).
- `output_tokens` includes thinking tokens (`output_tokens_details.thinking_tokens` is a subset — do not add it again).
- `isSidechain: true` lines are subagent turns — **count them**, they're real usage.
- `type: "user"` lines and everything else → ignore.

---

## Mapping to `UsageSnapshot`

| Field | Value |
|---|---|
| `provider` | `.claude` |
| `planName` | `"Claude"` — **fixed string.** No plan indicator exists in `~/.claude` (checked `settings.json`, `stats-cache.json`). |
| `sessionPercent` | `nil` |
| `weeklyPercent` | `nil` |
| `resetDate` | `nil` |
| `dailyTokenUsage` | per-day sum of `newTokens`, bucketed by the line's top-level `timestamp` into `Calendar.current` days, 7 entries, zero-filled, chronological |

### `newTokens` for Claude

```swift
static func newTokens(_ u: ClaudeTokenUsage) -> Int {
    (u.input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0) + (u.output_tokens ?? 0)
}
```
(`cache_read_input_tokens` deliberately absent.)

---

## Suggested structure (mirror the Codex adapter)

- `Sources/Takat/Core/Providers/ClaudeSessionParser.swift`
  - pure `enum ClaudeSessionParser` — `static func parse(lines: some Sequence<String>) -> [(Date, Int)]` (token deltas), `static func newTokens(_:)`, plus `dailyUsage(...)` **or** reuse `CodexSessionParser.dailyUsage` if you lift it to a shared helper. Prefer lifting `dailyUsage` + the 7-day zero-fill into one shared `DailyUsageBucketing` type so both adapters call it — do **not** copy-paste it a third time.
  - `Decodable` structs model **only** `type`, `timestamp`, `message.usage.{input_tokens, cache_creation_input_tokens, output_tokens}`. Nothing else — this is the privacy boundary (see below).
- `Sources/Takat/Core/Providers/ClaudeUsageProvider.swift`
  - `public struct ClaudeUsageProvider: UsageProvider`, `providerID = .claude`
  - `public init(projectsDirectory: URL = ClaudeUsageProvider.defaultProjectsDirectory)`
  - `defaultProjectsDirectory` = `~/.claude/projects`
  - Enumerate `*/*.jsonl` (one level of slug dirs), filter to `contentModificationDate` within the last 7 local days, **defensively skip any single file larger than ~200 MB**, parse each, concatenate deltas, bucket.
- Reuse `JSONLLines` from the Codex adapter for line iteration (lift it out of `CodexUsageProvider.swift` into its own file if that reads cleaner).

### Error mapping

| Condition | Result |
|---|---|
| `~/.claude` or `~/.claude/projects` missing | `throw .notConfigured` |
| Directory exists, zero `*.jsonl` anywhere | `throw .notConfigured` |
| Files exist but no assistant-usage lines in the 7-day window | **return a valid snapshot with an all-zero 7-day chart** — not an error. "Haven't used Claude this week" is a real state. |
| I/O error | `throw .unavailable` |

No new `UsageProviderError` cases.

---

## Privacy — read this twice

Claude transcripts contain the user's actual conversations, source code, file contents, and possibly secrets. The adapter must:

- Model **only** the three usage integers + `type` + `timestamp` in `Decodable` structs. `message.content` and everything else must be un-modelled so it cannot land in a `UsageSnapshot` or the on-disk cache.
- Never log a raw line, never hold `message.content` in a variable.
- Read-only. Never write under `~/.claude`.
- Touch only `projects/` — not `history.jsonl`, `settings.json`, `.credentials`, `shell-snapshots/`, `todos/`, etc.

Add a test that a fixture line containing a `"content"` field with sentinel text produces a snapshot whose values are purely numeric (i.e. the parser structurally cannot surface it).

---

## UI consequence — both bars `nil`

The Claude card will have `sessionPercent == nil && weeklyPercent == nil`. Today `ProviderCardView` would render two `UsageBar`s showing "—" and an empty track, and hide the "Resets" line.

**One's call:** when **both** percents are `nil`, replace the two `UsageBar`s with a single caption:

> *Session and weekly limits aren't reported by Claude.*

Small change in `Sources/Takat/Features/Dashboard/DashboardView.swift` (`ProviderCardView`). Keep it minimal and semantic — Two can refine the visual later. The 7-day chart still renders normally.

---

## Wire-up

`Sources/Takat/App/TakatApp.swift`:
```swift
let providers: [any UsageProvider] = [
    ClaudeUsageProvider(),
    CodexUsageProvider()
]
```

`SettingsView` status logic already handles this (a Claude snapshot with data → "Connected").

---

## Out of scope

- The `/usage` endpoint / Keychain / OAuth — deferred milestone, needs a privacy+ToS review (Six).
- Cost/pricing in currency.
- Per-model breakdown.
- Backfill beyond 7 days.
- Any change to the Codex adapter.
- Deleting `FixtureUsageProvider` — keep it.

---

## Tests

Sanitized hand-crafted fixtures under `Tests/TakatTests/Fixtures/claude-projects/<slug>/<uuid>.jsonl` — no real content. Cover:

- Parser: `newTokens` math; `cache_read_input_tokens` is **excluded** (a turn that is 100% cache-read → 0).
- Parser: `type: "user"` and unknown lines ignored; malformed final line tolerated.
- Parser: `isSidechain: true` assistant line **is** counted.
- Parser: bucketing by calendar day with an injected reference date.
- Privacy: a fixture line with `message.content` = `"SECRET-SENTINEL"` → resulting `UsageSnapshot` contains only integers/dates, sentinel never appears.
- Provider: aggregates across **two different slug directories**.
- Provider: mtime filter excludes an old file.
- Provider: missing dir → `.notConfigured`; dir with no `.jsonl` → `.notConfigured`.
- Provider: files present, none in the 7-day window → snapshot with 7 zero entries, `planName == "Claude"`, all percents `nil`.
- Shared `dailyUsage` helper (if lifted) keeps its existing Codex tests green.

Keep all 29 existing tests green. `swift build` + `swift test` before every push. `Package.swift` stays dependency-free.

---

## Handoff back

- Push, open the PR, fill test-evidence.
- Run the provider against the live `~/.claude/projects` and report the 7-day bar values so One can sanity-check magnitude (expect the same order-of-magnitude story as Codex — new tokens, not cache reads).
- **Visual eyeball on a desktop:** open the panel, confirm the Claude card shows the "Claude" header, the "limits aren't reported" caption in place of the two bars, and a 7-day chart. Screenshot in the PR.
- One re-reviews from remote.
