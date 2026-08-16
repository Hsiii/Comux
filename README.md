<h1 align="center">Comux</h1>
<div align="center">
  
  See your Codex account limits from the macOS menu bar.  
  
  <img src="https://raw.githubusercontent.com/orangesago/comux/main/assets/demo.png" alt="Comux menu bar usage demo" width="420" />

  <a href="https://github.com/orangesago/comux/releases/latest">Download latest release</a>
   ·
  <a href="#install">Install with Homebrew</a>
</div>

## Why

- **Zero setup:** Picks up local Codex app sessions automatically (you can also set it up manually with Codex CLI).
- **Usage in your menu bar:** Check your active account's remaining usage at a glance.
- **Track all at once:** See usage and reset info across accounts and workspace in one panel.
- **Smart planing:** Accounts are ranked by remaining headroom so you can pick the right account to burn.
- **Auto updates:** Comux checks GitHub Releases daily, even while it stays open, and can install updates from the menu bar.
- **Privacy first:** Comux supports custom display names and stores account metadata locally in `~/.comux`.

## Install

Install with Homebrew:

```bash
brew install --cask orangesago/tap/comux
```

Or download from [GitHub Releases](https://github.com/orangesago/comux/releases/latest).

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

If Comux does not show an account, open Codex and confirm that account is signed in locally, then reopen the Comux menu. If Homebrew installs an older version, use **Check for Updates** from the Comux menu or run `brew update` and then `brew upgrade --cask orangesago/tap/comux`.

## Development
### Run directly

```bash
swift run comux
```

When Codex returns a 5-hour window, Comux automatically shows it in the menu bar and enables short-window locking. Accounts without one continue to show weekly usage.

### Build a local DMG

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
brew install xcodegen
make dmg
```

Local builds are ad-hoc signed unless `COMUX_CODE_SIGN_IDENTITY` is set to a Developer ID Application identity.

### Build the native macOS app bundle

```bash
make build
```

### Build a DMG for distribution

```bash
make dmg
```
