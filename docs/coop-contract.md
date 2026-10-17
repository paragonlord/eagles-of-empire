# Co-op contract (vs AI, 2–4 players)

One server, one match, one human faction. Players split that faction's army by wing.

## Roles

- **commander**: the first player (existing rule). Picks the battle, difficulty and speed; can
  reassign wings; keeps the HQ.
- **officer**: every other player while fewer than 4 command. Commands only their own wing.
- **spectator**: the 5th player onward, or anyone who sends `spectate`. Sending `join` makes
  them an officer again if a slot is free.

## Wings

`m.controllers: { [formationId]: userId }` lives on the server.

- **Auto-split** happens on match create, when a player joins, or when a player leaves (before
  or during battle). It sorts the player faction's formations by position along the deploy
  zone's long axis, left to right, and cuts them into N contiguous wings, one per commanding
  player in join order. The HQ always goes to the commander.
- **Reassign**: a control `assign` with `value = { ids = {..}, userId = n }`, commander only.
  The target must be a commanding player.
- **Leaving**: an officer who leaves hands their formations back through the auto-split.

## Requests

- **Commands:** `Command` from a player whose ids include a formation they do not control fails
  with the new reason `notYours` ("That formation belongs to another officer"). The commander may
  command any formation (needed to take over an idle ally's units).
- **Commander-only controls:** `start`, `restart`, `difficulty`, `speed`, `assign`, `quit`, and
  the speed cap.
- **`ready`:** any player may send it. The battle starts when every commanding player is
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
  `{ userId, name, x, z, kind, tick }`.

## MatchState payload additions

```lua
role = "commander" | "officer" | "spectator",
players = { { userId, name, role, ready, slot } }, -- slot 1..4, stable while the player stays
controllers = { [formationId (string key)]: userId },
pauseVotes = n, pauseNeeded = n,
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

## Not yet

- PvP (two human factions).
- Per-player fog. All allies share the faction view.
- Voice or text chat beyond Roblox's own.
