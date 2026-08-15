# Releasing Glance

This is the runbook for cutting a new release. It works today without an
Apple Developer account (unsigned/ad-hoc DMG), and automatically upgrades to
a signed + notarized DMG the moment the one-time setup below is done —
`release.sh` detects which path to take, no flags needed.

## Every release

1. **Bump the version.** Edit `MARKETING_VERSION` in `project.yml` — strict
   [SemVer](https://semver.org/) (`MAJOR.MINOR.PATCH`, e.g. `1.0.3` → `1.0.4`
   for a fix, `1.1.0` for a backwards-compatible feature, `2.0.0` for a
   breaking change).
2. **Regenerate the Xcode project:**
   ```bash
   xcodegen generate
   ```
3. **Run the release script:**
   ```bash
   ./release.sh
   ```
   This builds the Release configuration, signs + notarizes it (if a
   Developer ID identity is available — see below), builds the DMG, and
   creates/updates the GitHub release with the DMG attached.

   To build and test everything except the GitHub upload (e.g. to verify a
   DMG locally before publishing), use:
   ```bash
   ./release.sh --no-upload
   ```
4. **Update the Homebrew cask.** See "Updating the Homebrew cask" below.

### What `release.sh` does under the hood

- Builds `glance.app` in Release configuration via `xcodebuild`.
- Looks for a **"Developer ID Application"** codesigning identity via
  `security find-identity -v -p codesigning` (override with the
  `SIGN_IDENTITY` env var to force a specific identity).
  - **Identity found:** codesigns the app (`--options runtime --timestamp`
    with the app's entitlements), builds the DMG, codesigns the DMG,
    submits it to Apple's notary service with `xcrun notarytool submit
    --wait`, staples the notarization ticket, and verifies the result with
    a Gatekeeper (`spctl`) assessment. Any failure in this chain aborts the
    script loudly (non-zero exit, notarization log printed on rejection).
  - **No identity found:** builds and packages the DMG exactly as before
    (ad-hoc signed by Xcode's default build settings, no notarization) and
    prints a note pointing back here.
- Creates the DMG via `create-dmg` if installed, else falls back to
  `hdiutil`.
- Creates or updates the `vX.Y.Z` GitHub release via `gh`, uploading the DMG
  — skipped entirely with `--no-upload`.

## One-time Apple Developer setup

Do this once (per machine, and per developer if the team grows) to unlock
the signed + notarized path. Until this is done, `release.sh` keeps working
exactly as it does today — nothing breaks by skipping this section.

1. **Enroll in the Apple Developer Program** ($99/year):
   https://developer.apple.com/programs/enroll/

2. **Create a "Developer ID Application" certificate.** Easiest via Xcode:
   - Xcode → Settings → Accounts → add your Apple ID → select your team →
     "Manage Certificates" → "+" → "Developer ID Application".

   Or via the [developer portal](https://developer.apple.com/account/resources/certificates/list)
   (Certificates, Identifiers & Profiles → Certificates → "+" →
   "Developer ID Application"), then double-click the downloaded `.cer` to
   install it into your keychain (the matching private key must already be
   in your keychain — it's created alongside the CSR).

   Verify it's visible with:
   ```bash
   security find-identity -v -p codesigning
   ```
   You should see a line like:
   `"Developer ID Application: Your Name (TEAMID1234)"`

   If you ever have more than one such identity in the keychain, pin the one
   `release.sh` should use with the `SIGN_IDENTITY` env var:
   ```bash
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID1234)" ./release.sh
   ```

3. **Create an app-specific password** for notarization at
   https://appleid.apple.com/account/manage (Sign-In and Security →
   App-Specific Passwords).

4. **Store notary credentials in the keychain**, so `release.sh` never needs
   secrets in the environment or on disk:
   ```bash
   xcrun notarytool store-credentials glance-notary \
       --apple-id "your-apple-id@example.com" \
       --team-id "TEAMID1234" \
       --password "xxxx-xxxx-xxxx-xxxx"   # the app-specific password from step 3
   ```
   `glance-notary` is the profile name `release.sh` looks for by default;
   override it with the `NOTARY_PROFILE` env var if you use a different name.

5. **Sanity check** with a dry run:
   ```bash
   ./release.sh --no-upload
   ```
   The script should now report a signed identity, sign the app and DMG,
   submit for notarization, staple, and pass the Gatekeeper (`spctl`)
   check — all without touching GitHub.

## Updating the Homebrew cask

After each release, `packaging/homebrew/glance.rb` needs its `version` and
`sha256` bumped to match the new DMG:

```bash
shasum -a 256 release/Glance-<version>.dmg
```

Copy the resulting hash into `sha256 "..."`, bump `version "..."` to match,
and push. See `packaging/homebrew/README.md` for the two distribution paths
(personal tap now vs. submitting to homebrew/homebrew-cask once notarized)
and what each requires.
