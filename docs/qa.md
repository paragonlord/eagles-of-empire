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
| Group selection, queued march, formation change, volley, artillery, cavalry charge, rout, full battle, one victory and one defeat | pass: victory at Austerlitz (round 4), defeats (rounds 37–38), UI-driven orders by mouse and keyboard (Ctrl+A, right-click march, limber/unlimber, follow camera; round 38) |
| Campaign turn → battle → casualties return → save → continue | pass (round 38, grand campaign: Tyrol, every battalion's strength returned exactly); the save is session-only in Studio without DataStore access, store paths covered by `tests/grand.spec.luau` |
| 1920×1080, 1366×768, ultrawide layouts; label overlap; click-through; camera clipping | blocked |
| Frame rate with normal roster and stress fixture; instance counts; restart leak check | partial: 60 fps in Jena and Waterloo battles on this Mac (rounds 11–12); stress fixture and leak check not run |
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

**2026-10-17 round 9 (moments and quick battles), builds 4ac313f → 554deef.** Boots clean on every
build. Battle select now has Quick (8–10 min) and Full (25–30 min) tabs with episode cards under
each battle (`battle-select-tabs.jpg`); the episode briefing with "What happened" reads well
(`episode-briefing.jpg`). Played "Lannes on the Landgrafenberg" twice at ×4: fog lifts at 4:00 as
the briefing promises, the "The fog lifts" moment fires with letterbox bars, a camera pan and the
title card (`moment-card.jpg`); the episode ends at 10:00 as a Draw with sane totals. No EoE errors.
- Fixed: generals without a named commander showed as **"Staff"**: the ticker read "Staff: Inspire
  (4 formations)" for Tauentzien, and the HQ inspector and ability button would read "General
  Staff". New `Generals.displayName(g, hqName)` names a generic HQ after its formation
  ("Tauentzien — Avantgarde HQ" → "Tauentzien"); used by the ability event text and both HUD
  spots. Checked on a Sim copy of the episode: "Tauentzien: Inspire (1 formation)".
- Open, the moment card: (1) it stays up 4 real seconds; at ×4 that is 16 game seconds of battle
  passing while the player reads two lines; pause or drop to ×1 while it shows, or hold ~7 s.
  (2) The band is 30 % transparent, so bright ground names and white unit plates show through the
  title (`moment-card.jpg`: "Landgrafenberg" sits across "THE FOG LIFTS", the battery's plate
  over the band's top edge); 0.1 or a darker band would keep it clean. (3) Moments do not appear
  in the results chronicle; "04:00 The fog lifts" there would tie the story together.
- Open: the second moment ("Closewitz is carried") needs Closewitz taken; in my ×4 attack-move run
  France took Cospeda but not Closewitz in 10 minutes, so it never showed. Chronicle still writes
  "prussia captured Cospeda" in lowercase ids.

**2026-10-18 round 10, build 9e6df9d.** Boots clean. Verified the round 9 fixes on the Landgrafenberg
episode at ×4: the moment card now pauses the battle (clock held at 03:05.7 for the whole card,
beacon "state=paused"), the band is dark and the title clean (`moment-card.jpg`); the chronicle
lists "03:05 Closewitz is carried" and "04:00 The fog lifts" with "France"/"Prussia" names; olive
fields read right at last (`menu-olive.jpg`). No EoE errors.
- Open: during the deployment intro sweep the camera rises high enough to see past FogEnd (1700):
  the far skirt is a flat cream slab ending in a hard edge against a bright cyan sky
  (`horizon-edge.jpg`). Fog colour and sky do not meet; tint the sky to the fog colour, or cap the
  sweep's height/pitch, or use an Atmosphere so the horizon blends.
- Open: at the default deployment zoom the far-LOD plates are blank white tabs with no text or
  colour (`far-banners.jpg`), so the line of battalions is a row of identical white flags; a
  faction-colour fill or the unit's number would make them useful.

**2026-10-18 round 10b (tutorial replay), builds 742bc5b → c01302d.** Played lessons 6–11 for real
(1–5 skipped; they passed twice before). **The tutorial now completes:** "Decisive victory ·
Ebersdorf is taken: the training is complete · 14:11" (`tutorial-won.jpg`). Lesson 6 ends with the
Grenzers withdrawing (battalion 561 v 250); lesson 7 passes with the battery in the ring; lesson 9's
chevaulegers come within 15 s; lesson 10 rallies. No EoE errors, co-op build included.
Two engine bugs blocked lesson 11; both fixed here (please run `tools/check.sh`):
- **One routing unit made a whole group order fail.** `Sim.precheck` refused the command if any id
  could not take orders, so a box-selected brigade with the broken conscripts in it got "routing"
  and nobody moved (seen twice: lesson 11 right after lesson 10's scripted rout). A group order now
  goes to the formations that can take it; a single routing formation is still refused. Test:
  "A group order skips routing formations instead of being refused whole".
- **Attack-move froze in musket range of a target it could not shoot.** `autoEngage` halted
  infantry for any visible enemy inside 0.95 × musket range, turned it halfway once, and never
  re-checked: with the target in Ebersdorf behind houses (or outside the 60° arc after the half
  turn) the line reported "No target", neither fired nor marched, forever (battalions idle at
  85–90 studs from IR 49 Kerpen for 5+ game minutes). It now halts only when it can fire
  (`fireBlockReason` nil, reloading, or only the arc), keeps wheeling toward the target while
  halted, and otherwise marches on. Test: "Infantry on attack-move does not halt in range of an
  enemy it cannot fire on". The existing "halts in musket range and fires", travel-column and new
  tests were run on the real Sim in Studio: all pass.
- Balance note, not fixed: the first assault (all four battalions, attack-move) broke both Austrian
  battalions in melee, then routed itself with ~15 % losses; a second attack-move after rallying
  took the village. Fine for a final exam, but a beginner may give up after the first rout; the
  aide-de-camp could say "Rally and go again" when the brigade breaks.
- Small: while the lesson panel changes, the title is blank for a moment ("2 / 11 |  |").

**2026-10-18 round 10c (Grand Campaign as France), build c01302d + feeab2a.** No EoE errors.
Played Jan 1805 → Jan 1806: marches, end turns, Third Coalition, battle prompt, Fight → deployment.
- Pass: the battle prompt lists every army with men and general, side totals and odds
  (`grand-prompt.jpg`: Grande Armée + III Corps 9,560 v four Austrian armies 18,280); province
  names on the board are readable and scale (Île-de-France, Lombardy); the briefing is dated by the
  campaign turn ("Headquarters, Jan 1806"); saves keep working past the first minute.
- Fixed: **the nation picker flags covered the first word of every name** (`picker-before.jpg`:
  "[flag]n Empire", "U[flag] Kingdom"). 9e6df9d made `Kit.flag` reserve the text padding itself,
  but the picker still set its own 46 px padding and shifted its flag −46 to match; the two
  cancelled (padding 2 px, flag on the text). The picker now passes a plain (5, 7) and lets
  Kit.flag reserve the space (`picker-after.jpg`).
- Open: "Battle of Lower Austria" still fights on the Jena-area map: the Saale, Camsdorf,
  Wenigenjena (`grand-battle-map.jpg`), and that map shows its raw edge against the sky with no
  surrounding skirt. Moves through neutral territory before the war are refused "noAccess"
  (correct), shown to the player only via the raw reason id if `Logic.reason` lacks it.
**With this, the Tutorial and the Grand Campaign pass as playable end to end.**

**2026-10-18 round 11 (graphics: uniforms, effects, countryside, lighting), builds 2ace55f → 0c1438b.**
Boots clean, no EoE errors. The countryside is a big step up (`countryside.jpg`): strip fields,
hedgerows and walls, tree-lined roads, villages with churches and a windmill.
- Performance, measured on this Mac (Jena, ×4, standard attack): 60 fps throughout. Bodies are
  capped and the part count levels off (EoEFigures 640 → 940 → 830 over 5 game minutes at the
  default height), so nothing piles up. **But zoomed in to the closest allowed height (120),
  EoEFigures jumps to ~14,000 parts (workspace 24,500)**: ~717 figures × ~20 parts each, at the
  default quality 2 (budget 800 figures). The budget counts figures, so the new detailed uniforms
  multiplied the real cost ~4×; at quality 3 it would be ~24,000 parts for soldiers alone. Still
  60 fps here, but phones are on the roadmap.
- **Most of that detail can never be seen.** At the closest zoom (camera 120 up, nearest figure
  151 studs, FOV 55) a soldier is ~13 px tall and a 0.1-stud cross-belt is 0.66 px
  (`closest-zoom.jpg`). Either let the camera come lower so the uniforms are actually seen, or
  drop the sub-pixel parts (belts, plumes, buttons, sword knots) beyond some distance and count
  the budget in parts.
- Dawn fog on Jena (`dawn-fog.jpg`): at the default height the field is a blue-white wash and the
  unit plates are barely legible for the first five minutes (Atmosphere density 0.45); right for
  "fog", but heavier than the reference and the colour is blue, not warm.
- The open-field strips in bright yellow-green read neon under the sun next to the muted greens
  (`countryside.jpg`); the reference fields are softer ochre and olive.
- Checked, not a bug: double-clicking a unit card does jump the camera to it, if the two clicks are
  under 0.35 s apart (my first test clicks were slower).

**2026-10-18 round 12 (graphics: the four views asked for, plus PvP solo), build 0c1438b.** Boots
clean, no EoE errors, 60 fps in battle (Waterloo PvP, 786 figure parts at default height).
- Pass: the Jena menu view shows the patchwork, Vierzehnheiligen with its church and ring, and the
  windmill on the Landgrafenberg slope (`r12-menu-before.jpg`, `r12-landgrafenberg-windmill.jpg`,
  `r12-vierzehnheiligen.jpg`). Waterloo's Hougoumont reads well: walled farm, courtyard, wood, and
  the poplars look like Lombardy poplars (`r12-hougoumont.jpg`). The Austerlitz fog lifts into a
  crisp winter sun over 20 s with no tint mid-way (`r12-austerlitz-sun.jpg`).
- Fixed: **fog and overcast rendered steel blue.** A dense Atmosphere is lit by the blue sky, so
  the grey Color/Decay in the `fog` and `overcast` grades came out blue-teal: all of Austerlitz and
  Jena before the fog lifts, and the whole Waterloo battle (`r12-fog-before.jpg`,
  `r12-waterloo-before.jpg`). Tested live: peach values (255,172,140) render neutral grey. Fog also
  gets exposure 0.6 (pale, not dull) and overcast density 0.38 → 0.3 so the far half of the field is
  readable (`r12-fog-after.jpg`, `r12-waterloo-after.jpg`). Clear grades are unchanged: the same
  shift there turns the sky into a sunset.
- Fixed: **hay stooks were near-black barrels** (`r12-stooks-dark.jpg`): Fabric (and Grass) render
  the straw colour dark brown on these parts. Now Sand: straw coloured and matte.
- Fixed: **autumn wheat strips read neon lime** (Limestone renders far brighter than its colour).
  178,162,104 → 150,132,86, soft khaki like the reference (`r12-menu-after.jpg`). Winter (Austerlitz)
  and summer wheat have the same glare (`r12-austerlitz-sun.jpg`), not changed yet: try ~0.84×.
- Fixed: the briefing title truncated long episode names ("THE FIGHT FOR…"); it now shrinks to fit
  (max 26 px).
- Open, intro sweep: from the start height (700) the whole map is a floating island with a hard
  cut edge in a flat teal "sea" (`r12-intro-island.jpg`): the 640-stud skirt is too narrow for that
  view. Start the sweep lower or steeper, or lay a huge flat ground plane under the skirt. On fog
  maps (Jena, Austerlitz) the sweep shows nothing at all, only fog, from start to end.
- Open, reeds: one-blob reeds read as dark green melons along every bank
  (`r12-goldbach-bridge.jpg`); Sand fixes the colour but not the shape. A thin pale fringe would read
  as a reed bed.
- Open, hedges: colour (47,68,29) on Grass renders near-black, so hedges look like black walls
  (Hougoumont, Austerlitz). Lighten ~30 %.
- Open, Goldbach bridges: each timber deck is 68 long over a 16-wide brook and sits at the higher
  bank's height, so most of it floats over the slope (`r12-goldbach-bridge.jpg`).
- Open, PvP (one player, Allied side): mode toggle, side buttons, Balance sides, roster, READY,
  speed locked at ×1 and the French AI advancing all work. But the second side's camera looks the
  same way as the first (north), so the Allies see their own line from the front with the French
  behind the camera (`r12-pvp-allied-view.jpg`); turning to face the enemy makes every ground label
  read upside down. Needs a per-side yaw and labels that flip with it. The mode and side carry over
  to the next battle (Vierzehnheiligen put me on Prussia). Co-op and two-human PvP need a 2-player
  Studio test (Test tab, Clients and Servers), which this setup cannot start.
- Small: `Lighting`'s `currentWeather` carries over between battles, so a clear battle started right
  after a fog battle (Jena → Vierzehnheiligen) sees "fog → clear", sets `fogLifted` and opens with a
  20 s fog-lift tween into the morning grade instead of the afternoon one.

**2026-10-18 round 13 (round 12 fixes, aged-post UI, new props, paper texture), build 31d4ccf.**
Boots clean, no EoE errors.
- Pass: the intro sweep now looks out over a ground plane fading into fog instead of a teal sea, and
  the fog thins with height (Atmosphere density 0.21 at 700 up), so the map is readable from the
  start (`r13-intro-high.jpg`). The map's far edge still shows as a low step. Hedges read green.
  Reeds are a pale fringe now, and the brook bridges fit the water (`r13-bridge-reeds.jpg`).
- Pass, PvP as Prussia: the camera faces the French on the Landgrafenberg and the ground labels read
  the right way up (`r13-pvp-prussia.jpg`).
- Pass: soldiers at the low camera: a two-rank Prussian line with flag and officer, with the
  Landgrafenberg windmill and Vierzehnheiligen church behind (`r13-soldiers-low.jpg`).
- Pass: the aged-post briefing (tea stain, foxing, crease, dépôt stamp) reads well.
- Added: **paper texture** `rbxassetid://4061980967` ("old paper texture" by Matroscin2, free) in
  `Kit.paperTextureId`. Note: an ImageLabel needs the *image* id; the Creator Store page shows the
  decal id (4061980998), and `game:GetObjects("rbxassetid://<decal>")[1].Texture` gives the image id.
  I tried four on the briefing. At the slot's 0.6 transparency all four are invisible because the
  stain layers cover the sheet, so I set it to 0.3: visible grain and specks, ink still sharp
  (`r13-paper-no-texture.jpg` vs `r13-paper-texture.jpg`). Spares: 6586250391 (smooth even
  parchment), 132770859 (aged brown, vignette baked in), 14456285433 (crumpled white: reads crumpled,
  not aged). Bark, grass and roof-tile textures not searched yet.
- Fixed: **the dawn valley-fog patches read as white ice sheets** (`r13-fog-patches-before.jpg`):
  4-stud flattened spheres at 0.55 show a hard shaded rim. Now 0.6 thick at 0.8 transparency: faint
  low mist (`r13-fog-patches-after.jpg`). On a slope the outline still shows where a patch cuts the
  ground. Stacking smaller discs gave visible rings, and Neon glowed.
- Open, UI: the coffee ring renders as two grey pill-shaped tabs over the Orders text, not a ring
  (`r13-paper-no-texture.jpg`, middle). The stamp is pinned to the panel's bottom right, so in PvP
  (the roster pushes the text down) it sits on top of the "What happened" text
  (`r13-pvp-prussia.jpg`).
- Open, hearth smoke: the grey egg-shaped puff above each chimney reads as a balloon at the low
  camera (`r13-soldiers-low.jpg`, bottom right).
- Small: isolated tree clumps and orchards read as piles of balls from the default height
  (`r13-intro-high.jpg`, left edge); the woods read fine as canopy.

**2026-10-18 round 14 (typography pass, typeface presets, place-name modes), build 66fb515.**
Boots clean, no EoE errors or warnings.
- Pass: the briefing's text column and margin work: weather and time sit in the margin and the
  stamp covers no text, in solo and PvP. The brass Settings button and wax Start Battle read well
  (`r14-settings.jpg`).
- Fixed: **the coffee ring was a pill** (81×132 px): its size was a scale of the sheet's width
  *and* height, so a tall sheet stretched it. It now has a UIAspectRatioConstraint and is round
  (`r14-briefing-ring.jpg`). SizeConstraint RelativeXX did nothing here, because the ring sits
  under the Deco folder.
- Fixed: **the typeface setting changed only the Start Battle button.** `Kit`'s typeset table
  was weak-keyed, and Luau drops an Instance key once its wrapper is collected, even while the
  label is on screen. Only labels a screen kept a handle on (startBtn) stayed registered. It now
  has strong keys and removes each label on Destroying.
- Fixed, uncovered by the above: labels built as ui text and then given `Kit.ITALIC` / `Kit.BOLD`
  by a screen (16 places: the briefing date, margin facts, difficulty note, results subtitle, menu,
  campaign, battle select...) turned into Source Sans on any preset change. `Kit.typeset` now
  re-roles a ui/figures label to body when its face is Garamond one frame after it is built.
  Checked: Antique gives Merriweather italic/bold, RomanAntique titles; back to Garamond restores
  everything (`r14-typeface-antique.jpg`).
- Fixed: **"Floating" place names were invisible**: the ground names hid, but the billboards
  (AlwaysOnTop) drew nothing in Studio (`r14-names-floating-before.jpg`). With AlwaysOnTop off
  they show (`r14-names-floating-fixed.jpg`); a name can now be clipped by a ridge or a formation
  plate ("losewitz", "Landgrafenberg" behind a plate). "Under cursor" shows only the hovered
  name (`r14-names-hover.jpg`); "Off" hides all.

**2026-10-18 round 15 (World QA 13-14), build 617ac90.** Boots clean, 0 errors.
- Pass: hearth smoke reads as small thinning wisps, not balloons (`r15-village-smoke-trees.jpg`).
  The fog patch that cut the Krippendorf slope is gone, and the rest are faint mist
  (`r15-fog-patches.jpg`). Floating place names now clear the unit plates and ridges
  ("Landgrafenberg" and "Closewitz" whole, `r15-names-floating.jpg`). The map edge ramps onto
  the ground plane more softly from the intro height (`r15-intro-high.jpg`).
- Open, lone and village trees at the low camera: the lobes are flat discs stacked with a visible
  gap between the lower and upper one, so each tree reads as two floating plates on a stick
  (bonsai), and a wooded skyline reads as a cloud of flying saucers (`r15-village-smoke-trees.jpg`,
  left and background). Thicker lobes (closer to `hgt = w * 0.9`) that overlap vertically would
  read as one crown both near and far.
- Small: the haystack in the village is one big golden ball the size of a cottage door
  (`r15-village-smoke-trees.jpg`, centre).

**2026-10-18 round 16 (mobile: touch layout), build b47a09a.** Boots clean, 0 errors. Touch
gestures and the order wheel need real touches; Studio MCP only sends mouse input, so those
are untested here (Device Emulator test for Bartosz).
- Pass, desktop: the battle HUD is unchanged (`r16-desktop-hud.jpg`).
- Pass, touch (Controls: Touch, 1080p, so scale 1.15): the deployment sheet has the touch hints
  (drag, hold then drag, pinch, twist), and the HUD has the minimap top left, the card bar
  bottom left and Select all / Settings / Menu over the command panel bottom right
  (`r16-touch-deployment.jpg`, `r16-touch-hud.jpg`).
- Fixed, desktop: **the Controls row pushed AI difficulty below the Settings panel's edge**
  (`r16-settings-cut-off.jpg`); the list scrolls but shows no scrollbar on desktop, so the row
  was simply gone. The desktop panel is 710 tall now (`r16-settings-desktop-fixed.jpg`).
- Fixed: **picking Touch never showed the touch Settings sheet.** The panel is built once and
  reused, and in Studio's emulator you must open it to pick Touch, so it was always the desktop
  build. It now rebuilds when Controls changes (`r16-settings-touch-sheet.jpg`).
- Fixed: **foxing spots were pills** on tall sheets, like the ring was (Fox3 89×133 px). Their
  w and h are both in sheet widths, so each now keeps its own aspect ratio (Fox3 78×64).
- Open, touch: switching Controls mid-battle leaves the HUD and briefing in the desktop layout
  until the next battle (the UIScale is only added at build time); fine for players, confusing
  in Studio. In the touch Settings sheet the volume percentages are clipped by the scrollbar
  ("80?", `r16-settings-touch-sheet.jpg`). The deployment's Settings button reads "SET.";
  "Settings" at 12 px or a gear would read better.

**2026-10-18 round 17 (Controls live), build 7b0d9e6.** Boots clean, no game errors.
- Pass: picking Touch in the briefing rebuilds it in the touch layout at 1.15 with "Options"
  that fits, and the Settings sheet's percentages now clear the scrollbar
  (`r17-live-touch-briefing.jpg`). Picking Desktop mid-battle rebuilds the HUD and the
  Settings panel in the desktop layout (`r17-live-desktop-battle.jpg`). All three round 16
  touch notes are closed. Gestures and the order wheel still need a Device Emulator run.

**2026-10-18 round 18 (server-built world), build 901927d.** Boots clean, no errors on the
client or the server.
- Pass: the server builds the menu world once (`[EoE world] built 11071 parts for jena in
  36.1 s`), and the client gate drops the loading screen when it has replicated (35 s). Starting
  Waterloo from the menu replaces it (MapId waterloo, 19194 parts) and the briefing is up after
  59 s (`r18-waterloo-server-world.jpg`). Jena with the new trees, villages and fields matches
  the client-built world from round 15.
- Fixed: **a teal cast over the whole field.** Studio puts its own `ColorGrading` effect
  (Retro tonemapper) and a zero-strength `Bloom` into Lighting; they are not in our place file,
  so they come from Studio and would be published. The grading cooled the greens and darkened
  the woods (`r18-grading-on.jpg` vs `r18-grading-off.jpg`, same camera). `Lighting.apply` now
  disables any ColorGradingEffect, so the grade is EoE's alone; checked in the rebuilt place.
- Note: 35 s (Jena) and 59 s (Waterloo) behind the loading bar is long for a phone. The server
  could build the next map while the briefing for the current one is read, or keep the last
  built maps.

**2026-10-18 round 19 (world loading checks asked for), build b8f7507.** No errors on either
side.
- Output: `[EoE world] built 11071 parts for jena in 36.1 s` / `client ready after 35.0 s
  (jena)`; `built 13312 parts for austerlitz in 42.5 s` / `client ready after 41.0 s
  (austerlitz)`. Jena's battle reuses the menu's world: no loading screen at all.
- Pass, holes: none when the fade ends, on the fresh menu boot (`r19-fade-end-menu.jpg`) and a
  fresh Austerlitz build (`r19-austerlitz-fade-end.jpg`). HITS_NEEDED can stay at 3.
- Pass, quality 1↔2 in battle: Low hides all 2978 parts of the `*Q2` folders (Woods, Villages,
  Water, Fields, GroundFog) and drops the Atmosphere; Medium shows them all again. No errors,
  nothing rebuilt.
- Pass, ground clicks: card-select the 34e Ligne, right-click open ground: it marches there
  ("Marching · No target") with the destination ghost on the spot (`r19-ground-click-move.jpg`).
- Fixed: **the loading screen could stay up forever.** In one Studio session the client ran at
  55-78 ms a frame; the gate waits for two frames under 20 ms and has no cap on that wait, so
  "Forming up…" never ended (150 s, `r19-stuck-forming-up.jpg`). A phone at 30 fps would hit
  the same wall. `Ready.step` now opens at most `FRAME_CAP` (3 s) after the world is in and
  settled; a test in `tests/world.spec.luau` covers it (not run here: no Luau CLI on this Mac).
- Open, Austerlitz: **236 valley-fog patches** cover the low ground as overlapping white discs
  with hard rims (`r19-austerlitz-fade-end.jpg`). Jena has 11. The "lowest 30 %" rule takes in
  most of a flat map; cap the count (~20, lowest and flattest first) or space them wider.
- Open, quality 1 (the phone default): with no Atmosphere the fog grade's plain distance fog
  (300-1500) washes the whole field white from the default height (`r19-quality1-fog.jpg`).
  Start/end ~800/3000 at q1 would keep the field readable.
- Open: the menu's long view toward the horizon is teal again (`r19-fade-end-menu.jpg`, top
  half), with ColorGrading confirmed off; it's the afternoon Atmosphere haze over the new
  far ground plane. Bring the menu camera lower or the haze warmer for that view.

**2026-10-18 round 20 (valley mist), build c535cf7.** No errors; menu 38 s, Austerlitz built
and faded in after 47.7 s.
- Pass: Austerlitz has no fog discs left (0 visible flat parts); 4 mist emitters run at 0.6 under
  the fog grade (`r20-austerlitz-no-discs.jpg`). Close to the Goldbach the mist reads as soft
  pale patches on the ground with no rims (`r20-valley-mist-close.jpg`); from the default
  height it is nearly invisible, which is fine for a light dawn mist.
- Note: `docs/assets-brief.md` says each slot is in `src/shared/Assets.luau`, but that file is
  not on main yet, so there is nowhere to paste an id. `Kit.paperTextureId` is still the only
  live slot.

**2026-10-18 round 21 (figures on the rendered ground; nothing clips), builds 32de9e6 and
2d27ca3.** No errors; Jena battle at 60 fps; menu ready after 35 s.
- Pass, figures: a French line on the Landgrafenberg's steepest slope stands on the drawn
  ground rank by rank (`r21-figures-on-slope.jpg`). Over 173 feet within 40 studs, the deepest
  sits 0.09 studs into the terrain: nothing sinks.
- Pass, world: houses on a slope stand on stone plinths and the walls step down the hill;
  nothing floats or sinks (`r21-houses-on-slope.jpg`). Assets.luau now exists with the world
  and texture slots.
- Note, `[EoE clip] world: 992 parts below ground (12182 checked)` on Jena (expect 0). It is
  mostly the check, not the world: it tests the four bottom corners of each part's *box*, and
  734 of the 992 are spheres or cylinders (crown lobes, bushes, stooks, trunks) whose box
  corners stick out past the round shape on a slope; 649 of all 992 are under 0.3 studs. Of the
  258 box parts, most deeper than 0.3 are reed strips (WaterQ2, 7 × 1.5 × 0.5), one 13 studs
  down at (1473, 2, 990) where the river leaves the map. For round parts, test the centre minus
  half the height instead of the corners, and the number will mean something.
- Still open from round 15: tree crowns read as stacked flat discs (`r21-figures-on-slope.jpg`
  background), and haystacks are big golden balls (foreground).

**2026-10-18 round 22 (world textures from the Creator Store).** No errors.
- Added to `Assets.luau` (image ids, all free): `roofTile` 18708362091 (aged clay tiles),
  `wall` 762795527 (white stucco), `bark` 6490108541 (brown pine bark). Picked from 18
  candidates on a contact sheet (`r22-texture-candidates.jpg`) and tried live on the slope
  village. `thatch` left empty: Jena has no thatched roof to try one on (4125863236, a light
  hay, is the candidate).
- Fixed in `WorldBuild`: textures are now tinted by the part's own colour (`Color3`), except
  bark. Untinted, every roof was the same bright orange and lost the palette's red-browns
  (`r22-roofs-untinted.jpg`); tinted, each house keeps its own roof and wall colour
  (`r22-village-textured.jpg`). Bark tinted by the dark trunk colour went black, so it stays
  as drawn.
- Fixed in `WorldBuild`: a trunk is a Cylinder along X, so its round side is Top, Bottom, Front
  and Back; the old face list (Front, Back, Left, Right) textured half the trunk and the two flat
  ends (`r22-bark-half-faces.jpg`). Cylinders now get the four round faces.
- Checked: at mid height the tiles read as red-brown roofs without shimmer
  (`r22-village-textured-mid.jpg`). 8142 Texture instances on Jena; this Studio session ran at
  15 fps with them, without them and with them again, so they cost nothing measurable (the slow
  frame rate is this Studio session; see round 19).

**2026-10-18 round 23 (clip checks, slopes, bridges, Hougoumont, Pratzen, Goldbach mist),
build de3fbe0.** No errors on either side.
- Server `[EoE clip]` after load is **not 0**: `world: 992 parts below ground (12182 checked)`
  on Jena, `1174 (14368)` on Austerlitz. As in round 21 this is mostly the check measuring box
  corners of round parts. Measured with each part's true shape (lowest point of a sphere, end
  circles of a cylinder, corners of a box), Jena has 308 parts below by more than 0.05 and **55
  deeper than 0.5**: 25 reed strips (WaterQ2), 16 Grass boxes and 7 Cobblestone boxes in Fields
  (hedge and road pieces), and a handful of others. Switching `World.checkClip` to the true
  shape would leave a short list worth fixing.
- Pass, `EoEClipCheck` (figures): with the attribute set, a line of the 14e de Ligne marched
  through Sokolnitz and over the Goldbach timber bridge and back; 104 one-second readings,
  every one `0 parts below ground of 11204` except the first (5, taken as the check switched on).
  On the field's steepest occupied ground (12 studs of rise over 30) the 8e de Ligne reads
  `0 of 12206` with the camera at the 55-stud floor. Ground rays cost 0.39 ms a frame typically,
  2.4 ms at most. On the deck the front ranks stand at deck height and the rear on the bank
  (`r23-bridge-crossing.jpg`, `r23-slope-figures.jpg`).
- Pass, Goldbach bridges: the timber deck spans the brook bank to bank with its piers in the
  water (`r23-goldbach-bridge.jpg`).
- Pass, Hougoumont: the farm walls run as 29 eight-stud segments, stepping down 3.3 studs across
  the farm; none sinks and none floats (`r23-hougoumont-walls.jpg`, the step at the join in
  `r23-hougoumont-wall-step.jpg`).
- Pass, Pratzen: houses stand on the ground with short stone plinths where it falls; the village
  sits on near-flat ground (at most 1 stud over 12), so the plinths are small
  (`r23-pratzen-houses.jpg`).
- Fixed: **the Goldbach dawn mist was invisible.** At 0.86/0.92 transparency the puffs vanished
  into the fog grade (`r23-mist-before.jpg`). Now 0.62/0.75: soft veils drift off the brook past
  the bridge (`r23-mist-after.jpg`, rebuilt place, after 35 s of steady emission). Only 4 anchors
  cover the whole map, so most of the Goldbach's length has none; one per bridge would spread it.
- Added: **thatch texture** `rbxassetid://4125863236` ("Seamless Hay Texture") in
  `Assets.thatch`; Austerlitz has 198 thatched roofs and all take it, tinted by their colour,
  reading as straw (`r23-pratzen-thatch.jpg`).
- Small: reed strips by the banks read as loose yellow planks up close (`r23-goldbach-bridge.jpg`).
  Chimney smoke puffs read as white balloons in the overcast and fog grades
  (`r23-hougoumont-wall-step.jpg`, top left). Under the fog grade the far ground plane reads as an
  orange band on the horizon (`r23-mist-after.jpg`).

**2026-10-18 round 24 (World QA 21-23), build 7151589.** No errors on either side.
- `[EoE clip]` with the true-shape check: Jena **92** (12489 checked, was 992), Austerlitz
  **58** (14429, was 1174). Not 0 yet. Of Austerlitz's 58, 46 are under 0.3 studs and only one
  is deeper than 1; 52 are the new reed stems (WaterQ2, Grass, 1-1.3 wide × 2-3 tall × 0.3)
  set on the steep bank, the rest single hedge, road and village pieces.
- Pass: trees read as single lumpy crowns, not stacked discs (`r24-trees-ground-level.jpg`);
  10 mist anchors along the Goldbach instead of 4; the thatch reads as straw close up
  (`r24-thatch-close.jpg`).
- Fixed: **no chimney smoke anywhere.** `WorldGen`'s `detail()` switched to the detail tier but
  left quality at 1, so the smoke anchors went into a "Smoke" folder while the client looks for
  "SmokeQ2"; the 65 anchors on Austerlitz never got an emitter. `detail()` now runs at quality 2
  (its only caller is the smoke). Rebuilt place: 65 emitters, faint grey wisps tinted to the
  fog, no balloons.
- Fixed: **the horizon was still an orange band under fog** (`r24-goldbach-orange-band.jpg`):
  the ground plane is tinted to the fog colour now, but the fog grade's Atmosphere Color/Decay
  (255,172,140) was itself the orange. Tried live: 236,206,190 for both turns the field blue
  again; Color 255,190,160 with Decay 236,206,190 keeps the field neutral, the horizon grey and
  the mist veils visible (`r24-goldbach-fog-fixed.jpg`).
- Open: the new reed beds read as flat green cards stuck in the bank, not stems (both shots
  above, along the brook). The haystacks (domed drum on a pole) are the right shape but pale
  cream with a swirl, so they read as cupcakes (`r24-haystacks.jpg`); a warmer, darker straw
  (~170,140,80) would read as hay.

**2026-10-18 round 25 (audio layer, ids empty), build e3cedb3.** No errors.
- Pass: every hook fires. With the Audio log on and the French sent into the Prussians on Jena
  (x4, 90 s): 56 volley events gave 47 `musketVolley` (cooldown/caps), 18 charges gave 12
  `bugleCharge` + 12 `cavalryCharge`, 13 routs gave 12 `rout`, plus `bugleRally` ×4,
  `unitDestroyed` ×2, `capture`, `momentSting`, `meleeClash`, `drumsMarchPr`; `ambienceFog` at
  deployment, `ambienceField` once the fog lifts; `battleMusicCalm`/`battleMusicTense` switch with
  the fighting; `uiHover` on the plaques. No cannon fired in that window, so `cannonFire` and
  `cannonBounce` were not seen.
- Fixed: **the Audio log printed every id-less loop every frame** (`ambienceField` 1786 times in
  45 s, `drumsMarchPr` 172), burying everything else. A loop with no id never enters `loops`, so
  each frame's `setLoop` logged it again. Each id-less loop now logs once until it stops (and is
  only marked logged while the log is on, so loops already running show when it is switched on).
