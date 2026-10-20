# Handoff / checkpoint

Resume from here; do not recap. Updated 2026-10-20.

## State of the build

- Everything on `main` builds and passes: 0 analyzer diagnostics in 97 files, 239 tests.
  `build/EaglesOfEmpire.rbxlx` is regenerated from source on every integration (never edit the
  place by hand: anything only in Studio is lost on the next rebuild).
- Roadmap toward Total War: Napoleon: `docs/plan.md` (living tracker; Phases 0–11 and the
  whole-game balance and AI pass done) and the graphics pass G0–G4 (generated soldiers, painted
  ground, real Europe on the board, paintings and portraits); next: the open items below.
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
- Studio QA log: `docs/qa.md` (rounds 1–41). Balance table: `docs/balance.md`.

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

- Graphics pass (2026-10-20), all generated in Studio through the MCP and published to your
  account; full list in `docs/assets-brief.md`:
  - **Soldiers are kits**: eight textured pieces per figure, posed on the old animation codes.
    Infantry and cavalry for France, Prussia, Austria, Russia, Britain, Saxony, Netherlands,
    Bavaria (`Assets.kits`); Napoleon's own; guns in three paints with kit crews; a limber; hats
    (bearskin, bicorne, crested helmet, Highland bonnet). `tools/kit_import.luau` turns a
    generated model into a kit entry.
  - **Ground**: seven MaterialVariants in `default.project.json` (MaterialService) override the
    terrain's base materials; the client turns them on (`World/Terrain.paintGround`).
  - **World**: hedgerow, willow, stone and trestle bridges, cart; ship of the line (board fleets).
  - **Paintings and portraits** (public domain, Wikimedia Commons): menu, loading per battle,
    results ribbon; the five sovereigns on the nation picker; the Thuringian parchment map drawn
    by `tools/thuringia_map.py`.
- Campaign board geography: `tools/geo.py` (Natural Earth, public domain) writes
  `src/shared/EuropeGeo.luau`; `src/shared/Relief.luau` reads it (land, relief, rivers).
- Filled earlier: trees, houses, barn, church, windmill, bark/roof/wall/thatch textures.
- Sound candidates with links (licensed APM / Pro Sound Effects first) are in
  `docs/assets-brief.md` "Sound candidates": audition, then fill the slots.
- Next: the eight priority sounds in `Assets.sounds` (musketVolley, cannonFire, drumsMarchFr,
  ambienceField, menuMusic, uiClick, bugleCharge, cavalryCharge); a kaskett for Austria; a wall
  and a fence section (both generations failed, they stay part-built).

## Open items

0. Studio checklist, what is left after QA round 41: the kit soldiers marching, reloading and
   thrusting in motion (stills cannot show them), the round shot in motion (1.3-stud ball), the
   volley light and the howitzer shell burst, burning Hougoumont at Waterloo's 4:00 moment, and
   the frame rate of a full Waterloo on a real machine (Studio's unfocused 15 fps hides the
   distant battalions' slower refresh, `Soldiers.refreshInterval`).

1. Two-player Studio test (Test → Clients and Servers → 2 Players, by hand): co-op wings, pause
   vote, pings, assign; PvP side picker, per-side fog, both result screens. Never run yet.
2. Sound: 13 slots now have ids, chosen by measurement (length, envelope, bass share) and seen
   playing in a battle, but nobody has listened yet. Play one battle with sound on: swap any id
   that sounds wrong (`src/shared/Assets.luau`, bottom), check volleys from many battalions do not
   stack into a wall, and fill bugles, melee and clicks (`docs/assets-brief.md`).
3. Balance: 17 flags in `docs/balance.md`, 3 against history, all Auerstedt (the Prussian horse
   pins Davout's battalions in square and the infantry shoots the squares). Waterloo now goes to
   the allies in 23 of 30 AI-vs-AI battles; the Hougoumont episode is about even (14 of 30).
   Next lever: when the AI forms square (not with enemy foot in musket range).
4. Real phone: pinch/twist direction and pan speed knobs in `src/client/Camera.luau` (finger
   drags were mirrored sideways like A/D, fixed). The Device Simulator keeps a keyboard: pick
   Touch in Settings before judging the touch layout.
5. A human playthrough of the grand campaign to a peace.
6. Reeds have no mesh slot; the wall and fence generations failed (part-built for now).

## Where things live

- Contracts: `docs/architecture.md`, `docs/coop-contract.md`, `docs/mobile-contract.md`,
  `docs/grand-campaign-contract.md`. Rules and formulas: `docs/rules.md`. Look: `docs/vision.md`,
  `docs/visual-notes.md`.
- Sim (pure, headless): `src/server/Sim/*`, AI `src/server/AI/init.luau`, world generation
  `src/shared/WorldGen.luau` (pure specs) → `src/shared/WorldBuild.luau` → `src/server/World.luau`.
- Client: `src/client/*` (Figures, Soldiers, Effects, Audio, Camera, Input, UI/Kit and screens).
