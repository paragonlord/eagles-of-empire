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
| Headquarters | 40 staff |

Casualties are applied to strength in men; the client removes one figure per 25 men lost.

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

Terrain: open 1.0, road 1.3, woods 0.6 (cavalry 0.4), village 0.7 (0.5), bridge 0.9, steep 0.5,
water/cliff impassable. Roads give the only >1.0 factor, so marching in column along a road is
the fastest way across the map.

Footprint: `width = files * figureSpacing`, `depth = ranks * rankSpacing`; files = ceil(figures / ranks).
Line 5/3 (a 600-man battalion: 8 files → 40 × 9 studs), column 4/3 (8 ranks), square 4/4, travel 4/3
(12 ranks). Square: side = ceil(sqrt(figures)) files. Half-width is used for clearance; if the path's
minimum clearance < half-width the formation adopts `travel` (half-width 8) until clearance
allows the previous shape again (restored automatically, costs the reform time).

Turning: heading moves toward the target at `shape.turnRate` rad/s; a line cannot fire until
within 0.15 rad of its facing.

Navigation: A* on the 16-stud nav grid, cost = distance / terrain.speed, nodes impassable
when clearance < 8. Replan when the path is blocked for `StuckSeconds = 4` or a new order
arrives. Avoidance: formations push apart when footprints overlap by more than
`AvoidanceRadius`; the lower id yields at choke points.

## Shapes and reforming

| Shape | ranks | fire | melee | cavalry shock taken | artillery taken |
| --- | --- | --- | --- | --- | --- |
| line | 3 | 1.0 | 1.0 | 1.0 | 1.0 |
| column | 8 | 0.3 | 1.15 | 1.3 | 1.9 |
| square | – | 0.5 | 0.9 | 0.15 | 2.2 |
| travel | 12 | 0 | 0.6 | 1.8 | 2.0 |

Reform times (seconds): line 12, column 8, square 15 (10 from column), travel 6, limber 25,
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
| HQ within 120 | + 0.3 /s extra recovery, cap base + 10 |
| no damage for 10 s | + 0.5 /s up to base |
| army HQ lost | − 15 once to every friendly formation |
| artillery battery destroyed | − 5 once to every friendly formation |

Bands with hysteresis: steady ≥ 50; shaken when < 40 (exit at ≥ 50); routing when < 20.
Routing: order cleared, moves toward its own map edge at ×1.3 speed through passable terrain,
takes no voluntary action, accepts no orders. Rally: after ≥ 20 s routing, morale ≥ 35 and no
enemy within 120 → `rallying` (5 s) → idle, shaken. HQ `Rally` order: formations within 100
that have routed ≥ 5 s get + 30 morale and rally immediately; cooldown 90 s.
Shattered: routing with strength < 30 % of start, or a third rout → never rallies. Exited:
centre crosses the map edge + 20 → removed from play, counted as lost.

## Fatigue

0–100. + 0.35 /s marching (infantry; cavalry 0.5, guns 0.3; ×terrain.fatigue), + 6 /s charging, + 2 /s in melee, − 1.5 /s resting
(idle). Effects: speed ×(1 − 0.4 f), accuracy ×(1 − 0.3 f), melee ×(1 − 0.4 f). Never immobile.

## Visibility

A formation sees enemies within its spot radius (infantry 260, cavalry 320, artillery 240, HQ
300) with clear LOS (heightmap + woods/village sight height, eye height 4, tolerance 0.5). Enemies inside woods or villages
are only seen within 60. Visible set per faction is the union; last-known entries remember
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
   minute 10 (`HoldAllEarliest`), so a defender starting on the objectives cannot win by default.
3. **Timeout** (25 min): more objectives held wins; equal → draw ("Indecisive").
Precedence when several trigger in the same tick: collapse of the *attacker* (player) is
checked first, then the enemy, then objectives, then timeout.

## Results

Per side: deployed, casualties, remaining, surviving/routed/shattered/destroyed/exited
formations. Totals reconcile with the sim: `deployed = remaining + casualties` where casualties
include the strength of exited formations. Feedback lines are generated from the match log
(e.g. "Your cavalry charged a formed square twice.").
