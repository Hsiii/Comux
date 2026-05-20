# CodexBoard

CodexBoard is a multi-account Codex usage dashboard built from the
`Hsiii/frontend-template` starter. It borrows the system-account and
usage-fetch approach from CodexBar, then pushes normalized snapshots to
Supabase so the dashboard can be fetched from anywhere:

- the current system account is discovered automatically from `~/.codex/auth.json`
- the native Swift app can upsert snapshots to Supabase
- extra accounts are synced independently
- the browser UI can read from Supabase with no localhost dependency

## What is implemented

- Vite + React dashboard with a distinctive operations-board layout
- native Swift collector with automatic live-system-account sync
- optional Supabase sync and hosted fetch path
- sample cache bootstrap so the native app still works offline
- cookie-based extra-account sync for accounts outside the current `~/.codex`
  login

## Architecture

1. The Swift app inspects `~/.codex/auth.json`, uses the ambient Codex bearer
   token, and refreshes the current system account directly from
   `https://chatgpt.com/backend-api/wham/usage`.
2. The same app can run extra-account loops using per-account ChatGPT cookies.
3. Each result is normalized into the shared account snapshot schema.
4. The Swift app stores snapshots in `~/.codexboard/cache.json`.
5. If `~/.codexboard/supabase.json` exists, the same snapshots are upserted to
   Supabase through the REST API.
6. The Vite app reads from Supabase when `VITE_SUPABASE_URL` and
   `VITE_SUPABASE_PUBLISHABLE_KEY` are set, and falls back to the local cache
   API otherwise.

## Run the web dashboard

```bash
bun install
bun run dev
```

If Supabase env vars are set, the web dashboard reads hosted data and does not
depend on localhost. Without them, it falls back to the local cache API.

## Run checks

```bash
bun run check
```

## Run the native app

The Swift app lives in
`/Users/hsi/Documents/Projects/Personal/CodexBoard/macos/CodexBoardPulse`.

For the primary account, no cookie config is needed. The app reads the current
ambient Codex login automatically from `~/.codex/auth.json`.

For extra accounts:

1. Copy `accounts.example.json` to `~/.codexboard/accounts.json`.
2. Fill in one entry per extra account with its own ChatGPT cookie.
3. Optionally copy `supabase.example.json` to `~/.codexboard/supabase.json`.
4. Launch the app:

```bash
cd macos/CodexBoardPulse
swift run
```

## Supabase setup

Create the snapshots table with
[codex_account_snapshots.sql](/Users/hsi/Documents/Projects/Personal/CodexBoard/supabase/codex_account_snapshots.sql).

Then create `~/.codexboard/supabase.json` from
[supabase.example.json](/Users/hsi/Documents/Projects/Personal/CodexBoard/macos/CodexBoardPulse/supabase.example.json):

```json
{
    "projectURL": "https://your-project-ref.supabase.co",
    "writeAccessToken": "your-service-role-or-user-jwt",
    "tableName": "codex_account_snapshots"
}
```

To point the web dashboard at Supabase:

```bash
VITE_SUPABASE_URL=https://your-project-ref.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
VITE_SUPABASE_SNAPSHOTS_TABLE=codex_account_snapshots
```

## Notes

- The native Swift app is the source of truth for collection.
- The current system account is pulled automatically from local Codex auth.
- Extra-account cookies stay in the native config, not in the browser UI.
- Supabase write credentials should stay in `~/.codexboard/supabase.json`, not
  in the repo or frontend env.
- The bundled sample data is synthetic and only exists to make the app usable
  before live sync is wired up.
