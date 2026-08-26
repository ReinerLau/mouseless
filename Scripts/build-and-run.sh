#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PROJECT="$REPO_ROOT/Mouseless.xcodeproj"
APP="$REPO_ROOT/build/Build/Products/Release/Mouseless.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Mouseless Local Development}"

command -v xcodegen >/dev/null || { echo "xcodegen is required; install it before building Mouseless." >&2; exit 1; }
xcodegen generate --spec "$REPO_ROOT/project.yml" --project "$REPO_ROOT"
xcodebuild -project "$PROJECT" -scheme Mouseless -configuration Release -derivedDataPath "$REPO_ROOT/build" build
"$SCRIPT_DIR/tcc-smoke-test.sh" "$APP"
printf 'Built and signed %s with %s\n' "$APP" "$SIGNING_IDENTITY"
open "$APP"
