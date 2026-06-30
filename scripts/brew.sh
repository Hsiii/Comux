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
NOTARY_MODE="wait"
FINALIZE_NOTARIZATION_ID=""
APPLE_ID="${COMUX_NOTARY_APPLE_ID:-${APPLE_ID:-}}"
APPLE_TEAM_ID="${COMUX_NOTARY_TEAM_ID:-${APPLE_TEAM_ID:-}}"
APPLE_PASSWORD="${COMUX_NOTARY_PASSWORD:-${APPLE_APP_SPECIFIC_PASSWORD:-}}"
NOTARY_KEYCHAIN_PROFILE="${COMUX_NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_KEYCHAIN="${COMUX_NOTARY_KEYCHAIN:-}"
NOTARY_TIMEOUT_SECONDS="${COMUX_NOTARY_TIMEOUT_SECONDS:-2700}"

usage() {
    cat <<'EOF'
Usage: scripts/brew.sh --version <version> [options]

Options:
  --build-number <value>  CFBundleVersion value. Defaults to the version string.
  --repo <owner/name>     GitHub repository that hosts release archives.
  --homepage <url>        Homepage for the generated cask. Defaults to the repo URL.
  --notarize              Submit the signed app to Apple notary service before packaging.
  --submit-notarization   Submit the signed app and exit after saving the submission ID.
  --finalize-notarization <id>
                          Check an accepted submission, staple, package, and write the cask.

Environment fallbacks:
  GITHUB_REPOSITORY, GITHUB_SERVER_URL, COMUX_VERSION, COMUX_BUILD_NUMBER,
  COMUX_NOTARY_APPLE_ID, COMUX_NOTARY_TEAM_ID, COMUX_NOTARY_PASSWORD,
  COMUX_NOTARY_KEYCHAIN_PROFILE, COMUX_NOTARY_KEYCHAIN,
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
            NOTARY_MODE="wait"
            shift
            ;;
        --submit-notarization)
            NOTARIZE=1
            NOTARY_MODE="submit"
            shift
            ;;
        --finalize-notarization)
            NOTARIZE=1
            NOTARY_MODE="finalize"
            FINALIZE_NOTARIZATION_ID="${2:-}"
            shift 2
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
notary_state_path="${DIST_DIR}/${APP_NAME}-${VERSION}.notary-submission"
download_url="${server_url}/${REPOSITORY}/releases/download/v#{version}/${APP_NAME}-#{version}.zip"

mkdir -p "$DIST_DIR"

if [[ "$NOTARY_MODE" != "finalize" ]]; then
    COMUX_VERSION="$VERSION" \
    COMUX_BUILD_NUMBER="$BUILD_NUMBER" \
    "$ROOT_DIR/scripts/build.sh" >/dev/null
elif [[ ! -d "$ROOT_DIR/.build/apple/${APP_FILENAME}" ]]; then
    echo "Missing built app at $ROOT_DIR/.build/apple/${APP_FILENAME}. Run --submit-notarization first." >&2
    exit 1
fi

rm -f "$archive_path"

