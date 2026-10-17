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

**2026-10-17 round 4 (First Empire UI), build 0f8e425.** `docs/shots/` now holds only this
round's shots: `menu.jpg`, `select.jpg`, `select-glitch.jpg`, `dispatch.jpg`,
`terrain-holes.jpg`, `hud.jpg`, `fight.jpg` (Pratzen), `results.jpg`. Played Austerlitz at ×4
to the end: Close Victory on time, totals reconcile (France 14,200 − 1,237 = 12,963; Allies
13,840 − 1,391 = 12,449). No EoE errors or warnings on client or server.
- Good: the menu column, battle cards with flags and stars, the parchment dispatch, the walnut
  top bar and the results report all read as one style and look finished.
- Open, ranked:
  1. **Terrain holes during the intro sweep** (`terrain-holes.jpg`). On Austerlitz, 9 s after
     Fight the dispatch is up and the camera sweeps over big rectangular holes in the ground,
     with trees and villages floating over the void; it fills in by about 25 s. `ensureWorld`
     has already written every voxel, so this is Roblox still meshing a large map. Holding the
     loading screen (or the sweep) a few seconds after `Terrain.build` would hide it.
  2. **Village houses are too big** (`fight.jpg`): plain boxes several times taller than the
     soldiers, flat dark tops, no pitched roofs. Reads as warehouses, not a village.
  3. Volley smoke still shows as stacks of opaque white balls (`fight.jpg`, by the Pratzen
     houses). The teal haze and snow-like roads from round 3 are unchanged.
  4. **Battle select, third card half-drawn on open** (`select-glitch.jpg`): before the list is
     scrolled, the Austerlitz card shows only its flags and a strip of parchment; title, frame
     and Fight button are missing. All its properties are normal (visible, ZIndex 1, opaque);
     after one scroll every card draws correctly. Looks like a Roblox clipping redraw issue on
     the first frame.
  5. **Flags**: Prussia is a white field with a black X, which reads as a close button; Britain
     (Waterloo) is a white cross on red, which reads as Denmark.
  6. **Card bar on big armies** (`hud.jpg`): Austerlitz has ~28 cards; the bar scrolls sideways
     with a 4 px bar and the last card is cut at the right edge next to the minimap. Nothing
     hints that it scrolls.
  7. The balance-of-power bar is fully blue at the start in fog (no enemy seen yet), so it reads
     as total superiority until contact.
  8. Menu column stops at the Roblox top-bar inset, leaving a strip of 3D world above it
     (`menu.jpg`, top left).
  9. Results: the objective chip "Pratzen Heights — Russia &…" is truncated; the lower third of
     the report is empty; "Notes from the field" was the same generic line in both battles.
  10. A 30-minute Austerlitz with 28 v 30 formations ended with no routed or destroyed formation
      on either side and about 10 % casualties: feels inconclusive (my orders were plain
      attack-moves on the three objectives, so a human plan may differ).
  11. Minor: `Terrain.ensurePickPlane` asks for map + 4000 studs, but Roblox caps a part at 2048,
      so on the 2400-wide maps the plane does not reach the outer 176 studs on each side. Only
      clicks past the map edge are affected, since terrain is raycast first.

**2026-10-17 round 4b, build 773498e (tutorial server side, figure jostle).** Started the
`tutorial` scenario through the Control remote: the training ground loads to deployment, Start
Battle runs at ×4 for two game minutes, no EoE errors on client or server (`tutorial.jpg`). The
lesson panel is not in this build, so the scripted steps were not exercised; full tutorial test
next round. Figures (`figures.jpg`): the jostle reads well, but a battalion in line draws as
8 thin files of 2–3 figures with gaps as wide as the files, so a line looks like open order. The
reference blocks are solid; closing the gaps (or more figures per file) would read as a line.
The small training map shows the floating-slab edge on all sides.

