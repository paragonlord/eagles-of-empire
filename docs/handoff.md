# Handoff / checkpoint

Updated whenever a gate moves. Resume from here; do not recap.

## State of the build

- Gate 0 complete; Gate 1–3 **source implementation** in progress under the source-only
  workflow exception (no Studio in this environment). Nothing is verified in-engine.
- Shared foundation, battle simulation, server runtime: implemented, type-clean, 22 CLI tests
  pass (`tools/check.sh`).
- Client (src/client), enemy AI (src/server/AI), campaign + persistence
  (src/server/Campaign, src/server/Persist): being implemented by parallel helpers with file
  ownership; integration owner is the main session. Until they land, `MatchService` has an
  unresolved `require(script.Parent.AI)`.

## Exact commands

```
export PATH=$HOME/.local/bin:$PATH      # luau, luau-analyze (built from luau-lang/luau, patched)
tools/check.sh                           # analysis + tests
python3 tools/build_place.py             # build/EaglesOfEmpire.rbxlx
```
Toolchain source: `/tmp/.../scratchpad/tools/luau-src` (not part of the repo). The patch adds
`--definitions=` to luau-analyze and lifts type-checker limits; `tools/analyze.py` rewrites
instance-path requires into string requires in a mirror under `build/analyze/`.

## Current errors

None in shared/server (except the pending AI module require).

## Next concrete action

1. Integrate AI, client and campaign deliveries; run `tools/check.sh`; rebuild the place.
2. Wire campaign remote (`Protocol.Remotes.Campaign`) into MatchService: campaign view,
   commands, battle hand-off (`Campaign.battleScenario` → `createMatch`), result commit
   (`Campaign.commitBattle`) once per battle id, continue flow from `ProfileStore`.
3. Write `docs/qa.md` with the requirement-to-evidence checklist (pass / fail / blocked).
4. Push to the user's repository once it exists (not yet created).
