#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

output_path="${1:-assets/demo.png}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/comux-demo-mockup.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

swiftc \
  src/Model.swift \
  src/Format.swift \
  src/Card.swift \
  tools/DemoMockup.swift \
  -o "$build_dir/comux-demo-mockup"

"$build_dir/comux-demo-mockup" "$output_path"
