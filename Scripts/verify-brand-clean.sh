#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FORBIDDEN_BRAND="mouse""less"
failures=0

LOWERCASE_ROOT=$(printf '%s' "$REPO_ROOT" | tr '[:upper:]' '[:lower:]')
if [[ "$LOWERCASE_ROOT" == *"$FORBIDDEN_BRAND"* ]]; then
  printf 'Legacy brand remains in the repository path: %s\n' "$REPO_ROOT" >&2
  failures=1
fi

while IFS= read -r path; do
  printf 'Legacy brand remains in a project path: %s\n' "$path" >&2
  failures=1
done < <(
  find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o -iname "*$FORBIDDEN_BRAND*" -print
)

if rg -i -a -n --hidden --no-ignore --glob '!.git/**' "$FORBIDDEN_BRAND" "$REPO_ROOT"; then
  printf 'Legacy brand remains in project content.\n' >&2
  failures=1
fi

if git -C "$REPO_ROOT" remote -v | rg -i "$FORBIDDEN_BRAND"; then
  printf 'Legacy brand remains in a Git remote.\n' >&2
  failures=1
fi

if (( failures != 0 )); then
  exit 1
fi

printf 'Brand guard passed for %s\n' "$REPO_ROOT"
