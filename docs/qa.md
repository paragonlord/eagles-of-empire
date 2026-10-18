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

## Known failures

None recorded yet.
