#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO=""
TARGET="main"
WATCH=1
NOTES=""
LOCAL_PACKAGE=0
ALLOW_EXISTING=0
TAP_DIR=""
SKIP_TAP=0

usage() {
    cat <<'EOF'
Usage: scripts/release.sh <version> [options]

Options:
  --repo <owner/name>     GitHub repository to release. Defaults to the current repo.
  --target <ref>          Release target branch or SHA. Defaults to main.
  --notes <text>          Release notes. Defaults to "Comux <version>".
  --local-package         Build, sign, notarize, package, and upload assets locally.
  --allow-existing        Upload local assets to an existing release instead of failing.
  --tap-dir <path>        Local Homebrew tap checkout. Defaults to ../homebrew-tap when present.
  --skip-tap              Do not update the local Homebrew tap checkout.
  --no-watch              Create the release without waiting for the workflow.
  --help, -h              Show this help.

Examples:
  scripts/release.sh 0.1.0
  scripts/release.sh 0.1.0 --local-package
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
        --local-package)
            LOCAL_PACKAGE=1
            shift
            ;;
        --allow-existing)
            ALLOW_EXISTING=1
            shift
            ;;
        --tap-dir)
            TAP_DIR="${2:-}"
            shift 2
            ;;
        --skip-tap)
            SKIP_TAP=1
            shift
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

if [[ -z "$TAP_DIR" && -d "$ROOT_DIR/../homebrew-tap/.git" ]]; then
    TAP_DIR="$ROOT_DIR/../homebrew-tap"
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

release_exists=0
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    release_exists=1
fi

publish_local_tap() {
    local cask_path="$1"

    if [[ "$SKIP_TAP" == "1" ]]; then
        return
    fi

    if [[ -z "$TAP_DIR" ]]; then
        echo "No local Homebrew tap checkout found; skipping local tap update." >&2
        return
    fi

    if [[ ! -d "$TAP_DIR/.git" ]]; then
        echo "Homebrew tap path is not a git checkout: $TAP_DIR" >&2
        exit 1
    fi

    if [[ -n "$(git -C "$TAP_DIR" status --porcelain)" ]]; then
        echo "Refusing to update dirty Homebrew tap checkout: $TAP_DIR" >&2
        git -C "$TAP_DIR" status --short >&2
        exit 1
    fi

    mkdir -p "$TAP_DIR/Casks"
    cp "$cask_path" "$TAP_DIR/Casks/comux.rb"

    if git -C "$TAP_DIR" diff --quiet -- Casks/comux.rb; then
        echo "Homebrew tap is already up to date."
        return
    fi

    git -C "$TAP_DIR" add Casks/comux.rb
    git -C "$TAP_DIR" commit -m "chore: update comux to $TAG"
    git -C "$TAP_DIR" push origin HEAD
}

