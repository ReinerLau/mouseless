#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PROJECT="$REPO_ROOT/Mouseless.xcodeproj"
APP="$REPO_ROOT/build/Build/Products/Release/Mouseless.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Mouseless Local Development}"

command -v xcodegen >/dev/null || { echo "xcodegen is required; install it before building Mouseless." >&2; exit 1; }

osascript -e 'tell application id "com.reinerlau.mouseless" to quit' >/dev/null 2>&1 || true
for _ in {1..40}; do
  if ! pgrep -x Mouseless >/dev/null; then break; fi
  sleep 0.25
done
if pgrep -x Mouseless >/dev/null; then
  echo "Could not stop the running Mouseless process before rebuilding." >&2
  exit 1
fi

xcodegen generate --spec "$REPO_ROOT/project.yml" --project "$REPO_ROOT"
xcodebuild -project "$PROJECT" -scheme Mouseless -configuration Release -derivedDataPath "$REPO_ROOT/build" build
"$SCRIPT_DIR/tcc-smoke-test.sh" "$APP"
printf 'Built and signed %s with %s\n' "$APP" "$SIGNING_IDENTITY"
open "$APP"
for _ in {1..20}; do
  if pgrep -x Mouseless >/dev/null; then break; fi
  sleep 0.25
done
APP_PID=$(pgrep -x Mouseless | head -n 1 || true)
if [[ -z "$APP_PID" ]]; then
  echo "Mouseless did not start after the successful build." >&2
  exit 1
fi
APP_PROCESS=$(ps -p "$APP_PID" -o command=)
if [[ "$APP_PROCESS" != "$APP/Contents/MacOS/Mouseless" ]]; then
  echo "The running Mouseless process is not the newly built app: $APP_PROCESS" >&2
  exit 1
fi
APP_STARTED=$(ps -p "$APP_PID" -o lstart=)
printf 'Running %s (PID %s, started %s)\n' "$APP" "$APP_PID" "$APP_STARTED"
