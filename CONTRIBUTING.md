# Contributing to Takat

Takat is a native macOS project. Contributions should preserve the macOS Human Interface Guidelines and keep provider integrations behind the shared usage-provider interface.

## Before opening a pull request

- Describe the user-facing change and its provider impact.
- Keep credentials, session data, and personal usage data out of commits.
- Run `swift build && swift test` on macOS 26 before every push. **Automated CI is paused** (no budget — see `.github/workflows/macos.yml`), so local verification is the only gate right now. State the local `swift test` result in the PR.
- Include screenshots for meaningful dashboard or settings changes.
- Document any provider-specific behavior or authentication requirement.

The distributable app is assembled with `scripts/build-app.sh` (source of truth stays `Package.swift`).

Small, focused pull requests are easier to review.
