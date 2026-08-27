#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../build/Build/Products/Release" && pwd)/Mouseless.app}"

[[ -d "$APP_PATH" ]] || { echo "App bundle not found: $APP_PATH" >&2; exit 1; }

open "$APP_PATH"
cat <<'EOF'
Mouseless recovery smoke test

Complete each scenario in order. The expected result after every recovery is:
free mode is Off, all virtual buttons have been released, and keyboard input is
passed through until left Option is tapped again.

1. Enter free mode, hold Space, then lock the screen and unlock it.
2. Enter free mode, hold Space, put the Mac to sleep, then wake it.
3. Enter free mode, revoke one of Accessibility, Input Monitoring, or Post
   Event permission in System Settings, then return to Mouseless.
4. Re-grant permissions, enter free mode, and use the event tap normally.
5. Exercise an event-tap disable/re-enable cycle using the available local
   event-tap test harness or a controlled timeout in Instruments, then verify
   the menu remains usable and the recovery counter changes. If the OS does
   not expose a way to induce the callback on this machine, record that as an
   unexecuted platform step; the runtime failure path is covered automatically.
6. Copy the diagnostic summary from the menu. Confirm it contains only
   capability state, recovery counters, and configuration state—not keys,
   applications, window titles, or pointer positions.

Expected menu/diagnostic results:
- lock, sleep, and permission loss each leave free mode Off;
- a tap timeout/user-input disable increments eventTapDisabled;
- a successful re-enable increments eventTapRecoveries;
- a failed re-enable increments eventTapRecoveryFailures and leaves free mode Off.
EOF

read -r -p "Press Enter after completing the checklist, or Ctrl-C to abort: " _
echo "Recovery smoke checklist completed by operator."
