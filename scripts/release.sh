#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO=""
TARGET="main"
WATCH=1
NOTES=""
LOCAL_PACKAGE=0
ALLOW_EXISTING=0
DRAFT=0
TAP_DIR=""
SKIP_TAP=0
LOCAL_NOTARY_MODE="submit"
FINALIZE_NOTARIZATION_ID=""

usage() {
    cat <<'EOF'
Usage: scripts/release.sh <version> [options]

Options:
  --repo <owner/name>     GitHub repository to release. Defaults to the current repo.
  --target <ref>          Release target branch or SHA. Defaults to main.
  --notes <text>          Release notes. Defaults to "Comux <version>".
  --draft                 Create a draft GitHub release.
  --local-package         Build, sign, submit notarization locally, and print the resume command.
  --wait-notarization     With --local-package, wait for Apple and publish in one command.
  --finalize-notarization [id]
                          Check an accepted submission, staple, package, upload, and update tap.
  --allow-existing        Replace local assets on an existing published release, or rerun
                          the Release workflow for a published release missing assets.
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
        --draft)
            DRAFT=1
            shift
            ;;
        --local-package)
            LOCAL_PACKAGE=1
            shift
            ;;
        --wait-notarization)
            LOCAL_PACKAGE=1
            LOCAL_NOTARY_MODE="wait"
            shift
            ;;
        --finalize-notarization)
            LOCAL_PACKAGE=1
            LOCAL_NOTARY_MODE="finalize"
            if [[ $# -gt 1 && "${2:-}" != --* ]]; then
                FINALIZE_NOTARIZATION_ID="$2"
                shift 2
            else
                shift
            fi
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

RELEASE_EXISTS=0
RELEASE_IS_DRAFT=0
RELEASE_IS_IMMUTABLE=0
RELEASE_URL=""
REMOTE_TAG_EXISTS=0
REPO_GIT_URL=""

refresh_release_state() {
    local release_metadata

    RELEASE_EXISTS=0
    RELEASE_IS_DRAFT=0
    RELEASE_IS_IMMUTABLE=0
    RELEASE_URL=""

    if release_metadata="$(
        gh release view "$TAG" \
            --repo "$REPO" \
            --json isDraft,isImmutable,url \
            --jq '[.isDraft, .isImmutable, .url] | @tsv' \
            2>/dev/null
    )"; then
        RELEASE_EXISTS=1
        IFS=$'\t' read -r RELEASE_IS_DRAFT RELEASE_IS_IMMUTABLE RELEASE_URL <<<"$release_metadata"
    else
        release_metadata="$(
            gh release list \
                --repo "$REPO" \
                --limit 200 \
                --json tagName,isDraft,isImmutable \
                --jq ".[] | select(.tagName == \"$TAG\") | [.isDraft, .isImmutable, \"\"] | @tsv" \
                2>/dev/null || true
        )"
        if [[ -n "$release_metadata" ]]; then
            RELEASE_EXISTS=1
            IFS=$'\t' read -r RELEASE_IS_DRAFT RELEASE_IS_IMMUTABLE RELEASE_URL <<<"$release_metadata"
        fi
    fi
}

release_asset_count() {
    gh release view "$TAG" \
        --repo "$REPO" \
        --json assets \
        --jq "[.assets[].name] | map(select(. == \"comux-${VERSION}.zip\" or . == \"comux.rb\")) | length" \
        2>/dev/null || printf '0\n'
}

resolve_repo_git_url() {
    if [[ -z "$REPO_GIT_URL" ]]; then
        REPO_GIT_URL="$(gh repo view "$REPO" --json url --jq .url)"
    fi
}

refresh_tag_state() {
    local remote_tag_output

    resolve_repo_git_url
    REMOTE_TAG_EXISTS=0

    remote_tag_output="$(
        git ls-remote --tags "$REPO_GIT_URL" "refs/tags/$TAG" 2>/dev/null \
            | awk -v ref="refs/tags/$TAG" '$2 == ref { print $1; exit }'
    )"
    if [[ -n "$remote_tag_output" ]]; then
        REMOTE_TAG_EXISTS=1
    fi
}

