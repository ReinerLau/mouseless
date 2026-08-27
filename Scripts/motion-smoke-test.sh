#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_PATH="${1:-$SCRIPT_DIR/../build/Build/Products/Release/Mouseless.app}"
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mouseless-motion-smoke.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT

[[ -d "$APP_PATH" ]] || {
  echo "App bundle not found: $APP_PATH" >&2
  echo "Build it first with ./Scripts/build-and-run.sh, then rerun this script." >&2
  exit 1
}

command -v swiftc >/dev/null || {
  echo "swiftc is required to run the motion smoke test." >&2
  exit 1
}

open "$APP_PATH"
sleep 1
read -r -p "Confirm Mouseless is running and Permissions says Ready [y/N]: " ready
case "$ready" in
  y | Y | yes | YES) ;;
  *)
    echo "Aborted: establish the stated precondition before running the smoke test." >&2
    exit 1
    ;;
esac
swiftc "$SCRIPT_DIR/motion-smoke-test.swift" -framework AppKit -framework CoreGraphics -o "$BUILD_DIR/motion-smoke-test"
"$BUILD_DIR/motion-smoke-test"
