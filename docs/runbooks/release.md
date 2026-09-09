# Release runbook — Takat

Maintainer-only. Requires the Developer ID Application certificate and a notarization
keychain profile (see Part A of `docs/reviews/step-6-signing-distribution-handoff.md`).

## One-time setup

1. **Developer ID cert** — create a `Developer ID Application` certificate for the
   publishing Apple Developer team.
   Verify:

   ```bash
   security find-identity -v -p codesigning
   ```

2. **Notarization credentials** — store an App Store Connect API key (`.p8`) under the
   profile `takat-notary`:

   ```bash
   xcrun notarytool store-credentials "takat-notary" \
     --key /path/to/AuthKey_XXXX.p8 --key-id <KEYID> --issuer <ISSUER-UUID>
   ```

3. **Local signing config** — copy `.signing.local.example` → `.signing.local` and fill in
   `TAKAT_SIGN_ID` / `TAKAT_NOTARY_PROFILE`. `.signing.local` is gitignored.

## Release

```bash
TAKAT_SIGN_ID="Developer ID Application: <TEAM NAME> (<TEAM ID>)" \
  ./scripts/release-app.sh
```

This builds + Developer-ID-signs (hardened runtime) `dist/Takat.app`, submits it to
notarization, staples it, and re-zips it as `dist/Takat-<version>.zip`.

Then tag and publish:

```bash
# Only after One approves the release candidate (41 OS rule — no 1.0.0 tag before RC approval).
git tag v0.x.y
git push origin v0.x.y
gh release create "Takat-0.x.y" dist/Takat-0.x.y.zip
```

## Reading a notarization rejection

If `notarytool submit` returns `status: Invalid`, fetch the log:

```bash
xcrun notarytool log <submission-id> --keychain-profile takat-notary
```

Common causes:

- **Missing hardened runtime** — the binary wasn't signed with `--options runtime`. The build
  script signs the inner binary and the bundle with runtime; a nested binary added later would
  need re-signing.
- **Unsigned nested code** — `codesign --verify --deep --strict --verbose=2 dist/Takat.app`
  shows which nested executable/dylib is unsigned.
- **Entitlements mismatch** — the entitlements used at sign time differ from the notarized
  submission (e.g. `keychain-access-groups` with a literal `$(AppIdentifierPrefix)`).

## Verification checklist (release candidate)

- `swift build && swift test` green locally.
- `xcrun stapler validate dist/Takat.app` → `The validate action worked!`
- `spctl -a -vvv -t install dist/Takat.app` → `accepted`, `source=Notarized Developer ID`.
- Fresh install on a second account/machine launches and the gauge icon appears.
