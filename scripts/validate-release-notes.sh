#!/usr/bin/env bash

set -euo pipefail

release_notes="$(tr -d '\r')"

changes_header_line="$(
    grep -n -m1 -Fx "## What's Changed" <<<"$release_notes" \
        | cut -d: -f1 \
        || true
)"
if [[ -z "$changes_header_line" ]]; then
    echo "Release notes must contain an exact ## What's Changed heading." >&2
    exit 1
fi

changes_section="$(
    tail -n "+$((changes_header_line + 1))" <<<"$release_notes" \
        | sed '/^## /q'
)"
if ! grep -Eq '^- .+' <<<"$changes_section"; then
    echo "Release notes must include at least one bullet under ## What's Changed." >&2
    exit 1
fi
