# Behavior specs

A behavior spec says what a change should do for the person using Takat, in plain language, before
anyone builds it. The maintainer approves it; then it is built, tested against its scenarios, and
tried by hand on the running app.

## When a change needs one

Write a spec when a change alters what a user can see or do: a new card or setting, a new provider,
a different number, label or reset time, a changed menu-bar or login behavior.

Skip it for dependency updates, internal refactors, build or CI changes, and investigations, unless
their result changes what the user sees. A bug fix needs a spec only when the right behavior is
unclear. Otherwise the handoff alone is enough.

## How it flows

1. **Describe the outcome.** The maintainer says what should be true for the user. The spec author
   asks only questions that could change visible behavior or scope.
2. **Approve the spec.** The maintainer approves the behavior and scope, not the code or design.
   Unresolved questions stay listed and are not guessed.
3. **Build.** The implementer turns each scenario into an automated check, writes tests first for
   the internals, then builds. Scenarios use Takat's fixture-based provider tests, including the
   `SECRET-SENTINEL` privacy checks, so a scenario never needs real usage data.
4. **Try it.** When checks pass, the implementer gives the maintainer a build to try (see the test
   card in the handoff template). The menu-bar item cannot be scripted headlessly, so a person
   looking at the real app is the only check for how it looks and feels.
5. **Accept or iterate.** The maintainer accepts, or reports what felt wrong. Each report is one of:
   - **Behavior defect:** an approved scenario was not met. Fix it.
   - **Usability issue:** the outcome is right but the experience is not. Improve it.
   - **Spec change:** the desired outcome changed. Revise the spec and get approval again before
     building it.
   - **Technical issue:** diagnose and fix.

Automated checks never stand in for step 4, and step 4 never stands in for code review or the
release gate.

## Spec file

One file per change: `docs/specs/<feature-slug>.md`. Keep it to the decisions needed to build and
judge the change. Describe what the user can observe, never code, types or libraries.

````markdown
# <Feature> — Behavior Spec

**Status:** Draft | Approved <date> | Superseded by <spec>
**Date:** <date>
**Handoff:** docs/reviews/<slug>-handoff.md (once written)

## Intended outcome
What should be true for the user once this ships. Add a success signal if one is measurable.

## In scope
- ...

## Not in scope
- ...

## Acceptance scenarios

```gherkin
Scenario: <what the user is doing>
  Given <starting situation>
  When <what they do or what happens>
  Then <what they see>
```

Cover the main path and the states that matter: no data, a provider not installed, stale or expired
data, a failure to read, first launch.

## Decisions
- Decisions the maintainer made while approving the spec.

## Open questions
- Anything unresolved. Empty before approval.
````
