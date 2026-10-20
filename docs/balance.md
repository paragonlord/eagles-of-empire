# Balance pass — AI vs AI

Run: `tools/balance.py` (bundles `src` with `tools/balance.luau` through the `tools/test.py`
machinery and runs it in the Luau CLI, four processes in parallel). Every listed scenario is played
with both sides under the same AI difficulty (easy, normal, hard), 5 seeds each: full battles for
40 minutes, episodes for their 10-minute limit. 180 battles take about 16 minutes of wall time on
four cores (a 40-minute Austerlitz is ~60 s; the no-contact runs of the first pass were the slow
ones). `--seeds`, `--difficulties`, `--only` and `--md` narrow or export a run.

Columns: winner counts over the seeds, the commonest end reason, mean duration (min), mean time to
the first volley/cannonade/charge, casualties as % of deployed (France / enemy), rout events,
formations shattered, formations destroyed or exited, objective flips, cannonades and cavalry
charges per battle, the historical result (`docs/battles.md`).

Flags (`tools/balance.py`): a side winning ≥ 90 % (allowed only when the battle was historically
lopsided *and* the winner is the historical one), ≥ 90 % draws, mean end before 4 min, a seed
without contact, casualties > 60 % or < 5 %, more than half of a side's formations shattered,
artillery that never fires, cavalry that never charges, objectives never contested, and quick
battles decided by the clock without a single capture.

## Final table (5 seeds, both sides AI; whole-game pass after Phase 11, 2026-10-20)

