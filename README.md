<div align="center">
  <img src="assets/logo.png" alt="Comux logo" width="160" />

<h1>Comux</h1>

See your Codex account limits from the macOS menu bar.

<br />

<a href="https://github.com/Hsiii/Comux/releases/latest">Download latest release</a>
 ·
<a href="#install">Install with Homebrew</a>

<br />
<br />

<img src="assets/demo.png" alt="Comux menu bar usage demo" width="420" />
</div>

## Why Comux

- **Zero Setup:** Picks up local Codex sessions automatically and refreshes usage in the background, no manual setup required.
- **Zero-Click 5h Usage:** See your active account's 5-hour usage directly beside the menu bar icon before opening anything.
- **Unified Tracking:** See weekly usage across local Codex accounts and workspace variants in one native menu.
- **Plan your Usage:** Accounts are ranked by remaining headroom so you can pick the right account before starting work.
- **Privacy First:** Keep account details readable without exposing more than you need. Comux supports custom display names and stores account metadata locally in `~/.comux`.

## Install

Homebrew is the recommended install path:

```bash
brew install --cask Hsiii/tap/comux
```

You can also download the latest signed and notarized build from [GitHub Releases](https://github.com/Hsiii/Comux/releases/latest).

Requirements:

- macOS 14 Sonoma or newer
- A local Codex install with at least one signed-in account

## First Run

- Keep Codex signed in locally; Comux reads existing Codex session state.
- Open Comux from Applications and use the menu bar item to review accounts and workspaces.
- Optional: rename accounts in Comux when you want private or easier-to-scan labels.

## Privacy

Comux uses your existing local Codex session state to refresh usage. Account metadata and custom display names are stored locally in `~/.comux`; Comux does not require a separate hosted account.

## Troubleshooting

If Comux does not show an account, open Codex and confirm that account is signed in locally, then reopen the Comux menu. If Homebrew installs an older version, run `brew update` and then `brew upgrade --cask Hsiii/tap/comux`.

## Development

Build a local DMG:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
brew install xcodegen
make dmg
```

Local builds are ad-hoc signed unless `COMUX_CODE_SIGN_IDENTITY` is set to a Developer ID Application identity.

Run directly:

```bash
swift run comux
```

Build the native macOS app bundle:

```bash
make build
```

Build a DMG for distribution:

```bash
make dmg
```

## Release

Run the release wrapper:

```bash
./scripts/release.sh 0.1.0
```

It publishes a GitHub release and waits for the `Release` workflow. The workflow builds a signed app, submits it to Apple notarization, and either publishes the release assets immediately when finalizing an accepted submission or saves the exact signed app for a later finalization run.

When Apple notarization is delayed, run the finalize command printed in the workflow summary or by `scripts/release.sh` after Apple reports the submission as accepted. Finalization staples the notarization ticket, uploads `comux-<version>.zip` and `comux.rb`, and updates the Homebrew tap configured by `HOMEBREW_TAP_REPOSITORY`.

Required repository secrets for signed and notarized releases:

- `APPLE_DEVELOPER_CERTIFICATE_P12_BASE64`
- `APPLE_DEVELOPER_CERTIFICATE_PASSWORD`
- `APPLE_KEYCHAIN_PASSWORD`
- `APPLE_NOTARY_APPLE_ID`
- `APPLE_NOTARY_TEAM_ID`
- `APPLE_NOTARY_PASSWORD`
- `HOMEBREW_TAP_TOKEN`

Required repository variable:

- `HOMEBREW_TAP_REPOSITORY`, for example `Hsiii/homebrew-tap`