ensure_release_tag_ready() {
    local local_tag_target_sha
    local target_sha

    refresh_tag_state

    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        local_tag_target_sha="$(git rev-parse -q --verify "refs/tags/$TAG^{}" 2>/dev/null || true)"

        if [[ "$REMOTE_TAG_EXISTS" == "1" ]]; then
            echo "Using existing remote tag $TAG."
            return
        fi

        target_sha="$(git rev-parse -q --verify "$TARGET^{commit}" 2>/dev/null || true)"
        if [[ -n "$target_sha" && -n "$local_tag_target_sha" && "$TARGET" != "main" && "$target_sha" != "$local_tag_target_sha" ]]; then
            echo "Local tag $TAG points at $local_tag_target_sha, but --target resolves to $target_sha." >&2
            echo "Push the intended tag manually or pass the matching --target." >&2
            exit 1
        fi

        echo "Pushing existing local tag $TAG to $REPO."
        git push "$REPO_GIT_URL" "refs/tags/$TAG:refs/tags/$TAG"
        REMOTE_TAG_EXISTS=1
        return
    fi

    if [[ "$REMOTE_TAG_EXISTS" == "1" ]]; then
        echo "Using existing remote tag $TAG."
    fi
}

release_target_args() {
    if [[ "$REMOTE_TAG_EXISTS" == "1" ]]; then
        printf '%s\n' "--verify-tag"
    else
        printf '%s\n' "--target"
        printf '%s\n' "$TARGET"
    fi
}

create_release() {
    local -a release_create_command

    ensure_release_tag_ready

    release_create_command=(
        gh release create "$TAG"
        --repo "$REPO"
        --title "$TAG"
        --notes "$NOTES"
    )
    while IFS= read -r arg; do
        release_create_command+=("$arg")
    done < <(release_target_args)
    if [[ "$DRAFT" == "1" ]]; then
        release_create_command+=(--draft)
    fi
    release_create_command+=("$@")

    "${release_create_command[@]}"
    refresh_release_state
}

edit_existing_draft_release() {
    local publish="$1"
    local -a release_edit_command

    ensure_release_tag_ready

    release_edit_command=(
        gh release edit "$TAG"
        --repo "$REPO"
        --title "$TAG"
        --notes "$NOTES"
    )
    while IFS= read -r arg; do
        release_edit_command+=("$arg")
    done < <(release_target_args)

    if [[ "$publish" == "1" ]]; then
        release_edit_command+=(--draft=false)
    else
        release_edit_command+=(--draft)
    fi

    "${release_edit_command[@]}"
    refresh_release_state
}

wait_for_release_workflow() {
    local release_started_at="$1"
    local event_name="$2"
    local run_id=""

    if [[ "$WATCH" != "1" ]]; then
        echo "Release action completed. Not watching workflow because --no-watch was passed."
        return
    fi

    echo "Waiting for Release workflow to start."
    for _ in {1..30}; do
        run_id="$(
            gh run list \
                --repo "$REPO" \
                --workflow Release \
                --event "$event_name" \
                --limit 10 \
                --json databaseId,headBranch,createdAt \
                --jq ".[] | select(.createdAt >= \"$release_started_at\" and (.headBranch == \"$TAG\" or \"$event_name\" == \"workflow_dispatch\")) | .databaseId" \
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
    report_remote_release_result "$run_id"
}

dispatch_existing_release_workflow() {
    local release_started_at

    release_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    gh workflow run Release \
        --repo "$REPO" \
        -f version="$VERSION" \
        -f repository="$REPO"
    wait_for_release_workflow "$release_started_at" "workflow_dispatch"
}

refresh_release_state

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

