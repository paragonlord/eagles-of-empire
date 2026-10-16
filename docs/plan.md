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
| 1 — visual target + command feel | source done | blocked (Studio) |
| 2 — real small battle | source done | blocked |
| 3 — full tactical depth | source done | blocked |
| 4 — quality & robustness | source: rules/net/AI/campaign tests + scripted 25-min battle | blocked (in-engine) |
| 5 — campaign | source done (rules, persistence, service, screen) | blocked |
| 6 — polish & delivery | docs/handoff current; place file built | blocked (screenshots, playtest) |

## Environment findings (Gate 0)

- Cloud Linux container, no Roblox Studio, no Studio MCP connection.
- `rojo`, `lune`, `luau` binaries unavailable (GitHub releases and crates.io blocked by
  network policy). Luau CLI + analyzer **built from source** in the session; definitions from
  `luau-lsp` `globalTypes.d.luau` for Roblox-aware strict checking.
- Reference frames arrived later (`docs/reference/`); see `docs/visual-notes.md`.
- Repository: github.com/paragonlord/eagles-of-empire (main).

## Task list (living)

- [x] Contracts: architecture, rules, visual notes
- [x] Shared: Config, Vec, RNG, Grid, MapGen (Jena map), Scenarios, Protocol, Types
- [x] Tools: test runner, analyzer wrapper, `.rbxlx` builder, `default.project.json`
- [x] Server: Sim core (formations, nav, movement, shapes), Net (remotes, validator, replicator), MatchService
- [x] Client: Net, World (terrain, props, labels), Figures (LOD), Camera, Input/Selection, HUD
- [x] Gate 2 (source): combat, morale, routing, objectives, victory, results, restart
- [x] Gate 3 (source): artillery, cavalry, squares, visibility, AI hierarchy, help panel, settings, audio fallback, effects
- [x] Gate 4 (source): edge-case tests, stress fixture benchmark, scripted full battle; in-engine profiling blocked
- [x] Gate 5 (source): campaign map, turns, recruitment, battle hand-off, persistence, campaign screen
- [~] Gate 6: docs/handoff current; art/usability pass needs Studio