- Fixed: **the new audio rows pushed AI difficulty out of the desktop Settings panel**
  (`r25-settings-cut-off.jpg`); the list scrolled but had no scrollbar on desktop, so the row was
  unreachable. The list now shows its scrollbar on desktop too (`r25-settings-scrolls.jpg`).
- Note: the music changed calm ↔ tense 5 times in 90 s of fighting; with real tracks that is a
  crossfade every ~18 s. A longer hold before switching back (or hysteresis on the tension score)
  would sit better.

**2026-10-18 round 26 (new AI, no orders given), build 1310358.** No errors.
- Jena, idle: Prussia advanced and took all three neutral objectives in the first minute
  (Vierzehnheiligen 0:38, Closewitz 0:45, Dornberg 1:04), then held them; at 25:00 **defeat**,
  "Time expired; the enemy holds more objectives" (`r26-jena-idle-defeat.jpg`). Doing nothing no
  longer wins. But not a shot was fired all battle (0 % casualties both sides): once it holds more
  objectives the AI defends and never comes for the army on the Landgrafenberg.
- Auerstedt, idle: a real attack. Poppel taken at 3:10, Hassenhausen at 8:04; by 12:23 Prussia had
  fired 42 volleys, ~21 cannonades and 11 charges, routed and destroyed French units and killed
  Davout's HQ. Batterie Oranien and Reitende Batterie Blücher stood on the right flank of the
  Prussian line beside IR 22 and IR 30, with clear lanes and gunsmoke (`r26-auerstedt-guns-flank.jpg`).
  Full run (rerun on build fc5fb32, again no orders): **defeat** at 25:00, "the enemy holds more
  objectives" (Hassenhausen 8:14 and Poppel 3:09 Prussian; France only took the Kösen bridge at
  19:23). Casualties France 31 % (2,615 of 8,400), Prussia 23 % (2,252 of 9,720), close to the
  harness's 34/23; 104 Prussian volleys, ~34 cannonades, 35 charges; Brunswick struck down at 8:00
  and his successor's Inspire on 12 formations (`r26-auerstedt-idle-defeat.jpg`).
