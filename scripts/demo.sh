#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

output_path="${1:-assets/demo.png}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/comux-demo-mockup.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

swiftc \
  src/Model.swift \
  src/AccountIdentity.swift \
  src/AccountSnapshotMerger.swift \
  src/UsagePayloadParser.swift \
  src/WorkspaceLabelResolver.swift \
  src/SystemRefreshErrorPolicy.swift \
  src/Path.swift \
  src/Persistence.swift \
  src/Store.swift \
  src/Pulse.swift \
  src/Format.swift \
  src/Card.swift \
  src/Menu.swift \
  src/LaunchAtLogin.swift \
  src/Resources.swift \
  tools/DemoMockup.swift \
  -lsqlite3 \
  -o "$build_dir/comux-demo-mockup"

"$build_dir/comux-demo-mockup" "$output_path"
