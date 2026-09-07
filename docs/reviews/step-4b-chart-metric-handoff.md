# Step 4b — Codex chart metric fix: Handoff to DeepSeek

**Spec owner:** One
**Implementer:** DeepSeek (Three)
**Branch:** `fix/codex-chart-metric` off `main` → PR (expected #7)
**Depends on:** PR #6 merged (`25b39b9`)
**Type:** small correction to the step-4 adapter — no new surface

## Why

The Codex adapter currently sums `last_token_usage.total_tokens` per turn for the 7-day chart. On real data each turn's `total_tokens` is ~95% **re-read cached context** (`cached_input_tokens`), so the bars land in the tens of millions per day and their shape tracks conversation length, not consumption. The chart needs to show *new work*, not cache replays.

## Change

### 1. Decode the token breakdown

In `Sources/Takat/Core/Providers/CodexSessionParser.swift`, expand `CodexTokenUsage`:

```swift
struct CodexTokenUsage: Decodable {
    let input_tokens: Int?
    let cached_input_tokens: Int?
    let cache_write_input_tokens: Int?
    let output_tokens: Int?
    let reasoning_output_tokens: Int?
    let total_tokens: Int?          // keep — may still be useful later
}
```

All optional; treat missing as `0`.

### 2. Compute "new tokens" per turn

Add to `CodexSessionParser`:

```swift
static func newTokens(_ u: CodexTokenUsage) -> Int {
    let inp = u.input_tokens ?? 0
    let cached = u.cached_input_tokens ?? 0
    let cacheWrite = u.cache_write_input_tokens ?? 0
    let out = u.output_tokens ?? 0
    let reasoning = u.reasoning_output_tokens ?? 0
    return max(0, inp - cached) + cacheWrite + out + reasoning
}
```

`cached_input_tokens` is a subset of `input_tokens` in the Codex shape (verified: `input_tokens: 23017`, `cached_input_tokens: 22272`), so `input - cached` is genuinely-new input. Cache **writes** are new tokens processed, so they count.

### 3. Use it in `tokenDeltas`

`parse(lines:)` currently does:
```swift
if let tokens = event.payload.info?.last_token_usage?.total_tokens, ... {
    data.tokenDeltas.append((date, tokens))
}
```
Change to append `newTokens(lastTokenUsage)` instead. Skip the entry only if `last_token_usage` is entirely absent (a turn with a real 0 is fine to record).

### 4. Document the metric

Add a doc comment on `DailyTokenUsage.tokenCount` (in `UsageSnapshot.swift`):
```swift
/// Non-cached tokens processed that day: new input + cache writes + output + reasoning.
/// Excludes cached-context reads, which dominate raw per-turn totals.
public let tokenCount: Int
```
No stored-property or `Codable` change — comment only.

### 5. Fold in the two review nits (cheap, do them here)

- Hoist the two `ISO8601DateFormatter` instances in `parse(lines:)` to `private static let` (they're rebuilt per file today).
- `latestRateLimits(in:)` runs the full parser just to read the last `rate_limits`; have it stop at the last `token_count` line's rate limits without accumulating `tokenDeltas` — either a dedicated lightweight scan or a `parse` variant with a `rateLimitsOnly` flag. Optional if it complicates the code; skip rather than make it ugly.

## Out of scope

- Everything else in the adapter — file discovery, fallback, error mapping, privacy boundary all stay.
- The Claude adapter (step 5).
- Any UI change — `DailyUsageChart` already normalises to the max, so smaller absolute numbers just render correctly.
- Cost/pricing.

## Tests

Update `Tests/TakatTests/CodexUsageProviderTests.swift` and `CodexSessionParserTests`:

- The shared `tokenCountLine(...)` helper currently emits only `last_token_usage.total_tokens`. Give it explicit `input`/`cached`/`output`/`reasoning`/`cacheWrite` params (default the extras to 0) and emit the full `last_token_usage` object.
- New parser test: `newTokens` math — e.g. `input 1000, cached 900, cacheWrite 0, output 200, reasoning 50` → `350`; all-cached turn (`input 900, cached 900, output 0`) → `0`.
- Update `testExtractsLastRateLimits` / `testBucketsIntoCalendarDays` / `testDailyTokenUsageAlwaysSevenEntries` expected values to the new metric.
- Add: a turn that is 100% cached reads contributes `0` to its day's bucket.

Keep all 27 tests green (adjusted expectations count as green). `swift build` + `swift test` before every push. `Package.swift` stays dependency-free.

## Handoff back

Push, open the PR, fill test-evidence, and include the **live-data before/after**: run the provider against `~/.codex/sessions` and report the 7-day bar values old-metric vs new-metric so One can sanity-check the magnitude drop. One re-reviews from remote. This is also the moment to do the still-open **visual eyeball** of the Codex card (open the app panel, confirm it renders) and note the result.
