# Gemini Antigravity `/usage` — Claude implementation handoff

**Spec owner:** One  
**Implementer:** Claude  
**Base:** current `main` after PR #43 (`96982ea`)  
**Scope:** replace the Gemini Antigravity notice with real quota groups obtained through the installed `agy` CLI

## Outcome

When Antigravity is installed and authenticated, the Gemini card shows the two quota groups reported by `/usage`:

1. Gemini models
2. Claude and GPT models

Each group shows weekly percentage **used** and its own reset time. Existing legacy Gemini CLI token history remains the fallback when Antigravity quota cannot be obtained.

## Verified contract

The following command works non-interactively:

```sh
agy --print "/usage" --output-format json --print-timeout 30s
```

The 2026-09-10 probe returned:

- exit status `0`
- top-level `status: "SUCCESS"`
- `conversation_id: ""`
- `duration_seconds: 0`
- `num_turns: 0`
- every token counter at `0`
- structured quota data under `command.data.groups`

This confirms that `/usage` is a local slash command and does not consume a model turn. Do not scrape the human-readable `response` or terminal bars; decode the structured `command.data` payload.

Representative, sanitized payload:

```json
{
  "status": "SUCCESS",
  "command": {
    "name": "usage",
    "data": {
      "description": "Within each group, models share a weekly limit.",
      "groups": [
        {
          "name": "Gemini Models",
          "description": "Models within this group: Gemini Flash, Gemini Pro",
          "buckets": [
            {
              "id": "gemini-weekly",
              "name": "Weekly Limit Remaining",
              "window": "weekly",
              "remaining_fraction": 0.84,
              "reset_time": "2099-09-14T04:48:31Z"
            }
          ]
        },
        {
          "name": "Claude and GPT models",
          "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS",
          "buckets": [
            {
              "id": "3p-weekly",
              "name": "Weekly Limit Remaining",
              "window": "weekly",
              "remaining_fraction": 0.25,
              "reset_time": "2099-09-15T17:41:12Z"
            }
          ]
        }
      ]
    }
  }
}
```

Antigravity's local log also confirms an internal `quota_manager` and calls to Google's Code Assist backend. Do not read its OAuth files or reproduce those private HTTP calls. Let the official `agy` executable own authentication and API compatibility.

## Data model

The current `UsageSnapshot` has only `sessionPercent`, `weeklyPercent`, and one `resetDate`; that cannot honestly represent two independent weekly groups. Add provider-neutral optional quota structures:

```swift
public struct UsageQuotaGroup: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let windows: [UsageQuotaWindow]
}

public struct UsageQuotaWindow: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let usedPercent: Double
    public let resetDate: Date?
}
```

Add `quotaGroups: [UsageQuotaGroup]?` to `UsageSnapshot` and its initializer. Keep it optional so cached snapshots written before this change decode without custom migration. Add explicit old-cache compatibility and round-trip tests.

The conversion is:

```text
usedPercent = clamp((1 - remaining_fraction) * 100, 0...100)
```

Use bucket IDs from the payload as stable window IDs. Derive a deterministic group ID from the group name or its bucket IDs; do not use randomized IDs because snapshots are persisted and SwiftUI identity must remain stable.

Normalize display labels from the stable bucket IDs (`gemini-weekly` → “Gemini models”, `3p-weekly` → “Claude and GPT models”, weekly buckets → “Weekly”). Ignore the payload's free-form description strings rather than persisting them. Unknown future IDs may use a generic, length-bounded label.

## Reader and process boundary

Add a focused reader, for example `AntigravityUsageReader.swift`, with two separable responsibilities:

1. Pure decoding/conversion of JSON into `[UsageQuotaGroup]`.
2. A process runner that invokes `agy` directly.

Do not invoke a shell. Use `Process.executableURL` plus explicit arguments:

```text
--print
/usage
--output-format
json
--print-timeout
30s
```

Resolve the executable in this order:

1. an injected URL used by tests
2. `~/.local/bin/agy`
3. `/opt/homebrew/bin/agy`
4. `/usr/local/bin/agy`

Only accept an executable regular file or executable symlink target. GUI apps do not inherit an interactive shell's `PATH`, so `command -v` is not sufficient.