validate_remote_release_configuration() {
    local secret_names
    local tap_repository
    local -a required_secrets
    local -a missing_secrets

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
}

report_remote_release_result() {
    local run_id="$1"
    local asset_count
    local notary_submission_id

    asset_count="$(
        gh release view "$TAG" \
            --repo "$REPO" \
            --json assets \
            --jq "[.assets[].name] | map(select(. == \"comux-${VERSION}.zip\" or . == \"comux.rb\")) | length"
    )"

    if [[ "$asset_count" == "2" ]]; then
        echo "Release workflow completed for $TAG."
        return
    fi

    notary_submission_id="$(
        gh run view "$run_id" --repo "$REPO" --log 2>/dev/null \
            | sed -n 's/^.*notary_submission_id=\([^[:space:]]*\).*$/\1/p' \
            | tail -n1 || true
    )"

    echo "Release workflow completed for $TAG, but release assets are not published yet."
    if [[ -n "$notary_submission_id" ]]; then
        echo "Notarization submission $notary_submission_id is pending or not finalized."
        echo "After Apple reports Accepted, finalize with:"
        echo "  gh workflow run Release -f version=$VERSION -f notarization_submission_id=$notary_submission_id -f notarization_run_id=$run_id"
    else
        echo "Check the Release workflow summary for notarization finalization details."
    fi
}

