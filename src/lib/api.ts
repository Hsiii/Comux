import type {
    AccountSnapshot,
    CachePayload,
    PaceSnapshot,
    UsageWindow,
} from '../types.js';

interface SupabaseRow {
    account_id: string;
    color: string;
    email: string;
    history: AccountSnapshot['history'];
    label: string;
    last_synced_at: string;
    pace: PaceSnapshot;
    plan: string;
    rolling_window: UsageWindow;
    source: string;
    weekly_window: UsageWindow;
    workspace_label: string;
}

function readSupabaseConfig() {
    const url = import.meta.env.VITE_SUPABASE_URL;
    const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
    const table =
        import.meta.env.VITE_SUPABASE_SNAPSHOTS_TABLE ??
        'codex_account_snapshots';

    if (typeof url !== 'string' || url === '') {
        return undefined;
    }

    if (typeof key !== 'string' || key === '') {
        return undefined;
    }

    return {
        key,
        table,
        url,
    };
}

function mapRow(row: SupabaseRow): AccountSnapshot {
    return {
        accountId: row.account_id,
        color: row.color,
        email: row.email,
        history: row.history,
        label: row.label,
        lastSyncedAt: row.last_synced_at,
        pace: row.pace,
        plan: row.plan,
        rollingWindow: row.rolling_window,
        source: row.source,
        weeklyWindow: row.weekly_window,
        workspaceLabel: row.workspace_label,
    };
}

async function fetchSupabaseCache(): Promise<CachePayload> {
    const config = readSupabaseConfig();

    if (config === undefined) {
        throw new Error('Supabase config not available.');
    }

    const url = new URL(`/rest/v1/${config.table}`, config.url);
    url.searchParams.set('select', '*');
    url.searchParams.set('order', 'label.asc');

    const response = await fetch(url, {
        headers: {
            apikey: config.key,
            Authorization: `Bearer ${config.key}`,
        },
    });

    if (!response.ok) {
        throw new Error(`Supabase request failed with ${response.status}.`);
    }

    const rows = (await response.json()) as SupabaseRow[];
    const accounts = rows.map((row) => mapRow(row));

    return {
        meta: {
            cachePath: 'supabase',
            generatedAt:
                accounts
                    .map((account) => account.lastSyncedAt)
                    .toSorted()
                    .at(-1) ?? new Date().toISOString(),
            source: 'supabase',
        },
        accounts,
    };
}

async function fetchLocalCache(): Promise<CachePayload> {
    const response = await fetch('/api/cache');

    if (!response.ok) {
        throw new Error(`Cache request failed with ${response.status}.`);
    }

    return (await response.json()) as CachePayload;
}

export async function fetchCache(): Promise<CachePayload> {
    const supabaseConfig = readSupabaseConfig();

    if (supabaseConfig !== undefined) {
        return await fetchSupabaseCache();
    }

    return await fetchLocalCache();
}
