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
- [~] Balance flags: Hougoumont guns and Spielberg normal fixed; battle roles added; Waterloo, Auerstedt, Hassenhausen, Spielberg easy/hard stand (docs/balance.md), moved to the whole-game pass

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
- [ ] General careers: traits, rank, death, appointment
- [ ] Siege assault

## Phase 9: diplomacy and agents
- [ ] Trade agreements, military access, gifts
- [ ] Spies

## Phase 10: navy (auto-resolved)
- [ ] Fleets, escorts, blockade, naval auto-resolve, Trafalgar
- [ ] Fleet tokens on the board

## Phase 11: modes and presentation
- [ ] Play either side in historical battles
- [ ] Custom battle
- [ ] Results: kills per unit, history comparison
- [ ] Loading screen tips
- [ ] Visible round shot
- [ ] Reload and melee animations

## Assets (Studio)
- [ ] Priority sounds from the Creator Store (ids listed in `docs/handoff.md` for approval)
- [ ] Soldier meshes (Bartosz picks)
