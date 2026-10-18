# Handoff / checkpoint

Resume from here; do not recap. Updated 2026-10-18.

## State of the build

- Everything on `main` builds and passes: 0 analyzer diagnostics in 90 files, 168 tests.
  `build/EaglesOfEmpire.rbxlx` is regenerated from source on every integration (never edit the
  place by hand: anything only in Studio is lost on the next rebuild).
- Features in: tactical battles (12 scenarios, quick and full modes), tutorial, Thuringian
  campaign, grand campaign 1805–1815, co-op (2–4 players by wing), PvP (1v1 to 2v2), mobile touch
  controls, audio layer (silent until ids are filled), aged-paper UI with typeface presets and
  place-name modes, server-built world with a readiness-gated loading screen, no-clip placement
  of every figure and object, AI-vs-AI balance harness.
- Studio QA log: `docs/qa.md` (rounds 1–28). Balance table: `docs/balance.md`.

## Workflow

- Source of truth is the repo. Studio work goes through files: asset ids into
  `src/shared/Assets.luau`, then `tools/check.sh`, commit, push.
- One commit per asset slot. Commit messages plain, no tool attributions.
- After code changes: `python3 tools/build_place.py`, commit `build/EaglesOfEmpire.rbxlx`, push.

## Exact commands

```
tools/check.sh                           # analysis + tests (see note below)
python3 tools/analyze.py src             # analysis only: must print 0 diagnostics
python3 tools/test.py                    # tests only; -k "<name>" runs one (and [slow] ones)
python3 tools/build_place.py             # build/EaglesOfEmpire.rbxlx
python3 tools/balance.py --seeds 3       # AI-vs-AI pass over every scenario (~10 min)
```

Analyzer note: `tools/analyze.py` needs a `luau-analyze` that accepts `--definitions=` and has the
type-checker limits lifted (a patched build of luau-lang/luau). The stock release (0.743) rejects
`--definitions`; until a patched build is installed locally, rely on `tools/test.py` plus Studio's
own script analysis, and let the cloud-built check catch type errors.

## Assets (src/shared/Assets.luau, guide in docs/assets-brief.md)

- Filled: trees `treeOak`, `treeBeech`, `treePine`, `treePoplar` (mesh + texture + `native`);
  textures `bark`, `roofTile`, `wall`, `thatch`; `Kit.paperTextureId`.
- A slot needs `mesh`, `texture`, `native` (the mesh's size in studs as Studio shows on import);
  leave `scale` at `{1, 1, 1}`. Trees stand on their centre; buildings on their highest corner
  with a stone plinth; bridges put the deck at bank height.
- Next: `houseA` (7 × 6 × 5), `houseB` (8 × 8 × 6), `barn` (13 × 7 × 6), `church`
  (22 × 22 × 7.4, nave along +X), `windmill` (20 × 20 × 20); then `soldierInfantry` (French) and
  the eight priority sounds in `Assets.sounds`: musketVolley, cannonFire, drumsMarchFr,
  ambienceField, menuMusic, uiClick, bugleCharge, cavalryCharge.

## Open items

1. Two-player Studio test (Test → Clients and Servers → 2 Players, by hand): co-op wings, pause
   vote, pings, assign; PvP side picker, per-side fog, both result screens. Never run yet.
2. Sound check once ids land: Settings → debug audio, every event fires, volleys from many
   battalions do not stack into a wall.
3. Defending AI: Wellington's line at Waterloo is static and falls in ~15 min to an AI attack
   (`docs/balance.md`). Spielberg draws 1–1; Hougoumont's guns have no line of sight.
4. Real phone: pinch/twist direction and pan speed knobs in `src/client/Camera.luau`.
5. A human playthrough of the grand campaign to a peace.
6. Willow, hedge, wall, fence, cart and reed meshes have no slots yet; add when assets exist.

## Where things live

- Contracts: `docs/architecture.md`, `docs/coop-contract.md`, `docs/mobile-contract.md`,
  `docs/grand-campaign-contract.md`. Rules and formulas: `docs/rules.md`. Look: `docs/vision.md`,
  `docs/visual-notes.md`.
- Sim (pure, headless): `src/server/Sim/*`, AI `src/server/AI/init.luau`, world generation
  `src/shared/WorldGen.luau` (pure specs) → `src/shared/WorldBuild.luau` → `src/server/World.luau`.
- Client: `src/client/*` (Figures, Soldiers, Effects, Audio, Camera, Input, UI/Kit and screens).
