#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO=""
TARGET="main"
WATCH=1
NOTES=""

usage() {
    cat <<'EOF'
Usage: scripts/release.sh <version> [options]

Options:
  --repo <owner/name>     GitHub repository to release. Defaults to the current repo.
  --target <ref>          Release target branch or SHA. Defaults to main.
  --notes <text>          Release notes. Defaults to "Comux <version>".
  --no-watch              Create the release without waiting for the workflow.
  --help, -h              Show this help.

Examples:
  scripts/release.sh 0.1.0
  scripts/release.sh v0.1.0 --notes "Initial signed and notarized release"
EOF
}

if [[ $# -eq 0 ]]; then
    usage >&2
    exit 1
fi

case "$1" in
    --help|-h)
        usage
        exit 0
        ;;
esac

VERSION="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            REPO="${2:-}"
            shift 2
            ;;
        --target)
            TARGET="${2:-}"
            shift 2
            ;;
        --notes)
            NOTES="${2:-}"
            shift 2
            ;;
        --no-watch)
            WATCH=0
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

VERSION="${VERSION#v}"
TAG="v${VERSION}"

if [[ ! "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
    echo "Invalid version: $VERSION" >&2
    echo "Use a semantic version like 0.1.0." >&2
    exit 1
fi

for command_name in git gh; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "error: $command_name is required" >&2
        exit 1
    fi
done

cd "$ROOT_DIR"

if [[ -z "$REPO" ]]; then
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

if [[ -z "$NOTES" ]]; then
    NOTES="Comux ${VERSION}"
fi

dirty_paths=()
while IFS= read -r status_line; do
    path="${status_line:3}"
    case "$path" in
        dist/*)
            ;;
        *)
            dirty_paths+=("$status_line")
            ;;
    esac
done < <(git status --porcelain)

if [[ "${#dirty_paths[@]}" -gt 0 ]]; then
    echo "Refusing to release with uncommitted non-dist changes:" >&2
    printf '  %s\n' "${dirty_paths[@]}" >&2
    exit 1
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release already exists: $TAG" >&2
    exit 1
fi

required_secrets=(
    APPLE_DEVELOPER_CERTIFICATE_P12_BASE64
    APPLE_DEVELOPER_CERTIFICATE_PASSWORD
    APPLE_KEYCHAIN_PASSWORD
    APPLE_NOTARY_APPLE_ID
    APPLE_NOTARY_TEAM_ID
    APPLE_NOTARY_PASSWORD
    HOMEBREW_TAP_TOKEN
)

secret_names="$(gh secret list --repo "$REPO" | awk '{print $1}')"
missing_secrets=()
for secret_name in "${required_secrets[@]}"; do
    if ! grep -qx "$secret_name" <<<"$secret_names"; then
        missing_secrets+=("$secret_name")
    fi
done

if [[ "${#missing_secrets[@]}" -gt 0 ]]; then
    echo "Missing required GitHub secrets on $REPO:" >&2
    printf '  %s\n' "${missing_secrets[@]}" >&2
    exit 1
fi

tap_repository="$(
    gh variable list --repo "$REPO" | awk '$1 == "HOMEBREW_TAP_REPOSITORY" { print $2 }'
)"
if [[ -z "$tap_repository" ]]; then
    echo "Missing required GitHub variable on $REPO: HOMEBREW_TAP_REPOSITORY" >&2
    exit 1
fi

echo "Creating release $TAG for $REPO at $TARGET."
gh release create "$TAG" \
    --repo "$REPO" \
    --target "$TARGET" \
    --title "$TAG" \
    --notes "$NOTES"

if [[ "$WATCH" != "1" ]]; then
    echo "Release created. Not watching workflow because --no-watch was passed."
    exit 0
fi

echo "Waiting for Release workflow to start."
run_id=""
for _ in {1..30}; do
    run_id="$(
        gh run list \
            --repo "$REPO" \
            --workflow Release \
            --event release \
            --limit 10 \
            --json databaseId,headBranch \
            --jq ".[] | select(.headBranch == \"$TAG\") | .databaseId" \
            | head -n1
    )"
    if [[ -n "$run_id" ]]; then
        break
    fi
    sleep 5
done

if [[ -z "$run_id" ]]; then
    echo "Timed out waiting for the Release workflow to start for $TAG." >&2
    exit 1
fi

gh run watch "$run_id" --repo "$REPO" --exit-status
echo "Release workflow completed for $TAG."
