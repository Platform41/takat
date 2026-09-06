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

The first milestone is a fixture-backed SwiftUI prototype, now in place. Live provider integrations will be added behind the provider protocol after their supported data sources are confirmed.

## Requirements

- macOS Tahoe 26 or later
- Xcode 26 or later

## License

Takat is released under the MIT License. See [LICENSE](LICENSE).