| scenario | diff | winner (n) | reason | min | contact | cas% F/E | routs F/E | shat F/E | lost F/E | flips | guns | charges | history | flags |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| jena | easy | france 5 | All objectives held | 17.9 | 2.7 | 36/53 | 8.6/21.6 | 2%/1% | 1.8/4.8 | 6.0 | 19 | 28.8 | French victory (decisive) | - |
| jena | normal | france 4 prussia 1 | All objectives held | 19.2 | 2.7 | 41/51 | 10.8/20.6 | 0%/0% | 2.4/4.8 | 6.2 | 15 | 28.4 | French victory (decisive) | - |
| jena | hard | france 5 | All objectives held | 18.6 | 2.4 | 38/53 | 10.0/20.8 | 0%/0% | 2.4/4.8 | 6.0 | 19 | 38.8 | French victory (decisive) | - |
| auerstedt | easy | prussia 5 | Your army has collapsed | 20.7 | 4.9 | 53/27 | 23.8/11.4 | 1%/3% | 6.6/1.8 | 4.2 | 51 | 19.4 | French victory (Davout outnumbered 2:1) | prussia wins 5/5 against history |
| auerstedt | normal | prussia 4 france 1 | Your army has collapsed | 25.1 | 4.7 | 60/38 | 21.6/13.0 | 2%/1% | 7.8/2.8 | 4.2 | 37 | 27.2 | French victory (Davout outnumbered 2:1) | - |
| auerstedt | hard | prussia 5 | Your army has collapsed | 19.8 | 4.8 | 60/28 | 22.2/6.6 | 6%/3% | 7.0/0.8 | 4.0 | 40 | 26.6 | French victory (Davout outnumbered 2:1) | prussia wins 5/5 against history |
| austerlitz | easy | russia 3 france 2 | Time expired; the enemy holds more objectives | 40.0 | 5.7 | 57/44 | 36.6/29.0 | 0%/0% | 10.0/5.2 | 4.8 | 26 | 37.8 | French victory (decisive) | - |
| austerlitz | normal | russia 4 france 1 | Time expired; the enemy holds more objectives | 40.0 | 4.6 | 58/50 | 43.2/38.8 | 0%/0% | 11.2/9.0 | 5.4 | 12 | 43.4 | French victory (decisive) | - |
| austerlitz | hard | russia 4 france 1 | Time expired; the enemy holds more objectives | 40.0 | 3.6 | 61/51 | 44.4/35.8 | 0%/1% | 11.2/8.0 | 5.0 | 30 | 55.6 | French victory (decisive) | france casualties 61% |
| waterloo | easy | britain 4 france 1 | The enemy holds every objective | 26.2 | 0.5 | 58/53 | 30.0/39.6 | 1%/2% | 7.8/10.0 | 6.8 | 67 | 44.8 | Allied victory (decisive) | - |
| waterloo | normal | france 5 | All objectives held | 21.6 | 0.5 | 49/62 | 29.2/47.0 | 1%/0% | 5.8/12.8 | 6.4 | 33 | 55.0 | Allied victory (decisive) | france wins 5/5 against history; britain casualties 62% |
| waterloo | hard | france 3 britain 2 | The enemy army has collapsed | 18.8 | 0.5 | 46/55 | 26.6/42.2 | 3%/0% | 5.8/13.6 | 6.0 | 49 | 49.4 | Allied victory (decisive) | - |
| jena_landgrafenberg | easy | draw 3 prussia 2 | Time expired with the field divided | 10.0 | 0.7 | 44/26 | 7.8/4.8 | 0%/0% | 1.2/0.6 | 2.6 | 7 | 6.4 | Closewitz and Cospeda taken | - |
| jena_landgrafenberg | normal | france 2 prussia 2 draw 1 | Time expired with the field divided | 10.0 | 0.7 | 37/29 | 6.0/6.8 | 0%/0% | 1.0/1.2 | 3.0 | 6 | 5.8 | Closewitz and Cospeda taken | - |
| jena_landgrafenberg | hard | prussia 3 draw 2 | Time expired; the enemy holds more objectives | 10.0 | 0.6 | 34/28 | 5.8/6.2 | 0%/0% | 0.2/1.4 | 2.8 | 4 | 7.2 | Closewitz and Cospeda taken | - |
| jena_vierzehnheiligen | easy | france 5 | All objectives held | 10.0 | 0.4 | 32/40 | 2.6/6.4 | 0%/0% | 0.4/0.8 | 1.8 | 9 | 13.0 | village taken, Grawert's line shot to pieces | france wins 5/5 |
| jena_vierzehnheiligen | normal | france 4 prussia 1 | All objectives held | 10.0 | 0.3 | 33/49 | 3.6/9.4 | 0%/0% | 0.4/2.0 | 2.2 | 10 | 12.0 | village taken, Grawert's line shot to pieces | - |
| jena_vierzehnheiligen | hard | prussia 3 france 1 draw 1 | Time expired; the enemy holds more objectives | 10.0 | 0.4 | 36/36 | 6.2/6.2 | 0%/0% | 1.4/0.8 | 0.8 | 5 | 15.4 | village taken, Grawert's line shot to pieces | - |
| auerstedt_hassenhausen | easy | draw 4 prussia 1 | Time expired with the field divided | 9.6 | 1.8 | 42/23 | 6.2/2.4 | 2%/0% | 1.4/0.2 | 2.0 | 3 | 8.4 | Gudin held Hassenhausen | - |
| auerstedt_hassenhausen | normal | prussia 5 | Time expired; the enemy holds more objectives | 9.3 | 1.6 | 50/26 | 7.4/0.8 | 0%/0% | 2.0/0.0 | 2.6 | 1 | 9.6 | Gudin held Hassenhausen | prussia wins 5/5 against history |
| auerstedt_hassenhausen | hard | draw 4 prussia 1 | Time expired with the field divided | 10.0 | 1.3 | 38/25 | 6.4/5.2 | 2%/0% | 1.0/0.2 | 2.2 | 5 | 9.6 | Gudin held Hassenhausen | - |
| auerstedt_spielberg | easy | draw 5 | Time expired with the field divided | 10.0 | 3.0 | 17/23 | 2.6/1.6 | 3%/3% | 0.0/0.2 | 2.0 | 5 | 6.2 | Friant turned the Prussian left | draw 5/5 |
| auerstedt_spielberg | normal | draw 5 | Time expired with the field divided | 10.0 | 3.1 | 24/18 | 4.4/1.2 | 0%/0% | 0.0/0.0 | 2.0 | 10 | 8.4 | Friant turned the Prussian left | draw 5/5 |
| auerstedt_spielberg | hard | draw 5 | Time expired with the field divided | 10.0 | 2.8 | 14/22 | 1.0/1.6 | 0%/0% | 0.0/0.4 | 2.0 | 4 | 6.2 | Friant turned the Prussian left | draw 5/5 |
| austerlitz_pratzen | easy | france 5 | All objectives held | 10.0 | 0.9 | 14/25 | 0.4/6.2 | 0%/0% | 0.0/1.6 | 4.4 | 6 | 1.2 | Pratzen taken | france wins 5/5 |
| austerlitz_pratzen | normal | france 5 | All objectives held | 10.0 | 0.9 | 21/22 | 0.8/6.8 | 0%/0% | 0.0/1.0 | 4.0 | 6 | 3.0 | Pratzen taken | france wins 5/5 |
| austerlitz_pratzen | hard | france 5 | All objectives held | 10.0 | 0.8 | 25/23 | 2.4/6.8 | 0%/2% | 0.6/1.2 | 4.0 | 8 | 2.8 | Pratzen taken | france wins 5/5 |
| austerlitz_sokolnitz | easy | draw 5 | Time expired with the field divided | 10.0 | 1.5 | 27/17 | 5.6/1.6 | 0%/0% | 1.2/0.2 | 3.0 | 10 | 0.0 | Telnitz/Sokolnitz held, allied left stuck | draw 5/5; cavalry never charges |
| austerlitz_sokolnitz | normal | draw 5 | Time expired with the field divided | 10.0 | 1.6 | 32/17 | 7.0/1.4 | 0%/0% | 1.4/0.0 | 3.0 | 6 | 0.2 | Telnitz/Sokolnitz held, allied left stuck | draw 5/5 |
| austerlitz_sokolnitz | hard | draw 5 | Time expired with the field divided | 10.0 | 1.6 | 29/16 | 6.2/1.4 | 0%/0% | 1.2/0.0 | 3.0 | 9 | 0.2 | Telnitz/Sokolnitz held, allied left stuck | draw 5/5 |
| waterloo_hougoumont | easy | britain 3 france 2 | Time expired; the enemy holds more objectives | 10.0 | 0.6 | 41/24 | 6.6/4.8 | 2%/0% | 0.6/0.8 | 1.4 | 0 | 1.8 | Hougoumont held all day | - |
| waterloo_hougoumont | normal | france 3 britain 2 | The enemy army has collapsed | 8.6 | 0.7 | 36/29 | 4.0/6.0 | 2%/0% | 0.0/1.2 | 1.2 | 7 | 2.8 | Hougoumont held all day | - |
| waterloo_hougoumont | hard | britain 4 france 1 | Time expired; the enemy holds more objectives | 10.0 | 0.7 | 38/25 | 5.4/5.4 | 0%/0% | 0.2/1.0 | 1.2 | 5 | 4.2 | Hougoumont held all day | - |
| waterloo_lahayesainte | easy | britain 3 draw 2 | Time expired; the enemy holds more objectives | 10.0 | 0.8 | 36/17 | 4.4/3.2 | 4%/0% | 0.0/0.0 | 2.8 | 22 | 3.6 | La Haye Sainte fell | - |
| waterloo_lahayesainte | normal | britain 2 draw 2 france 1 | Time expired with the field divided | 10.0 | 0.8 | 40/31 | 7.2/6.0 | 0%/0% | 0.4/0.8 | 3.6 | 32 | 4.8 | La Haye Sainte fell | - |
| waterloo_lahayesainte | hard | draw 3 france 1 britain 1 | Time expired with the field divided | 10.0 | 0.8 | 38/30 | 5.8/6.2 | 0%/0% | 0.0/1.0 | 3.0 | 23 | 3.0 | La Haye Sainte fell | - |