**2026-10-17 round 5 (tutorial), build 2e48234.** Played the tutorial from the menu entry as a
player: real keys, wheel, card clicks, shift-click, right-click and right-drag for lessons 1–5;
orders through the Command remote for 6–11 (those lessons only read field state). Shots in
`docs/shots/`. No EoE errors or warnings on client or server.
- Lessons 1–10 complete; 11 (Ebersdorf) could not, see the brook bug below.
- Fixed: **the tutorial panel was empty** (`tutorial-panel-before.jpg`). The panel was 1287 px tall
  on a 1101 px screen with every line below the bottom edge. `Kit.list` sat on the Kit panel
  itself, so the UIListLayout also stacked the panel's Trim and rosettes, and the Trim (sized
  to its auto-sized parent) grew to 1129 px. The lines now live in an inner `content` frame
  (`tutorial-panel-after.jpg`).
- Fixed: **the ground "ring" was a solid yellow disc** over the spot, hiding the place name. It
  was a neon cylinder Part; it is now a `CylinderHandleAdornment` with `InnerRadius` (a real
  ring, `tutorial-ring-after.jpg`), pulse range 0.15–0.5 so the thin ring stays visible.
- Fixed: **lesson 3 (March) could not be completed as written.** The text says "Right-click the
  ground to march"; a plain right-click gives the battalion a `dest` but no `destHeading`, and
  `done` required both, so a player following the text was stuck. `done` now accepts any `dest`
  (right-drag still works).
- **Open, serious: units that path into a brook are stuck there for good** (`stuck-in-brook.jpg`:
  three battalions standing in the Mühlbach, "moving" for 15+ game minutes; ordered back to the
  near bank, they still do not move). Reproduced in a fresh `Sim` on the tutorial map: a
  battalion at (400, 480) ordered to (400, 640) paths straight over the brook (waypoints
  (408,552) (408,568) (400,640)), switches to travel column, stops at (408, 540) on a `water`
  cell and stays `moving` forever; a later Move back to (400, 470) does nothing. Cause:
  `Nav.build` marks a 16-stud node walkable when `passable or maxClear >= TRAVEL_HALF`. That
  clause is for bridges and defiles, but a node straddling a 10–16-stud brook also has dry bank
  cells with clearance ≥ 8, so A* links the two banks across the water while Movement refuses
  water cells. Every map has it (river centre points, away from bridges, that Nav calls walkable):
  Jena Rau-Bach (14 wide) 48/169; Auerstedt Lissbach (12) 83/158; Austerlitz Goldbach (16)
  48/161; Waterloo Smohain brook (10) 54/78; tutorial Mühlbach (12) 55/116. The Saale and the
  ponds are fine (0). Not fixed here: checking each A* step with `segmentClear(…, TRAVEL_HALF)`
  is the obvious fix but needs the bridge tests (node centres sit up to 8 studs off a bridge
  axis), and Movement should also let a unit already standing on water step out (or snap it to
  `Nav.nearestWalkable`) so an old save or a scripted ford cannot strand it.
- Open, small: when Skip step closes the panel on the last lesson, its tooltip ("Move on to the
  next lesson") stays on screen. The enemy's own "route blocked" messages (Chevaulegers Nr. 3,
  Brigade-Hauptquartier) show in the player's ticker, repeated; they leak enemy movement and
  are noise. The Austrian HQ showed `routing` with strength 0 instead of being removed. Lesson 5
  can look stuck if the player presses Square before the column has formed (8 s); the highlight
  already moves from Column to Square, so maybe say "once in column" in the text.

**2026-10-17 round 6 (grand campaign), builds 7678e1f → ea04bec.** Menu → Grand Campaign →
French Empire → End Turn → dispatches → select III Corps → march Belgium → Rhineland. No server
errors. Shots in `docs/shots/`.
- Fixed (Kit, affects every screen): **panels with a list layout grew past the screen and hid
  their content.** `Kit.panel`'s gilt Trim frame is a direct child sized to the panel, so a
  `UIListLayout` on the panel stacks it as a row; on an auto-sized panel that inflates the panel
  and pushes the real rows below it. Seen on the nation picker (1037 px, the buttons at the
  bottom edge, `grand-nation-before.jpg`), the dispatches parchment and the army and province
  panels (empty walnut blocks, `grand-army-before.jpg`), and in round 5 on the tutorial panel.
  The Trim now sits in a `Folder` (layouts ignore Folder children), so every panel sizes to its
  rows (`grand-nation-after.jpg`, `grand-army-after.jpg`, 278 px for the picker).
