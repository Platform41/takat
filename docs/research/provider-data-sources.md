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

### Correction 2 (2026-09-07, later) — `/status` → Usage screenshot: **it's a local cache, not a server call**

The `/status` "Usage" tab shows Session 21% / Week 32% / reset times and states *"Approximate, based on local sessions on this machine."* That data is written to disk:

**`~/.claude.json` → `cachedUsageUtilization`** (the key literally says *cached*):

```jsonc
{
  "fetchedAtMs": 1788791249199,          // epoch ms — refreshed on ~every CLI interaction (observed 2 min old)
  "accountUuid": "871ccbac-…",           // matches oauthAccount.accountUuid
  "utilization": {
    "five_hour":  { "utilization": 21, "resets_at": "2026-09-07T15:39:59.661643+00:00", "locked_reason": null },
    "seven_day":  { "utilization": 32, "resets_at": "2026-09-07T21:59:59.661667+00:00", "locked_reason": null },
    "extra_usage": { "is_enabled": true, "used_credits": 0, "currency": "USD", … },
    "limits": [
      { "kind": "session",     "group": "session", "percent": 21, "severity": "normal", "resets_at": "…" },
      { "kind": "weekly_all",  "group": "weekly",  "percent": 32, "severity": "normal", "resets_at": "…" }
    ],
    "spend": { "used": { "amount_minor": 0, "currency": "USD" }, "percent": 0, … }
  }
}
```

**This changes the plan.** Claude Code fetches these numbers from the server and caches them here; Takat reads the cache — same file it already opens for `planName` (step 5.6). **No OAuth token, no Keychain, no network call, no ToS question.** Session/weekly/reset for Claude become a *local* enhancement, not the network milestone.

- `resets_at` is ISO8601 with **microseconds** and an explicit offset — `ISO8601DateFormatter(.withFractionalSeconds)` only does milliseconds, so truncate the fractional part before parsing (sub-second precision on a reset time is irrelevant).
- It's a cache: guard with `fetchedAtMs` and, more importantly, **`resets_at` in the past ⇒ the window rolled since the cache was written ⇒ that percentage is stale, treat as unknown (`nil`)**.
- Freshness for an active user is effectively live (refreshed every interaction). A dormant install goes stale → the past-`resets_at` check catches it.

### Correction 1 (2026-09-07, earlier) — Omarchy panel screenshot

