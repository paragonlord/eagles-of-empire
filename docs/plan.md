# Plan and gate tracker

Defaults in force (from the brief, not re-asked): PC-first commander controls; player commands
formations; solo vs AI; real-time with pause and ×1/×2/×4; France vs Prussia, condensed
Jena-inspired 1806 scenario; campaign after the battle gate.

Workflow in force: **source-only** (no Studio, no Rojo/Lune binaries reachable). Implementation
status and verification status are tracked separately below. Nothing here counts as verified
in-engine until `docs/qa.md` records a Studio run.

| Gate | Implementation | Verification |
| --- | --- | --- |
| 0 — environment, reference, contracts | done (this commit) | n/a |
| 1 — visual target + command feel | in progress | blocked (Studio) |
| 2 — real small battle | pending | blocked |
| 3 — full tactical depth | pending | blocked |
| 4 — quality & robustness | pending | blocked |
| 5 — campaign | pending | blocked |
| 6 — polish & delivery | pending | blocked |

## Environment findings (Gate 0)

- Cloud Linux container, no Roblox Studio, no Studio MCP connection.
- `rojo`, `lune`, `luau` binaries unavailable (GitHub releases and crates.io blocked by
  network policy). Luau CLI + analyzer **built from source** in the session; definitions from
  `luau-lsp` `globalTypes.d.luau` for Roblox-aware strict checking.
- `image.png` missing from the upload; see `docs/visual-notes.md`.
- Target repo not yet created; project initialised locally as a git repo.

## Task list (living)

- [x] Contracts: architecture, rules, visual notes
- [ ] Shared: Config, Vec, RNG, Grid, MapGen (Jena map), Scenarios, Protocol, Types
- [ ] Tools: test runner, analyzer wrapper, `.rbxlx` builder, `default.project.json`
- [ ] Server: Sim core (formations, nav, movement, shapes), Net (remotes, validator, replicator), MatchService
- [ ] Client: Net, World (terrain, props, labels), Figures (LOD), Camera, Input/Selection, HUD
- [ ] Gate 2: combat, morale, routing, objectives, victory, results, restart
- [ ] Gate 3: artillery, cavalry charge, squares, visibility/last-known, AI hierarchy, tutorial, settings, audio, effects
- [ ] Gate 4: edge cases, tests, profiling hooks, stress fixture
- [ ] Gate 5: campaign map, turns, recruitment, battle hand-off, persistence
- [ ] Gate 6: polish, docs, handoff