- Reinforcing an objective under attack (Jena): with Prussia holding all three villages, four
  French battalions were sent at Vierzehnheiligen at 1:50. The Prussians seen within 200 studs of
  the village went 0 → 6 → 11 as they closed; their cuirassiers, hussars and Saxon dragoons then
  rode out 200–400 studs to meet the attack (10 Prussian charges, 4 of my routs), and the village
  held. Pass.
- Two-player test still to do: Studio's server task refuses command-line launch ("Invalid Launch
  Intent! Too many arguments provided"), so it needs Test → Clients and Servers → 2 Players by hand.

**2026-10-18 round 27 (oak mesh slot), build 2621d83.** No errors; menu ready in 35 s.
- Pass: 1143 oaks on Jena are now the 848-triangle mesh (one part each, fitted from its 12×13×12
  native box); the server world dropped from 12,794 to 9,743 parts. Close up: a real branching
  trunk and faceted crowns, base exactly on the ground (bottom 19.4, terrain 19.4)
  (`r27-oak-mesh-close.jpg`). From the playing height the avenue to Vierzehnheiligen and the
  orchards read as single trees (`r27-oak-mesh-mid.jpg`).
- Small: the mesh's green is brighter and more saturated than the procedural beeches and the
  reference palette; SpecialMesh.VertexColor around (0.8, 0.85, 0.75) would settle it.
