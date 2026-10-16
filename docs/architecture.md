# Eagles of Empire — architecture contracts (Gate 0)

Short, binding decisions. Code that contradicts this file is a bug in one of the two.

## Platform & workflow

- Roblox, Luau, `--!strict` everywhere it compiles.
- Source tree is a Rojo 7 project (`default.project.json`). `tools/build_place.py` emits
  `build/EaglesOfEmpire.rbxlx` from the same tree so a place file exists without Rojo.
- Source checks run outside Studio: `luau-analyze` (strict, Roblox globals) and the Luau CLI
  test runner (`tools/run_tests.luau`). In-engine checks are **blocked** until a Studio session
  runs them; see `docs/qa.md`.

## Roblox tree ↔ source

| Roblox path | Source | Contents |
| --- | --- | --- |
| `ReplicatedStorage/EoE` | `src/shared/` | Config, Types, Protocol, Vec, RNG, Grid, MapGen, Scenarios, Util |
| `ServerScriptService/EoE` | `src/server/` | `Main.server.luau`, MatchService, Sim/*, AI/*, Net/*, Campaign/*, Persist/* |
| `StarterPlayer/StarterPlayerScripts/EoEClient` | `src/client/` | `Main.client.luau`, Camera, Input, Selection, Net, World/*, Figures, UI/*, Effects, Audio |

`ReplicatedStorage` holds only what clients need (map generator, config, protocol). Simulation,
AI, campaign and persistence code lives under `ServerScriptService` and never replicates.

## Coordinates and scale

- The simulation is **2D**: position = `{x, z}` in studs on the battlefield plane. Height comes
  from the authoritative heightmap (`Grid`). Roblox `Vector3`/`CFrame` appear only in client
  visuals and the thin server adapters; the sim never requires Roblox datatypes.
- 1 stud = 1 metre nominally, but distances are **condensed** for pacing (see `rules.md`).
  Musket effective range 90 studs, round shot 450, map 1600 × 1200 studs.
- Heading = radians, 0 along +x, increasing toward +z (right-handed on the ground plane).
  `Vec.fromHeading(h) = {x = cos h, z = sin h}`.
- Grid cell size: heightmap and terrain classes at **4 studs** (400 × 300 cells);
  navigation at **16 studs** (100 × 75 nodes). Both derive from one `MapGen` run.

## One source of terrain truth

`MapGen.generate(mapId)` is deterministic (seeded, pure Luau) and runs on both server and
client. The server uses its output for navigation, placement, line of sight, slopes and
objectives. The client uses the same output to write terrain voxels and place props. Nothing
decorative is ever queried for gameplay; client raycasts only pick the ground for cursor
position, and the server re-validates every coordinate against the grid.

Terrain classes: `open`, `road`, `woods`, `village`, `water`, `bridge`, `steep`. Passability,
speed, cover, sight-blocking and fatigue per class live in `Config.Terrain`.

Clearance: a distance transform of impassable cells gives `clearance[cell]` (studs to the
nearest impassable cell). A formation whose half-width exceeds clearance along its path travels
in **travel column** (half-width 8); cells with clearance < 8 are impassable for formations.

## Time

- Fixed logical step `Config.Sim.DT = 0.05` s (20 Hz). `Sim:step()` advances exactly one tick.
- Real time accumulates into a budget scaled by the speed multiplier (`1, 2, 4`); at most
  `Config.Sim.MaxTicksPerFrame = 6` ticks run per server frame. Beyond that, the sim runs
  slower than real time and reports `simLag` in snapshots instead of taking a giant step.
- Pause stops ticks. Control requests (pause/resume/speed/orders/deployment) are processed
  outside `step()` and are accepted while paused; they take effect at the next tick.
- AI decisions every `Config.AI.DecisionTicks = 10` ticks; perception every 4 ticks (staggered).
- Snapshots every 2 ticks (10 Hz).

## Tick order (deterministic)

1. Apply queued commands with `effectiveTick <= tick`, ordered by `(effectiveTick, seq)`.
2. AI (on schedule): produces commands for its faction via the same validator as the player.
3. Timed transitions: reforming, limber/unlimber, rally cooldowns, charge recovery.
4. Navigation & movement & facing (formations iterated in ascending id order).
5. Visibility (on schedule): per-faction visible sets + last-known memory.
6. Gather attacks from a frozen snapshot of positions/states: volleys, artillery, melee,
   charge impacts. Both sides resolve simultaneously; a unit that routes or is destroyed in
   step 8 of this tick still delivered its attack in step 6.
7. Apply damage and ammunition.
8. Fatigue, morale, rout/shatter/rally transitions, destroyed/exited.
9. Objectives (capture progress, contested).
10. Victory evaluation (once; terminal state freezes everything after).
11. Publish (on schedule).

Ties always break by ascending formation id. All randomness goes through `sim.rng`
(serializable xorshift state); cosmetic randomness is client-local.

## Formation (server record)

```
id, faction, ownerId, corps, class (infantry|cavalry|artillery|hq), name, startStrength,
strength, experience (0..3), pos {x,z}, heading, shape (line|column|square|limbered|deployed),
state (idle|moving|reforming|firing|charging|melee|retreating|routing|rallying|destroyed|exited),
morale (0..100), fatigue (0..100), ammo, reload (s remaining), order, queue[], path[],
pathIndex, targetId, timers {reform, limber, chargeRecover, rallyCd, shatterCheck},
stance {fireAtWill: bool}, cohesion (0..1), lastShotTick, melee {opponentId}, fled
```

Shape ≠ state. Legal transitions are in `docs/rules.md`.

## Protocol (RemoteEvents under `ReplicatedStorage/EoE/Remotes`)

Client → server
- `Command` `{matchId, requestId, kind, ids: {formationId...}, data}`; kinds in
  `Protocol.CommandKinds` (Move, AttackMove, Engage, Stop, Hold, Face, Retreat, Shape, Stance,
  Charge, Rally, Limber, Deploy). `data` is bounded and validated field by field.
- `Control` `{matchId, requestId, action, value}`; actions: `start, pause, resume, speed,
  restart, ready`.

Server → client
- `CommandResult` `{requestId, accepted, reason, effectiveTick}`.
- `Snapshot` `{matchId, tick, seq, kind: full|delta, state, formations, lastKnown, events,
  objectives, clock, speed, simLag}` filtered for the viewer's faction.
- `MatchState` `{matchId, state, briefing | results}`.

Every request carries `requestId` (client-unique); the server dedupes by `(player, requestId)`
for the life of the match and rejects unknown `matchId`. Rate limit: 30 requests / s / player,
batches ≤ 24 formation ids, payload numbers must be finite and inside map bounds.

## Session model (Release A)

One commander per server: the first player to join an idle match becomes commander. Any other
client is a spectator receiving the commander-faction snapshots and no control. Commander
departure pauses the match; reconnection within `Config.Match.ReconnectGrace` resumes it,
otherwise the match resets to the menu.

Lifecycle: `menu → loading → deployment → running ⇄ paused → results → (restart|campaign)`.
`MatchService:destroyMatch()` disconnects every connection, stops the loop and clears
replicated folders before a new match is created; the client mirrors this on `MatchState`.

## Campaign (Release B)

- Data: `src/shared/CampaignData.luau` (8 regions, adjacency, terrain variants, unit types,
  economy and victory constants). Rules: `src/server/Campaign/init.luau` (pure, seeded).
  Persistence: `src/server/Persist/ProfileStore.luau` (DataStore `UpdateAsync` semantics,
  bounded retry, session claims, memory adapter flagged `sessionOnly`).
- Session: `src/server/CampaignService.luau` owns one commander session per server; protocol on
  the `Campaign` remote: client `{requestId, action, data}` with `open | new | command | battle |
  skip | return`; server `{kind = "view", view, sessionOnly, battleId?}` or `{kind = "error"}`.
- Battle hand-off: `Campaign.battleScenario` → `MatchService.createMatchFrom(scenario, battleId)`;
  `MatchState.campaignBattle = {battleId, name}`. On results the match layer calls
  `CampaignService.onBattleEnded`, which commits through `Campaign.commitBattle` (idempotent by
  battle id, revision-checked, session-owned). The campaign is checkpointed before every battle;
  there is no mid-battle resume: a disconnect resumes from the checkpoint with the battle pending.
