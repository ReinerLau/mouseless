#!/usr/bin/env bash
set -euo pipefail

step() {
  printf '\n>>> %s\n' "$1"
  read -r -p "    [Enter when done] " _
}

capture() {
  local var="$1" question="$2" answer
  printf '\n>>> %s\n' "$question"
  read -r -p "    > " answer
  printf -v "$var" '%s' "$answer"
}

step "Open a new empty TextEdit document. Confirm the Keyveer menu says Permissions: Ready and Free mode: Off."
step "With free mode Off, type z then i into TextEdit."
capture OFF_TEXT "What exact text appeared in TextEdit? (expected: zi)"
step "Clear the document, tap Left Option once, and confirm the Keyveer menu says Free mode: On."
step "Type z once, then press and release i once."
capture ON_TEXT "What exact text appeared in TextEdit? (expected: z)"
capture POINTER_MOVED "Did pressing i move the pointer? (y/n)"
step "Tap Left Option once to return to Free mode: Off."

printf '\n--- Captured ---\n'
printf 'OFF_TEXT=%s\n' "$OFF_TEXT"
printf 'ON_TEXT=%s\n' "$ON_TEXT"
printf 'POINTER_MOVED=%s\n' "$POINTER_MOVED"

if [[ "$OFF_TEXT" != "zi" ]]; then
  printf 'FAIL: free mode Off did not pass both keys through.\n' >&2
  exit 1
fi
if [[ "$ON_TEXT" != "z" ]]; then
  printf 'FAIL: free mode On did not consume the mapped key or pass the unmapped key.\n' >&2
  exit 1
fi
case "$POINTER_MOVED" in
  y | Y | yes | YES) ;;
  *)
    printf 'FAIL: mapped movement key did not move the pointer.\n' >&2
    exit 1
    ;;
esac

printf 'PASS: mapped keys are consumed only while free mode is active.\n'
