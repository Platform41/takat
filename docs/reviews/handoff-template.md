# <Change> — Handoff to <implementer>

**Spec owner:** One
**Implementer:** <agent> (Three)
**Branch:** `<type>/<persona>-<task>` off `main` → PR
**Type:** feature | bug fix | refactor | docs
**Behavior spec:** `docs/specs/<feature-slug>.md` — approved <date>, or `not applicable` for a
change that does not alter what the user sees

## The change

What and why, with the files and types involved. For a bug, the root cause.

## Acceptance checks

Map each approved scenario to an automated check, written before the code it covers. Use fixtures,
never real usage data; adapters keep their `SECRET-SENTINEL` privacy test.

| Scenario | Automated check |
|---|---|
| <scenario title from the spec> | `<TestName>` |

## Validation

- `swift build && swift test` on macOS 26: <result>
- CI `test` check: <result>
- Reviewed diff: <reviewer, not the implementer>

## Try it (test card for the maintainer)

Only for a change that alters what the user sees. Build with `./scripts/build-app.sh`, copy
`dist/Takat.app` to `/Applications`, and launch it.

1. <what to do> — expect <what should appear>.
2. <what to do> — expect <what should appear>.

Report anything that looked, read or felt wrong, in plain words. No code review is needed from you.

## Acceptance

- **Maintainer's result:** accepted | iteration requested | blocked (<why>)
- **Feedback classified as:** behavior defect | usability issue | spec change | technical issue
- A spec change goes back to `docs/specs/` for re-approval before it is built.

## Out of scope

What this change deliberately does not do.