- `[EoE clip]` still `92 parts below ground (9438 checked)` on Jena: the mesh trees did not
  change it, so the 92 are the reed stems and odd hedge/road pieces from round 24.

**2026-10-18 round 28 (oak, beech, pine and poplar meshes), build 08c265b.** No errors.
- Jena: 1567 mesh trees (oak 1143, beech 280, pine 144), one part each. The server world is
  **8,486 parts**, down from 12,794 with the part-built trees (−34 %); `[EoE clip]` 92 of 8181,
  unchanged (reeds and odd hedge/road pieces, round 24). 60 fps at the menu view, over the woods
  at 90 studs and at a wood's edge at 12 studs (Studio caps at 60, so the saving shows in the
  part count rather than the frame rate here).
- Pass: the woods read as one mixed canopy, faceted oak and beech crowns with pine tips through
  them (`r28-wood-edge.jpg`); lone trees stand on the ground with branching trunks (round 27);
  the road avenue to Vierzehnheiligen and the orchards read as rows of single trees
  (`r28-jena-mesh-trees-mid.jpg`).
- No poplars on Jena: poplar avenues are the summer look (Waterloo), autumn uses fruit trees, so
  the poplar mesh was not seen. Waterloo run cut short (Play was stopped from outside the test).
- Small: the mesh greens are brighter and more lime than the old woods and the reference
  palette, most visible close up; a VertexColor of ~(0.8, 0.85, 0.75) on the tree meshes, or a
  darker texture, would bring them to olive.