Run the process off the main actor. Capture stdout separately from stderr, cap captured data (1 MiB is ample), enforce an outer timeout around 45 seconds, and terminate the child on timeout/cancellation. Never persist or surface raw stdout/stderr: future CLI versions could include account data in diagnostics.

Decoding rules:

- require exit status `0`, top-level `status == "SUCCESS"`, `command.name == "usage"`, and at least one valid bucket
- ignore unknown JSON fields
- skip malformed individual groups/buckets rather than failing an otherwise useful payload
- accept fractional ISO-8601 timestamps as well as the plain form shown above
- reject non-finite percentages and clamp finite values
- use the structured `command.data`; never fall back to parsing `response`

Inject the reader behind a small `Sendable` protocol or async closure so provider tests never launch the real CLI.

## Provider behavior

Update `GeminiUsageProvider` in this order:

1. If Antigravity's root exists and `agy` is resolvable, request live quota.
2. On a valid result, return a Gemini snapshot with:
   - `planName: "Antigravity"`
   - populated `quotaGroups`
   - no inaccurate note
   - no legacy token chart (the chart and quota would describe different clients)
3. If live quota fails, retain the existing legacy Gemini CLI parsing path.
4. If Antigravity is active and there is no usable legacy data, retain a concise fallback note, updated to say that Antigravity quota could not currently be read—not that quota is unavailable in principle.
5. If neither client is configured, continue throwing `.notConfigured`.

Live Antigravity quota takes precedence over legacy chat files when both exist. It represents the currently supported client and fixes the stale-file ambiguity addressed by PR #39.

Do not use the Antigravity group named “Claude and GPT models” to update Takat's separate Claude or Codex cards. It is an Antigravity-specific quota pool and belongs only on the Gemini/Antigravity card.

## Dashboard

In `ProviderCardView`, render non-empty `quotaGroups` before the legacy session/weekly branch.

For each group:

- show the group name as the row heading
- render each window using `UsageBar`, displaying Takat's percentage-used semantics
- show the reset directly under that group's window; do not use the snapshot's single global `resetDate`

Suggested compact labels:

```text
Gemini models
Weekly                                      16%
[████░░░░░░]
Resets Sep 14

Claude and GPT models
Weekly                                      75%
[████████░░]
Resets Sep 15
```

Keep `planName: "Antigravity"` visible in the pill; unlike the old “Gemini” pill, it adds useful source context. Preserve accessibility labels and values for every bar and reset time.

## Tests

Add coverage for at least:

- the exact two-group structured payload
- `remaining_fraction` conversion at `0`, `0.25`, `0.84`, and `1`
- clamping values below `0` and above `1`
- plain and fractional ISO-8601 reset timestamps
- unknown fields
- one malformed bucket alongside one valid bucket
- unsuccessful status, wrong command name, empty groups, invalid JSON, nonzero process exit, timeout, and missing executable
- direct argument invocation (no shell)
- Antigravity quota precedence over recent legacy files
- failed Antigravity read falling back to recent legacy data
- updated honest note when Antigravity is active but neither quota nor legacy usage is readable
- `UsageSnapshot` quota-group Codable round trip
- decoding an old cached snapshot with no `quotaGroups`
- dashboard rendering source/model tests as appropriate, including both independent reset dates
- privacy sentinel: raw response text, command descriptions, stderr, account identifiers, and unexpected JSON fields never enter a persisted snapshot

All existing 108 tests must remain green. No test may depend on a locally installed `agy`, live authentication, network access, or the developer's home directory.

## Acceptance criteria

- A real authenticated Antigravity installation displays both quota groups and reset dates in Takat.
- `0% remaining` displays as `100% used`; `84% remaining` displays as `16% used`.
- Refreshing Takat invokes no model turn and reports zero token use in the CLI contract.
- Failure is bounded by timeout and never freezes the UI.
- Legacy Gemini CLI behavior remains available as fallback.
- No OAuth credential, raw CLI payload, email address, prompt, or conversation content is read into the snapshot/cache.
- `swift build` and `swift test` pass.
- PR description includes the test count and a screenshot of the real two-group Gemini card.

## Delivery

Create a fresh feature worktree from `main`, implement there, and open a pull request. Do not work directly on `main`. Hand back to One for review; do not merge until the required `test` check is green and review conversations are resolved.
