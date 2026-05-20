/// <reference types='vite/client' />

interface ImportMetaEnv {
    readonly VITE_SUPABASE_PUBLISHABLE_KEY?: string;
    readonly VITE_SUPABASE_SNAPSHOTS_TABLE?: string;
    readonly VITE_SUPABASE_URL?: string;
}

interface ImportMeta {
    readonly env: ImportMetaEnv;
}
