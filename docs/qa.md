# QA report — requirement to evidence

Status values: **pass** (evidence recorded), **fail** (reproduction below), **blocked** (needs
Roblox Studio; not run in this environment). Source checks are not in-engine checks.

## Source-level checks (run: `tools/check.sh`)

| Requirement | Evidence | Status |
| --- | --- | --- |
| Same state + commands ⇒ same results | `tests/sim.spec.luau` "Sim is deterministic" | pass |
| Pause freezes ticks; orders accepted while paused | `tests/net.spec.luau` MatchClock; Sim queues apply on the next tick | pass (clock) / blocked (end-to-end with remotes) |
| Render rate does not change outcome | `tests/net.spec.luau` "Different render rates" | pass |
| No fire out of range / through ridge / limbered / without ammo | `tests/sim.spec.luau` "Volleys need range…" | pass |
| Facing distinguishes front / flank / rear | "Facing distinguishes…" | pass |
| Square reduces cavalry shock; square takes time to form | "Square blunts a cavalry charge…" | pass |
| Charge applies impact once; no spam in contact | "Charge impact applies once…" | pass |
| Routing overrides orders; shattered cannot rally; HQ rally | "A volley inflicts…", "Shattered formations never rally…" | pass |
| Bridge traversal respects clearance; never in water | "Pathing crosses the Saale…" | pass |
| Dead / exited / routing units do not capture | "Objectives: routing and HQ units cannot capture…" | pass |
| Simultaneous, stable attack resolution | Combat.gather/apply order (ascending id), determinism test | pass |
| Victory applied once; totals reconcile | "Objectives… victory applies once" | pass |
| Reject other player's units, enemy ids, bad kinds, oversized batches, NaN coords, wrong match | `tests/shared.spec.luau` Protocol tests | pass |
| Rate limit and duplicate request ids | `tests/net.spec.luau` CommandGate | pass |
| Hidden enemies absent from snapshots; last-known frozen | "Snapshots hide unseen enemies…" | pass |
| Map determinism, bridges passable, zones passable | `tests/shared.spec.luau` MapGen | pass |
| Sim cost on 24 v 24 | `tests/bench.spec.luau`: ~1.3 ms/tick in the Luau CLI | pass (CLI only; Roblox server time blocked) |
| AI: determinism, honest information, square reaction, guns protected, reserve held, 10-min run | `tests/ai.spec.luau` | pass |
| Campaign: adjacency, one battle per army, exactly-once results, survivors reconcile, economy, victory/defeat, serialize round trip, store stale/error handling, 20-turn loop | `tests/campaign.spec.luau` (17 tests) | pass |
| Full battle pacing (scripted French plan vs normal AI, seed 20261014) | `python3 tools/test.py -k battle`: ran to the 25-min timeout, 72 volleys, 23 charges, 17 routs (all rallied), France 1929 / Prussia 1677 casualties, totals reconcile | pass (CLI; a human plan will differ) |
| Strict type analysis with Roblox globals | `tools/analyze.py src` (0 diagnostics for shared/server at last run) | pass |

## In-engine checks (blocked: no Studio in this environment)

| Check | Status |
| --- | --- |
| Launch → menu → deployment → battle → results → restart without duplicate HUD/connections | blocked |
| Second Studio client cannot control or pause the commander's battle | blocked |
| Reconnect receives complete state without duplicate units/effects | blocked |
| Group selection, queued march, formation change, volley, artillery, cavalry charge, rout, full battle, one victory and one defeat | blocked |
| Campaign turn → battle → casualties return → save → continue | blocked |
| 1920×1080, 1366×768, ultrawide layouts; label overlap; click-through; camera clipping | blocked |
| Frame rate with normal roster and stress fixture; instance counts; restart leak check | blocked |
| Terrain visual vs reference image (image not supplied) | blocked |

## Known failures

None recorded yet.
