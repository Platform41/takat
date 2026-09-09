# Gemini — Antigravity "not measurable" notice: Handoff

**Spec owner:** One
**Implementer:** _assign_ (Claude/Three or DeepSeek) · **Review:** _assign_
**Branch:** `feat/gemini-antigravity-notice` off `main`
**Context:** PR #34 (rejected) established — verified — that **Google Antigravity records no token usage anywhere on disk**. Legacy Gemini CLI did; Antigravity's `~/.gemini/antigravity-cli/` is a conversation store only. This is option 1 from that review: make the Gemini card honest instead of showing a misleading "No usage in the last 7 days".

## The problem

`GeminiUsageProvider` reads legacy `~/.gemini/tmp/*/chats/session-*.json`. The maintainer now uses Antigravity, so:
- `~/.gemini/tmp` still has old chat files (June 2026) → the provider does **not** throw `.notConfigured`
- no files fall in the 7-day window → `DailyUsageBucketing` returns 7 zeros
- the card shows **"Session and weekly limits aren't reported by Gemini."** + **"No usage in the last 7 days"** — the second line reads as a bug

## The fix

Detect that Antigravity is the active Gemini tool and show a single honest line instead.

### 1. Model — `UsageSnapshot.note: String?`

`Sources/Takat/Core/Models/UsageSnapshot.swift` — add `public let note: String?` (optional, `Codable`, default `nil` in `init`, after `balance`). No cache schema bump (optional field; old JSON decodes → `nil`). Semantics: "this provider is present but its usage isn't locally measurable — here's why."

### 2. `GeminiUsageProvider`

- New injectable: `antigravityRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/antigravity-cli", isDirectory: true)`. Keep `now` injectable too (add if not present) for deterministic tests.
- `private func antigravityActive(at now: Date) -> Bool`: `antigravityRoot` exists **and** has activity within the last 7 local days — check the mtime of `antigravityRoot/history.jsonl`, and/or the newest entry in `antigravityRoot/conversations/`. Any one recent → `true`. (Do **not** parse the SQLite / transcripts — mtime is enough.)
- Restructure the end of `fetchUsage()`:

  ```
  1. scan legacy ~/.gemini/tmp for in-window token deltas  (unchanged)
  2. if deltas is non-empty      → return the normal token-chart snapshot   (unchanged, note = nil)
  3. else if antigravityActive   → return UsageSnapshot(
         provider: .gemini, planName: "Gemini",
         note: "Antigravity doesn't record token usage locally.",
         dailyTokenUsage: [])                                    // empty, not 7 zeros
  4. else if legacy tmp had files (just none in window) → return the 7-zeros snapshot  (unchanged)
  5. else                         → throw .notConfigured                    (unchanged)
  ```
- Also handle the **early** `.notConfigured` guards: if `~/.gemini/tmp` is missing or has no `chats/*.json` **but** `antigravityActive` → return the note snapshot (step 3) instead of throwing. Simplest: check `antigravityActive` before the early throws, or fall through to a single decision block.
- The 10-min-TTL / `.unavailable` / `inWindowCount` logic stays as-is for the legacy path.

### 3. `ProviderCardView` (`DashboardView.swift`)

Add a **first** branch to the card body, before `balance`:

```swift
if let note = snapshot.note {
    Text(note)
        .font(.caption)
        .foregroundStyle(.secondary)
} else if let balance = snapshot.balance {
    …
```

And skip the chart for a note snapshot — the existing `if !snapshot.dailyTokenUsage.isEmpty` guard already covers it (note snapshot has empty `dailyTokenUsage`). The `resetDate` line is already `nil`-guarded. Header (mark + name + plan pill) and `freshnessRow` still render.

### 4. Settings status (`SettingsView.swift`)

`statusText(for:)` — when `store.snapshot(for: .gemini)?.note != nil`, show a neutral **"Not measurable"** (`.secondary`) instead of "Connected". Small: add one branch.

## Out of scope

- Parsing Antigravity SQLite / transcripts (no token data there — verified).
- Any "session count" metric.
- The legacy Gemini CLI path (unchanged when it has real in-window data).
- Other providers.

## Docs

`docs/research/provider-data-sources.md` § Gemini — replace the speculative Antigravity correction with: Antigravity stores no usage data; Takat shows a "not measurable" notice; legacy Gemini CLI remains fully supported.

## Tests

`Tests/TakatTests/GeminiUsageProviderTests.swift` (+ fixtures under `Tests/TakatTests/Fixtures/`):

- **Antigravity active, no legacy in-window data** → snapshot `note == "Antigravity doesn't record token usage locally."`, `dailyTokenUsage.isEmpty`, `sessionPercent == nil`. (Fixture: an `antigravity-cli/history.jsonl` written with a current mtime; legacy `tmp` empty or absent.)
- **Legacy in-window token data present** (existing test) → `note == nil`, chart populated. Regression.
- **Legacy files exist but all stale, no Antigravity** → 7 zero entries, `note == nil` (unchanged "No usage" is legit here).
- **Neither legacy nor Antigravity** → `.notConfigured`.
- `UsageSnapshot` with `note` → `Codable` round-trip; JSON without `note` → decodes to `nil`.
- Update any `allCases` / snapshot-shape assertions that construct `UsageSnapshot` positionally.

Keep the full suite green. `swift build && swift test` locally (CI paused — state result in the PR). `Package.swift` dependency-free. No version bump.

## Handoff back

Push, open the PR, `swift test` result. **Screenshot the Gemini card** on this machine (Antigravity is active here) — it should show "Antigravity doesn't record token usage locally." and nothing else in the body. One re-reviews.