## What the first pass found (before any change)

1. **Nine of twelve scenarios never made contact.** The AI's only postures were defend / attack /
   withdraw, and `attack` needs a *seen* enemy outnumbered 1.5:1. Two defending AIs sat on their own
   objectives for the whole 40 minutes: Auerstedt, Austerlitz, Spielberg, Pratzen, Sokolnitz ended
   with 0 % casualties, no shot fired, and the side that started with more objectives "won" on the
   clock (Austerlitz 15/15 France, Pratzen 15/15 Russia, Auerstedt 15/15 France). Waterloo was a 3 %
   skirmish and a timeout. A human defending at Auerstedt or Austerlitz won by doing nothing.
2. **Batteries never fired** in 24 of 36 scenario/difficulty rows. The AI put its guns 25–35 behind the
   wing and its gun guard 35 *in front* of the gun, so its own infantry stood in the fire lane
   (`FriendlyBlocksFire`); in an attack the guns trailed the line limbered and were overrun.
3. **Guard duty ate armies.** A battalion sent to cover a battery kept the goal for ever; when the
   battery moved a fresh one was pulled. At Auerstedt 8 of 12 Prussian battalions ended as idle
   "covering Batterie …" and one advanced; at Spielberg 2 of 4 French. `exploit` had the same leak:
   five of Morand's battalions walked to the Kösen bridge, one every 20 s.

