# Step 4 — Codex Usage Adapter: Handoff to DeepSeek

**Spec owner:** One (architecture)
**Implementer:** DeepSeek (Three — implementation only)
**Branch:** `feat/codex-adapter` off `main` → PR (expected #5)
**Delivery-order step:** 4 of 6
**Depends on:** PR #4 merged (`b98cb96`) — `UsageStore` / persistence in place
**Source of truth for data shapes:** `docs/research/provider-data-sources.md` (§ Codex CLI)

## Goal

Replace the fixture Codex provider with a real adapter that reads the Codex CLI's local session logs — no network, no auth. The Claude side stays on `FixtureUsageProvider` until step 5.

---

## Where the data is

```
~/.codex/sessions/YYYY/MM/DD/rollout-<ISO8601>-<uuid>.jsonl
```

One newline-delimited-JSON file per Codex session, date-partitioned. ~88 files on the maintainer's machine; dates are sparse (only days Codex was used).

### Line shapes that matter

**First line — session metadata:**
```json
{ "timestamp": "2026-09-05T01:49:22.571Z", "type": "session_meta",
  "payload": { "session_id": "…", "cwd": "…", "cli_version": "0.153.4", "timestamp": "…" } }
```
> The `session_meta` line also embeds a ~30 KB `base_instructions.text` (Codex's full system prompt). **Do not decode or retain it.** Parse line-by-line and pull only the fields you need.

**Usage lines — repeated throughout the session (~400 per session):**
```json
{ "timestamp": "2026-09-06T06:50:06.843Z", "type": "event_msg",
  "payload": {
    "type": "token_count",
    "info": {
      "total_token_usage": { "total_tokens": 47686183, "input_tokens": …, "output_tokens": …, "reasoning_output_tokens": …, "cached_input_tokens": … },
      "last_token_usage":  { "total_tokens": 23613, "…": … },
      "model_context_window": 258400
    },
    "rate_limits": {
      "primary":   { "used_percent": 0.0,  "window_minutes": 300,   "resets_at": 1788690513 },
      "secondary": { "used_percent": 31.0, "window_minutes": 10080, "resets_at": 1788748053 },
      "plan_type": "plus",
      "limit_id": "codex", "credits": {…}, "rate_limit_reached_type": null
    }
  } }
```

- `primary` = rolling ~5 h window (`window_minutes: 300`)
- `secondary` = weekly window (`window_minutes: 10080`)
- `resets_at` = **epoch seconds**
- `used_percent` = float, 0–100+ (observed up to 97; may exceed 100 when over quota)
- `plan_type` observed: `"plus"`. Others presumably `"pro"`, `"team"`, `"enterprise"`, possibly `null`.

---

## Mapping to `UsageSnapshot`

| Field | Source | Notes |
|---|---|---|
| `provider` | `.codex` | |
| `planName` | `rate_limits.plan_type`, `.capitalized` (`"plus"` → `"Plus"`) | `nil`/unknown → `"Codex"` |
| `sessionPercent` | `rate_limits.primary.used_percent` | |
| `weeklyPercent` | `rate_limits.secondary.used_percent` | |
| `resetDate` | `Date(timeIntervalSince1970: rate_limits.secondary.resets_at)` | **Use `secondary` (weekly)** — `primary` resets every ~5 h, too noisy for the card's single "Resets" line. Design decision by One; revisit with Two if per-bar resets are wanted later. |
| `dailyTokenUsage` | per-day sum of `payload.info.last_token_usage.total_tokens`, bucketed by the line's top-level `timestamp` into `Calendar.current` calendar days, for the last 7 days | `last_token_usage` is the per-turn delta; summing across turns ≈ real daily usage. Include reasoning + output + input (`total_tokens` as-is). Days with no activity → `tokenCount: 0` entry so the chart still shows 7 bars. |

### "Current" rate-limit snapshot algorithm

1. List `~/.codex/sessions/**/rollout-*.jsonl`, pick the **most recent** by the timestamp in the filename (fall back to file mtime).
2. Stream it line by line; keep the **last** line where `payload.type == "token_count"` and `payload.rate_limits` is present.
3. If that file has no such line (brand-new session), move to the next-most-recent file. Try at most ~3 files, then `throw .unavailable`.
4. The newest file may be an **actively running** Codex session — its final line can be a partial write. A line that fails to parse is skipped, not fatal.

### Daily-usage scan

- Only open files whose date-partition path (or mtime) falls within the last 7 local days — do **not** scan all 88 files on every refresh.
- Bucket each `token_count` line's `last_token_usage.total_tokens` by `Calendar.current.startOfDay(for: <line timestamp>)`.

---

## Suggested structure

- `Sources/Takat/Core/Providers/CodexUsageProvider.swift`
  - `public struct CodexUsageProvider: UsageProvider` — `providerID = .codex`, does filesystem discovery, injectable root:
    ```swift
    public init(sessionsDirectory: URL = CodexUsageProvider.defaultSessionsDirectory)
    ```
    `defaultSessionsDirectory` = `FileManager.default.homeDirectoryForCurrentUser` + `.codex/sessions`.
  - A **pure, testable** parser split out — e.g. `enum CodexSessionParser` with `static func parse(lines: some Sequence<String>) -> CodexSessionData` returning the last `rate_limits` + an array of `(Date, Int)` token deltas. No filesystem, no dates-from-`Date()`.
- Keep `FixtureUsageProvider` — still used for `.claude` and for previews/tests.
- Line reading: use `FileHandle`/`AsyncBytes` or read `Data` and split on `\n`. Do **not** load a whole file into a `String` and JSON-decode the whole thing — lines are individually large and files reach multiple MB.
- Decode with `JSONDecoder` into small `Decodable` structs that only declare the fields above (`Decodable` ignores everything else) — this is also the privacy boundary: transcript / reasoning / tool-output fields are never modelled, so they can't leak into `UsageSnapshot` or the on-disk cache.

### Error mapping

| Condition | Throw |
|---|---|
| `~/.codex` or `~/.codex/sessions` missing | `UsageProviderError.notConfigured` |
| Directory exists but no session files at all | `.notConfigured` |
| Files exist but no parseable `rate_limits` in the newest ~3 | `.unavailable` |
| I/O error mid-read | `.unavailable` |

(No new error cases — the enum stays `notConfigured / unavailable / unauthorized`.)

---

## Wire-up

`Sources/Takat/App/TakatApp.swift`:
```swift
let providers: [any UsageProvider] = [
    FixtureUsageProvider(providerID: .claude),   // until step 5
    CodexUsageProvider()
]
```

`SettingsView` already renders "Connected / Unavailable / Not configured" from `store.errors` — a machine without Codex will now correctly show **Not configured** for Codex. Verify that path.

---

## Out of scope — do NOT build

- Claude adapter (step 5).
- Reading `~/.codex/auth.json`, `config.toml`, `history.jsonl`, or any of the non-standard sqlite/`herdr-*` files on this machine. **Touch only `sessions/`.**
- Cost/pricing calculation.
- Any `~/.codex` *write*. Read-only.
- Keychain, packaging, signing.
- Backfilling more than 7 days of chart history.

---

## Tests (required)

Add sanitized fixture session files under `Tests/TakatTests/Fixtures/codex-sessions/` — **hand-craft minimal ones**: a `session_meta` line with a short fake `base_instructions`, then a handful of `token_count` lines with known `rate_limits` and `last_token_usage`. No real prompts, paths, tokens, or usage numbers copied from a live machine.

- Parser: extracts the **last** `rate_limits` from a multi-event file.
- Parser: correct `planName` for `"plus"`, for an unknown value, and for `null`.
- Parser: tolerates a corrupt/truncated final line (returns data from prior lines).
- Parser: buckets `last_token_usage.total_tokens` into the right calendar days given an injected reference date.
- Provider: picks the newest file across nested date dirs.
- Provider: falls back to the 2nd file when the newest has no `token_count`.
- Provider: `sessionsDirectory` missing → `.notConfigured`; present but empty → `.notConfigured`.
- Provider: ignores non-`rollout-*.jsonl` entries in the tree.
- `dailyTokenUsage` always has 7 entries, chronologically ordered, zero-filled for idle days.

Keep all 17 existing tests green. `swift build` + `swift test` before every push. `Package.swift` stays dependency-free.

---

## Constraints & handoff back

- `@MainActor` isolation unchanged; all file I/O off the main actor (the provider's `fetchUsage()` is already `async` and called from a task group).
- Small conventional commits on `feat/codex-adapter`.
- No version bump / tag — One owns that.
- **Real-run check before handoff:** launch the app on this machine (Codex *is* installed here), open the panel, confirm the Codex card shows live `plan_type` / session % / weekly % / reset date / a 7-day bar chart that matches `codex` usage, and that the values are plausible vs what `codex` shows in its own TUI. Screenshot in the PR.
- Push, open the PR, fill the test-evidence section, list scope items landed vs deferred. One re-reviews from remote.
