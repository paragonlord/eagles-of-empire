# QA report — requirement to evidence

Status values: **pass** (evidence recorded), **fail** (reproduction below), **blocked** (needs
Roblox Studio; not run in this environment). Source checks are not in-engine checks.

## Source-level checks (run: `tools/check.sh`)

| Requirement | Evidence | Status |
| --- | --- | --- |
| Same state + commands ⇒ same results | `tests/sim.spec.luau` "Sim is deterministic" | pass |
| Pause freezes ticks; orders accepted while paused | `tests/net.spec.luau` MatchClock; Sim queues apply on the next tick | pass (clock) / blocked (end-to-end with remotes) |
| Render rate does not change outcome | `tests/net.spec.luau` "Different render rates" | pass |
| No fire out of range / through ridge / limbered / without ammo | `tests/sim.spec.luau` "Volleys need range…" | pass |
| Facing distinguishes front / flank / rear | "Facing distinguishes…" | pass |
| Square reduces cavalry shock; square takes time to form | "Square blunts a cavalry charge…" | pass |
| Charge applies impact once; no spam in contact | "Charge impact applies once…" | pass |
| Routing overrides orders; shattered cannot rally; HQ rally | "A volley inflicts…", "Shattered formations never rally…" | pass |
| Bridge traversal respects clearance; never in water | "Pathing crosses the Saale…" | pass |
| Dead / exited / routing units do not capture | "Objectives: routing and HQ units cannot capture…" | pass |
| Simultaneous, stable attack resolution | Combat.gather/apply order (ascending id), determinism test | pass |
| Victory applied once; totals reconcile | "Objectives… victory applies once" | pass |
| Reject other player's units, enemy ids, bad kinds, oversized batches, NaN coords, wrong match | `tests/shared.spec.luau` Protocol tests | pass |
| Rate limit and duplicate request ids | `tests/net.spec.luau` CommandGate | pass |
| Hidden enemies absent from snapshots; last-known frozen | "Snapshots hide unseen enemies…" | pass |
| Map determinism, bridges passable, zones passable | `tests/shared.spec.luau` MapGen | pass |
| Sim cost on 24 v 24 | `tests/bench.spec.luau`: ~1.3 ms/tick in the Luau CLI | pass (CLI only; Roblox server time blocked) |
| AI: determinism, honest information, square reaction, guns protected, reserve held, 10-min run | `tests/ai.spec.luau` | pass |
| Campaign: adjacency, one battle per army, exactly-once results, survivors reconcile, economy, victory/defeat, serialize round trip, store stale/error handling, 20-turn loop | `tests/campaign.spec.luau` (17 tests) | pass |
| Full battle pacing (scripted French plan vs normal AI, seed 20261014) | `python3 tools/test.py -k battle`: ran to the 25-min timeout, 72 volleys, 23 charges, 17 routs (all rallied), France 1929 / Prussia 1677 casualties, totals reconcile | pass (CLI; a human plan will differ) |
| Strict type analysis with Roblox globals | `tools/analyze.py src` (0 diagnostics for shared/server at last run) | pass |

## In-engine checks (blocked: no Studio in this environment)

| Check | Status |
| --- | --- |
| Launch → menu → deployment → battle → results → restart without duplicate HUD/connections | pass (Studio run log, round 2) |
| Second Studio client cannot control or pause the commander's battle | blocked |
| Reconnect receives complete state without duplicate units/effects | blocked |
| Group selection, queued march, formation change, volley, artillery, cavalry charge, rout, full battle, one victory and one defeat | partial: volley, cannon, charge, rout, rally, capture, full battle, one defeat pass; victory and UI-driven orders not yet run |
| Campaign turn → battle → casualties return → save → continue | blocked |
| 1920×1080, 1366×768, ultrawide layouts; label overlap; click-through; camera clipping | blocked |
| Frame rate with normal roster and stress fixture; instance counts; restart leak check | blocked |
| Terrain visual vs reference image (image not supplied) | blocked |

## Studio run log

**2026-10-17, Studio 0.743, Mac, 1 local client.**
- Pass: boot → menu → Play Battle → deployment → Start Battle → running; a unit selected and
  marched. No script errors or warnings from EoE (only Roblox CorePackages `FoundationProvider`
  noise).
- Fixed: voxel ground drew 2.0 studs above `Grid.heightAt` everywhere, burying ground labels and
  objective rings and sinking figures. `Terrain.build` now fills half a voxel lower; measured
  median offset 0.00 after.
- Fixed: ground labels were unreadable. A Top-face SurfaceGui runs its text along the part's -Z,
  and TextScaled caps at 100 px. Plates are now long in Z, turned 90°, canvas 400×100.
- Open (art, not bugs): wide labels on slopes clip at the ends (Lützeroda, Windknollen);
  Cobblestone roads read as rubble walls up close; olive-gold Grass reads brown at ClockTime 8.4;
  the camera can see past the map edge into the sky; the diagnostic beacon covers the date in
  the top bar.

