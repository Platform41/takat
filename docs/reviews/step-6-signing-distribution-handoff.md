# Step 6 — Signing, Notarization & Distribution: Handoff

**Spec owner:** One (release policy)
**Implementer:** DeepSeek (Three) for code/scripts; **maintainer** for the Apple-account prerequisites
**Branch:** `feat/signing-distribution` off `main` → PR (expected #30)
**Depends on:** PR #27 merged (`ae94155`) — the `.app` bundle + `scripts/build-app.sh` exist
**Delivery-order:** the rest of step 6 (packaging, signing, release checks). Accessibility audit is folded in as a lightweight pass.

---

## Part A — Maintainer prerequisites (blocking; nothing signs without these)

The keychain currently has `Apple Development: …` and `Apple Distribution: <TEAM NAME> (<TEAM ID>)` — the latter is **App Store** distribution, **not** what a notarized outside-the-store app needs.

1. **Create a "Developer ID Application" certificate** for team `<TEAM ID>`:
   - Xcode → Settings → Accounts → `<TEAM NAME>` → Manage Certificates → **+** → **Developer ID Application**
   - (or developer.apple.com → Certificates → + → Developer ID Application; Account Holder/Admin only; max 5)
   - Confirm: `security find-identity -v -p codesigning` shows `Developer ID Application: <TEAM NAME> (<TEAM ID>)`.

2. **Notarization credentials** — pick one, store locally:
   - **Recommended: App Store Connect API key** (`.p8`, doesn't expire). appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API → generate a key with the **Developer** role. Save `AuthKey_XXXX.p8` somewhere outside the repo; note the **Key ID** and **Issuer ID**.
   - Then: `xcrun notarytool store-credentials "takat-notary" --key <path.p8> --key-id <KEYID> --issuer <ISSUER-UUID>` — stores it in the keychain under the profile name `takat-notary`.
   - (Alternative: an app-specific password from appleid.apple.com + `store-credentials "takat-notary" --apple-id … --team-id <TEAM-ID> --password …`.)

3. Tell DeepSeek the **exact identity string** (`Developer ID Application: <TEAM NAME> (<TEAM ID>)`) and the **notary profile name** (`takat-notary`). Nothing secret is committed — see Part H.

---

## Part B — Quit / Settings affordance (code; do this even if A is delayed)

**Bug:** as an `LSUIElement` app there is **no Dock icon and no app menu**, so once installed the user has **no way to quit Takat** (only Activity Monitor / `killall`). `MenuBarExtra(.window)` can't also show a pull-down menu, so the controls go in the panel.

- `DashboardView` — add a small footer row below `content`:
  ```
  [gear] Settings…                              [power] Quit Takat
  ```
  - `Button` (borderless, `.secondary`, `.caption`) — Settings: `SettingsLink { … }` (SwiftUI 16+) or open the Settings scene; Quit: `Button("Quit Takat") { NSApplication.shared.terminate(nil) }`.
  - Keep it visually quiet — a `Divider()` then an `HStack` with `Spacer()` between the two.
- Accessibility: both are real buttons with labels; nothing extra needed.
- Add a `#Preview` / small test isn't necessary — but confirm ⌘Q works once running (it may already via the responder chain; the explicit button is the discoverable path).

This ships regardless of signing — it's a correctness fix for the installed app.

---

## Part C — Hardened runtime + Developer ID signing

### `App/Takat.entitlements` (new, committed)

Minimal — Takat is **not sandboxed** (it reads `~/.codex`, `~/.claude`, `~/.gemini` dotfiles; sandboxing would break that and isn't required for Developer ID distribution). Hardened runtime only:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- No sandbox. Hardened runtime is applied via `codesign --options runtime`. -->
    <!-- Reserved for the future DeepSeek adapter (Keychain read); harmless to include now: -->
    <key>keychain-access-groups</key>
    <array><string>$(AppIdentifierPrefix)net.41labs.takat.llm</string></array>
</dict>
</plist>
```
(If `$(AppIdentifierPrefix)` substitution is awkward outside Xcode, drop `keychain-access-groups` entirely for now — Keychain access still works for a non-sandboxed hardened app, just without a shared group. Add it when the DeepSeek adapter lands.)

### `scripts/build-app.sh` — replace the ad-hoc sign

Read the identity from an env var so the script still runs unsigned on a machine without the cert:

```sh
SIGN_ID="${TAKAT_SIGN_ID:-}"          # e.g. "Developer ID Application: <TEAM NAME> (<TEAM ID>)"
if [ -n "$SIGN_ID" ]; then
    codesign --force --options runtime --timestamp \
        --entitlements App/Takat.entitlements \
        --sign "$SIGN_ID" "$APP/Contents/MacOS/Takat"
    codesign --force --options runtime --timestamp \
        --entitlements App/Takat.entitlements \
        --sign "$SIGN_ID" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
else
    codesign --force --sign - "$APP"   # ad-hoc fallback, unchanged behaviour
    echo "⚠ ad-hoc signed (set TAKAT_SIGN_ID to Developer-ID sign)"
fi
```
- Sign the **inner binary first**, then the bundle. Drop `--deep` for *signing* (deprecated); keep `--deep` only in `--verify`.
- `--timestamp` needs network (Apple's TSA).

---

## Part D — Notarization + stapling: `scripts/release-app.sh` (new)

```sh
#!/usr/bin/env bash
set -euo pipefail
: "${TAKAT_SIGN_ID:?set TAKAT_SIGN_ID}"
NOTARY_PROFILE="${TAKAT_NOTARY_PROFILE:-takat-notary}"
VERSION="$(cat VERSION)"

./scripts/build-app.sh release            # builds + Developer-ID signs (Part C)

APP="dist/Takat.app"
ZIP="dist/Takat-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t install "$APP"           # expect: accepted, source=Notarized Developer ID

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"    # re-zip the now-stapled app
echo "Release artifact: $ZIP"
```
- `chmod +x`. If notarization is rejected, `xcrun notarytool log <submission-id> --keychain-profile "$NOTARY_PROFILE"` shows why (usually a missing hardened-runtime flag or an unsigned nested binary — there are none here).

---

## Part E — Distribution artifact

- **Zip** (`Takat-<version>.zip`, the stapled `.app`) for GitHub Releases. Double-click after download → Gatekeeper accepts silently (notarized + stapled).
- **DMG deferred** — a drag-to-Applications window is nicer but adds `create-dmg`/`hdiutil` scripting; do it as a follow-up once the zip flow is proven.

---

## Part F — App icon (placeholder now)

- `LSUIElement` apps show no Dock icon, but Finder / "About" / Login Items use the `.app` icon. Ship a **placeholder** so it's not the generic blank:
  - render the menu-bar gauge glyph (or a simple `ProviderMark`-style mark) to a 1024×1024 PNG, `iconutil -c icns` → `App/Takat.icns`
  - `Info.plist`: add `<key>CFBundleIconFile</key><string>Takat</string>`; build script copies `App/Takat.icns` → `Contents/Resources/`.
- **Real icon = a separate Five (visual) task** — note it in the PR, don't design it here.

---

## Part G — Accessibility pass (lightweight)

Not a full audit — a once-over while the panel is being touched for Part B:
- VoiceOver: tab through the switcher segments, the selected card's bars, the chart, the new footer buttons — every control announces something sensible. (The bars/chart already have `.accessibilityLabel`/`Value`; the switcher segments have labels.)
- Dynamic Type: the card and switcher should not clip at the largest accessibility text sizes (the marks now scale via `@ScaledMetric`; check the switcher segment text wraps or truncates gracefully).
- Fix anything obviously broken; log the rest as follow-ups. Don't gold-plate.

---

## Part H — Secrets & docs

- **Never commit:** the `.p8` key, the Developer ID cert/`.p12`, any password. They live in the maintainer's login keychain + the `takat-notary` keychain profile.
- `TAKAT_SIGN_ID` and `TAKAT_NOTARY_PROFILE` are read from the environment. Optionally support a **gitignored** `.signing.local` that the scripts `source` — add `.signing.local` to `.gitignore` and ship a `.signing.local.example`.
- **README** — add a "Releasing" section (maintainer-only): prerequisites (Part A), `TAKAT_SIGN_ID=… ./scripts/release-app.sh`, then tag + `gh release create Takat-<version>.zip`.
- **CONTRIBUTING** — note that a normal `./scripts/build-app.sh` (no env var) still produces an ad-hoc build for local testing; releases are maintainer-only.
- `docs/runbooks/` — a `release.md` runbook capturing the full sequence + how to read a notarization rejection.

---

## Out of scope (later)

- Mac App Store submission (needs the sandbox + a different provisioning path — a deliberate product decision, not now).
- Sparkle / auto-update.
- The **real** app icon (Five).
- A DMG (Part E — follow-up).
- CI-driven release (Actions is paused; and notary creds as CI secrets is its own review). The scripts are written so this is a later lift, not a rewrite.
- The DeepSeek adapter (separate milestone; this step just leaves the `keychain-access-groups` entitlement hook for it).

---

## Versioning / release gate

- Everything here stays on `0.x`. The **first `1.0.0` tag requires One's explicit approval of a release candidate** (41 OS rule) — a green `release-app.sh` run + the accessibility pass + the maintainer confirming the notarized app installs cleanly on a second account/machine is the RC checklist. Do **not** tag in this PR.

## Tests

- `scripts/build-app.sh` with `TAKAT_SIGN_ID` unset → still produces an ad-hoc `dist/Takat.app` (existing `Tests/build-app-test.sh` must still pass unchanged).
- Add to `Tests/build-app-test.sh`: assert `Contents/Resources/Takat.icns` exists and `codesign --verify` passes (ad-hoc is fine for the assertion).
- Part B footer — keep the 79 Swift tests green; no new unit tests required (UI).
- The full sign→notarize→staple path is **manually verified by the maintainer** (needs the cert + network + Apple's service) — the PR reports the `spctl` output.

## Handoff back

- DeepSeek: Parts B, C, F, G, H (code, scripts, entitlements, placeholder icon, docs). Open the PR; `swift test` 79/79; `build-app.sh` ad-hoc path still green.
- Maintainer: Part A, then run `TAKAT_SIGN_ID="Developer ID Application: <TEAM NAME> (<TEAM ID>)" ./scripts/release-app.sh` and paste the `notarytool` result + `spctl -a -vvv` output into the PR.
- One re-reviews from remote once both halves are in.
