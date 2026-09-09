# Takat

> Know your AI usage at a glance.

Takat is a native macOS menu-bar app that brings usage information from your AI coding tools into one compact dashboard.

## Provider support

| Provider | What Takat shows | Data source |
| --- | --- | --- |
| Claude Code | Plan, current-session and weekly utilization, reset date, and seven-day token activity | Claude Code's local configuration cache and transcripts |
| Codex CLI | Plan, current-session and weekly utilization, reset date, and seven-day token activity | Local Codex session logs |
| Gemini CLI | Seven-day token activity | Local legacy Gemini CLI chats |
| Google Antigravity | An explicit “not locally measurable” notice | Recent local Antigravity activity |
| DeepSeek | Remaining API credit balance | DeepSeek's balance API |

Takat 0.2.0 is a pre-release. Its four-provider dashboard uses real provider data; no fixture data is used by the app.

## Install

1. Download the newest `Takat-<version>.zip` from [GitHub Releases](https://github.com/Platform41/takat/releases).
2. Unzip it and move `Takat.app` to `/Applications`.
3. Launch Takat and look for the gauge icon in the menu bar.

Published releases are Developer ID signed and notarized. Takat requires macOS Tahoe 26 or later.

## Privacy

Takat is local-first:

- Claude, Codex, and legacy Gemini usage is derived from files already written by their command-line tools.
- Takat decodes only the metadata and token fields it needs. It does not decode, display, transmit, or cache prompt and response content.
- Derived usage snapshots are cached in `~/Library/Application Support/Takat/usage-cache.json` so the dashboard can open immediately.
- A DeepSeek API key is stored in the macOS Keychain and sent only to `api.deepseek.com` to request the account balance.
- Takat has no telemetry or analytics.

See [SECURITY.md](SECURITY.md) for private vulnerability reporting guidance.

## Build from source

Requirements:

- macOS Tahoe 26 or later
- Xcode 26 or later

```bash
swift build
swift test
./scripts/build-app.sh
```

The build script creates an ad-hoc-signed app at `dist/Takat.app`. Copy it to `/Applications` for local use. An ad-hoc build may require approval the first time it is opened.

## Project structure

- `Sources/Takat/App` — application entry point and menu-bar scene
- `Sources/Takat/Core/Providers` — Claude, Codex, Gemini, Antigravity, and DeepSeek adapters
- `Sources/Takat/Core` — shared models, caching, refresh policy, and Keychain access
- `Sources/Takat/Features` — dashboard and settings interfaces
- `Sources/Takat/DesignSystem` — provider marks and visual styling
- `Tests/TakatTests` — provider, persistence, and presentation-logic tests
- `docs` — architecture, research, reviews, and release runbooks

## Contributing

Contributions and forks are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request, keep credentials and personal usage data out of commits, and include screenshots for meaningful interface changes.

## Releasing

Release signing and notarization are maintainer-only. Configure an ignored `.signing.local` file, or provide your own Developer ID Application identity explicitly:

```bash
TAKAT_SIGN_ID="Developer ID Application: <TEAM NAME> (<TEAM ID>)" \
  ./scripts/release-app.sh
```

See [the release runbook](docs/runbooks/release.md) for the complete process. `TAKAT_SIGN_ID` is a public certificate identity, not a credential; the corresponding private key and notarization credentials must remain outside the repository.

## License

Takat is released under the [MIT License](LICENSE).
