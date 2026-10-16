#!/usr/bin/env bash
# Source-level checks: strict type analysis + Luau CLI tests. No Studio involved.
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
DEFS="${LUAU_DEFS:-tools/globalTypes.d.luau}"
status=0

echo "== luau-analyze (strict) =="
if command -v luau-analyze >/dev/null; then
  files=$(find src -name '*.luau' | sort)
  if [ -f "$DEFS" ]; then
    luau-analyze --mode=strict --definitions="$DEFS" --formatter=plain $files || status=1
  else
    echo "(no $DEFS; analysing without Roblox globals)"
    luau-analyze --mode=strict --formatter=plain $files || status=1
  fi
else
  echo "luau-analyze missing; skipped"
fi

echo "== tests =="
python3 tools/test.py "$@" || status=1
exit $status
