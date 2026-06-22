#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/.build/dist"
APP_NAME="comux"
APP_FILENAME="${APP_NAME}.app"
CASK_TOKEN="comux"

VERSION=""
BUILD_NUMBER=""
REPOSITORY=""
HOMEPAGE=""
NOTARIZE=0
APPLE_ID="${COMUX_NOTARY_APPLE_ID:-${APPLE_ID:-}}"
APPLE_TEAM_ID="${COMUX_NOTARY_TEAM_ID:-${APPLE_TEAM_ID:-}}"
APPLE_PASSWORD="${COMUX_NOTARY_PASSWORD:-${APPLE_APP_SPECIFIC_PASSWORD:-}}"
NOTARY_TIMEOUT_SECONDS="${COMUX_NOTARY_TIMEOUT_SECONDS:-2700}"

usage() {
    cat <<'EOF'
Usage: scripts/brew.sh --version <version> [options]

Options:
  --build-number <value>  CFBundleVersion value. Defaults to the version string.
  --repo <owner/name>     GitHub repository that hosts release archives.
  --homepage <url>        Homepage for the generated cask. Defaults to the repo URL.
  --notarize              Submit the signed app to Apple notary service before packaging.

Environment fallbacks:
  GITHUB_REPOSITORY, GITHUB_SERVER_URL, COMUX_VERSION, COMUX_BUILD_NUMBER,
  COMUX_NOTARY_APPLE_ID, COMUX_NOTARY_TEAM_ID, COMUX_NOTARY_PASSWORD,
  COMUX_NOTARY_TIMEOUT_SECONDS
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --build-number)
            BUILD_NUMBER="${2:-}"
            shift 2
            ;;
        --repo)
            REPOSITORY="${2:-}"
            shift 2
            ;;
        --homepage)
            HOMEPAGE="${2:-}"
            shift 2
            ;;
        --notarize)
            NOTARIZE=1
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

if [[ -z "$VERSION" ]]; then
    VERSION="${COMUX_VERSION:-}"
fi

if [[ -z "$VERSION" ]]; then
    echo "--version is required" >&2
    exit 1
fi

if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="${COMUX_BUILD_NUMBER:-$VERSION}"
fi

if [[ -z "$REPOSITORY" ]]; then
    REPOSITORY="${GITHUB_REPOSITORY:-}"
fi

if [[ -z "$REPOSITORY" ]]; then
    origin_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$origin_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
        REPOSITORY="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
fi

if [[ -z "$REPOSITORY" ]]; then
    echo "Unable to determine GitHub repository. Pass --repo owner/name." >&2
    exit 1
fi

server_url="${GITHUB_SERVER_URL:-https://github.com}"

if [[ -z "$HOMEPAGE" ]]; then
    HOMEPAGE="${server_url}/${REPOSITORY}"
fi

archive_name="${APP_NAME}-${VERSION}.zip"
archive_path="${DIST_DIR}/${archive_name}"
cask_path="${DIST_DIR}/${CASK_TOKEN}.rb"
download_url="${server_url}/${REPOSITORY}/releases/download/v${VERSION}/${archive_name}"

mkdir -p "$DIST_DIR"

COMUX_VERSION="$VERSION" \
COMUX_BUILD_NUMBER="$BUILD_NUMBER" \
"$ROOT_DIR/scripts/build.sh" >/dev/null

rm -f "$archive_path"

if [[ "$NOTARIZE" == "1" ]]; then
    if [[ -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_PASSWORD" ]]; then
        echo "Notarization requires COMUX_NOTARY_APPLE_ID, COMUX_NOTARY_TEAM_ID, and COMUX_NOTARY_PASSWORD." >&2
        exit 1
    fi

    if ! [[ "$NOTARY_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [[ "$NOTARY_TIMEOUT_SECONDS" -lt 1 ]]; then
        echo "COMUX_NOTARY_TIMEOUT_SECONDS must be a positive integer." >&2
        exit 1
    fi

    notary_archive_path="${DIST_DIR}/${APP_NAME}-${VERSION}-notary.zip"
    rm -f "$notary_archive_path"
    ditto -c -k --keepParent "$ROOT_DIR/.build/apple/${APP_FILENAME}" "$notary_archive_path"

    echo "Submitting ${notary_archive_path} for notarization with a ${NOTARY_TIMEOUT_SECONDS}s timeout." >&2
    xcrun notarytool submit "$notary_archive_path" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_PASSWORD" \
        --wait &
    notary_pid="$!"

    notary_deadline=$((SECONDS + NOTARY_TIMEOUT_SECONDS))
    while kill -0 "$notary_pid" 2>/dev/null; do
        if [[ "$SECONDS" -ge "$notary_deadline" ]]; then
            echo "Timed out waiting for notarization after ${NOTARY_TIMEOUT_SECONDS}s." >&2
            echo "Set COMUX_NOTARY_TIMEOUT_SECONDS to a larger value if Apple notary service is delayed." >&2
            kill "$notary_pid" 2>/dev/null || true
            wait "$notary_pid" 2>/dev/null || true
            exit 1
        fi
        sleep 15
    done

    wait "$notary_pid"

    xcrun stapler staple "$ROOT_DIR/.build/apple/${APP_FILENAME}"
    rm -f "$notary_archive_path"
fi

ditto -c -k --keepParent "$ROOT_DIR/.build/apple/${APP_FILENAME}" "$archive_path"

sha256_value="$(shasum -a 256 "$archive_path" | awk '{print $1}')"

cat > "$cask_path" <<EOF
cask "${CASK_TOKEN}" do
  version "${VERSION}"
  sha256 "${sha256_value}"

  url "${download_url}"
  name "${APP_NAME}"
  desc "macOS menu bar app to track and sort Codex account limits"
  homepage "${HOMEPAGE}"
  depends_on macos: ">= :sonoma"

  app "${APP_FILENAME}"

  zap trash: [
    "~/.comux",
  ]
end
EOF

printf 'archive=%s\n' "$archive_path"
printf 'sha256=%s\n' "$sha256_value"
printf 'cask=%s\n' "$cask_path"