## Changes (all in `src/server/AI/init.luau`; no Config or formula change)

- **`advance` posture.** When the AI holds no more objectives than the enemy (own-side neutral
  objectives count as held, as `defend` already assumed), and on equal counts only when it is not
  outnumbered in deployed strength, its line attack-moves on the nearest objective it does not own,
  70 short of it, and engages in musket range as `attack` does. The historical attacker now attacks:
  Prussia at Auerstedt, the allies at Austerlitz and Sokolnitz, France at Waterloo, Pratzen,
  Hougoumont, La Haye Sainte, the Landgrafenberg.
- **Guns on the wing's flank** (lateral ±35, 10–25 behind) with a penalty for a position whose lane
  to the front crosses the wing point; in `attack`/`advance` they stand 90 further back (round-shot
  range, outside musket range of the contact line). The guard stands beside the battery, escorts it
  to its planned position while it moves, and is released when the battery is gone or has moved
  more than 60 away. A limbered battery that makes no progress for 30 s unlimbers where it stands
  (Bull's Troop spent 6 minutes "moving" inside Hougoumont). A deployed battery with ammunition and
  infantry within 60 stands and fires canister at cavalry instead of limbering (25 s helpless at
  shock ×3 — Wellington lost all three batteries, −5 morale each, in the first five minutes).
- **`defend` reinforces.** Wings whose objective has no known enemy infantry within 300 move halfway
  toward the objective that has; `exploit` sends one formation per objective.

Before → after (normal, 5 seeds): Auerstedt 0 % / 0 % casualties, no contact → 34 % / 23 %, contact
at 9 min, 41 cannonades; Austerlitz 0 % / 0 % → 54 % / 52 %, 17 cannonades, 30 charges; Spielberg,
Pratzen, Sokolnitz no contact → contact at 2–5 min with 25–35 % casualties; artillery silent in 24
rows → 2 (Hougoumont, below). Jena, which already worked (zones touch), ends faster (29 → 7 min at
normal) because the French AI now presses with everything instead of waiting to be outnumbered.

## Remaining flags and why they stand

- **Waterloo: France 15/15, collapse in 12–15 min.** With both sides AI, Napoleon's army attacks as
  one body (17 battalions and 9 cavalry regiments on La Haye Sainte, squares shot to pieces by the
  infantry behind the horse); Wellington's AI has no reverse slope and Bülow enters at 12–18 min.
  The collapse is by the rules (14 routing + 3 destroyed of 24 on the field = 71 %). A human plays
  France here, so the fix would be a stronger *defending* AI (combined-arms counter), not an OOB
  change; left for a dedicated pass.
- **Auerstedt: Prussia 12/15.** Davout's win was the historical anomaly; an AI Davout at 1:1.2 odds
  of deployed strength with no player plan loses a 40-minute slugfest on points (casualties 34–54 %
  French, 23–34 % Prussian). The player defends with the ridge and Morand's arrival; not forced.
- **Spielberg 15/15 draws, Sokolnitz easy 5/5 draws.** Each side takes its own objective inside two
  minutes, then the two-battalion advance is checked (10–25 % casualties, 2–17 cannonades). A quick
  battle ending 1–1 is a draw by the rules; the episode is designed for the player to force it.
- **Hougoumont: artillery never fires** at normal/hard. The only French battery stands behind
  Hougoumont wood and the Guards sit inside the walled farm (village cells block sight beyond 90);
  the British troop deploys in the orchard with no target. Terrain, not a bug.
- Episodes in which the AI attacker fails an even assault (La Haye Sainte at easy/normal, the
  Landgrafenberg) are 4/5, not 5/5, and all show flips and 20–40 % casualties.

## Grand campaign (8 seeds, `tests/grand.spec.luau`)

France 8–11 provinces in January 1809; Austria beaten (dictated peace) in 5 of 8 seeds, white or
lost peace in 3; Prussia beaten in 3 of 8, at peace on its own terms in 4, still at war in 1; Paris
never falls. No nation wins by a fixed turn: not degenerate, unchanged.

## Open after unit types (2026-10-19)

Typed units (Phase 1) tilt the Auerstedt episodes further toward Prussia, whose order of battle has
the Garde du Corps, two Kürassier regiments, hussars, grenadiers and guard against Davout's line
regiments. 5 seeds a cell, before → after: Hassenhausen normal prussia 4 france 1 → prussia 5,
hard prussia 3 draw 2 → prussia 5; Auerstedt hard prussia 4 france 1 → unchanged. The cavalry
types drove it (with them off, the old results return); their gaps were narrowed (heavy charge
0.065, light pursuit ×1.4). Phase 5 (defending AI, Davout's squares) owns the rest.

## After Phases 3–5 (2026-10-19, 5 seeds a cell)

13–14 flags across the last runs (Phase 4 baseline 13, after the AI work 14), a changing mix:
- Fixed: Hougoumont's guns fire (howitzers), Spielberg normal fights (Orange on the east bank,
  attacker roles), Landgrafenberg no longer draws on hard.
- Standing: Waterloo goes to France (Wellington's line collapses at 16–17 min, before Bülow's
  Prussians arrive at 12–18 min); Auerstedt and Hassenhausen lean Prussian (heavy cavalry,
  grenadiers); Spielberg easy/hard still draw; La Haye Sainte flips side by difficulty (the KGL
  garrison); Auerstedt easy reports "no contact" in 4 seeds although a trace of seed 1 shows a
  full fight (the harness counts volleys, cannon and charges, not melee: to check).
- Next balance pass: the whole-game pass after Phase 11 (`docs/plan.md`).

## Whole-game pass after Phase 11 (2026-10-20, 5 seeds a cell)

Baseline 15 flags, 8 of them against history (Waterloo all three, Auerstedt normal and hard,
Vierzehnheiligen normal, Hassenhausen hard, La Haye Sainte easy). Traces of single battles
(per-minute posture, strength, routs; casualties by fire and melee; morale lost by cause) found
three bugs and two AI faults:
- **Squares had flanks.** Fire damage ignored a square's sides, but the attack still carried
  "flank"/"rear", so Morale charged a square the flank and rear shock (−1.5 and −3 a second in
  melee, −6/−12 a volley). At Waterloo it was most of the allied morale loss: 6,000 melee ticks
  on squares' flanks and rears against 250 on French units. `Combat.sideOf` makes every attack
  on a square or a garrison frontal.
- **Reinforcements counted against collapse.** Strength collapse (< 35 %) used deployed strength
  including units still off the map, so Wellington's army broke at 44 % of what was on the field
  (Bülow's 2,800 not yet arrived); the AI's withdraw test had the same error.
  `Objectives.fieldDeployed`.
- **Gridlock.** A formation marching through idle friends was pushed back by each one every tick,
  never progressed, replanned the same path and stayed "moving" for ever: Auerstedt easy had
  three seeds with no shot fired, the Prussian army knotted round its cavalry reserve for 40
  minutes. Marching formations now pass through idle friends and are spread by them only near
  the end of the march (`docs/rules.md`, Navigation).
- **The defender attacked.** `desiredPosture` checked "attack" (own strength 1.5× what it sees)
  before the battle roles, so Wellington, seeing a third of the French army, left the ridge at
  minute 2. The defender of a battle with roles now always defends.
- **The defender's line stood on its outposts.** Wing points were the objectives themselves, so
  Wellington's army marched down to Hougoumont and La Haye Sainte. Objectives with a building are
  now outposts for their garrison; the line forms level with the open objectives behind them,
  at most 150 back, with wings at least 200 apart; battalions still marching to their wing may
  be sent into a building.

Result 15 flags, 4 against history (table above): Waterloo goes to the allies in about 40 % of
battles over three difficulties (8 seeds: easy 4–4, normal 3–5, hard 2–6; before 0 of 15),
Vierzehnheiligen and La Haye Sainte follow history, Hassenhausen is a draw on easy and hard
(Gudin holds) and still Prussian on normal. Standing:
- **Auerstedt to Prussia** (all difficulties). With the gridlock gone every seed fights, and the
  larger Prussian army with the Garde and three heavy regiments wins against an AI Davout. A
  human Davout has the ridge and Morand's arrival; not forced.
- **Waterloo normal/hard lean French.** The rest of the allied morale loss is French infantry
  meeting the static allied line in its flank; letting a firing battalion turn to face changed
  nothing measurable and was dropped.
- **Draws:** Spielberg and Sokolnitz end with each side on its own objective (as before);
  Sokolnitz's allied left stuck is the historical result.
- **5/5 for the historical winner** in episodes (Pratzen, Vierzehnheiligen easy) is flagged only
  because the episodes are not marked lopsided.