**2026-10-18 round 29 (cottage mesh, buildings on plinths), build 4325bfd.** No errors.
- Pass: 86 cottages on Jena are the 788-triangle mesh; the server world is 8,068 parts (8,486
  before). Up close they read far better than the part-built houses: windows, a door, a
  chimney, a stone plinth (`r29-cottage-close.jpg`). A sampled cottage's base is 4.2 over ground
  of 2.8–3.9 under its corners: it stands on the highest corner and the plinth fills the fall,
  as the new rule says. From the playing height Vierzehnheiligen reads as one village
  (`r29-village-mid.jpg`).
- Small: the mesh cottages are visibly smaller than their part-built neighbours (5.6 × 5.4 ×
  4.5 against ~8 wide), and their roof texture is a brighter orange than the tinted part-built
  roofs, so a few stand out from the street (centre of both shots). Scaling the slot up ~1.3×
  and darkening the roof half of the texture would blend them.
- `[EoE clip]` 92 of 7767, unchanged.

**2026-10-19 round 30 (Phase 0 fixes), synced from source through the Studio MCP.** No EoE
errors or warnings (only Roblox CorePackages `FoundationProvider` noise).
- How it ran: `python3 tools/build_place.py`, a local `python3 -m http.server 8765 --bind
  127.0.0.1`, and `tools/studio_sync.luau` executed in Studio (Edit) pulled the 16 changed scripts
  into the open place; Play, then mouse and keys through the MCP.