**2026-10-17 round 2, build after eb34c7a (weather, reinforcements, battle select).**
- Pass: menu → Choose a battle → Fight → deployment → Start Battle → full battle at ×4 → Defeat
  ("The enemy holds every objective · 16:44") → Restart → deployment → running. One EoEHUD
  after restart, results/menu screens gone, workspace instance count steady (9458 → 9428).
  Totals reconcile (France 7700 − 1964 = 5736, Prussia 6880 − 752 = 6128). No EoE errors or
  warnings on client or server. Events seen: volley, cannon, charge, rout, rally, capture,
  destroyed, message.
- Fixed: a square only fired inside the 60° front arc, so cavalry on its side or rear was never
  shot at. Seen live: IR Nr. 20 in square next to the 1er Cuirassiers for 8 game minutes, no
  volleys, both at full strength. Reproduced with the real Sim in Studio (square vs cavalry at
  40 studs): before, volleys only at bearing 0; after, at 0/90/180/270. `fireBlockReason` now
  skips the arc for squares; assertion added to the "Volleys need range…" test. **Not run in
  the Luau CLI here (none on this Mac): please run `tools/check.sh`.**
- Fixed: on the battle card the difficulty note was pinned to the card bottom and overlapped the
  last line of a 4-line summary. Summary and note now stack in a list.
- Open (for the cloud): cavalry given AttackMove onto an enemy halts inside its footprint and
  stays idle (no charge, no melee) until given a Charge order. Routed units that rally at the
  home edge pile on top of each other at odd angles. The beacon (bottom-left) touches the
  bottom of the order bar. One message "44e de Ligne: route blocked" during the battle (unit
  had routed and rallied at the edge; no error).
- Round 1 notes now handled by the cloud: beacon moved off the date.

**2026-10-17 round 3 (visual pass), build 243f5f8.** Screenshots in `docs/shots/` (overwritten
each round): `deploy.jpg` (end of the intro sweep), `hud.jpg` (battle start, ×4), `troops.jpg`
(zoomed on the Landgrafenberg), `fight.jpg` (Closewitz fight). Compared with
`docs/reference/epic-history-jena-2.jpg`. Ranked by how much each hurts the look:
1. **Teal wash and no relief.** Everything sits under a cyan-teal haze; colours are grey-olive
   and contrast is low, so the ridges and valleys barely read. The reference is saturated
   olive-gold with dark shaded slopes. (Lighting at the time: Atmosphere density 0.28, haze 1.2,
   ColorCorrection saturation 0.04, contrast 0.08, ClockTime 10.2, Jena weather fog.)
2. **Map floats in a void.** The deployment camera sits south of the map (z = -165) and shows the
   slab's cut edge with flat teal below and around it (`deploy.jpg`, bottom; all four corners).
   The reference fills the frame with terrain.
3. **Roads read as snow.** Roads are a dotted trail of pale blotches far from the villages and a
   wide, bright, noisy white strip on the Landgrafenberg (`troops.jpg`), wider than a battalion.
   The reference roads are thin, faint lines.
4. **Smoke is solid white balls.** Volley smoke shows as rows of opaque white spheres, like a
   string of pearls along each line (`fight.jpg`). It should be soft and see-through.
5. **French and Prussians look alike up close.** Both read as dark blue figures; only the flags
   tell them apart. The reference: French cobalt, Prussians near-black charcoal.
6. **Name plates unreadable.** The plates above units are too small to read at any useful zoom
   (`troops.jpg`); the reference plates are big, framed, dark serif capitals.
7. **Small place names unreadable.** Closewitz, Vierzehnheiligen, Krippendorf and Cospeda are tiny
   and faint from the deployment camera while Landgrafenberg is huge (`deploy.jpg`).
8. **Villages are a few big grey boxes.** The reference villages are dense clusters of many small
   dark-brown roofs.
9. **Fog-of-war markers look like placeholders.** Last-known enemies show as flat grey slabs and
   white X plates (`fight.jpg`, top).
10. Ticker: red "is routing!" text on the dark-brown chip is hard to read (`troops.jpg`).
11. Command grid: "Auto ammo" wraps onto two lines in its cell (`hud.jpg`, bottom left).
- Good: new HUD layout, card bar (routing cards turn red), framed minimap, battle select with four
  battles, intro sweep, figures with horses and guns, objective rings change colour on capture.
- Incident: builds 0871170 to 67ad183 did not boot. `Kit.luau:27: Expected identifier when
  parsing method name, got '{'` (a type annotation on `Kit.MORALE`). Fixed in 243f5f8. A parse
  check before each push (`tools/check.sh`) would catch this class.
- New battles, build 9260d37: Auerstedt, Austerlitz and Waterloo each load to deployment with no
  errors (`auerstedt.jpg`, `austerlitz.jpg`, `waterloo.jpg`; started via the Control remote).
  Same haze, road and village notes as Jena, plus: the Austerlitz field reads flat, so the
  Pratzen plateau the briefing is about does not show; Waterloo's Brussels road is a wide white
  stripe through the middle of the field and through La Belle Alliance and Rossomme; Waterloo
  villages are a few tall narrow dark blocks that read as chimneys, not houses; the deployment
  briefing appears a second or two before the terrain finishes drawing (a patch of void shows).
- Fixed: the beacon ran off the right edge (only "E" visible). `AnchorPoint` was set to (1, 0) and
  then reset to (0, 0) two lines later; the second line is gone.

## Known failures

None recorded yet.
