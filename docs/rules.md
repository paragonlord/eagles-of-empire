# Battle rules

All constants come from `src/shared/Config.luau`; values quoted here are the defaults at the
time of writing and are shown for reading convenience. Formulas are the contract. Units: studs
(1 stud ≈ 1 m nominal, distances condensed for pacing), simulation seconds, soldiers.

## Scale and representation

| Quantity | Value |
| --- | --- |
| Logical step | 0.05 s (20 Hz) |
| Map | 1600 × 1200 studs, 4-stud terrain cells, 16-stud nav nodes |
| Infantry battalion | 600 men (Guard 700); 1 figure = 25 men → 24 figures |
| Cavalry regiment | 400 troopers → 16 figures |
| Artillery battery | 120 crew, 1 gun per 20 crew → 6 guns, 40 rounds per gun |
| Headquarters | the general and his escort: 120 heavy horse (mounted: rides, charges and fights as cavalry; charge 0.04, melee 1.2/0.9) |

Casualties are applied to strength in men; the client removes one figure per 25 men lost.

## Unit types

Every unit has a type (`Config.UnitTypes`) inside its class. A scenario may set `type`; otherwise
`Scenarios.typeOf` reads it from the regiment's name (Légère/Tirailleurs/Füsiliere/Grenzer →
light, Rifles/Jäger → rifles, Garde/Guards → guard, Grenadiers → grenadiers, Landwehr/Conscrits
→ militia; Cuirassiers/Carabiniers/Life Guards → heavy, Hussars/Chasseurs/Lancers/Uhlans/Light
Dragoons → light cavalry, other horse → dragoons; Reitende/à cheval/RHA → horse artillery). The
type's overrides merge over the class values below (`Config.TypeStats`); untouched keys keep the
class value.

| Type | Changes from its class |
| --- | --- |
| line, dragoons, foot artillery | none (the class values) |
| light | speed 6.2, accuracy 0.075, melee 0.95/0.95, spots 300; may skirmish |
| rifles | speed 6.0, range 130, reload 21 s, accuracy 0.11, 50 rounds, morale 70, melee 0.8/0.85; may skirmish |
| grenadiers | morale 72, melee 1.1/1.05 |
| guard | morale 76, melee 1.15/1.1 |
| militia | morale 58, accuracy 0.055, melee 0.85/0.9 |
| light cavalry | speed 16 (charge 22), melee 1.2/0.75, charge 0.05, ×1.4 charge impact on routing units, spots 380 |
| heavy cavalry | speed 13 (charge 19), morale 74, melee 1.35/1.0, charge 0.065, more fatigue on the move |
| horse artillery | speed 7.5, limber/unlimber and reform in half the time, round shot 380 and 2.5 per hit |
| howitzers | shells: range 400 (min 80), reload 26 s, hit 0.4, 3.5 per hit; indirect (any target the side can see, no line of sight, over friends); the burst hits every formation within 30 studs of the target, friend or foe, for up to half the strike |

## Movement

```
speed = base[class] * shape.speed * terrain.speed(class) * slopeFactor * fatigueFactor
slopeFactor = 1 - 0.6 * max(0, slopeAlong) + 0.15 * max(0, -slopeAlong)   (clamped ≥ 0.25)
fatigueFactor = 1 - 0.4 * fatigue / 100
```

| Class | base speed | charge speed | shapes |
| --- | --- | --- | --- |
| infantry | 5.5 | 7.5 | line ×0.75, column ×1.0, square ×0.3, travel ×1.0 |
| cavalry | 14.0 | 20.0 | wedge ×1.0, line ×1.0 |
| artillery | 4.5 (limbered) | – | limbered ×1.0, deployed ×0 |
| hq | 12.0 | – | staff |

Running (a march ordered with `run`, or the Run order on the current march; infantry, cavalry and
staff, never guns or a charge): speed ×1.4, marching fatigue ×3.