- Pass: far banners now wear the unit's colour (French blue tabs beyond 560 studs,
  `r30-far-banners-blue.jpg`). Menu → Play Battle → Vierzehnheiligen → deployment → running ×4.
- Pass: grand campaign picker → France opens on the 1805 map; Studio's memory store answers
  "No grand campaign in progress" (no stored save to be unreadable).
- Fixed: the loading screen's title and bar read black on navy (`r30-loading-title-dark.jpg`): the
  UIGradient sat on the CanvasGroup, which tints every child. It now sits on a backdrop frame
  (`r30-loading-title-fixed.jpg`).
- Fixed: on a 1081-px viewport the grand campaign's buttons covered the per-turn figure and the
  session warning (`r30-grand-topbar-overlap.jpg`); the bar now shrinks to fit
  (`r30-grand-topbar-fits.jpg`).
- Fixed: the ticker said "Prussia captured Vierzehnheiligen taken"; capture events carry the bare
  objective name.
- Not seen yet: a kept march route drawn on the board (the army panel covered the target in this
  window); the rule is covered by `tests/grand.spec.luau`.
- Load: each battle rebuilds the world (~36 s), even for an episode on the same ground as the menu
  map (jena → jena_vierzehnheiligen).
- Balance (3 seeds a cell, `tools/balance.py --seeds 3`): same majorities as the 5-seed table; the
  extra "wins 3/3" flags are the smaller sample, not new behaviour. Use 5 seeds for comparisons.

