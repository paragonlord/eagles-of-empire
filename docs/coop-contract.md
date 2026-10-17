# Co-op and PvP contract (2–4 players)

One server, one match. In co-op every player is on the scenario's player faction against the AI
and they split that army by wing. In PvP (below) the players take two sides; within a side the
co-op rules apply unchanged.

## Roles

- **commander**: the first player (existing rule). Picks the battle, difficulty and speed; can
  reassign wings; keeps the HQ.
- **officer**: every other player while fewer than 4 command. Commands only their own wing.
- **spectator**: the 5th player onward, or an officer who sends `spectate` with `value = true`
  (a plain `spectate` with no value stays a state refresh, as the client sends on startup; the
  commander cannot spectate: `badState`). Sending `join` makes them an officer again if a slot
  is free (`badState` when all four are taken).
- **Commander leaving**: command passes to the next commanding player in join order (else to a
  spectator). Only when nobody is left does the match pause for `ReconnectGrace`, as today.

## Wings

`m.controllers: { [formationId]: userId }` lives on the server.

- **Auto-split** happens on match create, when a player joins, or when a player leaves (before
  or during battle). It sorts the player faction's formations by position along the deploy
  zone's long axis (x when the zone is at least as wide as deep, else z; ascending), and cuts them into N contiguous wings, one per commanding
  player in join order. The HQ always goes to the commander. A join or leave that leaves the
  commanding set unchanged (a spectator) does not re-split; a re-split discards manual assigns.
- **Reassign**: a control `assign` with `value = { ids = {..}, userId = n }`, commander only.
  The target must be a commanding player (`badTarget`); every id must be a player-faction
  formation (`notOwned`).
- **Leaving**: an officer who leaves hands their formations back through the auto-split.

## Requests

- **Commands:** `Command` from a player whose ids include a formation they do not control fails
  with the new reason `notYours` ("That formation belongs to another officer"). The commander may
  command any formation (needed to take over an idle ally's units).
- **Commander-only controls:** `start`, `restart`, `difficulty`, `speed`, `assign`, `quit`, and
  the speed cap.
- Spectators get `notCommander` for everything except `spectate` and `join`.
- **`ready`:** any commanding player may send it. The battle starts when every commanding player is
  ready, or when the commander sends `ready` a second time (force).
- **`pause` / `resume` are votes:**
  - Each commanding player holds one vote.
  - The match pauses once ⌈n/2⌉ players vote `pause`.
  - Votes clear on every pause or resume.
  - `resume` works the same way, except the commander's `resume` alone is enough.
  - With one player, both act immediately, as today.
  - Moment cards (the client sends `pause`/`resume`) count only when solo; the client sends them
    only when `#players == 1`.
- **`ping`:** `value = { x, z, kind }` where kind is `look`, `attack` or `defend`. At most one
  per player per second. It is sent to every non-spectator player on the new remote `Ping` as
  `{ userId, name, x, z, kind, tick }`. Faster pings get `rateLimited`; off-map ones
  `badPosition`.

## MatchState payload additions

```lua
role = "commander" | "officer" | "spectator",
players = { { userId, name, role, ready, slot } }, -- commanding players only; slot 1..4, stable while the player stays
controllers = { [formationId (string key)]: userId },
pauseVotes = n, pauseNeeded = n, -- votes toward pausing while running, toward resuming while paused
```

Slot colours on the client: 1 gold, 2 sky blue, 3 crimson, 4 ivory green.

## Client

- **Selection** only picks your own formations. Allies' formations show their officer's slot
  colour on the plate stripe and the officer's name on hover.
- **Card bar**: your wing first, then allies' cards dimmed, and not selectable unless you are
  commander.
- **HUD**:
  - A player list (top left, under the clock) shows name, slot colour, ready ✓ and the pause
    vote count.
  - The pause button reads "Vote pause (1/2)" when n > 1.
- **Ping**: G plus a click, or a middle click.
  - A world marker: a coloured banner pole lasting 6 s.
  - A minimap blip.
  - A short sound hook in `Audio`.
- **Deployment**: each wing is tinted by its slot colour; the commander can drag-assign
  through `assign` (a later step; a plain "Give selected to …" menu is fine).

## PvP

- **Mode**: control `mode` with `value = "coop" | "pvp"`, commander only. Sent from the menu it
  applies to the next match; during deployment it switches the current one (ready flags and votes
  clear). Refused (`badState`) in other states, and `pvp` is refused for the tutorial and campaign
  battles, which always run co-op. `MatchState.mode` reports it.
- **Sides**: every commanding player has a side, the scenario's `player` or `enemy` faction. A
  player who enlists joins the side with fewer commanding players (ties: player side). At most 4
  command in total, so 1v1, 2v1 and 2v2 all work.
  - `side` with `value = faction id` (commanding players, PvP deployment only; `badState` otherwise,
    `badRequest` for a faction not in the scenario). Clears that player's ready flag.
  - `balance` (commander, PvP deployment): the commander keeps their side, the others alternate in
    join order starting on the other side.
- **Side lead**: the commander when on that side, else the side's first commanding player in join
  order. The lead holds the side's HQ (abilities, rally), may command any formation of the side and
  may `assign` within it (the target must be on the same side: `badTarget`). The commander (host)
  alone keeps the match controls (`start`, `restart`, `difficulty`, `mode`, `balance`, `quit`).
- **Wings** split per side among that side's players; a side or roster change re-splits.
- **AI** runs only a side without commanding players (both sides humans: no AI). If a side empties
  mid-battle the AI takes it over; a player joining it takes it back.
- **Views**: each player gets snapshots, `viewerFaction`, `controllers` (own side's formations only),
  pings (own side only) and `results` (outcome and feedback rewritten for their side) for their
  own side. Spectators see the host's side only. There is no observer of both sides.
- **Ready**: starts when every commanding player is ready; no forced start.
- **Pause**: needs every commanding player's vote (`pauseNeeded = n`); any one player's `resume`
  resumes (`pauseNeeded = 1` while paused). Moment cards never pause (they only do solo).
- **Speed** is fixed at 1×: `speed` with any other value gets `badState`.
- **Payload**: `mode`, `lead` (this player leads their side), and `players[].side` (faction id).

### Client

- Deployment: the host gets a mode toggle (also in Choose a battle). In PvP a side picker shows
  two flag buttons (name from `scenario.factionNames`, player count), the host's Balance sides, and
  the roster grouped by side.
- HUD player list grouped by side, own side first. Enemy plates and cards never name a player.
- `viewerFaction` is your side, so the Prussian, Austrian or Russian army is "own" for its players;
  a side switch rebuilds the deployment view.

## Not yet

- Per-player fog. All allies share the faction view.
- An observer who sees both sides.
- Voice or text chat beyond Roblox's own.
