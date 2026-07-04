#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUMP=""
VERSION=""
ASSUME_YES=0
DRY_RUN=0
DRAFT=1
release_args=()

usage() {
    cat <<'EOF'
Usage: scripts/release-cli.sh [options] [-- <release-options>]

Pick the next Comux release version, then run scripts/release.sh.

Options:
  --bump <major|minor|patch>
                          Select the version bump without prompting.
  --version <version>     Release an explicit semantic version.
  --draft                 Create a draft GitHub release. This is the default.
  --publish               Publish the GitHub release immediately.
  --yes, -y               Skip confirmation prompts.
  --dry-run               Print the release command without running it.
  --help, -h              Show this help.

Any options after -- are passed to scripts/release.sh.

Examples:
  make release
  make release ARGS="--bump minor"
  make release ARGS="--publish -- --local-package"
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bump)
            BUMP="${2:-}"
            shift 2
            ;;
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --draft)
            DRAFT=1
            shift
            ;;
        --publish)
            DRAFT=0
            shift
            ;;
        --yes|-y)
            ASSUME_YES=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            release_args+=("$@")
            break
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

cd "$ROOT_DIR"

latest_version() {
    local tag
    tag="$(
        git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname \
            | sed -nE 's/^v([0-9]+[.][0-9]+[.][0-9]+)$/\1/p' \
            | head -n1
    )"
    printf '%s\n' "${tag:-0.0.0}"
}

bump_version() {
    local version="$1"
    local bump="$2"

    if [[ ! "$version" =~ ^([0-9]+)[.]([0-9]+)[.]([0-9]+)$ ]]; then
        echo "Cannot bump invalid base version: $version" >&2
        exit 1
    fi

    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"

    case "$bump" in
        major)
            printf '%s.0.0\n' "$((major + 1))"
            ;;
        minor)
            printf '%s.%s.0\n' "$major" "$((minor + 1))"
            ;;
        patch)
            printf '%s.%s.%s\n' "$major" "$minor" "$((patch + 1))"
            ;;
        *)
            echo "Invalid bump: $bump" >&2
            echo "Use major, minor, or patch." >&2
            exit 1
            ;;
    esac
}

validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^v?[0-9]+[.][0-9]+[.][0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
        echo "Invalid version: $version" >&2
        echo "Use a semantic version like 0.1.0." >&2
        exit 1
    fi
}

prompt_version() {
    local current="$1"
    local patch_version minor_version major_version choice custom_version

    patch_version="$(bump_version "$current" patch)"
    minor_version="$(bump_version "$current" minor)"
    major_version="$(bump_version "$current" major)"

    echo "Latest release: v$current" >&2
    echo "Select next release:" >&2
    echo "  1) patch  v$patch_version" >&2
    echo "  2) minor  v$minor_version" >&2
    echo "  3) major  v$major_version" >&2
    echo "  4) custom" >&2
    printf "Choice [1]: " >&2
    read -r choice

    case "${choice:-1}" in
        1|patch)
            printf '%s\n' "$patch_version"
            ;;
        2|minor)
            printf '%s\n' "$minor_version"
            ;;
        3|major)
            printf '%s\n' "$major_version"
            ;;
        4|custom)
            printf "Version: " >&2
            read -r custom_version
            validate_version "$custom_version"
            printf '%s\n' "${custom_version#v}"
            ;;
        *)
            echo "Invalid choice: $choice" >&2
            exit 1
            ;;
    esac
}

current_version="$(latest_version)"

if [[ -n "$VERSION" && -n "$BUMP" ]]; then
    echo "Use either --version or --bump, not both." >&2
    exit 1
fi

if [[ -n "$VERSION" ]]; then
    validate_version "$VERSION"
    selected_version="${VERSION#v}"
elif [[ -n "$BUMP" ]]; then
    selected_version="$(bump_version "$current_version" "$BUMP")"
else
    selected_version="$(prompt_version "$current_version")"
fi

command_args=("$ROOT_DIR/scripts/release.sh" "$selected_version")
if [[ "$DRAFT" == "1" ]]; then
    command_args+=(--draft)
fi
if [[ "${#release_args[@]}" -gt 0 ]]; then
    command_args+=("${release_args[@]}")
fi

if [[ "$DRY_RUN" == "1" ]]; then
    printf 'Would run:'
    printf ' %q' "${command_args[@]}"
    printf '\n'
    exit 0
fi

if [[ "$ASSUME_YES" != "1" ]]; then
    if [[ "$DRAFT" == "1" ]]; then
        printf "Create draft release v%s? [Y/n] " "$selected_version"
    else
        printf "Create published release v%s? [y/N] " "$selected_version"
    fi

    read -r confirmation
    case "$confirmation" in
        y|Y|yes|YES)
            ;;
        "")
            if [[ "$DRAFT" != "1" ]]; then
                echo "Release canceled."
                exit 0
            fi
            ;;
        *)
            echo "Release canceled."
            exit 0
            ;;
    esac
fi

exec "${command_args[@]}"
