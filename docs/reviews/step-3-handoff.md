# Step 3 — Persistence & Refresh State: Handoff to DeepSeek

**Reviewer / spec owner:** One (architecture)
**Implementer:** DeepSeek (Three — implementation only)
**Branch:** new branch off `main` → `feat/persistence-refresh-state` → PR #3
**Delivery-order step:** 3 of 6 (`docs/architecture.md`)
**Depends on:** PR #2 (merged, `26b237d`)

## Goal

The panel should show **last-known usage instantly on launch**, before any network/provider call, and clearly tell the user **how fresh** that data is. No credentials, no Keychain yet — that arrives with the real adapters (steps 4–5). See `docs/research/provider-data-sources.md` for why persistence is safe to build now and what the real adapters will feed it.

---

## Scope

### 1. Snapshot persistence

- On `UsageStore` init: load persisted snapshots from disk synchronously (or in the first `.task`) so `snapshots` is non-empty before the first `refresh()`.
- After a successful `refresh()`: write the current `snapshots` map to disk.
- Location: `FileManager.default.url(for: .applicationSupportDirectory, ...)` → `Takat/usage-cache.json`. Create the directory if missing.
- Format: JSON. Make `UsageSnapshot`, `ProviderID`, `DailyTokenUsage` `Codable` (they're already `Sendable`/`Equatable` — add `Codable` conformance, no stored-property changes).
- Persist a `lastUpdated: Date` alongside the snapshots (per provider, keyed like `errors`).
- Corrupt / missing / schema-mismatched file → start empty, don't crash. Version the payload (`{"schema": 1, ...}`) so future changes are detectable.
- Only cache usage fields — never transcript or prompt content (there is none in the model today; keep it that way).

### 2. Refresh-state surfacing

- `UsageStore` exposes `lastUpdated(for: ProviderID) -> Date?`.
- `ProviderCardView`: show a relative "Updated 3 min ago" line (use `Text(date, format: .relative(presentation: .named))` or `RelativeDateTimeFormatter`).
- Stale indicator: if `lastUpdated` is older than a threshold (start with **15 minutes**, make it a named constant), show the timestamp in `.secondary`/`.orange` and a small `clock.badge.exclamationmark` affordance.
- If a provider currently has an error AND a stale cached snapshot: card renders the cached data **plus** an inline error badge (this closes the follow-up from the PR #2 review — dashboard currently hides provider errors; only Settings shows them).

### 3. Auto-refresh cadence

- Refresh when the menu bar panel opens (already happens via `.task` when `snapshots.isEmpty`; extend to also refresh if the newest `lastUpdated` is older than the stale threshold).
- While the panel is open, refresh on a timer (start with **60 s**, named constant). Stop the timer when the panel closes — use `.task`/`onDisappear` or a `TimelineView`, whichever is cleaner; do not leave a background timer running when the panel is dismissed.
- Never overlap refreshes — the existing `isRefreshing` guard covers this; keep it.

### 4. Carry-over polish (small, do them here)

- `.tint(snapshot.provider.accentColor)` on the Session/Weekly `ProgressView`s so each card is one colour system (from the PR #2 visual note).
- Regression test: `errors` is cleared on the next successful `refresh()` after a failed one.

---

## Out of scope — do NOT build

- Keychain / credential storage (steps 4–5).
- Any real provider adapter (Codex = step 4, Claude = step 5).
- The `/usage` endpoint reverse-engineering discussed in the research doc (needs a separate product + privacy decision).
- Packaging / signing / notarization (step 6).
- Settings for cadence/threshold — hard-code named constants for now.

---

## Tests (required)

`Tests/TakatTests/`:

- Persistence round-trip: refresh → new `UsageStore` from the same directory → `snapshots` + `lastUpdated` restored.
- Corrupt cache file → new store starts empty, no throw.
- Schema-version mismatch → treated as empty.
- `lastUpdated(for:)` returns `nil` before first refresh, a `Date` after.
- Stale-threshold logic is a pure function and is unit-tested at the boundary (14:59 vs 15:01).
- Carry-over: `errors` cleared after fail-then-succeed.
- Inject the cache directory (e.g. `UsageStore(providers:, cacheDirectory:)` defaulting to Application Support) so tests use a temp dir — do not write to the real `~/Library`.

Keep all 9 existing tests green. `swift build` + `swift test` before every push.

---

## Constraints

- Commit small, conventional-commit messages, onto `feat/persistence-refresh-state`.
- No version bump / tag — One owns that after merge.
- `@MainActor` isolation on `UsageStore` stays; file I/O off the main actor (use `Task.detached` or a `nonisolated` helper) but assign results back on the main actor.
- Match existing code style (SwiftUI, `@Observable`, no external deps — `Package.swift` stays dependency-free).

## Handoff back to One

Push, open PR #3, fill the test-evidence section, and comment which scope items landed vs deferred with reasons. One re-reviews from remote before merge.
