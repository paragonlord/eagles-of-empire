# Handoff / checkpoint

Resume from here; do not recap. Updated 2026-10-20.

## State of the build

- Everything on `main` builds and passes: 0 analyzer diagnostics in 95 files, 221 tests.
  `build/EaglesOfEmpire.rbxlx` is regenerated from source on every integration (never edit the
  place by hand: anything only in Studio is lost on the next rebuild).
- Roadmap toward Total War: Napoleon: `docs/plan.md` (living tracker; Phases 0–11 and the
  whole-game balance and AI pass done; next: the open items below).
- Features in: tactical battles (12 scenarios, quick and full modes), tutorial, Thuringian
  campaign, grand campaign 1805–1815, co-op (2–4 players by wing), PvP (1v1 to 2v2), mobile touch
  controls, audio layer (silent until ids are filled), aged-paper UI with typeface presets and
  place-name modes, server-built world with a readiness-gated loading screen, no-clip placement
  of every figure and object, AI-vs-AI balance harness.
- Added on the roadmap: unit types (light, rifles, grenadiers, guard, militia, light/heavy
  cavalry, dragoons, foot/horse artillery, howitzers), skirmish order, run/walk, fire by rank,
  TW hotkeys and control groups, card ammo/fatigue/group marks, stats ratings and enemy
  inspection, edge scroll and follow camera, ricochet and friendly fire, howitzer shells, downhill
  bonus, fords, garrisonable buildings (with AI), hedge and wall cover; corps generals with their
  own auras and 120-sabre escorts, battle experience; a defending and manoeuvring battle AI;
  campaign: kept march routes, unreadable saves kept, buildings, taxes and revolts, gradual
  refill and winter attrition, a research tree, national rosters, a battle map per province,
  reinforcing armies, forced march, general careers and appointments, siege assaults, trade
  agreements, military access, gifts, spies, a navy (fleets, escorts, naval battles, blockades,
  shipbuilding; Trafalgar sinks the Franco-Spanish fleets, after which the Royal Navy AI
  blockades); either side in the listed battles,
  custom battles, kills and an In history section in the results, loading tips, visible round
  shot, reload and bayonet animations.
- Studio QA log: `docs/qa.md` (rounds 1–38). Balance table: `docs/balance.md`.

## Workflow

- Source of truth is the repo. Studio work goes through files: asset ids into
  `src/shared/Assets.luau`, then `tools/check.sh`, commit, push.
- One commit per asset slot. Commit messages plain, no tool attributions.
- After code changes: `python3 tools/build_place.py`, commit `build/EaglesOfEmpire.rbxlx`, push.
- Studio MCP (`claude mcp add --transport stdio Roblox_Studio -- /Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`):
  to get source into the open place without reopening it, run `python3 tools/build_place.py`
  (also writes `build/sync.json`), serve the repo with `python3 -m http.server 8765 --bind
  127.0.0.1`, stop Play and execute the text of `tools/studio_sync.luau` in Edit. Viewport input
  coordinates = screenshot coordinates / (capture width / viewport width), minus the 58-px top
  inset on y.

## Exact commands

```
tools/check.sh                           # analysis + tests (see note below)
python3 tools/analyze.py src             # analysis only: must print 0 diagnostics
python3 tools/test.py                    # tests only; -k "<name>" runs one (and [slow] ones)
python3 tools/build_place.py             # build/EaglesOfEmpire.rbxlx
python3 tools/balance.py --seeds 3       # AI-vs-AI pass over every scenario (~10 min)
```

Analyzer note: `luau` and `luau-analyze` live in `~/.local/bin`. The analyzer is Luau 0.743 plus
`tools/luau-analyze.patch` (adds `--definitions=`, lifts the child limit that the Roblox
definitions trip); `tools/check.sh` runs it through `tools/analyze.py`, which fails on any
diagnostic. To rebuild (macOS needs only the Xcode command line tools, ~30 s):

```
git clone --depth 1 --branch 0.743 https://github.com/luau-lang/luau.git && cd luau
git apply ~/eagles-of-empire/tools/luau-analyze.patch
make config=release -j8 luau luau-analyze
cp build/release/luau build/release/luau-analyze ~/.local/bin/
```

## Assets (src/shared/Assets.luau, guide in docs/assets-brief.md)

- Filled: trees `treeOak`, `treeBeech`, `treePine`, `treePoplar` (mesh + texture + `native`);
  buildings `houseA`, `houseB`, `barn`, `church`, `windmill`; textures `bark`, `roofTile`,
  `wall`, `thatch`; `Kit.paperTextureId`. Only `houseA` has been seen in Studio (QA round 29).
- A slot needs `mesh`, `texture`, `native` (the mesh's size in studs as Studio shows on import);
  leave `scale` at `{1, 1, 1}`. Trees stand on their centre; buildings on their highest corner
  with a stone plinth; bridges put the deck at bank height.
- Sound candidates with links (licensed APM / Pro Sound Effects first) are in
  `docs/assets-brief.md` "Sound candidates": audition, then fill the slots.
- Next: `soldierInfantry` (French) and the eight priority sounds in `Assets.sounds`:
  musketVolley, cannonFire, drumsMarchFr, ambienceField, menuMusic, uiClick, bugleCharge,
  cavalryCharge.

## Open items

0. Studio checklist, what is left after QA round 38: the reload and bayonet beats in motion (stills
   cannot show them), and whether the round-shot trail is bold enough from the normal camera
   height (`docs/shots/r38-round-shot.jpg`; one line in `src/client/Effects.luau`).

1. Two-player Studio test (Test → Clients and Servers → 2 Players, by hand): co-op wings, pause
   vote, pings, assign; PvP side picker, per-side fog, both result screens. Never run yet.
2. Sound check once ids land: Settings → debug audio, every event fires, volleys from many
   battalions do not stack into a wall.
3. Balance: 15 flags in `docs/balance.md`, 4 against history (Auerstedt goes to Prussia against
   an AI Davout; Waterloo normal/hard lean French, the allies win ~40 % overall). Next lever:
   the defending line meeting attacks in its flank (see the whole-game pass notes).
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
