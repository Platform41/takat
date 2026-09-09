# Fix — Codex stale rate-limit window: Handoff to DeepSeek

**Spec owner:** One
**Implementer:** DeepSeek (Three)
**Branch:** `fix/codex-stale-window` off `main` → PR
**Type:** bug fix to the shipped Codex adapter (`v0.1.0`). Small.

## The bug

Maintainer's `codex /status` showed **5h limit: 100% left** (0% used); Takat's Codex card showed **Session 90%**.

Root cause — `CodexUsageProvider.fetchUsage()`:
```swift
sessionPercent: rateLimits.primary?.used_percent,
weeklyPercent:  rateLimits.secondary?.used_percent,
resetDate:      rateLimits.secondary?.resets_at.map { Date(timeIntervalSince1970: $0) },
```
It takes `used_percent` from the **last `token_count` event in the newest session file, verbatim** — with **no check that the window is still open**. The maintainer's newest session file was from the previous day; its last recorded `primary` was `used_percent: 90, resets_at: <22 h ago>`. That 5-hour window reset long ago, so 90% is stale garbage. (The weekly figure was correct — that window was still open.)

This is the exact class of bug the **Claude adapter's step-5.8** `windowPercent` guards against (`resets_at` in the past ⇒ `nil`). Codex — shipped earlier in step 4 — never got it.

## The fix

Apply a stale-window guard, mirroring `ClaudePlanReader.windowPercent` / `windowReset`.

`CodexRateLimits.primary` / `.secondary` are `CodexWindow?` with `used_percent: Double?` and `resets_at: Double?` (epoch **seconds**).

```swift
// in CodexUsageProvider (or a CodexRateLimits helper), with `now = Date()`:
func percent(_ w: CodexWindow?) -> Double? {
    guard let w, let r = w.resets_at, Date(timeIntervalSince1970: r) > now else { return nil }
    return w.used_percent
}
func reset(_ w: CodexWindow?) -> Date? {
    guard let w, let r = w.resets_at, Date(timeIntervalSince1970: r) > now else { return nil }
    return Date(timeIntervalSince1970: r)
}
```

Then:
```swift
sessionPercent: percent(rateLimits.primary),
weeklyPercent:  percent(rateLimits.secondary),
resetDate:      reset(rateLimits.secondary),   // weekly reset, unchanged choice
```

- Past `primary.resets_at` ⇒ `sessionPercent = nil` ⇒ the Session bar shows "—" (or, if **both** percents end up `nil`, the card falls to the "limits aren't reported" caption — acceptable; it means the newest session data is entirely stale).
- `used_percent` can legitimately be `0.0` in a fresh window — that's a real 0, not "unknown". The guard is on `resets_at`, not on the value, so a fresh 0% still shows correctly.
- Keep `now` captured once at the top of `fetchUsage()` (there's already a `let now = Date()` for the daily cutoff — reuse it).

## Tests — the existing fixtures will break; fix them too

`Tests/TakatTests/CodexUsageProviderTests.swift` — the `tokenCountLine(...)` helper hardcodes `"resets_at":1788690513` (primary) and `1788748053` (secondary). **Both are now in the past**, so every provider test asserting a non-nil `sessionPercent`/`weeklyPercent` will fail once the guard lands.

- Change the helper to emit **future** timestamps relative to `Date()`: e.g. `primaryResetsAt = Date().timeIntervalSince1970 + 2*3600`, `secondaryResetsAt = + 5*24*3600`. Make them overridable params so a stale case can be tested.
- Add:
  - `primary.resets_at` in the past → `snapshot.sessionPercent == nil`, `weeklyPercent` still populated (future secondary).
  - `secondary.resets_at` in the past → `weeklyPercent == nil` **and** `resetDate == nil`.
  - fresh window with `used_percent: 0` → `sessionPercent == 0` (not nil).
- The `CodexSessionParser` tests that only check `data.rateLimits?.primary?.used_percent` (raw parse, no window logic) stay as-is — the parser still returns the raw block; the guard is in the provider.

Keep the rest of the suite green. `swift build && swift test` locally (CI paused — state result in the PR). No version bump; this rolls into the next `0.x`.

## Out of scope

- The Claude adapter (already has the guard).
- Gemini (no percentages).
- Changing which reset date the card shows (still weekly).
- Any staleness *indicator* in the UI beyond the existing "Updated N ago" / the bar going to "—".

## Handoff back

Push, open the PR, `swift test` result. Screenshot the Codex card after the fix — with a stale newest session it should show "—" for Session (or the caption) and the correct Weekly. One re-reviews from remote.
