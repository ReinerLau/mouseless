#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_PATH="${1:-$SCRIPT_DIR/../build/candidate/Build/Products/Release/Keyveer.app}"
SAMPLE_SECONDS=10
IDLE_CPU_LIMIT=0.5
ACTIVE_CPU_LIMIT=3.0
MEMORY_LIMIT_MB=50.0
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keyveer-performance-smoke.XXXXXX")
driver_pid=
cleanup() {
  if [[ -n "$driver_pid" ]]; then
    if kill -0 "$driver_pid" 2>/dev/null; then
      kill "$driver_pid" 2>/dev/null || true
      wait "$driver_pid" 2>/dev/null || true
    fi
    if [[ -x "$BUILD_DIR/performance-smoke-test" ]]; then
      "$BUILD_DIR/performance-smoke-test" cleanup >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

[[ -d "$APP_PATH" ]] || {
  echo "App bundle not found: $APP_PATH" >&2
  echo "Build it first with ./Scripts/candidate-build.sh, then rerun this script." >&2
  exit 1
}

command -v swiftc >/dev/null || {
  echo "swiftc is required to run the performance smoke test." >&2
  exit 1
}
command -v top >/dev/null || {
  echo "top is required to measure a time-bounded CPU sample." >&2
  exit 1
}

swiftc "$SCRIPT_DIR/performance-smoke-test.swift" -framework CoreGraphics \
  -o "$BUILD_DIR/performance-smoke-test"

APP_PATH=$(cd "$APP_PATH" && pwd -P)
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/Keyveer"

find_pid() {
  while read -r candidate_pid; do
    command_path=$(ps -p "$candidate_pid" -o command= || true)
    if [[ "$command_path" == "$APP_EXECUTABLE" ]]; then
      printf '%s\n' "$candidate_pid"
      return 0
    fi
  done < <(pgrep -x Keyveer || true)
  return 1
}

if existing_pid=$(find_pid); then
  echo "Quit the existing candidate process (PID $existing_pid) before measuring this build." >&2
  exit 1
fi

open "$APP_PATH"
sleep 1
read -r -p "Confirm Keyveer is running, Permissions says Ready, and Free mode is Off [y/N]: " ready
case "$ready" in
  y | Y | yes | YES) ;;
  *)
    echo "Aborted: establish the stated precondition before running the performance test." >&2
    exit 1
    ;;
esac

pid=$(find_pid || true)
[[ -n "$pid" ]] || { echo "Could not find the Keyveer process." >&2; exit 1; }

sample_process() {
  local output=$1
  : > "$output"
  local sample_count=0
  local deadline=$((SECONDS + SAMPLE_SECONDS))
  while (( SECONDS < deadline )); do
    local cpu
    cpu=$(top -l 1 -pid "$pid" -stats pid,cpu | awk -v target="$pid" '$1 == target { print $2; found = 1 } END { exit !found }') || {
      echo "Keyveer exited while sampling process $pid." >&2
      return 1
    }
    local rss_kb
    rss_kb=$(ps -p "$pid" -o rss= | awk 'NF == 1 { print $1; found = 1 } END { exit !found }') || {
      echo "Keyveer exited while sampling process $pid." >&2
      return 1
    }
    printf '%s %s\n' "$cpu" "$rss_kb" >> "$output"
    sample_count=$((sample_count + 1))
  done
  (( sample_count > 0 )) || { echo "No process samples were collected." >&2; return 1; }
}

summarize() {
  awk '
    { cpu += $1; if ($1 > peak_cpu) peak_cpu = $1; if ($2 > max_rss) max_rss = $2; count++ }
    END {
      if (count == 0) exit 1
      printf "%.2f %.2f %.0f\n", cpu / count, peak_cpu, max_rss
    }
  ' "$1"
}

within() {
  awk -v value="$1" -v limit="$2" 'BEGIN { exit !(value < limit) }'
}

echo "Sampling idle CPU and memory for ${SAMPLE_SECONDS}s..."
sample_process "$BUILD_DIR/idle.samples"
read -r idle_cpu idle_peak_cpu idle_max_rss_kb < <(summarize "$BUILD_DIR/idle.samples")

echo "Sampling continuous movement for ${SAMPLE_SECONDS}s..."
"$BUILD_DIR/performance-smoke-test" "$SAMPLE_SECONDS" &
driver_pid=$!
if ! sample_process "$BUILD_DIR/active.samples"; then
  kill "$driver_pid" 2>/dev/null || true
  wait "$driver_pid" 2>/dev/null || true
  exit 1
fi
wait "$driver_pid"
driver_pid=
read -r active_cpu active_peak_cpu active_max_rss_kb < <(summarize "$BUILD_DIR/active.samples")

max_rss_kb=$(awk -v idle="$idle_max_rss_kb" -v active="$active_max_rss_kb" 'BEGIN { print (idle > active ? idle : active) }')
max_rss_mb=$(awk -v kb="$max_rss_kb" 'BEGIN { printf "%.2f", kb / 1024 }')

printf 'Idle average CPU: %.2f%% (limit %.2f%%)\n' "$idle_cpu" "$IDLE_CPU_LIMIT"
printf 'Active average CPU: %.2f%% (limit %.2f%%)\n' "$active_cpu" "$ACTIVE_CPU_LIMIT"
printf 'Peak resident memory: %.2f MB (limit %.2f MB)\n' "$max_rss_mb" "$MEMORY_LIMIT_MB"
printf 'Observed peak samples: idle CPU %.2f%%, active CPU %.2f%%\n' "$idle_peak_cpu" "$active_peak_cpu"

failed=0
within "$idle_cpu" "$IDLE_CPU_LIMIT" || { echo "FAIL: idle CPU budget exceeded." >&2; failed=1; }
within "$active_cpu" "$ACTIVE_CPU_LIMIT" || { echo "FAIL: active CPU budget exceeded." >&2; failed=1; }
within "$max_rss_mb" "$MEMORY_LIMIT_MB" || { echo "FAIL: resident memory budget exceeded." >&2; failed=1; }

if (( failed != 0 )); then
  exit 1
fi
echo "PASS: CPU and memory budgets were met for this sample window."