Still valid: **plan name IS local** (`~/.claude.json` → `oauthAccount.organizationType`, shipped in PR #17). The Omarchy widget most likely also reads `cachedUsageUtilization` (or calls the server) — either way, Correction 2 gives Takat the same data locally.

### What is genuinely NOT on disk

- A *guaranteed-fresh* session/weekly figure independent of Claude Code having run recently. The cache is as fresh as the last CLI interaction. For Takat's purpose (a glanceable menu-bar dashboard) that is fine.
- Per-model or per-day server-side breakdown beyond what `cachedUsageUtilization` and the transcripts already give.

### Options for the Claude adapter

**Option A — local transcript parsing** — ✅ shipped (PR #11): `dailyTokenUsage` from `projects/**/*.jsonl`.

**Option A+ — plan name from `~/.claude.json`** — ✅ shipped (PR #17).

**Option A++ — session/weekly/reset from `cachedUsageUtilization`** — **new, recommended next.** Local, no auth, no Keychain, no ToS review. Full parity with the Codex card. Removes the "limits aren't reported by Claude" caption. → spec: `docs/reviews/step-5.8-claude-local-usage-handoff.md`.

**Option B — the `/usage` server endpoint** — **now unnecessary.** Only value over A++ is fresher numbers for a rarely-used install; not worth the Keychain read, settings toggle, and ToS review. **Dropped from the roadmap** unless a concrete need appears.

### Trap doors

- Transcript `.jsonl` lines can be multi-MB (embedded images, tool output) — stream-parse line by line, never load whole files.
- Token accounting double-counts: `cache_read_input_tokens` is cheap/free — a naive sum overstates "usage". Define the metric explicitly.
- `projects/` slugs are `-`-escaped absolute paths; a project appears under multiple slugs (worktrees). Aggregate globally, not per-slug, for "my Claude usage".
- Transcripts hold highly sensitive content. Adapter reads `message.usage` only; ADR must state that no transcript text is read into memory beyond the JSON parse or written to Takat's cache.
- `stats-cache.json` staleness means it can't be the primary source.

### Auth

- Options A / A+ / A++: **none** — all local file reads.
- Option B (dropped): Keychain read + entitlements.

---

## Gemini CLI — `~/.gemini/`

### Correction (2026-09-09) — Antigravity's local *files* record no usage

The maintainer moved from the legacy Gemini CLI to **Google Antigravity** (`~/.gemini/antigravity-cli/`). Its on-disk storage is a **conversation store only** — `brain/<id>/.system_generated/logs/transcript*.jsonl`, `conversations/<id>.db` (protobuf blobs), `history.jsonl`, `conversation_summaries.db` — **none carry token counts**. No quota cache on disk either.

PR #39 shipped a "not measurable" notice for this case.

### Correction 2 (2026-09-10) — Antigravity `/usage` slash command *does* expose quota

`agy` has a **local** `/usage` slash command that returns structured quota data without a model turn:

```sh
agy --print "/usage" --output-format json --print-timeout 30s
```

Returns `status: "SUCCESS"`, zero token counters, and `command.data.groups` — two independent **weekly** quota pools:

| group | bucket id | `remaining_fraction` → `usedPercent` | `reset_time` |
|---|---|---|---|
| Gemini Models | `gemini-weekly` | `0.84` → 16% | ISO-8601 (plain or fractional) |
| Claude and GPT models | `3p-weekly` | `0.25` → 75% | ISO-8601 |

So Antigravity usage **is** trackable — via the CLI, not files. The Gemini adapter now:

1. If `~/.gemini/antigravity-cli/` exists and `agy` resolves (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`), runs `/usage` off the main actor (`AntigravityUsageReader`, `Process` — no shell, no OAuth files, bounded ~45 s), decodes `command.data`, and returns a snapshot with `planName: "Antigravity"` + `quotaGroups` (new provider-neutral `UsageQuotaGroup` / `UsageQuotaWindow` on `UsageSnapshot`). Live quota **wins over legacy chat files.**
2. If the CLI can't be read, falls back to the legacy Gemini CLI token chart.
3. If neither yields data but Antigravity is active, a concise "*Antigravity usage couldn't be read right now.*" note.

Privacy: the decoder models only `status`, `command.name/data`, group `name`, and bucket `id/window/remaining_fraction/reset_time` — never the free-form `response` / `description` strings or `stderr`. (`feat/three-antigravity-usage`, supersedes PR #39's notice-only approach.)

### Where usage lives (legacy Gemini CLI)

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

API key, stored in the **macOS Keychain**. Needs the signed-bundle entitlement work (step 6) and a settings UI to paste the key. DeepSeek is now the **only** provider in the "network adapters" milestone — Claude no longer belongs there (see Correction 2).

---

## Recommended delivery impact

1. **Step 4 = Codex adapter.** ✅ shipped (PR #6/#8).
2. **Step 5 = Claude adapter, Option A** (token chart, percentages `nil`). ✅ shipped (PR #11).
3. **Step 5.5 = Gemini CLI adapter.** ✅ shipped (PR #13). Antigravity `/usage` quota groups via the `agy` CLI — `feat/three-antigravity-usage` (see Correction 2, 2026-09-10). PR #39's notice is the fallback when the CLI can't be read.
4. **Step 5.6 = Claude plan name** (`~/.claude.json` → `organizationType`). ✅ shipped (PR #17).
5. **Step 5.8 (new) = Claude session/weekly/reset from `cachedUsageUtilization`** — local, no auth. Full parity with the Codex card. → `docs/reviews/step-5.8-claude-local-usage-handoff.md`.
6. **"Network adapters" milestone (after step 6 signing)** = **DeepSeek balance only** (Claude Option B dropped — Correction 2). Needs Keychain + a settings UI + the `balance` model field. Optionally a Six ToS check for the DeepSeek API key handling.
7. **`ProviderID` scaling:** fine as an `enum` while providers are hardcoded. If providers become user-toggleable, refactor to a string id + self-describing `UsageProvider` and iterate a registry.
8. Model already supports partial snapshots — **no model change** for Codex/Claude/Gemini. Only DeepSeek forces a `balance` field.

---

## Open research gaps

- [ ] Does Codex ever write usage outside `sessions/` (e.g. a summary cache)? Not observed, not exhaustively checked.
- [x] Claude session/weekly — **found locally** in `~/.claude.json` → `cachedUsageUtilization` (Correction 2). Option B / Keychain no longer needed.
- [ ] `cachedUsageUtilization` on a fresh install / a user who never ran `/status` — is the key absent, or present-but-empty? Adapter must handle both → `nil` percentages.
- [ ] All CLIs: behaviour when the user is signed out / on a metered API key instead of a subscription.
- [ ] Confirm formats against a second machine / newer CLI build before locking each adapter contract.
- [ ] Gemini CLI: does a paid Code Assist / Vertex tier write rate-limit or quota data anywhere? Only `oauth-personal` (free) was observed.
- [ ] Gemini CLI: confirm `tokens.total == input + output + thoughts` holds across model families (checked only `gemini-3-flash-preview`).
- [x] DeepSeek: is there any per-day spend endpoint? **No** — confirmed against api-docs.deepseek.com (2026-09-07). `/user/balance` (point-in-time) is the only signal; rate limits are concurrency-only. Balance-delta snapshotting is the only path to a chart.
- [ ] DeepSeek: does the account here even have API credits, or is it web-chat only? (No local footprint to confirm usage.)
