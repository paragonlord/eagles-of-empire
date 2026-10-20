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
- [~] Priority sounds from the Creator Store: candidates listed in `docs/assets-brief.md` ("Sound candidates") for Bartosz to audition; none wired in unheard
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
- [~] Artillery: gun kits (French olive, Austrian ochre, blue-grey) with kit crews; limber still part-built
- [ ] Specials: officer, drummer, colour bearer, bodyguard
- [x] Men at the default view (far-slab switch 600/700/850 by quality, budget by piece count)

## G2: battlefield
- [ ] Ground MaterialVariants
- [ ] Lighting regrade
- [x] Place names off the battle at low camera
- [ ] Props: retints and new meshes (willow, hedge, wall, fence, cart, reeds, bridges, manor)
- [ ] Powder smoke banks, muzzle light, shell bursts, burning buildings
- [ ] Map edge hidden

## G3: campaign map
- [ ] Real coasts, lakes and rivers (Natural Earth), provinces clipped to land
- [ ] 3D Europe terrain with water
- [ ] Ownership by border ribbons; political overlay toggle
- [ ] Settlements, forts, ports and token meshes
- [ ] Labels: contrast and nation names at high zoom
- [ ] Thuringian parchment map

## G4: menus and UI art
- [ ] Public-domain battle paintings (menu, loading, results)
- [ ] Unit card portraits (ViewportFrame)
- [ ] Ruler portraits in the nation picker
- [ ] Ornaments: wax, stamp, eagle

## G5: performance and phones
- [ ] Frame time at High and Low on Waterloo; LOD and pools tuned
- [ ] Phone check (Device Simulator)
- [ ] Final QA round and handoff