if [[ "$LOCAL_PACKAGE" == "1" ]]; then
    output_file=""
    release_keychain_dir=""
    release_keychain_path=""
    original_keychains_file="$(mktemp)"
    security list-keychains -d user > "$original_keychains_file"
    cleanup_local_release() {
        if [[ -n "$output_file" ]]; then
            rm -f "$output_file"
        fi
        if [[ -n "$release_keychain_path" ]]; then
            security delete-keychain "$release_keychain_path" >/dev/null 2>&1 || true
        fi
        if [[ -s "$original_keychains_file" ]]; then
            original_keychains=()
            while IFS= read -r keychain_path; do
                original_keychains+=("$keychain_path")
            done < <(sed 's/^ *"//; s/"$//' "$original_keychains_file")
            if [[ "${#original_keychains[@]}" -gt 0 ]]; then
                security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1 || true
            fi
        fi
        rm -f "$original_keychains_file"
        if [[ -n "$release_keychain_dir" ]]; then
            rm -rf "$release_keychain_dir"
        fi
    }
    trap cleanup_local_release EXIT

    if [[ "$LOCAL_NOTARY_MODE" != "finalize" ]]; then
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
    fi

    release_keychain_dir="$(mktemp -d)"
    release_keychain_path="$release_keychain_dir/comux-release.keychain-db"
    release_keychain_password="$(uuidgen)-$(uuidgen)"
    notary_profile="${COMUX_RELEASE_NOTARY_PROFILE:-comux-release}"
    original_keychains_for_search=()
    while IFS= read -r keychain_path; do
        original_keychains_for_search+=("$keychain_path")
    done < <(sed 's/^ *"//; s/"$//' "$original_keychains_file")

    security create-keychain -p "$release_keychain_password" "$release_keychain_path"
    security set-keychain-settings -lut 21600 "$release_keychain_path"
    security unlock-keychain -p "$release_keychain_password" "$release_keychain_path"
    security list-keychains -d user -s "$release_keychain_path" "${original_keychains_for_search[@]}"

    if [[ "$LOCAL_NOTARY_MODE" != "finalize" && -z "${COMUX_CODE_SIGN_IDENTITY:-}" ]]; then
        certificate_path="${COMUX_DEVELOPER_CERTIFICATE_P12_PATH:-$HOME/.comux-release-cert/developer-id-application.p12}"
        certificate_password_file="${COMUX_DEVELOPER_CERTIFICATE_PASSWORD_FILE:-$HOME/.comux-release-cert/p12-password.txt}"
        certificate_password="${COMUX_DEVELOPER_CERTIFICATE_PASSWORD:-}"

        if [[ -z "$certificate_password" && -f "$certificate_password_file" ]]; then
            certificate_password="$(<"$certificate_password_file")"
        fi

        if [[ -f "$certificate_path" && -n "$certificate_password" ]]; then
            security import "$certificate_path" \
                -P "$certificate_password" \
                -A \
                -k "$release_keychain_path"
            security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$release_keychain_password" "$release_keychain_path"
        fi

        COMUX_CODE_SIGN_IDENTITY="$(
            security find-identity -v -p codesigning \
                | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
                | head -n1
        )"
        export COMUX_CODE_SIGN_IDENTITY
    fi

    if [[ "$LOCAL_NOTARY_MODE" != "finalize" && -z "${COMUX_CODE_SIGN_IDENTITY:-}" ]]; then
        echo "No Developer ID Application signing identity found." >&2
        security find-identity -v -p codesigning >&2
        exit 1
    fi

    output_file="$(mktemp)"

    if [[ -n "${COMUX_NOTARY_APPLE_ID:-}" && -n "${COMUX_NOTARY_TEAM_ID:-}" && -n "${COMUX_NOTARY_PASSWORD:-}" ]]; then
        xcrun notarytool store-credentials "$notary_profile" \
            --apple-id "$COMUX_NOTARY_APPLE_ID" \
            --team-id "$COMUX_NOTARY_TEAM_ID" \
            --password "$COMUX_NOTARY_PASSWORD"
    fi

    brew_args=(
        --version "$VERSION"
        --repo "$REPO"
    )
    case "$LOCAL_NOTARY_MODE" in
        submit)
            brew_args+=(--submit-notarization)
            ;;
        wait)
            brew_args+=(--notarize)
            ;;
        finalize)
            if [[ -z "$FINALIZE_NOTARIZATION_ID" ]]; then
                notary_state_path="$ROOT_DIR/.build/dist/comux-${VERSION}.notary-submission"
                if [[ -f "$notary_state_path" ]]; then
                    FINALIZE_NOTARIZATION_ID="$(
                        sed -n 's/^SUBMISSION_ID=//p' "$notary_state_path" | head -n1
                    )"
                fi
            fi
            if [[ -z "$FINALIZE_NOTARIZATION_ID" ]]; then
                echo "No notarization submission ID found." >&2
                echo "Pass --finalize-notarization <submission-id> or run --local-package first." >&2
                exit 1
            fi
            brew_args+=(--finalize-notarization "$FINALIZE_NOTARIZATION_ID")
            ;;
        *)
            echo "Unknown local notarization mode: $LOCAL_NOTARY_MODE" >&2
            exit 1
            ;;
    esac

    echo "Running local release packaging for $TAG (${LOCAL_NOTARY_MODE})."
    COMUX_NOTARY_KEYCHAIN_PROFILE="$notary_profile" \
    "$ROOT_DIR/scripts/brew.sh" "${brew_args[@]}" | tee "$output_file"

    archive_path=""
    cask_path=""
    notary_submission_id=""
    notary_status=""
    notary_state=""
    while IFS= read -r line; do
        case "$line" in
            archive=*)
                archive_path="${line#archive=}"
                ;;
            cask=*)
                cask_path="${line#cask=}"
                ;;
            notary_submission_id=*)
                notary_submission_id="${line#notary_submission_id=}"
                ;;
            notary_status=*)
                notary_status="${line#notary_status=}"
                ;;
            notary_state=*)
                notary_state="${line#notary_state=}"
                ;;
        esac
    done < "$output_file"

    if [[ -z "$archive_path" || -z "$cask_path" ]]; then
        if [[ -n "$notary_submission_id" ]]; then
            echo "Notarization submission $notary_submission_id is ${notary_status:-submitted}."
            if [[ -n "$notary_state" ]]; then
                echo "Saved notarization state: $notary_state"
            fi
            echo "Finalize later with:"
            echo "  scripts/release.sh $VERSION --finalize-notarization $notary_submission_id --allow-existing --no-watch"
            exit 0
        fi
        echo "Failed to generate release archive or cask." >&2
        exit 1
    fi

    refresh_release_state
    should_wait_for_release_event=0
    release_started_at=""

    if [[ "$RELEASE_EXISTS" == "1" ]]; then
        if [[ "$RELEASE_IS_DRAFT" == "true" ]]; then
            echo "Updating existing draft release $TAG with local assets."
            edit_existing_draft_release 0
            gh release upload "$TAG" \
                --repo "$REPO" \
                "$archive_path" \
                "$cask_path" \
                --clobber

            if [[ "$DRAFT" != "1" ]]; then
                echo "Publishing existing draft release $TAG."
                release_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
                edit_existing_draft_release 1
                should_wait_for_release_event=1
            fi
        else
            if [[ "$RELEASE_IS_IMMUTABLE" == "true" ]]; then
                echo "Release $TAG is immutable; assets cannot be replaced." >&2
                exit 1
            fi

            if [[ "$ALLOW_EXISTING" != "1" ]]; then
                echo "Published release already exists: $TAG" >&2
                echo "Pass --allow-existing to replace its local release assets." >&2
                exit 1
            fi

            echo "Uploading local assets to existing published release $TAG."
            gh release upload "$TAG" \
                --repo "$REPO" \
                "$archive_path" \
                "$cask_path" \
                --clobber
        fi
    else
        echo "Creating release $TAG for $REPO at $TARGET with local assets."
        release_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        create_release "$archive_path" "$cask_path"
        if [[ "$DRAFT" != "1" ]]; then
            should_wait_for_release_event=1
        fi
    fi

    if [[ "$DRAFT" == "1" ]]; then
        echo "Draft release is ready. Publish $TAG on GitHub to trigger the Release workflow."
        exit 0
    fi

    publish_local_tap "$cask_path"

    if [[ "$should_wait_for_release_event" == "1" ]]; then
        wait_for_release_workflow "$release_started_at" "release"
    fi
    exit 0
