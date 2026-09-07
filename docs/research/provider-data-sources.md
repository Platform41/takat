# Provider Data Sources — Research Dossier

**Persona:** Insider (domain research) → hand to One before adapter architecture
**Date:** 2026-09-07 (Codex + Claude); 2026-09-07 addendum (Gemini + DeepSeek)
**Method:** direct inspection of `~/.codex/`, `~/.claude/`, `~/.gemini/` on the maintainer's machine; DeepSeek from public API docs (no local footprint)
**Tool versions inspected:** `codex-cli 0.153.4`, `Claude Code 2.1.263`, Gemini CLI (oauth-personal auth, `sessionRetention 30d`)

> All findings are from one machine. Treat file shapes as "observed", not "guaranteed stable across versions". These CLIs are pre-1.0 and change their on-disk formats without notice — every adapter must be defensive and version-tolerant.

---

## Summary

| Provider | Session % | Weekly % | Reset date | Plan name | Daily tokens | Balance | Auth needed |
|---|---|---|---|---|---|---|---|
| **Codex** | ✅ on disk | ✅ on disk | ✅ on disk | ✅ on disk | ✅ on disk | — | ❌ none (local files) |
| **Claude** | ❌ not persisted | ❌ not persisted | ❌ not persisted | ⚠️ indirect | ✅ derivable | — | ❌ for tokens / ⚠️ for % |
| **Gemini CLI** | ❌ not persisted | ❌ not persisted | ❌ not persisted | ⚠️ model id only | ✅ derivable | — | ❌ none (local files) |
| **DeepSeek** | ❌ n/a | ❌ n/a | ❌ n/a | ❌ pay-as-you-go | ⚠️ only if you log API calls yourself | ✅ via API | ⚠️ API key (Keychain) |

**Adapter difficulty order:** Codex (done) → **Claude** (local, tokens only) → **Gemini CLI** (local, tokens only — near-copy of Claude) → **DeepSeek** (network + Keychain, dollar balance not %, bundle with the deferred Claude `/usage` milestone).

Consumer subscriptions with no CLI — Gemini Advanced / Google One AI, ChatGPT Plus web, Claude.ai web — expose **no usage API and no local logs**. Nothing to build for those.

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
| `~/.claude.json` → `oauthAccount` | `organizationType` (`"claude_pro"`, `"claude_max"`, …), `emailAddress`, `organizationUuid`, `billingType`, `hasExtraUsageEnabled` | ✅ **plan name is local after all** — see correction below |
| Keychain item `Claude Code-credentials` | `{ "claudeAiOauth": { "accessToken": "sk-ant-oat01-…", "refreshToken", "expiresAt", … } }` | ✅ OAuth token for the `/usage` server endpoint (Option B) |

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

These are fetched live from Anthropic's server by the CLI and rendered in `/usage`; no local cache file for them was found.

### Correction (2026-09-07) — prompted by an Omarchy panel screenshot

An Omarchy widget renders Claude Code **Session %, Weekly %, "Resets in Xh Ym", plan ("PRO"), tokens-by-day and tokens-by-model** — i.e. everything the fixture had. Re-investigation:

1. **Plan name IS local.** `~/.claude.json` → `oauthAccount.organizationType` = `"claude_pro"` on this machine (→ "Pro"). Earlier scan only checked `~/.claude/settings.json` and `stats-cache.json` and missed `~/.claude.json`. **`planName` no longer needs to be a hardcoded `"Claude"`.**
2. **Session/weekly % + resets are Option B, and Option B demonstrably works.** Omarchy calls the same server endpoint the in-session `/usage` command hits, authorised with the OAuth `accessToken` from the Keychain item `Claude Code-credentials`. There is no `claude usage` CLI subcommand and nothing on disk — the network call is the only route, but it is a proven one, not speculative.
3. Exact endpoint + request headers still need confirming — read it out of Omarchy's widget script (`omarchy` repo) or capture what `/usage` sends. Token is an `sk-ant-oat01-…` bearer; the CLI uses an `anthropic-beta` OAuth header.

### Options for the Claude adapter (step 5)

**Option A — local transcript parsing** — ✅ **shipped in PR #11.**
- Parses `projects/**/*.jsonl`, `newTokens = input + cache_creation + output` per calendar day → `dailyTokenUsage`.
- `planName = "Claude"` (hardcoded), `sessionPercent` / `weeklyPercent` / `resetDate` = `nil`.
- No auth, no ToS risk, deterministic. No percentage bars.

