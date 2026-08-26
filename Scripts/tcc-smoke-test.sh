#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../build/Build/Products/Release" && pwd)/Mouseless.app}"
EXPECTED_IDENTIFIER="com.reinerlau.mouseless"
EXPECTED_IDENTITY="Mouseless Local Development"

[[ -d "$APP_PATH" ]] || { echo "App bundle not found: $APP_PATH" >&2; exit 1; }
codesign --verify --strict --verbose=2 "$APP_PATH"
DETAILS=$(codesign --display --verbose=4 "$APP_PATH" 2>&1)
REQUIREMENTS=$(codesign --display --requirements - "$APP_PATH" 2>&1)
grep -q "Authority=$EXPECTED_IDENTITY" <<<"$DETAILS" || { echo "Unexpected signing identity" >&2; exit 1; }
grep -q "identifier \"$EXPECTED_IDENTIFIER\"" <<<"$REQUIREMENTS" || { echo "Unexpected designated requirement" >&2; exit 1; }
grep -q "runtime" <<<"$DETAILS" || { echo "Hardened Runtime is not enabled" >&2; exit 1; }

# TCC persistence and active event-tap behavior were established by the native
# throwaway prototype at prototype/tcc-signing-spike, commit 83e5f60. Those
# interactive checks remain a manual step because TCC cannot be granted in CI.
echo "Signature smoke test passed. Run the TCC checklist from the prototype on this Mac."