fi

if [[ "$RELEASE_EXISTS" == "1" ]]; then
    if [[ "$RELEASE_IS_DRAFT" == "true" ]]; then
        if [[ "$DRAFT" == "1" ]]; then
            echo "Draft release already exists for $TAG; updating title, notes, and target."
            edit_existing_draft_release 0
            echo "Draft release is ready. Publish $TAG on GitHub to trigger the Release workflow."
            exit 0
        fi

        validate_remote_release_configuration

        echo "Publishing existing draft release $TAG."
        release_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        edit_existing_draft_release 1
        wait_for_release_workflow "$release_started_at" "release"
        exit 0
    fi

    if [[ "$DRAFT" == "1" ]]; then
        echo "Published release already exists for $TAG; cannot recreate it as a draft." >&2
        exit 1
    fi

    asset_count="$(release_asset_count)"
    if [[ "$asset_count" == "2" ]]; then
        echo "Published release $TAG already has release assets."
        exit 0
    fi

    if [[ "$ALLOW_EXISTING" != "1" ]]; then
        echo "Published release $TAG exists but is missing release assets." >&2
        echo "Pass --allow-existing to rerun the Release workflow for this version." >&2
        exit 1
    fi

    validate_remote_release_configuration

    echo "Published release $TAG exists but is missing assets; dispatching Release workflow."
    dispatch_existing_release_workflow
    exit 0
fi

validate_remote_release_configuration

echo "Creating release $TAG for $REPO at $TARGET."
release_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
create_release

if [[ "$DRAFT" == "1" ]]; then
    echo "Draft release created. Publish $TAG on GitHub to trigger the Release workflow."
    exit 0
fi

wait_for_release_workflow "$release_started_at" "release"
