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

## Final table (5 seeds, both sides AI; after unit types, skirmish, run and fire by rank, 2026-10-19)

| scenario | diff | winner (n) | reason | min | contact | cas% F/E | routs F/E | shat F/E | lost F/E | flips | guns | charges | history | flags |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| jena | easy | france 5 | The enemy army has collapsed | 10.6 | 1.0 | 22/48 | 9.2/24.0 | 1%/5% | 0.6/4.6 | 4.4 | 19 | 16.4 | French victory (decisive) | - |
| jena | normal | france 5 | The enemy army has collapsed | 8.8 | 1.1 | 17/33 | 4.4/17.0 | 0%/1% | 0.2/2.6 | 4.6 | 15 | 15.6 | French victory (decisive) | - |
| jena | hard | france 5 | The enemy army has collapsed | 9.4 | 1.1 | 16/38 | 3.6/20.4 | 0%/3% | 0.4/4.0 | 5.0 | 8 | 14.0 | French victory (decisive) | - |
| auerstedt | easy | prussia 4 france 1 | Time expired; the enemy holds more objectives | 38.5 | 9.4 | 52/47 | 25.4/27.0 | 2%/1% | 6.0/5.4 | 6.2 | 58 | 22.0 | French victory (Davout outnumbered 2:1) | - |
| auerstedt | normal | prussia 4 france 1 | Your army has collapsed | 30.6 | 8.7 | 44/24 | 24.2/15.2 | 3%/1% | 5.2/2.2 | 5.0 | 55 | 13.0 | French victory (Davout outnumbered 2:1) | - |
| austerlitz | easy | russia 3 france 2 | Time expired holding more objectives | 39.1 | 4.5 | 60/55 | 53.0/45.2 | 3%/0% | 10.6/9.0 | 6.0 | 15 | 30.0 | French victory (decisive) | - |
| austerlitz | normal | france 3 russia 2 | Time expired holding more objectives | 37.9 | 4.0 | 53/52 | 46.2/46.2 | 0%/2% | 8.4/9.2 | 5.8 | 14 | 25.2 | French victory (decisive) | - |
| austerlitz | hard | russia 4 france 1 | Time expired; the enemy holds more objectives | 37.9 | 4.4 | 60/49 | 52.0/43.6 | 0%/1% | 11.6/7.6 | 6.4 | 12 | 27.2 | French victory (decisive) | - |
| waterloo | easy | france 5 | The enemy army has collapsed | 19.5 | 1.2 | 38/64 | 21.4/51.8 | 1%/1% | 4.6/14.0 | 5.0 | 5 | 37.6 | Allied victory (decisive) | france wins 5/5 against history; britain casualties 64% |
| waterloo | normal | france 5 | The enemy army has collapsed | 10.5 | 0.8 | 20/41 | 9.4/38.2 | 1%/2% | 1.4/8.4 | 4.6 | 9 | 24.6 | Allied victory (decisive) | france wins 5/5 against history |
| jena_landgrafenberg | easy | prussia 3 draw 2 | Time expired; the enemy holds more objectives | 10.0 | 0.7 | 33/27 | 6.4/6.4 | 2%/0% | 1.4/0.2 | 2.8 | 5 | 3.6 | Closewitz and Cospeda taken | - |
| jena_landgrafenberg | normal | prussia 4 draw 1 | Time expired; the enemy holds more objectives | 9.2 | 0.6 | 33/26 | 8.8/5.0 | 0%/0% | 1.4/0.6 | 2.2 | 5 | 3.4 | Closewitz and Cospeda taken | - |
| jena_landgrafenberg | hard | prussia 4 france 1 | Your army has collapsed | 5.6 | 0.6 | 30/21 | 8.0/3.6 | 2%/0% | 1.2/0.2 | 2.4 | 8 | 2.4 | Closewitz and Cospeda taken | - |
| jena_vierzehnheiligen | easy | france 3 draw 2 | The enemy army has collapsed | 8.7 | 0.4 | 33/34 | 4.8/7.2 | 2%/0% | 1.8/1.2 | 0.6 | 8 | 10.0 | village taken, Grawert's line shot to pieces | - |
| jena_vierzehnheiligen | normal | france 4 prussia 1 | All objectives held | 10.0 | 0.5 | 28/41 | 4.4/8.6 | 0%/0% | 1.2/0.6 | 1.8 | 2 | 9.4 | village taken, Grawert's line shot to pieces | - |
| auerstedt_hassenhausen | easy | prussia 4 draw 1 | The enemy holds every objective | 10.0 | 1.8 | 39/18 | 7.8/1.4 | 8%/0% | 1.4/0.0 | 2.8 | 5 | 7.8 | Gudin held Hassenhausen | - |
| auerstedt_hassenhausen | normal | prussia 5 | The enemy holds every objective | 10.0 | 1.6 | 32/20 | 7.4/2.0 | 0%/0% | 1.2/0.0 | 3.0 | 3 | 6.4 | Gudin held Hassenhausen | prussia wins 5/5 against history |
| auerstedt_hassenhausen | hard | prussia 5 | The enemy holds every objective | 9.1 | 1.3 | 32/18 | 6.4/3.8 | 2%/0% | 0.8/0.2 | 2.8 | 1 | 9.0 | Gudin held Hassenhausen | prussia wins 5/5 against history |
| auerstedt_spielberg | easy | draw 5 | Time expired with the field divided | 10.0 | 3.7 | 19/17 | 2.2/2.2 | 0%/0% | 0.0/0.2 | 2.0 | 11 | 2.8 | Friant turned the Prussian left | draw 5/5 |
| auerstedt_spielberg | normal | draw 5 | Time expired with the field divided | 10.0 | 4.6 | 7/12 | 1.8/2.8 | 0%/0% | 0.0/0.0 | 2.0 | 13 | 3.0 | Friant turned the Prussian left | draw 5/5 |
| austerlitz_pratzen | easy | france 4 draw 1 | All objectives held | 9.8 | 1.5 | 27/34 | 3.4/8.4 | 0%/2% | 0.6/1.0 | 4.4 | 3 | 2.0 | Pratzen taken | - |
| austerlitz_pratzen | normal | draw 2 russia 2 france 1 | Time expired with the field divided | 9.7 | 1.4 | 34/31 | 6.2/7.0 | 0%/2% | 1.0/1.0 | 4.4 | 6 | 2.8 | Pratzen taken | - |
| austerlitz_pratzen | hard | draw 4 france 1 | Time expired with the field divided | 10.0 | 1.3 | 29/27 | 5.4/5.0 | 0%/0% | 0.6/1.0 | 4.8 | 4 | 3.8 | Pratzen taken | - |
| austerlitz_sokolnitz | easy | draw 4 russia 1 | Time expired with the field divided | 10.0 | 2.8 | 26/22 | 5.4/5.4 | 2%/2% | 1.2/0.2 | 3.2 | 13 | 1.2 | Telnitz/Sokolnitz held, allied left stuck | - |
| austerlitz_sokolnitz | normal | russia 3 draw 2 | The enemy holds every objective | 10.0 | 2.0 | 33/16 | 6.8/2.0 | 0%/0% | 1.4/0.0 | 4.0 | 2 | 0.4 | Telnitz/Sokolnitz held, allied left stuck | - |
| waterloo_hougoumont | easy | britain 3 france 2 | Time expired; the enemy holds more objectives | 10.0 | 0.7 | 33/28 | 4.2/5.2 | 0%/0% | 0.0/0.2 | 1.8 | 1 | 2.4 | Hougoumont held all day | - |
| waterloo_hougoumont | normal | britain 4 france 1 | Time expired; the enemy holds more objectives | 10.0 | 0.7 | 38/31 | 8.0/3.8 | 2%/0% | 1.0/0.2 | 1.6 | 1 | 4.2 | Hougoumont held all day | - |
| waterloo_hougoumont | hard | france 3 britain 2 | All objectives held | 10.0 | 0.7 | 34/31 | 5.0/5.0 | 0%/0% | 0.4/0.4 | 1.6 | 2 | 3.2 | Hougoumont held all day | - |
| waterloo_lahayesainte | easy | britain 4 draw 1 | Time expired; the enemy holds more objectives | 10.0 | 0.8 | 23/25 | 2.6/3.8 | 2%/0% | 0.0/0.4 | 2.2 | 20 | 4.2 | La Haye Sainte fell | - |
| waterloo_lahayesainte | normal | france 4 draw 1 | Time expired holding more objectives | 10.0 | 0.8 | 28/41 | 3.4/10.8 | 0%/5% | 0.0/1.6 | 3.8 | 10 | 6.2 | La Haye Sainte fell | - |
| auerstedt | hard | prussia 4 france 1 | Time expired; the enemy holds more objectives | 35.2 | 5.4 | 44/27 | 21.4/13.8 | 2%/1% | 5.2/2.6 | 5.4 | 72 | 20.8 | French victory (Davout outnumbered 2:1) | - |
| waterloo | hard | france 5 | The enemy army has collapsed | 12.2 | 0.8 | 26/44 | 15.0/43.0 | 1%/6% | 2.6/8.8 | 4.6 | 8 | 28.6 | Allied victory (decisive) | france wins 5/5 against history |
| jena_vierzehnheiligen | hard | prussia 2 france 2 draw 1 | Time expired holding more objectives | 9.4 | 0.4 | 32/36 | 5.6/5.6 | 0%/2% | 2.2/0.4 | 0.6 | 2 | 10.8 | village taken, Grawert's line shot to pieces | - |
| auerstedt_spielberg | hard | draw 5 | Time expired with the field divided | 10.0 | 3.5 | 10/17 | 2.4/4.0 | 0%/0% | 0.0/0.2 | 2.0 | 12 | 1.4 | Friant turned the Prussian left | draw 5/5 |
| austerlitz_sokolnitz | hard | russia 3 france 1 draw 1 | The enemy holds every objective | 10.0 | 2.4 | 35/18 | 9.4/3.2 | 0%/0% | 1.8/0.2 | 3.8 | 7 | 0.8 | Telnitz/Sokolnitz held, allied left stuck | - |
| waterloo_lahayesainte | hard | britain 5 | Time expired; the enemy holds more objectives | 10.0 | 0.8 | 22/21 | 3.4/2.0 | 0%/0% | 0.0/0.2 | 2.0 | 22 | 4.8 | La Haye Sainte fell | britain wins 5/5 against history |

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