**2026-10-19 round 31 (unit types, TW orders and controls), synced through the Studio MCP.** No EoE
errors or warnings.
- Pass: the command panel is four rows (Line, Column, Square, Skirmish / Wedge, Fire at will, Charge,
  Run / Attack, Hold, Halt, Retreat / Limber, Auto, Rally) and fits the 96-px bar; Légère cards wear
  the one-musket-and-horn glyph, line cards the crossed muskets; every card has an amber ammunition
  bar under strength and morale (`r31-command-grid-type-cards.jpg`).
- Pass: K on the 17e Légère: the inspector reads Type "Light infantry", Shape "Skirmish"; close up
  the battalion is two loose, staggered ranks across a footprint twice a line's width
  (`r31-skirmish-close.jpg`).
- Pass: Ctrl+1 then R then a right-click: the card shows "1" and the running mark, the Run button
  lights, the status reads Marching and fatigue climbs (`r31-run-group-card.jpg`).
- Pass: the wheel zooms in steps down to the new 25-stud floor (MCP scrolls need a pause between
  them, a burst is dropped).
- Fixed: the running chevrons pointed backwards («); now ».
- Not exercised here (no MCP way to hold Alt or reach the window edge): Alt+right-click facing,
  edge scrolling, V follow. Bartosz: try them in a normal Play.

**2026-10-19 round 32 (Phase 3: ricochet, howitzers, downhill, fords, buildings, field cover).** No EoE
errors.
- Pass: Hougoumont episode: Reille's battery is "Obusiers du 2e Corps"; their shells reach the
  château and the "Hougoumont ablaze" moment fires on cue (`r32-hougoumont-ablaze-howitzers.jpg`).
  The command panel's 16th button is Occupy; O arms it.
- Fixed: 1er Légère ordered (O, right-click) into Hougoumont stopped in the wood, idle, 34 studs out
  (`r32-stuck-before-storm-fix.jpg`). Reproduced in the CLI: the British AI had garrisoned the
  château with the 2/3rd Foot Guards (the AI rule works); the storm check fired only within 24 studs
  and contact with the garrison holds attackers at 34. Now a Garrison order sees the holder from 90
  studs and storms (or gives way to a friend), enters a free building within 40 or on arrival. In the
  CLI rerun the 1er Légère charges at 60 s and breaks against the Guards at 120 s, as on the day.
- Not seen in Studio yet: fords as shallow water, a French garrison's corner sentries.

**2026-10-19 round 33 (Phase 6: campaign buildings, taxes, order).** No EoE errors.
- Pass: the province panel (Champagne & Lorraine) lists "Drill ground · Cavalry school · Foundry ·
  Fortress", the recruit list and a two-column Build grid with the next level of every chain and its
  price (`r33-province-buildings.jpg`).
- Pass: Farms · 150 starts work ("Building the farms: 1 turn", treasury 1,500 → 1,350); clicking the
  per-turn figure raises taxes to High (+223 → +445 a turn) (`r33-building-farms-tax-high.jpg`).
- To see by hand: a revolting province's panel text; the generals' escorts (120 sabres) charging.

**2026-10-19 round 34 (Phases 7–8: research, generals, siege assault), synced through the Studio MCP.**
No EoE errors or warnings on server or client.
- Pass: the army panel's general line carries his record, "General Masséna ★★★★ · Lombardy / 0 won,
  0 lost, 0 fortresses taken", over a full-width Forced March button (`r34-army-career.jpg`).
- Pass: war on Austria, Masséna into Venetia; Archduke Charles withdrew, and at the turn's end
  Venetia read "Besieged by French Empire: falls in 1 turn unless relieved" with an Assault button
  (`r34-siege-assault-button.jpg`). Assault opens "Storming of Venetia": 3,520 against the
  garrison's 1,320 (2 battalions and a battery for Fortress I), odds favourable, and Fight /
  Auto-resolve / Call off (`r34-storming-prompt.jpg`).
- Pass: the tactical battle is on Venetia's own field (Caldiero, Verona, Vicenza) with the storming
  orders (`r34-storming-deploy.jpg`). The garrison took Caldiero at 03:28; the 7e Légère, first to
  reach a held village, broke against it (`r34-storming-legere-breaks.jpg`); time ran out with the
  enemy holding more objectives: defeat, 74 against 104 casualties (`r34-storming-defeat.jpg`).
  Back on the map Masséna had fallen back to Lombardy, his record "0 won, 1 lost", the Légère at
  526/600 (`r34-career-after-loss.jpg`). The fog hid the garrison inside the villages, so a
  headless check now proves it (`tests/ai.spec.luau`: the garrison occupies a village).
- Pass: split one battery off: "Army of Italy (detachment) · No general" shows Forced March and
  Appoint General; appointing gives "General Augereau ★★", treasury 1,723 → 1,223, strength
  455 → 500 (`r34-appointed-augereau.jpg`).
- Pass: Research lists Military / Industry / Philosophy with known, open (gold, with price) and
  locked subjects; Lancers → "Studying Lancers: 0 / 450 (+35 a turn)" (`r34-research-lancers.jpg`).
- Fixed: Forced March stayed clickable on an army that had just retreated with 0 moves, which let
  a beaten army march again. A forced march is now decided before the army moves (full moves
  only, `alreadyMarched`), in the server and the button.
- Not seen yet: a general falling with his HQ, reinforcements marching onto a campaign field
  (Charles refused battle). Both are covered by `tests/grand.spec.luau`.

**2026-10-19 round 35 (Phase 9: trade, access, gifts, spies), synced through the Studio MCP.** No
EoE errors or warnings.
- Pass: every nation in Diplomacy has a second row, Trade / Access / Gift 500, greyed for Britain
  (at war). Trade with Prussia: per turn +223 → +273, the button reads "Trading"; Austria (−40)
  refuses with "They refuse your proposal"; a gift to Austria takes 500 (1,500 → 1,000) and
  lengthens its relations bar (`r35-diplomacy-trade.jpg`).
