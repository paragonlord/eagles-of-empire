# Plan: toward Total War: Napoleon

Living tracker. `[x]` done, `[ ]` to do, `[!]` blocked (reason given). One task = one commit,
`tools/check.sh` green before each. Phases end with the balance harness (if the sim or AI
changed), a place rebuild, a Studio QA round (`docs/qa.md`) and a push.

Kept on purpose: 1 figure = 25 men (performance), naval battles are auto-resolved (no 3D sea
battles), the campaign is single-player.

The gate history of the first build (gates 0–6) is in git history and `docs/qa.md`.

## Phase 0: fix what is broken
- [x] Corrupt campaign save refused and kept, never overwritten
- [x] Nav never links brook banks without a bridge
- [x] Cavalry in melee with a square takes `SquareReturnsDamage`
- [x] Hard AI morale bonus applied; infantry ammo in Config; dead config removed; rules.md facing text
- [x] Campaign: army `path` sent; replenish and war-on-ally rules agree between UI and server
- [x] Far banner tabs tinted by faction

## Phase 1: real unit types
- [x] `type` on units, `Config.UnitTypes` merged over the class stats
- [x] Types inferred from regiment names in every scenario
- [x] Per-type stats (rifles, grenadiers, guard, light/heavy cavalry, dragoons, horse artillery)
- [x] Campaign unit types map onto sim types
- [x] Cards and inspector show the type

## Phase 2: TW orders and controls
- [x] Skirmish order for light infantry and rifles
- [x] Run / walk
- [x] Fire by rank (passive)
- [x] TW hotkeys: speed on +/-, control groups 1–9, Ctrl+A, double-click selects type, order keys, attack-move, face
- [x] Cards show ammo, fatigue, group number
- [x] Unit stats panel; inspect visible enemies
- [x] Camera: edge scroll, follow unit, lower minimum height

## Phase 3: battlefield physics and terrain
- [x] Round shot travels a lane and bounces through what is behind (friendly fire)
- [x] Howitzer shells: indirect, area hits
- [x] Downhill charge and melee bonus
- [x] Fords
- [x] Garrisonable buildings (strongpoints)
- [x] Walls and hedges as cover lines

## Phase 4: generals
- [x] One aura per HQ; corps generals in full battles; local death shock
- [x] General's cavalry bodyguard
- [x] Experience earned in battle

## Phase 5: battle AI
- [x] Defence: reverse slope, garrisons, skirmish screens, counter-attacks, cavalry counter-charges
- [x] Attack: pin and flank; light cavalry hunts routers and guns
- [x] Balance flags: Hougoumont guns and Spielberg normal fixed; battle roles added; whole-game pass after Phase 11 (squares without flanks, collapse on field strength, march gridlock, defender posture and outposts): 8 flags against history down to 4, Waterloo to the allies in ~40 %; Auerstedt (Prussia) and the episode draws stand (docs/balance.md)
- [x] Reinforcements join the line, reserves counterattack lost objectives (a garrison counts double), Auerstedt's Prussians arrive in pieces: against history 4 → 3, Waterloo to the allies in 23 of 30 (docs/balance.md)

## Phase 6: campaign economy
- [x] Buildings and construction; recruitment needs buildings
- [x] Tax levels, public order effects, rebellion
- [x] Gradual replenishment
- [x] Winter and supply attrition
- [x] Settlement panel and tax control

## Phase 7: technology and national rosters
- [x] Research tree (unlocks units, battle passives, economy)
- [x] National rosters

## Phase 8: campaign armies and battles
- [x] Per-province battle maps
- [x] Adjacent armies reinforce battles
- [x] Forced march
- [x] General careers: traits, rank, death, appointment
- [x] Siege assault

## Phase 9: diplomacy and agents
- [x] Trade agreements, military access, gifts
- [x] Spies

## Phase 10: navy (auto-resolved)
- [x] Fleets, escorts, blockade, naval auto-resolve, Trafalgar (after Trafalgar the Royal Navy AI blockades)
- [x] Fleet tokens on the board

## Phase 11: modes and presentation
- [x] Play either side in historical battles
- [x] Custom battle
- [x] Results: kills per unit, history comparison
- [x] Loading screen tips
- [x] Visible round shot
- [x] Reload and melee animations

