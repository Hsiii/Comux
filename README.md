# CodexMux

<img src="assets/demo.png" alt="CodexMux demo" width="50%"/>

A macOS menu bar app to track and sort your Codex account limits at a glance.

## Features

- Local-only auth, cache, and nickname storage.
- Reads Codex sessions from `~/.codex/auth.json`.
- Ranks accounts by usage pressure and nearest reset.
- Uses local nicknames to keep email addresses off-screen.

## Install

Run from source:

```bash
swift run CodexMux
```

Build the app bundle:

```bash
./scripts/build-app.sh
open .build/apple/CodexMux.app
```

Install with Homebrew once a release is published:

```bash
brew install --cask YOUR_GITHUB_OWNER/tap/codexmux
```

## Release

This repo follows the same split release structure as
[`steipete/CodexBar`](https://github.com/steipete/CodexBar):

- GitHub Releases host the macOS app archive.
- A separate Homebrew tap hosts `Casks/codexmux.rb`.
- The cask targets `macOS Sonoma` or newer.

Build release artifacts for `0.0.0`:

```bash
./scripts/package-homebrew.sh --version 0.0.0 --repo YOUR_GITHUB_OWNER/CodexMux
```

This writes:

- `.build/dist/CodexMux-0.0.0.zip`
- `.build/dist/codexmux.rb`

The generated cask expects this release asset URL:

```text
https://github.com/YOUR_GITHUB_OWNER/CodexMux/releases/download/v0.0.0/CodexMux-0.0.0.zip
```

Bootstrap a custom tap repo:

```bash
./scripts/bootstrap-homebrew-tap.sh \
  --version 0.0.0 \
  --source-repo YOUR_GITHUB_OWNER/CodexMux \
  --tap-repo YOUR_GITHUB_OWNER/homebrew-tap
```

The release workflow in `.github/workflows/release.yml`:

- `.github/workflows/release.yml` packages `CodexMux.app` on `macos-14`
- On a published release, uploads `CodexMux-<version>.zip` and `codexmux.rb`
- If `HOMEBREW_TAP_REPOSITORY` and `HOMEBREW_TAP_TOKEN` are set, also updates the tap automatically

Required repo configuration for tap publishing:

- Repository variable: `HOMEBREW_TAP_REPOSITORY=YOUR_GITHUB_OWNER/homebrew-tap`
- Repository secret: `HOMEBREW_TAP_TOKEN` with push access to that tap repo

## Extra Accounts

To monitor additional accounts independently, create `~/.codexmux/accounts.json`
with one object per account:

Minimal example:

```json
{
  "pollIntervalSeconds": 300,
  "accounts": [
    {
      "id": "work-pro",
      "label": "Work Pro",
      "email": "me@company.com",
      "workspaceLabel": "Company",
      "plan": "Codex Pro",
      "color": "#7cc6ff",
      "chatGPTCookie": "YOUR_CHATGPT_COOKIE"
    }
  ]
}
```

Supported fields come from [`AccountConfig`](./src/Model.swift):

- `id`: stable local ID for that configured account
- `label`: default display label before nicknames
- `email`: used as part of merge identity
- `workspaceLabel`: fallback workspace name if the API does not return one
- `plan`: used for display and merge identity
- `color`: card accent color
- `chatGPTCookie`: required for extra accounts
- `source`, `sessionEndpoint`, `usageEndpoint`, `accountHeader`: optional

Use `accountHeader` when a specific ChatGPT account or workspace header is
required.
