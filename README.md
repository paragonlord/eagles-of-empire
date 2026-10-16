# Eagles of Empire

A Napoleonic real-time tactics game for Roblox: command formations, not soldiers, on a
condensed Jena 1806 battlefield. Luau, server-authoritative, built as a Rojo project.

## Open it in Roblox Studio

**Fastest:** open `build/EaglesOfEmpire.rbxlx` in Studio (File → Open from File), press Play.
Rebuild it after any source change with `python3 tools/build_place.py` (no Rojo needed).

**With Rojo (live sync):** install the Rojo plugin in Studio, run `rojo serve` in this folder
and connect from the plugin. `default.project.json` maps `src/` into the place.

Playtest: the first player to press **Play Battle** is the commander; other clients spectate.

## Layout

| Path | Contents |
| --- | --- |
| `src/shared/` | Config (every constant), map generator, scenarios, protocol, pure math |
| `src/server/` | `Sim/` (authoritative battle rules), `AI/`, `Net/`, `MatchService` |
| `src/client/` | camera, input, selection, world rendering, figures, HUD, effects, audio |
| `tests/` | Luau CLI tests (no Studio required) |
| `tools/` | test runner, analyzer wrapper, place builder |
| `docs/` | architecture, rules, visual notes, plan/gates, QA evidence, handoff |

## Source checks (no Studio)

```
tools/check.sh            # strict type analysis with Roblox globals + all tests
python3 tools/test.py -k sim   # one test group
python3 tools/analyze.py src/client
```
Requires the Luau CLI (`luau`, `luau-analyze`) on PATH; see `docs/plan.md` for how they were
built in this environment. The analyzer is a patched build that accepts
`--definitions=tools/globalTypes.d.luau`.

## Controls

See **How to Command** in the game or `docs/architecture.md`.
