#!/usr/bin/env bash
# Source-level checks: strict type analysis + Luau CLI tests. No Studio involved.
set -u
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
status=0

echo "== luau-analyze (strict) =="
if command -v luau-analyze >/dev/null; then
  python3 tools/analyze.py src || status=1
else
  echo "luau-analyze missing (build it: docs/handoff.md)"
  status=1
fi

echo "== tests =="
python3 tools/test.py "$@" || status=1
exit $status
