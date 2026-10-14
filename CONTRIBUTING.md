# Contributing to Takat

Takat is a native macOS project. Contributions should preserve the macOS Human Interface Guidelines and keep provider integrations behind the shared usage-provider interface.

## Before opening a pull request

- Describe the user-facing change and its provider impact.
- Keep credentials, session data, and personal usage data out of commits.
- Run `swift build && swift test` on macOS 26 before every push. Automated CI repeats both checks for pull requests and updates to `main`; state the local `swift test` result in the PR.
- Include screenshots for meaningful dashboard or settings changes.
- Document any provider-specific behavior or authentication requirement.

The distributable app is assembled with `scripts/build-app.sh` (source of truth stays `Package.swift`). A plain `./scripts/build-app.sh` (no signing env vars) produces an ad-hoc build for local testing; Developer ID signing + notarization is maintainer-only — see `docs/runbooks/release.md`. Never commit `.signing.local`, `.p8`, `.p12`, or any signing credential.

## How user-visible changes are built

A change that alters what a user sees or does starts from a short behavior spec in
[`docs/specs/`](docs/specs/README.md): the outcome, what is in and out of scope, and acceptance
scenarios in plain language. The maintainer approves the spec before the change is built. The
implementer writes the automated checks for those scenarios first, and the maintainer then tries the
running app before the change is accepted. Hand off work with the template in
[`docs/reviews/handoff-template.md`](docs/reviews/handoff-template.md). Dependency updates,
refactors and CI changes do not need a spec.

Small, focused pull requests are easier to review.
