# Dashboard polish (post-switcher): Handoff to DeepSeek

**Owner:** Two (visual) — commissioned by One
**Implementer:** DeepSeek (Three)
**Branch:** `feat/dashboard-polish` off `main` → PR (expected #21)
**Depends on:** PR #20 merged (`351ae0f`)
**Type:** three small visual fixes surfaced by the switcher screenshots. No data-layer changes.

## 1. All-zero chart → caption instead of flat dashes

`DailyUsageChart` in `DashboardView.swift`. When **every** bucket is `0` (a provider with no usage in the 7-day window — e.g. Gemini on a machine that hasn't used the CLI recently), the current bar row renders 7 identical 4 pt stubs and reads as broken.

- When `usage.allSatisfy { $0.tokenCount == 0 }` (or `usage.isEmpty`), replace the bar `HStack` with:
  ```swift
  Text("No usage in the last 7 days")
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
  ```
- Keep the existing `.accessibilityLabel("Daily token usage")` on the container, or set it to "No usage in the last 7 days" for that state.
- Normal (some non-zero) case unchanged.

## 2. Segment hover state

`providerSwitcher` in `DashboardView.swift`. The custom segment buttons have no hover feedback — in a menu-bar panel that hurts discoverability.

- Add `@State private var hoveredProvider: ProviderID?` and `.onHover { hoveredProvider = $0 ? provider : nil }` per segment.
- Background priority: selected → `provider.accentColor.opacity(0.18)` (see #3); else hovered → `Color.primary.opacity(0.06)`; else clear.
- No animation needed beyond SwiftUI's implicit; a `.animation(.easeOut(duration: 0.1), value: hoveredProvider)` on the row is fine if it reads well.

## 3. Selected segment uses the provider's own accent

Currently the selected segment tints with the **system** accent (`Color.accentColor.opacity(0.18)`). Switch to the **provider's** accent so the selected Claude segment is orange-tinted, Codex teal, Gemini blue — consistent with the card header and chart, and a stronger "you are here" signal.

- `isSelected ? provider.accentColor.opacity(0.18) : …`
- Keep the foreground `isSelected ? .primary : .secondary`.
- If the tint on `.blue`/`.teal` at 0.18 looks too weak or too strong against the panel, nudge the opacity — Two-judgement, land what reads best.

## Out of scope

- Provider **brand icons** — separate decision pending (One is putting the options to the maintainer; may become its own handoff).
- Any `ProviderCardView` / bars / data changes.
- The switcher's structure, selection logic, or `ProviderSwitcher` helper.

## Tests

Almost entirely visual. Add one pure-logic test if you extract an `allZero(_:)` helper for the chart (`[] → true`, `[0,0,0] → true`, `[0,5,0] → false`). Otherwise no new tests — keep the 71 green.

`swift build && swift test` locally before every push (CI paused — state the result in the PR). `Package.swift` dependency-free. No version bump.

## Handoff back

Push, open the PR, **desktop screenshots**: the all-zero chart caption (switch to Gemini), a segment mid-hover, and the three selected states showing their provider colours. One re-reviews; Two reviews the visual.
