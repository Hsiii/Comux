create table if not exists public.codexboard_ingest_tokens (
    token_id text primary key,
    token_sha256 text not null,
    created_at timestamptz not null default now(),
    revoked_at timestamptz
);

alter table public.codexboard_ingest_tokens enable row level security;

grant select, insert, update, delete on public.codexboard_ingest_tokens to service_role;

create policy "service_role_manage_codexboard_ingest_tokens"
on public.codexboard_ingest_tokens
for all
to service_role
using (true)
with check (true);