## Assets (Studio)
- [~] Priority sounds from the Creator Store: 13 slots filled with measured ids (volleys, cannon, hooves, drums, ambience, four music tracks, victory) and checked playing in a battle; not yet listened to by a person (`docs/assets-brief.md`); bugles, melee, clicks, rain still empty
- [ ] Soldier meshes (Bartosz picks)

# Graphics pass (toward the TW:N look; plan approved 2026-10-20)

Art: Studio AI meshes (generate_mesh / generate_texture, published to Bartosz's account),
painterly realistic. Ids live in `src/shared/Assets.luau`; an empty slot keeps the part build.

## G0: foundations
- [x] Realistic lighting style (Technology is not script-writable; LightingStyle Realistic, quality-first shadows at High)
- [x] Mesh pipeline spike: generated pieces publish as assets; one figure retextures per nation
- [x] Art direction rewritten in `docs/assets-brief.md`
- [x] Shot rig: Studio-only `EoECamera` workspace attribute moves the battle camera

## G1: soldiers, horses, guns
- [x] Infantry kit per nation (eight posed pieces; arms/musket/legs keep the anim codes)
- [x] Headgear set: bearskin, bicorne, crested helmet, Highland bonnet (the Austrian kaskett failed twice: Austria wears its kit helmet)
- [x] Cavalry: horse and rider kits for the eight nations; officers in bicornes
- [x] Artillery: gun kits (French olive, Austrian ochre, blue-grey) with kit crews and a generated limber
- [x] Specials: Napoleon (Guard chasseur on a grey), officers in bicornes, kit drummers and colour bearers, bodyguards as kit riders
- [x] Men at the default view (far-slab switch 600/700/850 by quality, budget by piece count)

## G2: battlefield
- [x] Ground MaterialVariants (seven generated, in the place file; lighter season tints over them)
- [~] Lighting: LightingStyle Realistic, quality-first shadows at High; the four grades kept (they read well over the painted ground)
- [x] Place names off the battle at low camera
- [~] Props: olive tree tint, full-size cottage; generated hedgerow, willow, stone and trestle bridges, cart (wall and fence generations failed: part-built; no reeds or manor mesh)
- [x] Powder smoke banks, muzzle light (High), howitzer shell bursts, burning roofs on 'ablaze' moments
- [~] Map edge: the 5000-stud ground plane now takes the painted meadow too; the far edge was not re-checked from a low camera

## G3: campaign map
- [x] Real coasts, lakes and rivers (Natural Earth), province tint clipped to the shore
- [x] 3D Europe terrain with water, snow on the high chains
- [~] Ownership: gilt borders over land and the translucent owner tint (no separate overlay toggle: the tint is always on)
- [x] Settlements (mesh houses, a town in every province), piers on the real coast, army tokens on the nation's cavalry kit, fleets as a generated ship of the line
- [x] Labels: dark ink names; nation names across their lands at high zoom
- [x] Thuringian parchment map

## G4: menus and UI art
- [x] Public-domain battle paintings (menu, loading, results)
- [x] Unit card portraits (ViewportFrame)
- [x] Ruler portraits in the nation picker
- [ ] Ornaments: wax, stamp, eagle (not started; the code-drawn seal and stamp stay)

## G5: performance and phones
- [x] Frame time: Waterloo measured at High, Medium and Low (QA round 41); distant battalions refresh 15–30 times a second, the soldiers' script 13 → 2 ms at the default view; a real machine's frame rate still to see
- [x] Phone check (Device Simulator, iPhone 17 Pro): menu, battle picker, panels and the battle HUD fit; Low's haze restored
- [x] Final QA round and handoff (round 42, handoff 2026-10-21)

## Polish (2026-10-21)
- [x] Start-up 37 s → 5 s (world builders work in time slices)
- [x] Rivers never stand above their banks (tested on every map)
- [x] Quick battles: their battle's season and buildings; winter leaves
- [x] Hougoumont burns in the full Waterloo
- [x] Menu backdrop: low over the field, slowly turning
- [x] Campaign board: clear air, readable nation names, plates on the pole and off at far zoom
- [x] Grand-campaign dispatches: the turn's news only; Russian and Austrian flags; no empty top bar behind the nation choice
