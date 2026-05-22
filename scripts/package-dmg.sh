#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$BUILD_DIR/dist"
STAGING_DIR="$BUILD_DIR/dmg"
APP_BUILD_DIR="$BUILD_DIR/apple"
APP_NAME="CodexMux"
APP_BUNDLE_PATH="$APP_BUILD_DIR/${APP_NAME}.app"

VERSION=""
VOLUME_NAME="$APP_NAME"

usage() {
    cat <<'EOF'
Usage: scripts/package-dmg.sh [--version <version>] [--volume-name <name>]

Options:
  --version <version>      Include the version in the DMG filename.
  --volume-name <name>     Volume name shown when the DMG is mounted.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --volume-name)
            VOLUME_NAME="${2:-}"
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

if ! command -v hdiutil >/dev/null 2>&1; then
    echo "error: hdiutil is required to build a DMG" >&2
    exit 1
fi

"$ROOT_DIR/scripts/build-app.sh" >/dev/null

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
    echo "error: expected app bundle at $APP_BUNDLE_PATH" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

dmg_name="$APP_NAME"
if [[ -n "$VERSION" ]]; then
    dmg_name="${dmg_name}-${VERSION}"
fi

dmg_path="$DIST_DIR/${dmg_name}.dmg"
temp_dmg_path="$BUILD_DIR/${dmg_name}-temp.dmg"

rm -f "$dmg_path" "$temp_dmg_path"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDRW \
    "$temp_dmg_path" >/dev/null

hdiutil convert "$temp_dmg_path" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$dmg_path" >/dev/null

rm -f "$temp_dmg_path"

printf '%s\n' "$dmg_path"
