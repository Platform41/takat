# Provider Data Sources — Research Dossier

**Persona:** Insider (domain research) → hand to One before step 4/5 architecture
**Date:** 2026-09-07
**Method:** direct inspection of `~/.codex/` and `~/.claude/` on the maintainer's machine
**Tool versions inspected:** `codex-cli 0.153.4`, `Claude Code 2.1.263`

> All findings are from one machine. Treat file shapes as "observed", not "guaranteed stable across versions". Both CLIs are pre-1.0 and change their on-disk formats without notice — every adapter must be defensive and version-tolerant.

---

## Summary

| Provider | Session % | Weekly % | Reset date | Plan name | Daily tokens | Auth needed |
|---|---|---|---|---|---|---|
| **Codex** | ✅ on disk | ✅ on disk | ✅ on disk | ✅ on disk | ✅ on disk | ❌ none (local files) |
| **Claude** | ❌ not persisted | ❌ not persisted | ❌ not persisted | ⚠️ indirect | ✅ derivable | ❌ for tokens / ⚠️ for % |

**Codex is the easy adapter and should be step 4.** Claude has no local record of subscription session/weekly usage — only per-message token counts. Ship the Claude adapter with token/chart data and leave the percentage bars `nil` (the model already treats them as optional).

---

## Codex CLI — `~/.codex/`

### Where usage lives

```
~/.codex/sessions/YYYY/MM/DD/rollout-<ISO8601>-<uuid>.jsonl
```

One file per Codex session, newline-delimited JSON events, date-partitioned directories.

### Relevant event shapes

Events with `"type":"token_count"` and `"type":"token_usage_record"` carry:

```json
{
  "info": {
    "total_token_usage": {
      "input_tokens": 47508941, "cached_input_tokens": 46157952,
      "cache_write_input_tokens": 0, "output_tokens": 177242,
      "reasoning_output_tokens": 50585, "total_tokens": 47686183
    },
    "last_token_usage": { "input_tokens": 23017, "output_tokens": 596, "total_tokens": 23613, "...": "..." },
    "model_context_window": 258400
  },
  "rate_limits": {
    "limit_id": "codex",
    "primary":   { "used_percent": 0.0,  "window_minutes": 300,   "resets_at": 1788690513 },
    "secondary": { "used_percent": 31.0, "window_minutes": 10080, "resets_at": 1788748053 },
    "credits": { "has_credits": false, "unlimited": false, "balance": "0" },
    "plan_type": "plus",
    "rate_limit_reached_type": null
  }
}
```

### Mapping to `UsageSnapshot`

| `UsageSnapshot` field | Source |
|---|---|
| `planName` | `rate_limits.plan_type` (`"plus"` → "Plus", title-cased) |
| `sessionPercent` | `rate_limits.primary.used_percent` (300 min ≈ 5 h window) |
| `weeklyPercent` | `rate_limits.secondary.used_percent` (10080 min = 7 d window) |
| `resetDate` | `Date(timeIntervalSince1970: rate_limits.primary.resets_at)` |
| `dailyTokenUsage` | aggregate `last_token_usage.total_tokens` by the event's day across recent session files (or `total_token_usage` deltas) |

### "Current" usage = newest event in the newest session file

1. Walk `~/.codex/sessions/`, find the most recently modified `rollout-*.jsonl`.
2. Read it; take the **last** event that contains a `rate_limits` block.
3. For the 7-day chart, scan session files whose date-path falls in the last 7 days and sum `last_token_usage.total_tokens` per calendar day.

### Trap doors

- `resets_at` is **epoch seconds**.
- A brand-new session's first `rate_limits` may be absent until the first model response — fall back to the previous file.
- `used_percent` is a float and can exceed 100 (over-quota) — the model's `min(_, 100)` clamp already handles the bar; keep the real number for the label.
- This machine's `~/.codex/` has non-standard extra files (`goals_1.sqlite`, `herdr-agent-state.sh`, `logs_2.sqlite`) from a customized setup. The adapter must touch **only** `sessions/` and ignore everything else.
- `history.jsonl` is prompt text + timestamp only — **no usage data**, and it contains private prompt content. Do not read it.
- Session files contain full conversation transcripts. Read only the `info` / `rate_limits` fields; never persist transcript text (CONTRIBUTING.md rule).

### Auth

None required — all data is local, world-readable-by-owner. `~/.codex/auth.json` (mode 600) holds OAuth tokens and is **out of scope** for the local-file adapter.

