# Provider marks (simplified brand glyphs): Handoff to DeepSeek

**Design owner:** Two (visual) — commissioned by One
**Implementer:** DeepSeek (Three)
**Branch:** `feat/provider-marks` off `main` → PR (expected #22)
**Depends on:** PR #20 merged (`351ae0f`); land after or alongside PR #21 (dashboard polish)
**Decision:** approach **B** from `docs/reviews/dashboard-polish-handoff.md` context — simplified, brand-*evoking* single-colour marks, not the companies' actual logos.

## Intent

Replace the generic SF Symbols (`sparkles` / `terminal` / `diamond`) with three custom marks that read as Claude / Codex / Gemini at a glance, while staying monochrome, template-tinted, and consistent with the panel's aesthetic. **Not pixel-exact logos** — evocative geometric glyphs drawn in code.

## Build

### `Sources/Takat/DesignSystem/ProviderMark.swift`

A `View` that draws the mark for a provider using `Path`/`Shape`, no colour of its own (inherits `.foregroundStyle` from context, so existing `.foregroundStyle(accentColor)` / `.primary` / `.secondary` at call sites keep working):

```swift
struct ProviderMark: View {
    let provider: ProviderID
    var size: CGFloat = 14

    var body: some View {
        Canvas { ctx, rect in … }   // or a ZStack of Shapes
            .frame(width: size, height: size)
            .accessibilityHidden(true)   // decorative; callers carry the text label
    }
}
```

### The three marks — geometric recipes (Two owns final proportions)

- **Gemini** — four-pointed concave star (Google's "spark"): 4 outer points on the axes, 4 inner control points pulled ~15% toward centre, quadratic curves between. Essentially the `sparkle` silhouette; make the points a touch sharper.
- **Claude** — radial burst: N tapered rays (start with **N = 12**) from centre, each a thin rounded wedge, outer tips ~48% of the frame, slight length alternation (long/short) for the organic Anthropic feel. Filled, single colour.
- **Codex** — a rounded terminal glyph: a bold `>` chevron (two strokes meeting at a point, `lineCap: .round`, `lineJoin: .round`) with a short underscore bar to its lower right. Reads as a shell prompt without being OpenAI's knot.

**Escape hatch:** if any single mark can't be made to look clean in a reasonable time, ship the other two custom and use the closest SF Symbol for that one (`sparkle` for Gemini, `asterisk` for Claude, `chevron.right` for Codex) — note which in the PR. Don't block the whole change on one fiddly path.

### Wire it in — `ProviderStyle.swift`

- Keep `displayName` and `accentColor` unchanged.
- Keep `symbolName` **only** as an accessibility/fallback string (or drop it if nothing needs it after the call-site edits — check).
- Call sites to update (3):
  1. `DashboardView.swift` card header — `Label(displayName, systemImage: symbolName)` → `Label { Text(snapshot.provider.displayName) } icon: { ProviderMark(provider: snapshot.provider, size: 16) }`. The surrounding `.foregroundStyle(accentColor)` stays and tints the mark.
  2. `DashboardView.swift` switcher segment — `Image(systemName: provider.symbolName)` → `ProviderMark(provider: provider, size: 12)`.
  3. `SettingsView.swift` — `Label(displayName, systemImage: symbolName)` → same `Label { } icon: { ProviderMark(...) }` treatment, `size: 14`.
- **Do not** touch `TakatApp.swift`'s `MenuBarExtra(systemImage:)` — that's the app's menu-bar icon and must stay an SF Symbol string.

## Out of scope

- Colour logos, official brand assets, an asset catalog / `Package.swift` resource changes (code `Path`s only).
- `ProviderCardView` layout, chart, switcher logic, data layer.
- A settings option to switch icon styles.

## Constraints

- Marks must render cleanly at 12–16 pt and in both light and dark (they're template-tinted, so this follows automatically — just verify the burst/star don't turn to mud at 12 pt).
- No new dependencies. `Package.swift` untouched.
- `swift build && swift test` green locally (CI paused — state result in PR). Keep the 71 tests green; no new tests needed (pure geometry), a compile-time `ForEach(ProviderID.allCases) { ProviderMark(provider: $0) }` in a `#Preview` is enough.
- No version bump.

## Governance note

Six flag for later: if Takat is ever distributed publicly, Six reviews these marks for trademark proximity to the real logos. For the current prototype, proceed.

## Handoff back

Push, open the PR. **Desktop screenshots required** (visual change): the three marks in the switcher, in a card header (tinted with the accent), and in Settings. Note any mark that fell back to an SF Symbol. One re-reviews; Two reviews the visual.