- **Incident: 2199ae7 → b00fb2a did not boot.** `CampaignUI:776: Expected 'end' (to close
  'function' at line 375)`, so `Main` failed and the screen was blank sky. ea04bec fixed it.
  Second boot break today after `Kit.MORALE`; a Luau parse of `src/` before each push would
  catch both (no luau CLI on this Mac, so I cannot run it here).
- The recruit-list (province ids as 0-gold units), men-vs-strength and "marchs" bugs I found on
  7678e1f were fixed by the cloud in b00fb2a at the same time; I dropped my copies.
- Open: the army title in Garamond reads "ĪI Corps" for III Corps (the three I's merge); the
  province names on the board are too small to read at the default zoom; the board's corner
  shows the edge of the table and sky.

**2026-10-17 round 6b (grand campaign AI), build 61a1c76.** Boots clean. As France, ended 8 turns
without moving (Jan 1805 → May 1806) through the Campaign remote, answering events with the
default and one battle with auto-resolve: no refusals, no client or server errors, treasury
+223/turn, armies on the board 22 → 27. With France idle, Austria beat Bavaria, Württemberg and
the Kingdom of Italy and dictated peace on the first two by Jan 1806; plausible, but France's
allies fold fast if the player does not move (`grand-dispatches.jpg`). Notes: the event line
"Sep 1805: Trafalgar." has no text after the name; a long dispatch list is one tall parchment,
fine at 12 lines, may need a scroll after a busy year.

**2026-10-17 round 7 (Tutorial + Grand Campaign as France), builds 64f7aa3 → 8598156.**
Shots in `docs/shots/`. No EoE script errors on client or server at any point.

*Fixed here (please run `tools/check.sh`; I have no Luau CLI):*
- **Campaign saves stop working one minute into every session, and a fought battle then rolls the
  campaign back.** `ProfileStore.update` bumps `revision` on every write, including
  `claimSession`, and `CampaignService` renews the claim every 60 s on both stores. From then on
  the stored revision is ahead of `state.revision`: every checkpoint fails "stale" (the client
  gets `kind=error … Could not save the grand campaign (stale)`, which the UI does not show), and
  `onGrandBattleEnded` answers the "stale" commit by reloading the last good profile. Seen: Fight
  at Nov 1806 turn 12, Return to Campaign showed Jan 1806 turn 7 with both armies back on the
  Rhine. Same for the small campaign's `store`, and for live DataStores, not just Studio.
  Lock-only writes (claim, renew, release) now keep the revision; test added to "checkpoint +
  commitBattle …" (renew, then checkpoint succeeds); its revision assert is 1 after the claim
  (was 2). Verified in Studio: 77 s into a session, 3 end turns and 4 more with marches, no save
  errors; a fought battle at Jan 1806 returned to Jan 1806 with the defeat in the log.
- **Tutorial lesson 7 (guns) could not be finished.** At the ring (480, 330) the battery stops at
  z 303 below the crest and the ridge hides the Grenzers; on the crest, facing north from the
  march, the Grenzers sit 38° off its 30° arc, so it never fires. Ring moved to (480, 355); the
  lesson also counts a battery deployed inside the ring; text now says the battery starts
  limbered (it did, the old text said "Limber the battery") and to right-drag to aim.

*Tutorial, open:*
1. Lesson 9 (Cavalry!) can stall: the chevaulegers were drawn into my lesson-8 hussar charge,
   were last seen on our bank (744, 423), then went out of sight, and the one-shot step-9
   AttackMove never brought them; 100 s with no cavalry, Skip step needed. Re-issue the order
   while the step is active, or accept a square after N seconds.
2. Lesson 11 (Ebersdorf): the brook fix works (battalions path over the bridge, none stuck in
   water), but the brigade cannot take the village: units stop idle with status "No target"
   60–70 studs short; Austrians inside Ebersdorf are invisible from there and silently block
   movement (one battalion went into melee with something unseen); the routed Grenzers froze in
   "routing" on the village centre (637, 690) for minutes; Charge on them is refused "Invalid
   target"; the objective sat "contested", progress 0, for 20 game minutes
   (`tutorial-bridge-jam.jpg`: four battalions piled on the bridge exit). A player sees a
   brigade that ignores orders, with no message why.
3. The lesson-6 battalion loses its firefight with the Grenzers alone and routes during lesson 7.
4. The stale "Move on to the next lesson" tooltip still stays over the Skip buttons after a click.
5. The debug beacon (top right, y 90) covers the panel's "AIDE-DE-CAMP · n/11" line.

*Grand Campaign as France, open:* Third Coalition fires May 1805 → war with Austria, Russia,
Naples, Sweden in Jul 1805, as history. Recruit, march (Normandy → Belgium → Rhineland in one
turn), end turn, events, battle prompt, Fight → battle → results → Return to Campaign all work.
1. The battle prompt lists one army per side (Grande Armée 6,040 v Army of Italy 7,040, "odds are
   poor") but the battle used both French armies (9,600 v 13,623). Show every army that fights.
2. The campaign battle is the Jena map: "Battle of Lower Austria" with Wenigenjena, Camsdorf and
   Camsdorf bridge; its briefing says Sep 1806 while the campaign says Nov 1806.
3. Results chronicle: "01:10 prussia captured Camsdorf" in a battle against Austria; raw lowercase
   faction ids. Notes say "Your formations broke 8 times" next to a table that says Routed 1.
4. Armies walked into Tyrol with 11,142 Austrians and no battle followed (they had left?); four
   army figures in one province overlap (`grand-board.jpg`); province names and army plates are
   too small to read on the board.
5. "Kingdom of Prussia" runs into its flag on the nation picker (`grand-flags.jpg`).
6. Casualties back to the campaign not verified: the battle I fought after the fix had no French
   orders and maybe no French losses; armies kept 6,040 / 3,520.

*Look (new lighting/terrain):* the teal wash is gone and roads are thin dark lines (good), but the
ground is now saturated orange, reading as desert, not the olive-gold of the reference
(`menu-orange.jpg`); the countryside outside each map shows flat dark-green cut-out patches;
the tutorial brook ends abruptly at the map's east edge; the crimson rout ribbon in the ticker
is unreadable (dark text on dark red, `campaign-battle.jpg`).

**2026-10-17 round 8 (generals and abilities), build 07f9b0e.** Boots clean; Jena runs with no
EoE errors. Napoleon's HQ carries `general=napoleon`; the Vive l'Empereur! button (selected HQ,
bottom left) fires from a click, the ticker reads "Napoléon: Vive l'Empereur! (10 formations)",
the button greys out while recharging and a second request is refused "Ability is recharging";
its tooltip shows the effect text. Hohenlohe's AI used Inspire three times in one battle.
- Fixed: **accented and dashed names were broken in capitals** (`plates-before.jpg`): the HQ plate
  read "NAPOLéON �� IMPERIAL HQ", and "17E LéGèRE", "à CHEVAL", "RéSERVE". Roblox's
  `string.upper` is byte-wise: it leaves é/è/à lowercase and turns the lead byte of "—" (and of
  "’", "…") into an invalid sequence, which also stopped the HQ name from splitting at the dash.
  New `Kit.upper` (UTF-8 aware, Latin-1 letters and œ/ÿ) now backs `Kit.title`, caps buttons,
  `Kit.spaced` and the name plates in `Figures` (`plates-after-ability.jpg`: "NAPOLÉON / IMPERIAL
  HQ", "17E LÉGÈRE", "9E CHASSEURS À CHEVAL").
- Open: the plates are now very large at the default deployment zoom and cover most of the field
  (`plates-after-ability.jpg`); fog weather still gives the whole map a strong teal tint.

## Known failures

None recorded yet.