---

## Claude Code — `~/.claude/`

### What exists

| Path | Content | Usable? |
|---|---|---|
| `projects/<cwd-slug>/<session-uuid>.jsonl` | full transcripts; assistant messages carry `message.usage` | ✅ for tokens/cost |
| `stats-cache.json` | daily `messageCount`, `sessionCount`, `toolCallCount` — **not tokens**; recomputed lazily (observed `lastComputedDate` 2 months stale) | ⚠️ weak |
| `history.jsonl` | prompt text + cwd + timestamp | ❌ no usage |
| `total_tokens_reminder` events in transcripts | per-**agent-session** harness budget (e.g. cloud/CI runs), not subscription usage | ❌ misleading |

### `message.usage` shape (assistant messages)

```json
"usage": {
  "input_tokens": 2,
  "cache_creation_input_tokens": 36326,
  "cache_read_input_tokens": 0,
  "output_tokens": 206,
  "server_tool_use": { "web_search_requests": 0, "web_fetch_requests": 0 }
}
```

### What is NOT on disk anywhere

- Subscription **session %** (the 5-hour window shown by `/usage` in the TUI)
- **Weekly %**
- **Reset timestamp**
- Explicit **plan name** (Pro / Max 5x / Max 20x)

These are fetched live from Anthropic's server by the CLI and rendered in `/usage`; no local cache file for them was found.

### Options for the Claude adapter (step 5)

**Option A — local transcript parsing (recommended for first ship)**
- Parse `projects/**/*.jsonl`, sum `output_tokens + input_tokens + cache_creation_input_tokens` (decide cache-read handling) per calendar day → `dailyTokenUsage`.
- Optionally compute cost with a bundled model-price table (this is what community tool `ccusage` does).
- `planName` = "Claude" or read from config if a field appears; `sessionPercent` / `weeklyPercent` / `resetDate` = **`nil`** → bars hide automatically.
- Pros: no auth, no ToS risk, deterministic. Cons: no percentage bars.

**Option B — reverse-engineer the `/usage` endpoint**
- The CLI has OAuth credentials (macOS Keychain item `Claude Code-credentials`, or `~/.claude/.credentials.json` on some installs).
- Call the same internal endpoint the TUI uses to get session/weekly %.
- Pros: full parity with fixture. Cons: undocumented, unstable, Keychain access prompt, arguably against ToS. **Do not build this without an explicit product decision.**

### Trap doors

- Transcript `.jsonl` lines can be multi-MB (embedded images, tool output) — stream-parse line by line, never load whole files.
- Token accounting double-counts: `cache_read_input_tokens` is cheap/free — a naive sum overstates "usage". Define the metric explicitly.
- `projects/` slugs are `-`-escaped absolute paths; a project appears under multiple slugs (worktrees). Aggregate globally, not per-slug, for "my Claude usage".
- Transcripts hold highly sensitive content. Adapter reads `message.usage` only; ADR must state that no transcript text is read into memory beyond the JSON parse or written to Takat's cache.
- `stats-cache.json` staleness means it can't be the primary source.

### Auth

- Option A: none.
- Option B: Keychain read (`Claude Code-credentials`) — triggers a system authorization prompt; needs entitlements once Takat is a signed bundle.

---

## Recommended delivery impact

1. **Step 4 = Codex adapter**, local-file only. High confidence, ~1 day. Full `UsageSnapshot` parity with the fixture.
2. **Step 5 = Claude adapter, Option A** (token/chart only, percentages `nil`). Medium confidence.
3. **Defer Option B** to a later, explicitly-scoped milestone with a ToS/privacy review (Six).
4. Model already supports partial snapshots (`sessionPercent?`, etc.) — **no model change needed**. Dashboard should gracefully render a card that only has `planName` + `dailyTokenUsage`.
5. New research gap for One: confirm Codex `plan_type` value set (`plus`, `pro`, `team`, `enterprise`?) and whether `secondary` is always the weekly window.

---

## Open research gaps

- [ ] Does Codex ever write usage outside `sessions/` (e.g. a summary cache)? Not observed, not exhaustively checked.
- [ ] Claude Code config/keychain: exact credential location on this install (`.credentials.json` vs Keychain) — only needed if Option B is ever approved.
- [ ] Both: behaviour when the user is signed out / on a metered API key instead of a subscription.
- [ ] Confirm formats against a second machine / newer CLI build before locking the adapter contract.
