<div align="center">
  <img src="assets/logo.png" alt="CodexMux logo" width="160" />

<h1>CodexMux</h1>

A macOS menu bar app to track and sort your Codex account limits at a glance.

<img src="assets/demo.png" alt="CodexMux demo" height="720" />
</div>

## Why CodexMux

- **Unified Tracking:** Monitor usage across multiple Codex accounts and workspaces in one place.
- **Zero-Touch Sync:** Automatically discovers local Codex sessions and keeps usage data in sync without manual login or credential input.
- **Intelligent Prioritization:** Accounts are ranked by current usage relative to their expected pacing, lets you identify which account has the most available headroom at a glance.
- **Privacy First:** Built natively in Swift with local-only storage and nickname support to keep account details private and unobtrusive.

## Install

Open [CodexMux.app](dist/CodexMux.app) directly or [CodexMux.dmg](dist/CodexMux.dmg) to install it to your Applications folder.

## Development

Run directly:

```bash
swift run CodexMux
```

Build the native macOS app bundle:

```bash
./scripts/build-app.sh
```

Build a DMG for distribution:

```bash
./scripts/package-dmg.sh
```
