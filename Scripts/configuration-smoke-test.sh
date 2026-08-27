#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_PATH="${1:-$SCRIPT_DIR/../build/Build/Products/Release/Mouseless.app}"
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mouseless-config-smoke.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT

[[ -d "$APP_PATH" ]] || {
  echo "App bundle not found: $APP_PATH" >&2
  echo "Build it first with ./Scripts/build-and-run.sh, then rerun this script." >&2
  exit 1
}

command -v swiftc >/dev/null || {
  echo "swiftc is required to run the configuration smoke test." >&2
  exit 1
}

swiftc "$SCRIPT_DIR/configuration-smoke-test.swift" -framework AppKit -o "$BUILD_DIR/configuration-smoke-test"

# The helper opens the app after moving the existing config to a recoverable temporary backup.
"$BUILD_DIR/configuration-smoke-test" "$APP_PATH"