if [[ "$LOCAL_PACKAGE" == "1" ]]; then
    output_file=""
    release_keychain_dir=""
    release_keychain_path=""
    cleanup_local_release() {
        if [[ -n "$output_file" ]]; then
            rm -f "$output_file"
        fi
        if [[ -n "$release_keychain_path" ]]; then
            security delete-keychain "$release_keychain_path" >/dev/null 2>&1 || true
        fi
        if [[ -n "$release_keychain_dir" ]]; then
            rm -rf "$release_keychain_dir"
        fi
    }
    trap cleanup_local_release EXIT

    required_local_env=(
        COMUX_NOTARY_APPLE_ID
        COMUX_NOTARY_TEAM_ID
        COMUX_NOTARY_PASSWORD
    )
    missing_local_env=()
    for env_name in "${required_local_env[@]}"; do
        if [[ -z "${!env_name:-}" ]]; then
            missing_local_env+=("$env_name")
        fi
    done

    if [[ "${#missing_local_env[@]}" -gt 0 ]]; then
        echo "Missing required local notarization environment variables:" >&2
        printf '  %s\n' "${missing_local_env[@]}" >&2
        exit 1
    fi

    if [[ -z "${COMUX_CODE_SIGN_IDENTITY:-}" ]]; then
        certificate_path="${COMUX_DEVELOPER_CERTIFICATE_P12_PATH:-$HOME/.comux-release-cert/developer-id-application.p12}"
        certificate_password_file="${COMUX_DEVELOPER_CERTIFICATE_PASSWORD_FILE:-$HOME/.comux-release-cert/p12-password.txt}"
        certificate_password="${COMUX_DEVELOPER_CERTIFICATE_PASSWORD:-}"

        if [[ -z "$certificate_password" && -f "$certificate_password_file" ]]; then
            certificate_password="$(<"$certificate_password_file")"
        fi

        if [[ -f "$certificate_path" && -n "$certificate_password" ]]; then
            release_keychain_dir="$(mktemp -d)"
            release_keychain_path="$release_keychain_dir/comux-release.keychain-db"
            release_keychain_password="$(uuidgen)-$(uuidgen)"

            security create-keychain -p "$release_keychain_password" "$release_keychain_path"
            security set-keychain-settings -lut 21600 "$release_keychain_path"
            security unlock-keychain -p "$release_keychain_password" "$release_keychain_path"
            security import "$certificate_path" \
                -P "$certificate_password" \
                -A \
                -k "$release_keychain_path"
            security list-keychains -d user -s "$release_keychain_path"
            security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$release_keychain_password" "$release_keychain_path"
        fi

        COMUX_CODE_SIGN_IDENTITY="$(
            security find-identity -v -p codesigning \
                | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
                | head -n1
        )"
        export COMUX_CODE_SIGN_IDENTITY
    fi

    if [[ -z "${COMUX_CODE_SIGN_IDENTITY:-}" ]]; then
        echo "No Developer ID Application signing identity found." >&2
        security find-identity -v -p codesigning >&2
        exit 1
    fi

    output_file="$(mktemp)"

    echo "Building, signing, and notarizing $TAG locally."
    "$ROOT_DIR/scripts/brew.sh" \
        --version "$VERSION" \
        --repo "$REPO" \
        --notarize | tee "$output_file"

    archive_path=""
    cask_path=""
    while IFS= read -r line; do
        case "$line" in
            archive=*)
                archive_path="${line#archive=}"
                ;;
            cask=*)
                cask_path="${line#cask=}"
                ;;
        esac
    done < "$output_file"

    if [[ -z "$archive_path" || -z "$cask_path" ]]; then
        echo "Failed to generate release archive or cask." >&2
        exit 1
    fi

    if [[ "$release_exists" == "1" ]]; then
        if [[ "$ALLOW_EXISTING" != "1" ]]; then
            echo "Release already exists: $TAG" >&2
            echo "Pass --allow-existing to upload local assets to it." >&2
            exit 1
        fi
        echo "Uploading local assets to existing release $TAG."
        gh release upload "$TAG" \
            --repo "$REPO" \
            "$archive_path" \
            "$cask_path" \
            --clobber
    else
        echo "Creating release $TAG for $REPO at $TARGET with local assets."
        release_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        gh release create "$TAG" \
            --repo "$REPO" \
            --target "$TARGET" \
            --title "$TAG" \
            --notes "$NOTES" \
            "$archive_path" \
            "$cask_path"
    fi

    publish_local_tap "$cask_path"

    if [[ "$WATCH" != "1" || "$release_exists" == "1" ]]; then
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
                --json databaseId,headBranch,createdAt \
                --jq ".[] | select(.headBranch == \"$TAG\" and .createdAt >= \"$release_started_at\") | .databaseId" \
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
    exit 0
fi

if [[ "$release_exists" == "1" ]]; then
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
release_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
            --json databaseId,headBranch,createdAt \
            --jq ".[] | select(.headBranch == \"$TAG\" and .createdAt >= \"$release_started_at\") | .databaseId" \
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
