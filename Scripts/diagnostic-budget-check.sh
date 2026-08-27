#!/usr/bin/env bash
set -euo pipefail

SUMMARY_PATH="${1:-}"
MAX_LATENCY_LIMIT_MS=1.0

[[ -n "$SUMMARY_PATH" && -f "$SUMMARY_PATH" ]] || {
  echo "Usage: $0 <debug-diagnostic-summary.txt>" >&2
  exit 1
}

value_for() {
  sed -n "s/^$1: //p" "$SUMMARY_PATH" | head -n 1
}

callbacks=$(value_for callbacks)
samples=$(value_for callbackLatencySamples)
maximum=$(value_for maximumCallbackLatencyMilliseconds)

[[ "$callbacks" =~ ^[0-9]+$ && "$callbacks" -gt 0 ]] || {
  echo "FAIL: diagnostic summary has no event-tap callbacks." >&2
  exit 1
}
[[ "$samples" =~ ^[0-9]+$ && "$samples" -gt 0 ]] || {
  echo "FAIL: no callback latency samples found; collect the summary from a Debug build." >&2
  exit 1
}
[[ "$maximum" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
  echo "FAIL: diagnostic summary has no valid maximum callback latency." >&2
  exit 1
}

if ! awk -v value="$maximum" -v limit="$MAX_LATENCY_LIMIT_MS" 'BEGIN { exit !(value < limit) }'; then
  echo "FAIL: maximum callback latency ${maximum}ms is not below ${MAX_LATENCY_LIMIT_MS}ms." >&2
  exit 1
fi

echo "PASS: maximum callback latency ${maximum}ms is below ${MAX_LATENCY_LIMIT_MS}ms."
