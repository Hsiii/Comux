create table if not exists public.codex_account_snapshots (
    account_id text primary key,
    label text not null,
    email text not null,
    workspace_label text not null,
    plan text not null,
    color text not null,
    source text not null,
    last_synced_at timestamptz not null,
    weekly_window jsonb not null,
    rolling_window jsonb not null,
    pace jsonb not null,
    history jsonb not null default '[]'::jsonb,
    updated_at timestamptz not null default now()
);

alter table public.codex_account_snapshots enable row level security;

create policy "public read codex snapshots"
on public.codex_account_snapshots
for select
to anon, authenticated
using (true);
