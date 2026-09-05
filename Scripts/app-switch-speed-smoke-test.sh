#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keyveer-app-switch-speed.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT

command -v swiftc >/dev/null || {
  echo "swiftc is required to run the app-switch speed smoke test." >&2
  exit 2
}

swiftc "$SCRIPT_DIR/app-switch-speed-smoke-test.swift" \
  -framework AppKit -framework CoreGraphics \
  -o "$BUILD_DIR/app-switch-speed-smoke-test"
"$BUILD_DIR/app-switch-speed-smoke-test"
