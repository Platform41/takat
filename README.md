# Takat

> Know your AI usage at a glance.

Native macOS menu bar usage dashboard for AI development tools.

The product takes the usage visibility of Omarchy’s panel as inspiration and follows macOS Human Interface Guidelines for its interaction model, typography, colors, accessibility, and menu bar behavior.

## Status

Early prototype. The current repository contains the native app shell, provider-neutral usage models, and architecture baseline. Live provider integrations are not available yet.

## Structure

- `Sources/Takat/App` — application entry point and menu bar scene
- `Sources/Takat/Core/Models` — provider-neutral usage data
- `Sources/Takat/Core/Providers` — Claude and Codex data adapters
- `Sources/Takat/Core/Storage` — Keychain and local cache abstractions
- `Sources/Takat/Features` — dashboard and settings screens
- `Sources/Takat/DesignSystem` — shared visual tokens and components
- `Tests/TakatTests` — model and provider tests
- `docs` — product and architecture decisions

## Development

The first milestone is a fixture-backed SwiftUI prototype. Live provider integrations will be added behind the provider protocol after their supported data sources are confirmed.

## Requirements

- macOS Tahoe 26 or later
- Xcode 26 or later

## License

Takat is released under the MIT License. See [LICENSE](LICENSE).
