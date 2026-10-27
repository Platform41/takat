# Takat — Agent Context

Read by every coding agent (Claude Code via `CLAUDE.md`, Codex, Antigravity, others). This file
holds **only** Takat-specific rules.

## Maintainer workflow (41 Foundation OS)

The maintainer's agents follow the 41 Foundation OS workflow, personas, and guardrails. Resolve it
from `$FOUNDATION_OS`. If it is not already in your context, read in order:

1. `$FOUNDATION_OS/bootstrap/startup.md`
2. `$FOUNDATION_OS/bootstrap/operating-rules.md`
3. `$FOUNDATION_OS/AGENTS.md` — personas and operating rules

Then load only the lead persona file, `$FOUNDATION_OS/personas/<persona>.md`. If `$FOUNDATION_OS`
is not set, say so before continuing. Outside contributors without it follow
[`CONTRIBUTING.md`](CONTRIBUTING.md) alone.

## Project

Native macOS menu-bar app (SwiftUI, Swift Package) showing AI-tool usage. Layout:
[`README.md`](README.md) → "Project structure"; design: [`docs/architecture.md`](docs/architecture.md).

- Build and test before every push: `swift build && swift test` (macOS 26). CI repeats both.
- App bundle: `./scripts/build-app.sh`. Releases and signing: [`docs/runbooks/release.md`](docs/runbooks/release.md).
- Providers stay behind the shared usage-provider interface. Tests use fixtures, never real usage
  data; every adapter keeps its `SECRET-SENTINEL` privacy test.
- Never commit credentials, session data, personal usage data, `.signing.local`, `.p8`, or `.p12`.

## Workflow

- **Public repo:** never commit machine-specific paths, private project names, or anything from
  `$FOUNDATION_OS` — reference it, don't copy it.
- `main` is integration and release only. Task work goes on `<type>/<persona>-<task>` in its own
  worktree (`git worktree add ../takat-<persona>-<task> <branch>`), then a PR.
- User-visible changes start from an approved behavior spec: [`docs/specs/README.md`](docs/specs/README.md).
- Hand off with [`docs/reviews/handoff-template.md`](docs/reviews/handoff-template.md).
- Only One approves release candidates and creates tags.
