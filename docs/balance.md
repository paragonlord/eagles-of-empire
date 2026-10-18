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

## Final table (5 seeds, both sides AI)

| scenario | diff | winner (n) | reason | min | contact | cas% F/E | routs F/E | shat F/E | lost F/E | flips | guns | charges | history | flags |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| jena | easy | france 5 | The enemy army has collapsed | 10.3 | 1.1 | 18/45 | 4.8/20.4 | 1%/3% | 0.4/4.2 | 4.8 | 18 | 16.0 | French victory (decisive) | - |
| jena | normal | france 5 | The enemy army has collapsed | 6.6 | 1.2 | 14/28 | 3.6/16.2 | 0%/0% | 0.2/2.6 | 3.8 | 12 | 10.6 | French victory (decisive) | - |
| jena | hard | france 5 | The enemy army has collapsed | 12.1 | 1.1 | 20/52 | 8.4/23.6 | 1%/3% | 0.4/5.0 | 5.4 | 16 | 22.8 | French victory (decisive) | - |
| auerstedt | easy | prussia 5 | Time expired; the enemy holds more objectives | 31.4 | 6.9 | 50/26 | 25.0/11.8 | 1%/0% | 5.6/2.0 | 4.0 | 65 | 23.4 | French victory (Davout outnumbered 2:1) | prussia wins 5/5 against history |
| auerstedt | normal | prussia 3 france 2 | Time expired holding more objectives | 36.8 | 8.8 | 34/23 | 15.8/14.4 | 1%/1% | 4.4/2.2 | 5.2 | 41 | 16.0 | French victory (Davout outnumbered 2:1) | - |
| auerstedt | hard | prussia 4 france 1 | Time expired; the enemy holds more objectives | 38.0 | 4.9 | 54/34 | 28.4/18.0 | 1%/0% | 7.2/3.8 | 5.0 | 79 | 34.2 | French victory (Davout outnumbered 2:1) | - |
| austerlitz | easy | france 3 russia 2 | Time expired holding more objectives | 38.4 | 6.3 | 50/45 | 45.8/39.6 | 4%/1% | 7.8/6.6 | 6.2 | 21 | 28.2 | French victory (decisive) | - |
| austerlitz | normal | russia 3 france 2 | Time expired; the enemy holds more objectives | 39.1 | 4.7 | 54/52 | 48.0/45.8 | 0%/1% | 9.0/9.6 | 6.0 | 17 | 30.0 | French victory (decisive) | - |
| austerlitz | hard | russia 3 france 2 | Time expired; the enemy holds more objectives | 33.7 | 3.8 | 56/51 | 51.6/42.0 | 0%/0% | 10.4/9.4 | 7.0 | 15 | 29.4 | French victory (decisive) | - |
| waterloo | easy | france 5 | The enemy army has collapsed | 11.7 | 1.1 | 17/37 | 8.2/36.0 | 1%/1% | 1.0/7.8 | 4.8 | 25 | 27.0 | Allied victory (decisive) | france wins 5/5 against history |
| waterloo | normal | france 5 | The enemy army has collapsed | 14.7 | 1.1 | 22/48 | 12.2/43.0 | 0%/1% | 2.6/10.0 | 4.8 | 9 | 34.6 | Allied victory (decisive) | france wins 5/5 against history |
| waterloo | hard | france 5 | The enemy army has collapsed | 12.1 | 1.1 | 20/42 | 11.2/44.6 | 1%/4% | 2.2/9.2 | 5.0 | 7 | 31.6 | Allied victory (decisive) | france wins 5/5 against history |
| jena_landgrafenberg | easy | prussia 3 draw 1 france 1 | Time expired; the enemy holds more objectives | 8.6 | 0.7 | 30/19 | 7.6/3.2 | 2%/0% | 1.0/0.0 | 2.6 | 5 | 3.6 | Closewitz and Cospeda taken | - |
| jena_landgrafenberg | normal | prussia 4 draw 1 | Time expired; the enemy holds more objectives | 8.6 | 0.6 | 39/21 | 8.6/4.0 | 0%/0% | 1.8/0.2 | 2.2 | 11 | 3.4 | Closewitz and Cospeda taken | - |
| jena_landgrafenberg | hard | draw 3 prussia 1 france 1 | Time expired with the field divided | 8.8 | 0.6 | 32/27 | 6.6/5.8 | 0%/2% | 1.6/0.6 | 3.0 | 5 | 4.8 | Closewitz and Cospeda taken | - |
| jena_vierzehnheiligen | easy | france 4 prussia 1 | Time expired holding more objectives | 10.0 | 0.4 | 29/42 | 3.6/8.2 | 2%/5% | 0.8/0.8 | 1.2 | 7 | 12.2 | village taken, Grawert's line shot to pieces | - |
| jena_vierzehnheiligen | normal | prussia 4 france 1 | Time expired; the enemy holds more objectives | 10.0 | 0.5 | 37/36 | 5.8/6.8 | 2%/0% | 1.4/0.8 | 1.2 | 5 | 13.4 | village taken, Grawert's line shot to pieces | - |
| jena_vierzehnheiligen | hard | france 4 prussia 1 | All objectives held | 9.9 | 0.4 | 24/47 | 3.0/9.4 | 0%/0% | 2.0/1.8 | 2.2 | 7 | 7.4 | village taken, Grawert's line shot to pieces | - |
| auerstedt_hassenhausen | easy | prussia 3 draw 2 | The enemy holds every objective | 10.0 | 1.9 | 31/20 | 7.4/2.2 | 0%/0% | 1.2/0.0 | 3.0 | 6 | 5.8 | Gudin held Hassenhausen | - |
| auerstedt_hassenhausen | normal | prussia 4 draw 1 | The enemy holds every objective | 10.0 | 1.6 | 40/18 | 8.2/2.0 | 5%/0% | 0.6/0.0 | 2.8 | 3 | 7.8 | Gudin held Hassenhausen | - |
| auerstedt_hassenhausen | hard | draw 3 prussia 2 | Time expired with the field divided | 10.0 | 1.3 | 32/21 | 6.6/5.0 | 0%/0% | 0.6/0.0 | 2.4 | 3 | 11.2 | Gudin held Hassenhausen | - |
| auerstedt_spielberg | easy | draw 5 | Time expired with the field divided | 10.0 | 4.1 | 19/15 | 3.8/1.6 | 3%/0% | 0.0/0.0 | 2.0 | 17 | 1.8 | Friant turned the Prussian left | draw 5/5 |
| auerstedt_spielberg | normal | draw 5 | Time expired with the field divided | 10.0 | 4.6 | 9/25 | 0.0/3.6 | 0%/0% | 0.0/0.0 | 2.0 | 8 | 5.4 | Friant turned the Prussian left | draw 5/5 |
| auerstedt_spielberg | hard | draw 5 | Time expired with the field divided | 10.0 | 3.5 | 9/14 | 1.8/4.0 | 0%/0% | 0.0/0.0 | 2.0 | 9 | 2.4 | Friant turned the Prussian left | draw 5/5 |
| austerlitz_pratzen | easy | draw 3 france 1 russia 1 | Time expired with the field divided | 10.0 | 1.7 | 25/33 | 3.4/7.6 | 0%/0% | 0.6/1.6 | 5.0 | 4 | 2.4 | Pratzen taken | - |
| austerlitz_pratzen | normal | france 4 draw 1 | All objectives held | 10.0 | 1.7 | 27/30 | 5.2/6.6 | 0%/2% | 0.4/1.2 | 4.2 | 3 | 2.8 | Pratzen taken | - |
| austerlitz_pratzen | hard | draw 3 russia 1 france 1 | Time expired with the field divided | 10.0 | 1.6 | 29/28 | 5.2/6.6 | 2%/0% | 0.4/1.2 | 4.6 | 3 | 3.8 | Pratzen taken | - |
| austerlitz_sokolnitz | easy | draw 5 | Time expired with the field divided | 10.0 | 2.8 | 25/10 | 5.6/2.2 | 2%/0% | 0.4/0.0 | 3.0 | 3 | 0.8 | Telnitz/Sokolnitz held, allied left stuck | draw 5/5 |
| austerlitz_sokolnitz | normal | russia 3 draw 2 | Time expired; the enemy holds more objectives | 10.0 | 2.0 | 35/14 | 8.6/1.8 | 2%/0% | 1.6/0.0 | 3.6 | 2 | 0.8 | Telnitz/Sokolnitz held, allied left stuck | - |
| austerlitz_sokolnitz | hard | russia 3 draw 2 | Time expired with the field divided | 9.9 | 2.0 | 38/15 | 9.8/2.4 | 2%/0% | 1.8/0.2 | 3.6 | 6 | 0.6 | Telnitz/Sokolnitz held, allied left stuck | - |
| waterloo_hougoumont | easy | france 4 britain 1 | All objectives held | 10.0 | 0.8 | 33/32 | 6.0/6.0 | 0%/3% | 1.0/0.4 | 1.8 | 1 | 1.2 | Hougoumont held all day | - |
| waterloo_hougoumont | normal | france 4 britain 1 | All objectives held | 9.8 | 0.7 | 30/29 | 6.0/4.6 | 0%/0% | 0.8/0.6 | 1.6 | 0 | 2.4 | Hougoumont held all day | artillery never fires |
| waterloo_hougoumont | hard | france 4 britain 1 | All objectives held | 9.2 | 0.8 | 33/32 | 5.6/6.2 | 0%/0% | 0.8/0.6 | 1.6 | 0 | 2.4 | Hougoumont held all day | artillery never fires |
| waterloo_lahayesainte | easy | britain 4 draw 1 | Time expired; the enemy holds more objectives | 10.0 | 1.1 | 25/27 | 3.0/4.4 | 0%/0% | 0.0/0.4 | 2.2 | 13 | 4.8 | La Haye Sainte fell | - |
| waterloo_lahayesainte | normal | britain 4 draw 1 | Time expired; the enemy holds more objectives | 10.0 | 1.1 | 30/29 | 5.2/5.6 | 2%/2% | 0.4/0.2 | 2.2 | 22 | 5.2 | La Haye Sainte fell | - |
| waterloo_lahayesainte | hard | france 4 britain 1 | All objectives held | 10.0 | 1.1 | 25/43 | 3.0/11.0 | 0%/8% | 0.2/1.2 | 3.6 | 14 | 3.8 | La Haye Sainte fell | - |

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
