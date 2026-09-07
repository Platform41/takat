# Takat

> Know your AI usage at a glance.

Native macOS menu bar usage dashboard for AI development tools.

The product takes the usage visibility of Omarchy’s panel as inspiration and follows macOS Human Interface Guidelines for its interaction model, typography, colors, accessibility, and menu bar behavior.

## Status

Early prototype with a fixture-backed dashboard. The repository contains the native app shell, provider-neutral usage models, a `UsageStore` refresh layer, and a fixture adapter. Live provider integrations are not available yet.

## Structure

- `Sources/Takat/App` — application entry point and menu bar scene
- `Sources/Takat/Core/Models` — provider-neutral usage data
- `Sources/Takat/Core/Providers` — usage provider protocol and fixture adapter
- `Sources/Takat/Core/UsageStore.swift` — refreshes snapshots from providers and exposes them to views
- `Sources/Takat/Features` — dashboard and settings screens
- `Sources/Takat/DesignSystem` — provider visual mapping (symbols, colors, display names)
- `Tests/TakatTests` — model, provider, and store tests
- `docs` — product and architecture decisions

## Development

- **Run (dev):** `swift run Takat`
- **Build the app:** `./scripts/build-app.sh` → `dist/Takat.app`; drag to `/Applications`; first launch: right-click → Open (unsigned).
- **Start at login:** toggle in Takat → Settings (⌘,).

## Requirements

- macOS Tahoe 26 or later
- Xcode 26 or later

## License

Takat is released under the MIT License. See [LICENSE](LICENSE).
