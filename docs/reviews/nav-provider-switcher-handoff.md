# UX — Provider Switcher (replace the stacked scroll): Handoff to DeepSeek

**Design owner:** Two (interaction) — commissioned by One
**Implementer:** DeepSeek (Three)
**Branch:** `feat/provider-switcher` off `main` → PR (expected #19)
**Depends on:** PR #17 merged (`c3403cf`)
**Trigger:** with three provider cards the menu-bar panel scrolls and the `ScrollView` over-reserves height. Maintainer wants a tab/segmented navigation instead.

## Decision

**A segmented switcher at the top of the panel; one provider card shown at a time, at full detail.** This is the `progressive_disclosure` principle applied — the panel answers "how's my usage?" for the provider you care about right now, the others one click away. It stays a fixed compact height, scales to ~5 providers before needing a "more" affordance, and is a native macOS control.

Rejected: keeping the scroll (the current problem); compact always-visible rows (more to build, and the per-provider detail — bars, reset, 7-day chart — doesn't compress well).

## Layout

```
┌────────────────────────────────────────────┐   width 360 (unchanged)
│  Takat                    ↻   Updated 2m ago│   ← header: title, refresh, global freshness
│                                            │
│  ┌──────────┬──────────┬──────────┐        │   ← segmented switcher (SwiftUI Picker .segmented)
│  │ ✦ Claude │ ⌥ Codex ●│ ◆ Gemini │        │      icon + name per segment; ● = that provider errored
│  └──────────┴──────────┴──────────┘        │
│                                            │
│  ┌────────────────────────────────────┐    │   ← the selected provider's card (existing ProviderCardView,
│  │ ✦ Claude                      Pro  │    │      unchanged content: plan pill, freshness row,
│  │ Updated 2m ago                     │    │      Session/Weekly bars OR the "limits aren't reported"
│  │ Session & weekly limits aren't …   │    │      caption, Resets line, 7-day chart)
│  │ ▁▃▂▅▁▂█  M T W T F S S              │    │
│  └────────────────────────────────────┘    │
└────────────────────────────────────────────┘
```

## Behaviour

### Which segments appear
- One segment per provider that **has a snapshot** (`store.snapshot(for:) != nil`), in the fixed order **Claude, Codex, Gemini** (define `ProviderID.displayOrder`).
- Providers with no snapshot — "not configured", or a hard error with nothing cached — get **no segment**. They remain visible in **Settings** (`SettingsView` unchanged: it stays the "everything at once" view). Don't send the user to a blank card.
- **0 snapshots** → no switcher; show the existing `emptyState` / loading spinner.
- **1 snapshot** → no switcher (a 1-segment control is noise); show that card directly.
- **2–3 snapshots** → switcher + selected card.

### Selection
- `@AppStorage("takat.selectedProvider")` holds the last choice (store the `rawValue`). Wrap reads in the usual defensive pattern.
- On open: if the stored provider still has a snapshot, select it; else select the first in `displayOrder` that does.
- If the selected provider loses its snapshot while the panel is open (e.g. a refresh clears it), fall back to the first available; never leave a dead selection.

### Per-segment error dot
- If `store.errors[id] != nil` **and** that provider still has a (stale) snapshot, show a small `●` in `.orange` trailing the segment label — so the user sees "Codex has a problem" without switching.
- If a provider has an error and **no** snapshot, it has no segment (see above), so no dot.
- Keep it to the dot; the card itself already carries the full `hasError` / stale treatment.

### Freshness in the header
- Move the "Updated Nm ago" / stale indicator to the **header** (right of the refresh button), showing the **oldest** `lastUpdated` across providers that have snapshots — it's now a panel-level fact, not per-card.
- Keep the per-card `freshnessRow` too (it's still useful when a single provider is stale/errored). Minor duplication is fine; if you'd rather not, drop the per-card row and rely on the header + the per-card error badge — Two's call, either is acceptable.

### Transitions
- `.animation(.easeInOut(duration: 0.15), value: selectedProvider)` on the card swap. Subtle, no slide.

## Implementation notes

- `DashboardView.content` — replace the `ScrollView { VStack { ForEach … } }.frame(maxHeight: 480)` block with: the switcher (`Picker("", selection:).pickerStyle(.segmented)` or a small custom `HStack` of buttons if the segmented control can't show icon+text+dot cleanly) + a single `ProviderCardView` for the selected provider.
- Delete the `maxHeight: 480` frame — with one card the panel sizes to content naturally.
- `ProviderCardView`, `UsageBar`, `DailyUsageChart` — **no changes**.
- `ProviderID` gets `static var displayOrder: [ProviderID]` (`[.claude, .codex, .gemini]`); `allCases` order already matches but be explicit so a future reorder is one place.
- Accessibility: `Picker` segments are natively focusable; label each `"\(provider.displayName)\(hasError ? ", attention needed" : "")"`. The card content already has its a11y.
- `.frame(width: 360)` in `TakatApp` stays.

## Out of scope

- Any change to `ProviderCardView` internals, the chart, or the data layer.
- A "balance" card variant (DeepSeek — future milestone).
- Reordering providers by urgency / auto-selecting the highest-usage one (nice idea, later).
- Settings redesign.
- A "+ Add provider" affordance (providers are hardcoded until the registry refactor).

## Tests

Mostly view logic — keep it light but cover:
- `selectedProvider(stored:available:)` pure helper: stored value present in available → returned; stored absent → first of `displayOrder` in available; available empty → nil.
- The "1 snapshot → no switcher", "0 → empty state", "2+ → switcher" branching (a small view-model or computed property is easier to test than the view — extract `switcherProviders: [ProviderID]` and test that).
- Existing 63 tests stay green.

`swift build && swift test` locally before every push (CI still paused — state the result in the PR). `Package.swift` dependency-free. No version bump.

## Handoff back

- Push, open the PR, fill test-evidence.
- **Desktop screenshots** (this is a visual change — required): the switcher with all three segments, a switch between two providers, the 1-provider fallback (no switcher), and the Claude card showing its new "Pro" pill (closes the step-5.6 eyeball too).
- One re-reviews from remote; Two reviews the visual result.
