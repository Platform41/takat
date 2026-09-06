# PR #2 — Review Handoff to DeepSeek

**Branch:** `feat/fixture-usage-dashboard` (work in place — same branch, no new branch/worktree)
**PR:** #2 `feat: fixture-backed usage dashboard`
**Reviewer:** One (architecture / release gate)
**Implementer:** DeepSeek (Three lane — implementation only)
**Milestone:** delivery-order steps 1–2 (fixture dashboard + menu bar / settings shell)

## Verified baseline

- `swift build` — passes
- `swift test` — 6 passing, 0 failures
- Scope matches milestone; no secrets, no migrations, no deployment surface.

## Rules for this handoff

- Commit onto `feat/fixture-usage-dashboard`; push updates the existing PR.
- No version bump, no git tag — One owns that after merge.
- Do not start delivery-order step 3+ (persistence, Codex/Claude adapters). Out of scope.
- Keep commits small and focused; conventional-commit messages.
- Run `swift build` + `swift test` before every push.

---

## Must fix (blockers for "menu bar shell done")

### 1. `MenuBarExtra` window style
- **File:** `Sources/Takat/App/TakatApp.swift:15-20`
- **Problem:** `DashboardView` uses interactive controls (refresh `Button`, `ProgressView`) and a custom `VStack` layout with `.frame(width: 360)`. Default `MenuBarExtra` `.menu` style renders these as broken/disabled menu items.
- **Fix:** Add `.menuBarExtraStyle(.window)` to the `MenuBarExtra` scene.
- **Done when:** dashboard opens as a panel with a working refresh button and visible bars/chart; verify in a real run (menu bar click), not just build.

### 2. Concurrent provider refresh
- **File:** `Sources/Takat/Core/UsageStore.swift:27-33`
- **Problem:** `for provider in providers { ... await provider.fetchUsage() }` runs serially — refresh time is the sum of provider latencies, not the max.
- **Fix:** Fan out with `withThrowingTaskGroup` / `async let`, collect results, then assign `snapshots` / `errors` on the main actor. Preserve current behavior: one failing provider must not abort the others; `isRefreshing` guard and `defer { isRefreshing = false }` stay.
- **Done when:** new test (see Test tasks) asserts total refresh ≈ one provider's duration, not N.

---

## Should fix

### 3. Stale snapshot on partial failure
- **File:** `Sources/Takat/Core/UsageStore.swift:21-34`, `Sources/Takat/Features/Settings/SettingsView.swift:42-53`
- **Problem:** `refresh()` clears `errors` but keeps a prior `snapshots[id]` when the new fetch fails, so `statusText` still shows "Connected" for a provider that just errored.
- **Decision (One):** keep-last-good data, but status must reflect the error. When `errors[id] != nil`, `statusText` shows "Unavailable" even if a stale snapshot exists — reorder the checks so the error branch wins.

### 4. Accessibility on `UsageBar`
- **File:** `Sources/Takat/Features/Dashboard/DashboardView.swift:100-118`
- **Fix:** Give the bar an `.accessibilityElement(children: .ignore)` with `.accessibilityLabel(title)` and `.accessibilityValue` of the percent string (or "No data" when `nil`).

### 5. Over-quota percent clamp
- **File:** `Sources/Takat/Features/Dashboard/DashboardView.swift:115`
- **Fix:** `ProgressView(value: min(percent ?? 0, 100), total: 100)`. Keep the exact number in the trailing `Text` unclamped (it may legitimately read >100%).

---

## Nits (fix if touching the file)

### 6. Fixture pattern-to-day mapping
- **File:** `Sources/Takat/Core/Providers/FixtureUsageProvider.swift:48-51`
- `tokenPattern[0]` currently maps to *today*, `[6]` to 7 days ago. Reverse the index so the array reads oldest-first: `tokenCount: tokenPattern[(tokenPattern.count - 1 - offset) % tokenPattern.count]` (or restructure the loop). Output stays deterministic and chronologically ordered — existing tests must still pass.

### 7. README structure drift
- **File:** `README.md` (Structure section)
- Lists `Sources/Takat/Core/UsageStore` as a directory; it's `UsageStore.swift`. Correct the line.

---

## Test tasks

- `Tests/TakatTests/UsageStoreTests.swift`
  - Concurrency: two providers each sleeping ~200ms → assert `refresh()` completes in < ~350ms (well under the 400ms serial sum).
  - `isRefreshing` guard: a second `refresh()` call while one is in flight is a no-op (no duplicate fetches).
  - Partial failure keeps the good provider's snapshot AND records the failing provider's error.
- Keep all existing tests green. Do not weaken the fixture-stability assertions.

## Out of scope — do not touch

- `Core/Storage` (Keychain / cache) — step 3.
- Codex adapter — step 4.
- Claude adapter — step 5.
- Packaging / signing / release — step 6.

## Handoff back to One

When done: push to `feat/fixture-usage-dashboard`, update the PR description test-evidence section, and note in a PR comment which items (1–7) are addressed and which are deferred with reasons.