if [[ "$NOTARIZE" == "1" ]]; then
    if [[ "$NOTARY_MODE" == "finalize" && -z "$FINALIZE_NOTARIZATION_ID" ]]; then
        echo "--finalize-notarization requires a submission ID." >&2
        exit 1
    fi

    if [[ -z "$NOTARY_KEYCHAIN_PROFILE" && ( -z "$APPLE_ID" || -z "$APPLE_TEAM_ID" || -z "$APPLE_PASSWORD" ) ]]; then
        echo "Notarization requires either COMUX_NOTARY_KEYCHAIN_PROFILE or COMUX_NOTARY_APPLE_ID, COMUX_NOTARY_TEAM_ID, and COMUX_NOTARY_PASSWORD." >&2
        exit 1
    fi

    if ! [[ "$NOTARY_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [[ "$NOTARY_TIMEOUT_SECONDS" -lt 1 ]]; then
        echo "COMUX_NOTARY_TIMEOUT_SECONDS must be a positive integer." >&2
        exit 1
    fi

    notary_auth_args=()
    if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
        notary_auth_args+=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
        if [[ -n "$NOTARY_KEYCHAIN" ]]; then
            notary_auth_args+=(--keychain "$NOTARY_KEYCHAIN")
        fi
    else
        notary_auth_args=(
            --apple-id "$APPLE_ID"
            --team-id "$APPLE_TEAM_ID"
            --password "$APPLE_PASSWORD"
        )
    fi

    if [[ "$NOTARY_MODE" == "submit" || "$NOTARY_MODE" == "wait" ]]; then
        notary_archive_path="${DIST_DIR}/${APP_NAME}-${VERSION}-notary.zip"
        submit_output_path="${DIST_DIR}/${APP_NAME}-${VERSION}.notary-submit.json"
        rm -f "$notary_archive_path" "$submit_output_path"
        xattr -cr "$ROOT_DIR/.build/apple/${APP_FILENAME}"
        find "$ROOT_DIR/.build/apple/${APP_FILENAME}" -name '._*' -delete
        ditto --norsrc -c -k --keepParent "$ROOT_DIR/.build/apple/${APP_FILENAME}" "$notary_archive_path"
    fi

    if [[ "$NOTARY_MODE" == "submit" ]]; then
        echo "Submitting ${notary_archive_path} for notarization without waiting." >&2
        xcrun notarytool submit "$notary_archive_path" \
            "${notary_auth_args[@]}" \
            --no-progress \
            --output-format json > "$submit_output_path"

        submission_id="$(plutil -extract id raw -o - "$submit_output_path")"
        status="$(plutil -extract status raw -o - "$submit_output_path" 2>/dev/null || printf 'Submitted')"
        cat > "$notary_state_path" <<EOF
VERSION=${VERSION}
REPOSITORY=${REPOSITORY}
SUBMISSION_ID=${submission_id}
NOTARY_ARCHIVE=${notary_archive_path}
APP_PATH=$ROOT_DIR/.build/apple/${APP_FILENAME}
EOF
        printf 'notary_submission_id=%s\n' "$submission_id"
        printf 'notary_status=%s\n' "$status"
        printf 'notary_state=%s\n' "$notary_state_path"
        exit 0
    fi

    if [[ "$NOTARY_MODE" == "wait" ]]; then
        echo "Submitting ${notary_archive_path} for notarization with a ${NOTARY_TIMEOUT_SECONDS}s timeout." >&2
        xcrun notarytool submit "$notary_archive_path" \
            "${notary_auth_args[@]}" \
            --wait \
            --timeout "${NOTARY_TIMEOUT_SECONDS}s"
    fi

    if [[ "$NOTARY_MODE" == "finalize" ]]; then
        info_output_path="${DIST_DIR}/${APP_NAME}-${VERSION}.notary-info.json"
        log_output_path="${DIST_DIR}/${APP_NAME}-${VERSION}.notary-log.json"

        xcrun notarytool info "$FINALIZE_NOTARIZATION_ID" \
            "${notary_auth_args[@]}" \
            --no-progress \
            --output-format json > "$info_output_path"
        status="$(plutil -extract status raw -o - "$info_output_path")"
        printf 'notary_submission_id=%s\n' "$FINALIZE_NOTARIZATION_ID"
        printf 'notary_status=%s\n' "$status"

        if [[ "$status" != "Accepted" ]]; then
            if [[ "$status" == "Invalid" || "$status" == "Rejected" ]]; then
                xcrun notarytool log "$FINALIZE_NOTARIZATION_ID" "$log_output_path" \
                    "${notary_auth_args[@]}" || true
                echo "Notarization failed with status ${status}. Log: ${log_output_path}" >&2
                exit 1
            fi
            echo "Notarization is ${status}; rerun finalization later." >&2
            exit 0
        fi
    fi

    xcrun stapler staple "$ROOT_DIR/.build/apple/${APP_FILENAME}"
    if [[ -n "${notary_archive_path:-}" ]]; then
        rm -f "$notary_archive_path"
    fi
fi

xattr -cr "$ROOT_DIR/.build/apple/${APP_FILENAME}"
find "$ROOT_DIR/.build/apple/${APP_FILENAME}" -name '._*' -delete
ditto --norsrc -c -k --keepParent "$ROOT_DIR/.build/apple/${APP_FILENAME}" "$archive_path"

sha256_value="$(shasum -a 256 "$archive_path" | awk '{print $1}')"

cat > "$cask_path" <<EOF
cask "${CASK_TOKEN}" do
  version "${VERSION}"
  sha256 "${sha256_value}"

  url "${download_url}"
  name "${APP_NAME}"
  desc "macOS menu bar app to track and sort Codex account limits"
  homepage "${HOMEPAGE}"
  depends_on macos: :sonoma

  app "${APP_FILENAME}"

  zap trash: [
    "~/.comux",
  ]
end
EOF

printf 'archive=%s\n' "$archive_path"
printf 'sha256=%s\n' "$sha256_value"
printf 'cask=%s\n' "$cask_path"
