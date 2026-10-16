# Handoff / checkpoint

Updated whenever a gate moves. Resume from here; do not recap.

## State of the build

- Release A and Release B are **implemented at source level** under the source-only workflow
  exception (no Studio in this environment). Nothing is verified in-engine; see `docs/qa.md`.
- 50 files, 0 analyzer diagnostics, 47 CLI tests + 1 slow scripted battle pass.
- `build/EaglesOfEmpire.rbxlx` builds from the tree (`tools/build_place.py`).

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

None known at source level.

## Next concrete action

1. Open `build/EaglesOfEmpire.rbxlx` in Roblox Studio, press Play, and work through the manual
   checklist in `docs/qa.md` starting at Gate 1 (terrain, camera, selection, one move). Fix
   what fails before claiming any gate verified.
2. Known unverifiable-without-Studio spots are marked `ponytail:` in the client (ground-label
   SurfaceGui face orientation, sun azimuth, campaign map aspect at 1366×768).
3. Measure performance in Studio (normal roster and the `stress` scenario via `/start stress`
   is not wired to UI: start it from the server console with
   `require(game.ServerScriptService.EoE.MatchService)._internal.createMatch("stress")`).
