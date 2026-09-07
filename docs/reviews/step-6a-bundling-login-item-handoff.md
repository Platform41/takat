# Step 6a — Basic .app bundle + Login Item: Handoff to DeepSeek

**Spec owner:** One (packaging / release policy)
**Implementer:** DeepSeek (Three)
**Branch:** `feat/app-bundle-login-item` off `main` → PR (expected #25)
**Depends on:** PR #23 merged (or not — independent). Land after the marks PR settles.
**Scope:** a slice of delivery-order step 6, pulled forward so Takat is an always-on menu-bar app the maintainer can actually use daily. **Not** full signing/notarization — that stays step 6.

## Goal

`swift run` today gives a bare executable that has to be started by hand. This step produces a double-clickable `Takat.app` that:
- runs as a menu-bar-only agent (no Dock icon),
- can be added to Login Items so it starts at boot,
- carries a real `Info.plist` (bundle id, version, min-OS).

The data-driven show/hide of providers already works — nothing there changes.

## Naming (decided)

- **Bundle identifier:** `net.41labs.takat.llm` — matches KiraSaku's Apple-platform convention (`net.41labs.kirasaku`); the `.llm` leaf reserves `net.41labs.takat` as a product-family namespace for future measuring apps.
- **Display name** (`CFBundleName` / menu-bar / window title / everyday use): **`Takat`** — unchanged. "Takat LLM" is not a display name; the "what it measures" lives in positioning copy (*"Takat — usage for AI development tools"*), not the name. Revisit only if a second Takat app ships.
- **Apple `DEVELOPMENT_TEAM`** (for step 6 signing, not this step): `R798HXVTJ5` (same as KiraSaku).

## Build

### 1. Version file

Create `VERSION` at repo root containing `0.1.0` (pre-production per the 41 OS versioning rule — no tag until One approves a release candidate). The build script reads it.

### 2. `Info.plist` — committed at `App/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Takat</string>
    <key>CFBundleDisplayName</key>     <string>Takat</string>
    <key>CFBundleIdentifier</key>      <string>net.41labs.takat.llm</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>Takat</string>
    <key>CFBundleShortVersionString</key> <string>__VERSION__</string>
    <key>CFBundleVersion</key>         <string>__BUILD__</string>
    <key>LSMinimumSystemVersion</key>  <string>26.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 41 Labs. MIT-licensed.</string>
    <key>NSSupportsAutomaticTermination</key> <true/>
    <key>NSSupportsSuddenTermination</key>    <true/>
</dict>
</plist>
```
- `LSUIElement` = true → menu-bar only, no Dock icon, no app menu. (`MenuBarExtra` is the whole UI.)
- `__VERSION__` / `__BUILD__` are substituted by the build script (`CFBundleVersion` = a monotonic integer; start with a `git rev-list --count HEAD` or just `1`).

### 3. `scripts/build-app.sh`

```sh
#!/usr/bin/env bash
set -euo pipefail
VERSION="$(cat VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
CONFIG="${1:-release}"

swift build -c "$CONFIG" --product Takat
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Takat"

APP="dist/Takat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Takat"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" App/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

# Ad-hoc sign so Gatekeeper is less hostile locally and SMAppService behaves.
codesign --force --deep --sign - "$APP"

echo "Built $APP ($VERSION build $BUILD)"
```
- `chmod +x`. Add `dist/` to `.gitignore`.
- Ad-hoc signing (`--sign -`) is enough for personal use + `SMAppService`; Developer ID signing is step 6.
- If there's an app icon later, this is where `.icns` → `Resources/` + `CFBundleIconFile` goes — out of scope now.

### 4. Login Item — `Sources/Takat/App/LoginItem.swift`

```swift
import ServiceManagement

@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else       { try SMAppService.mainApp.unregister() }
        } catch {
            // Surface via the toggle reverting; don't crash.
        }
    }
}
```

### 5. Settings toggle — `SettingsView.swift`

Add a section:
```swift
Section {
    Toggle("Open Takat at Login", isOn: Binding(
        get: { LoginItem.isEnabled },
        set: { LoginItem.setEnabled($0) }
    ))
} footer: {
    Text("Requires running Takat from /Applications. An unsigned build may need approval in System Settings → General → Login Items.")
}
```
- Keep the existing Providers + Refresh sections.

### 6. Docs

- **README** — replace the thin "Development" section with:
  - **Run (dev):** `swift run Takat`
  - **Build the app:** `./scripts/build-app.sh` → `dist/Takat.app`; drag to `/Applications`; first launch: right-click → Open (unsigned).
  - **Start at login:** toggle in Takat → Settings (⌘,).
- **CONTRIBUTING.md** — note the app is built via `scripts/build-app.sh`, source of truth stays `Package.swift`.

## Out of scope — stays step 6

- Developer ID signing, notarization, stapling.
- A `.dmg` / installer / Sparkle auto-update.
- App icon / `.icns`.
- Hardened runtime + entitlements (needed for the Keychain-based Claude `/usage` adapter — that's the network-adapters milestone).
- Accessibility audit, release checklist.

## Tests

- `tests/build-app-test.sh` — run `scripts/build-app.sh`, assert `dist/Takat.app/Contents/MacOS/Takat` exists and is executable, and `plutil -lint` passes on the generated `Info.plist`. Wire it into the existing `tests/` convention if there is one.
- `LoginItem` is a thin `SMAppService` wrapper — not unit-testable without the system service; a `#Preview`-level smoke (does `LoginItem.isEnabled` read without throwing) is enough, or skip.
- Keep all 72 Swift tests green — this step doesn't touch the data layer or views beyond the Settings toggle.

`swift build && swift test` locally (CI paused — state result in the PR). `Package.swift`: `import ServiceManagement` is a system framework, **no new SPM dependency**. Confirm it links on `.macOS(.v26)` (it will).

## Handoff back

- Push, open the PR, fill test-evidence.
- **Do the real thing:** build `dist/Takat.app`, move it to `/Applications`, launch it, toggle "Open at Login", reboot (or log out/in), confirm the gauge icon comes back on its own. Screenshot the Settings toggle and report the reboot result.
- One re-reviews from remote. No version tag (still `0.x`).
