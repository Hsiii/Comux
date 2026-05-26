## Account Sync & Storage
- Preserve additive account history by default; do not broadly replace or clear system-auth accounts on session changes.
- Support coexistence for same-email cross-workspace accounts and same-email workspace/no-workspace variants.
- Derive storage identity from stable raw data, preferring `email + workspaceId`, then `email + raw workspace label`; never use display-only `"Personal"` normalization for storage keys.
- Treat workspace labels as storage data and `"Personal"` as an internal workspace normalization, not a user-facing tier label.
- On logout or loss of system auth, publish a system-state refresh so `isCurrentSystemAccount` is cleared.
- Treat workspace-list fetch failures as sync errors, not as proof that the account has no workspaces.
- Scope any system-auth cleanup to the same stable profile identity, and only discard snapshots that clearly supersede the same workspace-backed slot.
- Do not broadly delete no-workspace historical entries or cookie-synced accounts during system-auth cleanup.
