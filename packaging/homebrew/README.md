# Homebrew Cask distribution

YourUsual is distributed through a **personal tap** (`s-age/homebrew-your-usual`)
as a notarized DMG. End users install with:

```bash
brew tap s-age/your-usual   # shorthand for the s-age/homebrew-your-usual repo
brew install --cask your-usual
```

This also symlinks the bundled executable onto `PATH` as `your-usual`, so the
CLI (e.g. `your-usual cd <path>`) works after install.

## One-time setup

### 1. Notarization credentials

Create a keychain profile so `Scripts/release.sh` can notarize without
prompting (requires an Apple Developer Program membership):

```bash
xcrun notarytool store-credentials "yourusual-notary" \
  --apple-id "<your-apple-id>" \
  --team-id  "7VF2T8G76X" \
  --password "<app-specific-password>"
```

Generate the app-specific password at <https://account.apple.com> →
**Sign-In and Security → App-Specific Passwords**.

### 2. The tap repository

The tap lives at **`s-age/homebrew-your-usual`** (the `homebrew-` prefix is what
makes `brew tap s-age/your-usual` resolve). Place the cask at
`Casks/your-usual.rb`.

## Cutting a release

```bash
# 1. Bump the version in Resources/Info.plist
#    (CFBundleShortVersionString and CFBundleVersion).

# 2. Build the signed + notarized + stapled DMG.
./Scripts/release.sh
#    → prints the artifact path, version, and sha256.

# 3. Create a GitHub release tagged v<version> on s-age/YourUsual and upload
#    the YourUsual-<version>.dmg artifact.
gh release create "v<version>" "YourUsual-<version>.dmg" \
  --repo s-age/YourUsual --title "v<version>" --generate-notes

# 4. Update packaging/homebrew/your-usual.rb with the new version + sha256,
#    then copy it into the tap repo and push:
cp packaging/homebrew/your-usual.rb /path/to/homebrew-your-usual/Casks/your-usual.rb
#    (commit & push in the tap repo)

# 5. Verify end to end:
brew update
brew upgrade --cask your-usual   # or: brew install --cask your-usual
```

## Notes

- The DMG is signed with **Developer ID Application** and notarized, so
  Gatekeeper opens it cleanly — no `--no-quarantine` workaround is needed.
- Releases are hosted on `s-age/YourUsual`; the cask is published from a separate
  `s-age/homebrew-your-usual` repo. Adjust the URLs in `your-usual.rb` and this
  file if you publish under different repository names.
- Audit the cask by **tap name**, not file path:
  `brew audit --cask s-age/your-usual/your-usual`.
- Do **not** add a `verified:` parameter while `url` and `homepage` share the
  `github.com` domain — `brew audit` rejects it as unnecessary.
- Promotion to the official `Homebrew/homebrew-cask` tap later requires the repo
  to meet notability criteria (e.g. 30+ days old or 75+ stars). The cask here is
  already compatible with the official format.