Fords: authored shallow crossings of the brooks (30 studs along the bed; Rau-Bach ×2, Lissbach ×2,
Goldbach ×1, Smohain ×1; none on the Saale or the tutorial's Mühlbach). Speed 0.45 (cavalry 0.55),
fatigue ×1.6, cohesion loss; no firing while wading; melee ×0.7 from the ford.

Terrain: open 1.0, road 1.3, woods 0.6 (cavalry 0.4), village 0.7 (0.5), bridge 0.9, steep 0.5,
water/cliff impassable. Roads give the only >1.0 factor, so marching in column along a road is
the fastest way across the map.

Footprint: `width = files * figureSpacing`, `depth = ranks * rankSpacing`; files = ceil(figures / ranks).
Line 5/3 (a 600-man battalion: 8 files → 40 × 9 studs), column 4/3 (8 ranks), square 4/4, travel 4/3
(12 ranks). Square: side = ceil(sqrt(figures)) files. Half-width is used for clearance; if the path's
minimum clearance < half-width the formation adopts `travel` (half-width 8) until clearance
allows the previous shape again (restored automatically, costs the reform time).

Turning: heading moves toward the target at `shape.turnRate` rad/s. Fire arcs: infantry ±60°,
guns ±30° from their facing; a square fires all round.

Navigation: A* on the 16-stud nav grid, cost = distance / terrain.speed, nodes impassable
when clearance < 8. Replan when the path is blocked for `StuckSeconds = 4` or a new order
arrives. Avoidance: friendly formations whose footprints (half-radii) overlap push apart; the lower id
yields at choke points (clearance < 24).

## Shapes and reforming

| Shape | ranks | fire | melee | cavalry shock taken | artillery taken |
| --- | --- | --- | --- | --- | --- |
| line | 3 | 1.0 | 1.0 | 1.0 | 1.0 |
| column | 8 | 0.3 | 1.15 | 1.3 | 1.9 |
| square | – | 0.5 | 0.9 | 0.15 | 2.2 |
| travel | 12 | 0 | 0.6 | 1.8 | 2.0 |
| skirmish (light, rifles) | 2, open | 0.5 | 0.5 | 2.0 (charge ×2.0) | 0.35 |

Skirmishers fire on the move without halting and all round, and are hit by muskets ×0.45.

Fire by rank: drilled infantry (a scenario's `fireByRank`, else every guard battalion and British
foot; in the grand campaign a technology) reloads ×0.75 while halted in line.

Reform times (seconds): line 12, column 8, square 15 (10 from column), travel 6, skirmish 6, limber 25,
unlimber 20. While `reforming`, fire = 0, melee ×0.6, shock taken ×1.5. A square ordered after
cavalry contact completes only after its timer; the charge already in contact resolves against
the *previous* shape.

## Fire

Eligibility: has musket/gun, ammo > 0, reload = 0, state in {idle, firing, moving-with-halt},
target visible to the faction, target centre inside range, bearing within the fire arc
(infantry ±60°, artillery ±30° from the gun line), line of sight clear, no friendly formation
within the fire lane (half-width 10) unless `FriendlyBlocksFire = false`. Infantry halts to
volley (movement resumes after). Fire-at-will off ⇒ never fires unless ordered to Engage.

```
shooters   = strength * shape.fire * readiness          (readiness = cohesion, ≥ 0.4; ×0.7 when shaken)
rangeF     = 1 - 0.65 * (dist / range)
hit        = accuracy(0.07) * rangeF * (1 - cover) * (1 - 0.3 fatigue/100) * (1 + 0.08 exp)
             * targetShape * sideFactor * (1 + 0.1 if higher)        clamped to ≤ 0.30
casualties = round(shooters * hit)       (seeded roll: floor + chance(frac))
```
targetShape: line 1.0, column 1.5, square 1.3, travel 1.6. sideFactor: front 1.0, flank 1.35,
rear 1.6 (side is computed from the target's heading and the shooter's position). Reload 15 s.

Artillery: per gun, per shot. Round shot range 60–450, hit 0.5 × rangeF, 3 casualties per hit
× shape.artillery, +3 morale. Canister range 0–120, hit 0.9, 7 per hit, +5 morale. Reload 20 /
18 s. Ammunition mode `auto` picks canister inside 120. A gun reports why it cannot fire:
`Limbered`, `Reloading`, `Out of range`, `Line of fire blocked`, `No target`, `Out of ammunition`.

Field borders: a hedge (+0.25 cover) or dry-stone wall (+0.4) within 6 studs of the target's centre,
on open or steep ground, shelters it from musketry that has to cross the border (WorldGen's field
lattice: `WorldGen.borderCover`, the same hedges and walls the props draw).

Higher ground (attacker more than 3 studs above the target): charge impact ×1.25, melee ×1.1
(`Config.Slope`), on top of the musket's ×1.1.

Round shot carries on past its target (`Config.Combat.Ricochet`): the two nearest formations of
either side whose footprints touch the next 140 studs of the line of fire take 0.45 of the first
strike (before shape), fading to half at the far end, × their own shape's artillery factor; half the
round shot's morale shock. Canister does not carry. Friendly troops behind the enemy are not safe.

## Buildings

Every village (and farm: Hougoumont, La Haye Sainte, Papelotte…) has one strongpoint at its heart
(`MapGen` `strongpoints`), held by at most one infantry battalion (`Sim/Garrison.luau`).

- **Garrison** order: the battalion marches to the building; within 40 studs (or on arriving at its
  door) it moves in if it is free (shape `garrison`, 8 s). From 90 studs it sees who holds it: a
  friend, the order ends; the enemy, the order becomes a charge on the garrison (storming).
- Inside: footprint 16 × 16, fires all round at 0.45 of its muskets, hit ×0.4 by muskets (on top of
  the village's cover) and ×0.5 by guns, melee ×1.4; cavalry charges do nothing and horse fight it at
  ×0.15. It cannot move.
- Leaving: any march, charge or shape order files it out (column, 8 s) and then carries the order
  out; Engage, Hold and Face only choose its target from the windows. A routing garrison pours out at
  once. The building is free as soon as its holder leaves, breaks or dies.

## Melee and charges

Contact: footprints within 6 studs and the attacker's order targets the defender, or either
side charges into the other. Both sides deal damage each tick:

```
casualties/s = strength * 0.0025 * melee.attack * shape.melee * dir * (1 - 0.4 fatigue/100)
               * (1 + 0.08 exp) * bayonetBonus / defender.melee.defense
```
dir: front 1.0, flank 1.6, rear 2.2. Shaken attackers ×0.8; cavalry in melee for more than 25 s ×0.5. Bayonet charge: ×1.3 for 10 s after contact and a morale
shock of 10 (front) / 20 (flank or rear) to the target.

Cavalry charge impact, applied once at first contact:
```
impact = strength * 0.06 * runUpF * dirF * shapeF * (1 - 0.4 fatigue/100)
runUpF = clamp(runUp / 80, 0.3, 1)        (distance travelled at charge speed before contact)
dirF   = front 1.0 / flank 1.8 / rear 2.5
shapeF = line 1.0, column 1.3, square 0.15, travel 1.8, limbered/deployed 3.0, routing ×1.5
```
After impact the cavalry fights ordinary melee (attack 1.4, defense 0.8); against a square it
takes ×2 damage. A new impact needs 40 s of recovery out of contact. Cavalry in woods: speed
×0.4 and charge impact ×0.5.

Experience (0–3) is also earned in battle: every 150 enemy casualties a formation inflicts
(`ExperienceKills`; friendly fire never counts) raise it a level, with +4 base morale; it carries
back to both campaigns with the survivors.

## Morale

0–100, starts at `baseMorale + 4·exp`. Per tick (scaled by dt where rates are per second):

| Cause | Effect |
| --- | --- |
| casualties | − (lost / strength) × 100 × 1.0 |
| volley / cannonade / charge from the flank | − 6 once per attack (rear: − 12) |
| melee from the flank | − 1.5 /s (rear: − 3 /s) |
| friend routing within 80 | − 2 every 5 s per friend, max − 6 |
| no friend within 150 | − 1 every 5 s |
| fatigue > 70 | − 0.2 /s |
| any friendly HQ within 120 (army or corps general) | + 0.3 /s extra recovery, cap base + 10 |
| no damage for 10 s | + 0.5 /s up to base |
| army HQ lost | − 15 once to every friendly formation |
| corps general's HQ lost | − 15 once to friendly formations within 300 of it |
| artillery battery destroyed | − 5 once to every friendly formation |

Bands with hysteresis: steady ≥ 50; shaken when < 40 (exit at ≥ 50); routing when < 20.
Routing: order cleared, moves toward its own map edge at ×1.3 speed through passable terrain,
takes no voluntary action, accepts no orders. Rally: after ≥ 20 s routing, morale ≥ 35 and no
enemy within 120 → `rallying` (5 s) → idle, shaken. HQ `Rally` order: formations within 100
that have routed ≥ 5 s get + 30 morale and rally immediately; cooldown 90 s.
Shattered: routing with strength < 30 % of start, or a third rout → never rallies. Exited:
centre crosses the map edge + 20 → removed from play, counted as lost. A routing formation
that moves less than 5 in 20 s (hemmed in) scatters: exited, counted as lost.

## Fatigue

0–100. + 0.35 /s marching (infantry; cavalry 0.5, guns 0.3; ×terrain.fatigue), + 6 /s charging, + 2 /s in melee, − 1.5 /s resting
(idle). Effects: speed ×(1 − 0.4 f), accuracy ×(1 − 0.3 f), melee ×(1 − 0.4 f). Never immobile.

## Visibility

A formation sees enemies within its spot radius (infantry 260, cavalry 320, artillery 240, HQ
300) with clear LOS (heightmap + woods/village sight height, eye height 4, tolerance 0.5). Enemies inside woods or villages
are only seen within 90. Formations whose footprints come within 15 of each other always see
each other (contact reveals). Visible set per faction is the union; last-known entries remember
position, heading, shape and class with an age, and are forgotten after 180 s. AI receives the
same observation set as the player. Snapshots to a client contain only that faction's view.

## Objectives and victory

Objective: radius 60, capture 30 s by eligible formations (infantry/cavalry, not routing /
shattered / destroyed / exited / reforming into square), contested when both sides have
eligible formations inside (progress freezes). Ownership shows on the HUD and minimap.

Victory evaluator (one, server, runs after step 9, terminal once):
1. **Collapse**: a side with ≥ 70 % of formations routing/shattered/destroyed/exited, or
   remaining strength < 35 % of deployed → the other side wins.
2. **Objectives**: a side holding every objective for 120 s continuous wins, but not before
   minute 10 (`HoldAllEarliest`) and only if at least one of them was taken from the enemy
   during the battle, so a defender starting on the objectives cannot win by default.
3. **Timeout** (25 min): more objectives held wins; equal → draw ("Indecisive").
Precedence when several trigger in the same tick: collapse of the *attacker* (player) is
checked first, then the enemy, then objectives, then timeout.

## Results

Per side: deployed, casualties, remaining, surviving/routed/shattered/destroyed/exited
formations, and `routEvents` (every rout in the battle, including those that rallied). Totals reconcile with the sim: `deployed = remaining + casualties` where casualties
include the strength of exited formations. Feedback lines are generated from the match log
(e.g. "Your cavalry charged a formed square twice.").

## Weather and reinforcements

`scenario.weather` (clear | rain | mud | fog | snow) multiplies musket accuracy, artillery hit
chance, movement speed and spotting distance (`Config.Weather`); `scenario.weatherUntil` clears it
at that simulation second with a message. Fog: spotting ×0.45. Mud: cannon ×0.7, speed ×0.8.

A unit definition with `arrival = { seconds, pos }` starts **off the map**: hidden, unorderable,
not deployable, not counted toward collapse or objectives. At `seconds` it appears at `pos`
(a passable point near the map edge) with a message. Off-map units count as surviving in the
results and their strength as deployed.

## Generals

Data: `src/shared/Generals.luau` (21 commanders plus a generic staff); sim: `src/server/Sim/Abilities.luau`.
Every HQ has a general: the unit definition's `general` id, else matched from the HQ name, else the
generic staff. Corps commanders need no unit: a formation whose corps names a general after the "·"
("V Corps · Lannes") carries his traits.

**Traits** (two per general, always on, recomputed every tick after commands and the AI):
*local* traits reach friendly formations within 200 of the general's HQ, or his own corps; *army*
traits reach the whole army (a corps commander's only his corps). A trait applies once per
formation however it is reached; some only for a class (cavalry, infantry, guns) or a condition:
*advancing* (moving or charging toward the enemy's edge) or *crest* (infantry halted with ground at
least 1.5 higher 30 or 60 ahead). Modifiers and their bounds after stacking:

| Modifier | Effect | Bounds |
| --- | --- | --- |
| speed | × movement speed | 0.8 – 1.25 |
| chargeImpact | × cavalry charge impact | 0.8 – 1.5 |
| chargeRecovery | × the 40 s charge recovery | 0.6 – 1.3 |
| accuracy | × musket hit chance and gun hits | 0.8 – 1.6 |
| melee | × melee casualties dealt | 0.85 – 1.25 |
| cover | + cover against incoming fire | 0 – 0.2 |
| recovery | + morale per second (always, also under fire) | 0 – 0.6 |
| shockFloor | casualty shock cannot push morale below it (other shocks can) | 0 – 30 |
| hideBeyond | enemies cannot spot it beyond this distance; lifted for 10 s after it fires | 120 |
| steadyRetreat | a Retreat order costs no cohesion (normally − 0.2) | – |

**Ability** (one per general, command `Ability { abilityId }` on the own HQ only): refused when the
HQ cannot take orders, the id is not its general's, it is recharging (`cooldown`) or nobody would be
affected (`noTarget`, no cooldown spent). Instant effects apply when the command applies; timed
effects hold for the formations in reach at that moment. Both sides see a ticker line naming the
general and the ability, without his position.

| General | Ability | Effect | Cooldown |
| --- | --- | --- | --- |
| Napoléon | Vive l'Empereur! | within 200: routing (not shattered) formations rally; all + 20 morale | 180 s |
| Ney | Charge! | cavalry within 200: charge impact × 1.3 for 30 s | 120 s |
| Davout | Hold the line | within 150, 45 s: morale stops at 20 (no rout) unless strength < 30 % | 150 s |
| Wellington | Up, Guards, and at 'em! | infantry within 250 halted behind a crest: reloaded, fire at will, accuracy × 1.5 for 12 s | 180 s |
| Blücher | Vorwärts! | within 200: + 10 morale; 60 s of speed × 1.2 and + 0.3 morale/s | 150 s |
| Kutuzov | Strategic withdrawal | routing (not shattered) within 250 rally, then retreat 200 toward their edge | 180 s |
| Archduke Charles | Personal example | nearest routing formation within 200 rallies (morale ≥ 45); else nearest shaken + 20 | 90 s |
| everyone else | Inspire | non-routing formations within 150: + 10 morale | 120 s |

Morale never exceeds 100. The AI uses its HQ's ability through the same command when at least two
of its formations within the ability's radius are shaken or routing and it is ready. The owner's
snapshot carries the HQ's `general` and `abilityReadyAt` (sim seconds) and, per formation, `tags`:
the trait and ability ids acting on it, shown on its card and in the inspector with their full text.

## Battle honours (campaigns)

When a campaign battle is decided, every surviving unit of the winning side gains "<battle> <year>"
("Jena 1806"; the grand campaign uses the set piece's name, e.g. "Austerlitz 1805", else the
province and the year of the turn). No repeats; at most 5 per unit, the oldest gives way. The
campaign log gets one chronicle line per honoured army (the player's own in the grand campaign).
Profiles with more than 5 honours on a unit, or one longer than 40 characters, are rejected on load.

## Battle roles (AI)

A scenario may name its `attacker` (TW's attacker and defender): the attacking AI keeps advancing
while the enemy holds any objective; the defending AI holds its positions, garrisons its buildings
and counter-attacks only when it is overwhelming (the attack posture at 1.5 : 1). Without one
(Auerstedt, Austerlitz) both sides decide by the objectives and numbers, as before. Set from
history: France attacks at Jena, Waterloo and in their episodes and at the Landgrafenberg,
Vierzehnheiligen, Spielberg and the Pratzen; Prussia at Hassenhausen; the allies at Sokolnitz.

