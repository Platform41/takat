# Step 5.9 — Antigravity (agy) Gemini Usage Adapter: Handoff to Claude

**Spec owner:** One
**Implementer:** Claude (Three)
**Branch:** `feat/antigravity-gemini-adapter` off `main`
**Target repository:** `takat` (`/Users/nurulazrad/Projects/ningenai/takat`)
**Issue context:** User transitioned from legacy Gemini CLI to Google Antigravity (`agy`). Takat's Gemini stats stopped updating and show 0 tokens because Takat was inspecting legacy `~/.gemini/tmp` chat files (dormant since June 2026 and filtered out by the 7-day cutoff).

---

## 1. Problem Statement & Root Cause

In `GeminiUsageProvider.swift`:
```swift
public static var defaultChatsRoot: URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".gemini", isDirectory: true)
        .appendingPathComponent("tmp", isDirectory: true)
}
```

### Why it stopped working:
1. **Wrong Directory:** Antigravity (`agy` CLI & IDE) stores its runtime data in `~/.gemini/antigravity-cli/`, not `~/.gemini/tmp/`.
2. **Changed Storage Architecture:**
   - **Legacy Gemini CLI:** Stored individual chat JSON objects under `~/.gemini/tmp/<hash>/chats/session-*.json` matching `GeminiSession` (`{"messages": [{"type": "gemini", "tokens": ...}]}`).
   - **Antigravity (`agy`):** Stores sessions in:
     - SQLite databases: `~/.gemini/antigravity-cli/conversations/<uuid>.db`
     - Step logs & transcripts: `~/.gemini/antigravity-cli/brain/<uuid>/.system_generated/logs/transcript.jsonl`
     - Global command history: `~/.gemini/antigravity-cli/history.jsonl`
3. **7-Day Rolling Cutoff Filter:**
   Takat ignores files older than 7 days. Because files in `~/.gemini/tmp` were last modified in June 2026, Takat skips all of them and reports 0 tokens.

---

## 2. Technical Objective

Update `GeminiUsageProvider.swift` and `GeminiSessionParser.swift` (or introduce an `AntigravitySessionParser`) so that Takat accurately tracks active Gemini usage from Antigravity sessions while preserving backwards-compatibility if legacy session files are present.

---

## 3. Data Inspection & Antigravity Structure

### A. Directory Paths
- Root: `~/.gemini/antigravity-cli`
- History: `~/.gemini/antigravity-cli/history.jsonl`
  - Each line is a JSON object:
    ```json
    {
      "display": "read ./41-foundation-os",
      "timestamp": 1788884848425,
      "workspace": "/Users/nurulazrad/Projects/ningenai",
      "conversationId": "98d51e42-6976-459b-bce6-37e4870bf648"
    }
    ```
- Transcripts: `~/.gemini/antigravity-cli/brain/<conversationId>/.system_generated/logs/transcript.jsonl`
  - Each line represents a step in the conversation:
    - `step_index` (Int)
    - `source` ("USER_EXPLICIT" | "MODEL" | "SYSTEM")
    - `type` ("USER_INPUT" | "PLANNER_RESPONSE" | "GENERIC")
    - `created_at` (ISO8601 string, e.g. "2026-09-08T16:27:28Z")
    - `content` / `tool_calls`
- SQLite Conversation Store: `~/.gemini/antigravity-cli/conversations/<conversationId>.db`
  - Tables: `gen_metadata`, `steps`, `trajectory_meta`.
  - `gen_metadata` contains serialized protobuf payloads recording the model (e.g. `gemini-3.8-flash`), request IDs, timestamps, and model invocation metadata.

### B. Usage Extraction Strategy

1. **Primary Source — `brain/<uuid>/.system_generated/logs/` or `history.jsonl`:**
   - Detect active conversations within the last 7 days by inspecting mtime of files in `~/.gemini/antigravity-cli/conversations/` or `~/.gemini/antigravity-cli/brain/`.
   - If token counts are directly recorded in telemetry/chunks or database steps, extract input/output/cached/thought tokens.
   - If token counts are not explicitly logged in plain text in `transcript.jsonl`, extract tokens from the session metadata in `conversations/<uuid>.db` or estimate per step based on prompt/completion characters if telemetry is masked.
2. **Fallback / Legacy Source:**
   - If `~/.gemini/antigravity-cli` does not exist or has no sessions in the window, fallback to checking `~/.gemini/tmp/` for legacy Gemini CLI sessions.

---

## 4. Scope of Changes

1. **`Sources/Takat/Core/Providers/GeminiUsageProvider.swift`**
   - Update default search path to prioritize `~/.gemini/antigravity-cli` and fall back to `~/.gemini/tmp`.
   - Update file enumeration to discover `transcript.jsonl` and/or `conversations/*.db`.
   - Ensure Entitlements (`App/Takat.entitlements`) continues to permit access to `~/.gemini`.

2. **`Sources/Takat/Core/Providers/GeminiSessionParser.swift`**
   - Add parser logic for Antigravity JSONL / SQLite session formats.
   - Map extracted usage into `[(Date, Int)]` deltas.

3. **`Tests/TakatTests/GeminiUsageProviderTests.swift`**
   - Add unit test fixtures for Antigravity directory structure and transcripts.
   - Verify 7-day daily bucketing works as expected.

---

## 5. Verification Checklist

- [ ] `swift test` passes cleanly.
- [ ] `./scripts/build-app.sh` builds without errors.
- [ ] Running the app (`dist/Takat.app`) reflects real Gemini tokens for recent queries run in Antigravity today.
- [ ] Backwards-compatibility: Does not crash if only legacy `tmp/` exists.