**Option A+ — local, plus plan name from `~/.claude.json`** — small follow-up, low risk.
- Read `oauthAccount.organizationType` → map (`claude_pro`→"Pro", `claude_max`→"Max", else title-case / "Claude").
- Still no bars. No network, no Keychain. **Recommended next Claude change.**

**Option B — the `/usage` server endpoint** — feasible (Omarchy prior art), scoped milestone not "never".
- OAuth `accessToken` from Keychain `Claude Code-credentials` → GET the endpoint behind `/usage` → session %, weekly %, reset timestamps.
- Needs: exact endpoint confirmed; Keychain read (system prompt unless the signed bundle is entitled — step 6); a settings toggle so the user opts in; **Six's ToS/privacy review** (undocumented endpoint, token handling).
- Bundle with the **"network adapters" milestone** (DeepSeek balance, same infrastructure).

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

## Gemini CLI — `~/.gemini/`

### Where usage lives

```
~/.gemini/tmp/<project-hash>/chats/session-<ISO8601>.json
```

One JSON file per chat session (not JSONL — a single object). `sessionRetention` defaults to **30 days**, then the CLI prunes — fine for a 7-day chart.

- `tmp/` also holds `logs.json` (flat prompt log, **no tokens** — ignore, like Codex's `history.jsonl`) and unrelated `antigravity-*` dirs. Touch only `tmp/*/chats/session-*.json`.
- Directory names under `tmp/` are a mix of sha-hashes and plain slugs — just glob, don't try to resolve them. `~/.gemini/projects.json` maps real paths → slug names but isn't needed.

### Session file shape

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

- `total == input + output + thoughts` (verified). `cached` is a **subset of `input`** (cheap context re-reads).
- `thoughts` is **separate from `output`** here (Gemini bills reasoning separately) — so it must be added, not treated as a subset.
- `type: "user"` messages carry a zeroed `tokens` block — skip them; only `type: "gemini"` matters.

### Mapping to `UsageSnapshot`

| Field | Source |
|---|---|
| `provider` | `.gemini` (new `ProviderID` case) |
| `planName` | no plan string anywhere → `"Gemini"` fixed. `model` per message (`gemini-3-flash-preview`, …) is the only identifier; could show the most-used model as a subtitle later. |
| `sessionPercent` / `weeklyPercent` / `resetDate` | `nil` — not persisted. Auth here is `oauth-personal` (Code Assist free tier); request/day limits are enforced server-side and not written to these files. |
| `dailyTokenUsage` | per-day sum of **`newTokens`**, bucketed by each `gemini` message's `timestamp` into `Calendar.current` days, 7 zero-filled entries |

```swift
// new work, excluding cached re-reads — consistent with the Codex/Claude metric
newTokens = max(0, tokens.input - tokens.cached) + tokens.output + tokens.thoughts
```

### Trap doors

- Whole-file JSON (not JSONL) — but files stay small (one chat). Still, cap defensively.
- `thoughts` also appears as a top-level **array of reasoning summaries** on each message (`thoughts: [{subject, description, …}]`) — sensitive content. The token count is `tokens.thoughts` (an Int); do **not** confuse it with the array, and do not read the array.
- Same privacy rule as Claude: model only `type`, `timestamp`, `model`, and the `tokens` integers. Never touch `content` / `thoughts[]`.
- Sessions older than 30 days are gone — a "last 7 days" chart is always fully covered, but historical/monthly views are impossible.

### Auth

None — local files, `oauth-personal` login already done by the CLI.

---

## DeepSeek — no local footprint

Checked: no `~/.deepseek`, no `~/.config/deepseek`, no first-party CLI on this machine. DeepSeek is **pay-as-you-go API credit**, not a subscription with a session/weekly quota. "My DeepSeek subscription" = a prepaid dollar balance.

### What's available — confirmed against api-docs.deepseek.com (2026-09-07)

| Source | Data | Notes |
|---|---|---|
| `GET https://api.deepseek.com/user/balance` | `{ is_available: Bool, balance_infos: [{ currency: "CNY"｜"USD", total_balance, granted_balance, topped_up_balance }] }` (balances are **strings**) | Auth: `Authorization: Bearer <API_KEY>`. **Point-in-time only** — no time window, no history, no expiry breakdown. The only first-party signal. |
| Chat completions response `usage` | `{ prompt_tokens, completion_tokens, total_tokens, prompt_cache_hit_tokens, prompt_cache_miss_tokens }` | Per-call only — no server-side history endpoint. Useless to Takat (it doesn't proxy the calls). |
| Rate limits | **concurrency caps only** (e.g. 500 concurrent for the pro model), surfaced as HTTP 429 | Docs explicitly state: no headers for remaining quota or reset, no usage endpoint, no weekly/session quota. |
| platform.deepseek.com/usage | spend graphs, request counts | Web dashboard, **no documented API behind it**. |
| Third-party tools (aider / cline / …) using a DeepSeek key | that tool's own local logs | Tool-specific; out of scope. |

### Verdict: **session / weekly / reset bars are impossible for DeepSeek** — not deferred, not-going-to-happen

DeepSeek's pay-as-you-go model has no subscription quota, so there is nothing for those bars to show. The API confirms it: balance snapshot + `is_available`, nothing else.

### Mapping to `UsageSnapshot`

A DeepSeek card can show:
- **"$X.XX remaining"** from `balance_infos` (prefer the `USD` entry; `total_balance`).
- a **status** from `is_available` ("OK" / "Low — top up").
- optionally a **spend sparkline** Takat builds itself: persist the daily balance reading, chart `previous − current` per day. Caveats: only works after Takat has run for several days; a top-up makes the delta negative → clamp to 0 and/or annotate; not a token count.

`sessionPercent` / `weeklyPercent` / `resetDate` / `dailyTokenUsage` all stay `nil`/empty.

**Model change required** (only when this adapter is scheduled):
- optional `balanceRemaining: Decimal?` + `balanceCurrency: String?` on `UsageSnapshot` (or a small `Balance` type).
- the card layout needs a "balance" treatment distinct from the percent-bars layout — a Two task.

### Auth

API key, stored in the **macOS Keychain** — same infrastructure as the deferred Claude `/usage` route. Needs the signed-bundle entitlement work (step 6) and a settings UI to paste the key. **Bundle DeepSeek with the "network adapters" milestone, after step 5.**

---

## Recommended delivery impact

1. **Step 4 = Codex adapter**, local-file only. ✅ shipped (PR #6/#8).
2. **Step 5 = Claude adapter, Option A** (token/chart only, percentages `nil`). ✅ shipped (PR #11).
3. **Step 5.5 = Gemini CLI adapter** — near-copy of Claude. ✅ shipped (PR #13).
4. **Step 5.6 (new) = Claude Option A+** — read `planName` from `~/.claude.json`. Tiny, local, no auth. Do this soon; it also matters for the Codex card consistency (all cards should show a real plan).
5. **"Network adapters" milestone (after step 6 signing)** = Claude Option B (`/usage` endpoint → session/weekly/reset bars — **feasible, Omarchy prior art**) **+ DeepSeek balance**. Both need Keychain + a settings UI for credentials + a ToS/privacy review (Six). This is where `UsageSnapshot` gains an optional `balance` concept and where the Claude card finally gets its bars.
5. **`ProviderID` scaling:** fine as an `enum` while providers are hardcoded (add a case + a `ProviderStyle` entry each). If providers ever become user-toggleable, refactor to a string id + self-describing `UsageProvider` (`displayName`/`symbolName`/`accentColor` on the provider) so the dashboard iterates a registry instead of `.allCases`.
6. **UX:** 3+ stacked cards in the 360 pt menu panel will scroll — hand Two a compact/collapsible card mode before the Gemini adapter merges.
7. Model already supports partial snapshots (`sessionPercent?`, etc.) — **no model change** for Codex/Claude/Gemini. Only DeepSeek forces a `balance` field.

---

## Open research gaps

- [ ] Does Codex ever write usage outside `sessions/` (e.g. a summary cache)? Not observed, not exhaustively checked.
- [ ] Claude Code config/keychain: exact credential location on this install (`.credentials.json` vs Keychain) — only needed if Option B is ever approved.
- [ ] All CLIs: behaviour when the user is signed out / on a metered API key instead of a subscription.
- [ ] Confirm formats against a second machine / newer CLI build before locking each adapter contract.
- [ ] Gemini CLI: does a paid Code Assist / Vertex tier write rate-limit or quota data anywhere? Only `oauth-personal` (free) was observed.
- [ ] Gemini CLI: confirm `tokens.total == input + output + thoughts` holds across model families (checked only `gemini-3-flash-preview`).
- [x] DeepSeek: is there any per-day spend endpoint? **No** — confirmed against api-docs.deepseek.com (2026-09-07). `/user/balance` (point-in-time) is the only signal; rate limits are concurrency-only. Balance-delta snapshotting is the only path to a chart.
- [ ] DeepSeek: does the account here even have API credits, or is it web-chat only? (No local footprint to confirm usage.)