- Pass: Champagne (no government) shows "Recruit spy · 300" greyed; Paris (Prefecture) recruits
  one: 300 gold, a cloaked figure on a gilt-rimmed plinth beside the Paris armies. Selected, it
  glows and the panel reads "Spy · Île-de-France · 2/2 marches" with Sabotage greyed ("Only inside
  a fortress you besiege") (`r35-spy-panel.jpg`). A right-click on Bavaria (three marches)
  answers "Too far for this turn"; on the Rhineland the spy goes (0/2), and the Bavarian and Saxon
  armies come out of the fog (`r35-spy-rhineland.jpg`). The Bavarian Army's panel lists its six
  regiments (`r35-spy-reveals-bavarians.jpg`).
- Fixed: the campaign's left column was a full-height scrolling frame, so with any panel open it
  swallowed clicks on the map anywhere in the left 362 px, even below the panels (the spy and
  Piedmont could not be clicked there). It is now only as tall as its panels.
- Fixed: the first spy token was ~9 px wide at the opening zoom; it is now larger, with a gilt
  rim like the army plinths.
- Harness note: Escape in Play opens Roblox's own menu, which eats clicks until a second Escape.
- Not seen yet: sabotage inside a besieged fortress (covered by `tests/grand.spec.luau`).

**2026-10-19 round 36 (Phase 10: the navy), synced through the Studio MCP.** No EoE errors or
warnings. Played as Britain.
- Pass: every 1805 fleet lies off its port's pier: Channel Fleet (England), Cork Squadron (Ireland),
  the Batavian Squadron (Holland), the Brest Squadron (Normandy), the Danes (`r36-fleet-tokens.jpg`).
  Clicking the Channel Fleet opens its panel ("England & Scotland · 3/3 lanes, 10 ships of the line ·
  6 frigates", how sailing and blockades work); the England panel offers "Frigate · 400" and
  "Ship of the line · 900" (`r36-fleet-panel.jpg`).
- Pass: a right-click on Holland sails the fleet there (0/3 lanes). At the turn's end: "Naval
  battle off Holland: United Kingdom defeats Batavian Republic, which loses 2 of 5 ships"; the
  Channel Fleet is down to 8 + 5, the Dutch survivors fall back to Belgium
  (`r36-naval-battle-holland.jpg`), and Holland reads "Blockaded by an enemy fleet: the port earns
  half its income" (`r36-holland-blockaded.jpg`).
- Fixed: the ship plates sat below the waterline (the sea hid them) and the sails were set
  fore-and-aft along the coast, so the camera saw them edge-on. Ships are now drawn broadside to
  the board camera with square sails, like the army figures, and the plate rides above the hull.
- Fixed: "10 ship of the lines" reads "10 ships of the line".
- Small: the sails face away from the board's sun and read grey rather than white; a ship mesh
  (Bartosz's asset list) would do better than parts.
- Not seen yet: an escorted landing, a fleet built in port, Trafalgar removing the French and
  Spanish fleets (all covered by `tests/grand.spec.luau`).

**2026-10-19 round 37 (Phase 11: modes and presentation), Studio MCP, scripted.** No EoE errors.
Studio stopped rendering partway (screen captures timed out and the client sat behind its
loading screen, as when the display sleeps), so this round checked the live game through
remotes and the client's GUI tree instead of screenshots.
- Pass: the loading screen showed a tip under the bar ("Fire by rank lets a halted line reload
  faster; British infantry was famous for it.").
- Pass: `command` = other, then Jena: deployment as Prussia (viewer `prussia`, player `prussia`,
  enemy `france`), briefing "14 October 1806. You command Prussia. France comes to take the
  field: hold the objectives until time runs out, or break their army." At ×4 the French AI
  attacked and won the field.
- Pass: own formations' snapshots carry `kills` (the top French-facing battalion reached 173).
- Pass: `custom` {Britain against France, Belgium field, 8,000 gold, 6 line, 2 rifles, 2 light
  cavalry, 2 batteries}: accepted, deployment of "United Kingdom against French Empire" on
  `province:belgium`.
- Pass (code path): a round-shot cannon event fed to the client effects creates the iron ball
  and its streaks; the live events in the sampled minute were canister at close range.
- Studio checklist (Bartosz, by eye): the battle picker's tab row (Quick · Full · Custom battle and
  "Command: history's army"), the custom battle screen and its Fight, a ball skimming through its
  grazes, firing lines loading and levelling on their own beats and bayonet thrusts in melee, the
  results' Kills column, "Most enemy casualties" and the In history section.

**2026-10-20 round 38 (whole-game balance pass; round 37's checklist by eye), Studio MCP.** No
EoE errors. Studio rendered again; synced 6 scripts and played by mouse and keyboard.
- Pass: the loading screen shows a tip; a map takes ~36 s to build (7,551 parts), so "Raising the
  hills…" at 30 % is the build in progress, not a hang (last round's stall was the display asleep).
- Pass: the picker's tab row reads Quick · Full · Custom battle · "Command: history's army"; a
  click flips it to "Command: the other army" with its tooltip (`r38-picker-command.jpg`).
- Pass: the custom battle screen (nation, enemy, eight fields, three budgets, the unit list)
  counts "Spent 2950 of 8000 gold · 8 of 20 regiments"; Fight opens the custom briefing and the
  battle starts with the army bought (`r38-custom-battle.jpg`).
- Pass: lines of figures in two ranks, flags and mounted officers read well up close; a firing
  line stands in its own smoke and "3e de Ligne is blooded: experience 2" appears
  (`r38-line-firing.jpg`); the 1er de Ligne in melee in Closewitz stands round the houses
  (`r38-melee-closewitz.jpg`). Follow camera (V) and Ctrl+A work. The reload and thrust beats
  cannot be judged from stills.
- Pass, faint: the round-shot effect, fired by script at the view's centre, draws the iron ball
  and its grey grazing trail (`r38-round-shot.jpg`); from the normal camera height the ball is a
  few pixels and the trail a thin line. Fixed: static probes at a normal command zoom (134 studs
  away) show a 0.7-stud ball as a speck, 1.3 as a clear dot, 3 as a big ball
  (`r38-ball-sizes.jpg`); the ball is now 1.3 and its trail 0.4 thick (was 0.18).
- Pass: the results' order of battle has the Kills column, and the kills add up to the enemy's
  casualties (620); "Most enemy casualties: 3e de Ligne, 464" (`r38-results-kills.jpg`). After a
  listed episode (Landgrafenberg) the In history section gives the summary and "History went
  otherwise: France carried the day." (`r38-in-history.jpg`).
- Seen: a player battery ordered across a hedge stopped short once ("Holding · Limbered");
  re-ordered, it went. Not reproduced.
- Not checked by eye: Waterloo after the balance pass (covered by `tools/balance.py`).
- Pass, the grand campaign loop end to end: a new campaign as France (session-only save in
  Studio), war on Austria, Masséna's Army of Italy (3,520) into Tyrol against Archduke Charles
  (7,040), with the three Austrian armies next door in Vienna joining as reinforcements (34
  formations). Fought on the Tyrol map (Innsbruck, Brixen, Wörgl): a defeat on objectives,
  France 1,005 of 3,640 lost (`r38-tyrol-defeat.jpg`). Back on the board, July 1805: Masséna
  retreated to Lombardy with 2,515 men (3,520 − 1,005), the battery gone and each battalion at
  its battle strength (25e 299/600, 26e 280/600, 27e 462/600…), and his career reads "0 won,
  1 lost" (`r38-massena-after-tyrol.jpg`); the log has "Battle of Tyrol: Austrian Empire defeats
  French Empire".
- Harness note: driving the campaign by remotes skips the client's "in the grand campaign" flag,
  so that battle's Return to Campaign opened the Thuringian map; opening Grand Campaign from the
  menu showed the same session. Through the UI the flag is set.

## Known failures

None recorded yet.
