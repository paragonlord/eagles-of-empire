# Grand campaign contract (Europe 1805–1815)

Binding interface between the grand-campaign rules (server) and the campaign map (client).
Owner of this file: main session. Change it only by agreement.

## Data (`src/shared/EuropeData.luau`, shared, pure)

- `Nations`: `{ [id] = { id, name, adjective, colour (palette key), capital (province id), playable: boolean, major: boolean } }`
  majors: `france`, `britain`, `austria`, `prussia`, `russia`; minors as needed (`spain`, `bavaria`,
  `saxony`, `naples`, `ottoman`, `sweden`, `denmark`, `portugal`, `netherlands`, …).
- `Provinces`: `{ { id, name, owner1805, centre = {x, z}, outline = { {x, z}, ... } (convex or
  simple polygon, map units 0..2000 × 0..1500, +z north), neighbours = {ids}, terrain =
  "jena"|"auerstedt"|"austerlitz"|"waterloo"|"bridge"|"village"|<other map id> (tactical map used
  for battles there), income, manpower, isCapital, isPort, fort (0..2) } }`, ~35–45 provinces.
- `StartArmies`, `StartRelations` (pairwise -100..100), `StartWars` (pairs), `Events` (scripted,
  dated: `{ id, turn, title, text, condition?, effects }`), `SetPieces` (`{ scenarioId, province,
  turnFrom, turnTo, attacker, defender }`: when an army battle happens there in that window, the
  historical scenario is offered), `TurnLength = "2 months"`, `StartTurn` = Jan 1805, `EndTurn` = Dec 1815.

## Server → client (`Campaign` remote, kind = "grandView")

```
{ kind = "grandView", sessionOnly, view = {
    turn, date = "May 1805", playerNation,
    nations = { [id] = { name, colour, treasury?, manpower?, atWarWith = {ids}, allies = {ids},
                         relationToPlayer, provinces } },        -- treasury/manpower only for the player
    provinces = { [id] = { owner, occupiedBy?, siege? = {by, turnsLeft}, unrest?, visibleArmies = {ids} } },
    armies = { [id] = { id, nation, name, general, provinceId, strength, units?, movesLeft?, path? } },  -- enemy armies only when visible (own or adjacent provinces)
    recruitment = {...}, diplomacy = { offers = { {id, from, kind, terms} } },
    events = { {id, title, text, choices?} },                     -- unread pop-ups
    pendingBattle? = { battleId, provinceId, attacker, defender, scenarioId?, odds = "favourable|even|poor" },
    log = {...}, victory? = {outcome, reason}, objectives = {...} } }
```

## Client → server

`{ requestId, action = "grand", data = { kind, ... } }` with kinds:
`newCampaign {nation}`, `move {armyId, path = {provinceIds}}`, `recruit {provinceId, unitType}`,
`merge {armyId, intoArmyId}`, `split {armyId, unitKeys}`, `replenish {armyId}`,
`diplomacy {nation, kind = "peace"|"alliance"|"war"|"accept"|"reject", offerId?}`,
`eventChoice {eventId, choice}`, `endTurn`, `fight`, `autoResolve`, `retreat`.
Errors come back as `{ kind = "error", requestId, reason }`.

## Additions (agreed with the client, as implemented)

1. Opening: `{action = "grand", data = {kind = "view"}}` → `grandView` if a grand campaign exists,
   otherwise `{kind = "error", reason = "noCampaign"}`; the client then sends `newCampaign {nation}`. A stored campaign that cannot be read answers `reason = "unreadable"`: it is kept untouched
   until the player picks a nation (`newCampaign` replaces it). The Thuringian campaign does the same:
   `open` sends the error after the view, and turns, battles and skips are refused until `new`.
2. `move {armyId, path}`: `path` excludes the army's current province (max 8 steps). The army goes as
   far as the rules allow; the call fails only if the first step is impossible. If only this turn's
   movement cut it short, the rest is kept: own armies carry `path` (the provinces still to go) and
   march on at the start of each turn until it is done or the rules stop them; any new move replaces it.
3. `movesLeft` counts provinces; armies of the player also carry `movesMax`. Army ids are strings
   (`"a12"`), so `armies` is a string-keyed table.
4. `recruitment = { options = { [provinceId] = { {unitType, name, class, cost, manpower, turns, upkeep,
   available, reason?} } }, queue = { {provinceId, unitType, name, turnsLeft} } }`.
5. `pendingBattle.attacker/defender` are army ids (the strongest army of each leading nation), with
   `attackerNation`/`defenderNation`, the full `attackers`/`defenders` nation lists, every army in
   the battle as `armies = { attacker = {ids}, defender = {ids} }`, and `attackerMen`/`defenderMen`
   (all of them; `odds` is computed over all of them too).
6. `view.events` holds unread events; `eventChoice {eventId}` without `choice` acknowledges a
   choiceless event and drops it. Unanswered choices take the first (historical) choice at end of turn.
7. `view.log` entries are strings (`"May 1805: …"`).
8. `diplomacy {nation, action = "peace"|"alliance"|"war"|"accept"|"reject", offerId?}`: the
   diplomatic verb is in `action` (data.kind is the action family "diplomacy"). A refused proposal
   comes back as `{kind = "error", reason = "refused"}` (also `truce`, `notAtWar`, `alreadyAtWar`).
9. `victory.outcome` is `"victory" | "defeat" | "draw"`.
10. Extra view fields: `campaignId, phase ("player"|"battle"|"ended"), endTurn, flags (navalSupremacy,
    continentalSystem, guerrilla, confederation, abdicated, …)`; per nation `adjective, capital, major,
    alive, truceUntil?, warScore?` (player's view, at war only) and, for the player only, `income,
    manpowerIncome, upkeep`; per army `rating, men, unitCount`; `objectives = { {id, text, done} }`;
    offers carry `terms = {winner, loser, score, provinces, dictated}` for peace.
11. Colour palette keys used by `Nations[*].colour` and battle units that the palette may lack:
    `Spain, Portugal, Italy, Naples, Wurttemberg, Sweden, Denmark, Ottoman`.
12. Tactical hand-off: in a generic battle the scenario's `factions` are the province map's two
    deploy-zone keys (e.g. `france`/`prussia` on `jena`) whatever the nations are; each unit carries
    its nation's `colour`, and `factionNames` gives the real side names ("Austria & allies"). Set
    pieces use the historical scenario's factions and OOB (strengths scaled to the campaign armies,
    keys `h:<side>:<n>`); `factions.player` is the side of the player's nation. Results commit with
    survivors `{strength, experience, destroyed, initial}` per unit key (CampaignService does this).
13. Persistence: the grand campaign is stored in its own DataStore (`EoEGrand/<scope>`) with its own
    session claim; the small campaign's `view` envelope now carries `name = "Thuringian Campaign"`.
14. Buildings: `build {provinceId, chain}` starts the next level of a chain (`EuropeData.Buildings`).
    Own provinces carry `buildings = { [chain] = level }`, `construction? = {chain, turnsLeft}`;
    every province carries `fort` (its fortress level). `view.buildings.options[provinceId]` lists
    `{chain, name, level, cost, turns, available, reason?}` for the next level of each chain.
    Recruitment refusals for a missing building read `needs:<chain>:<level>`.
15. Taxes and order: `tax {level}` (1 Low … 4 Very high); the player's nation carries `tax`; every
    province carries `revolt?` (in open revolt) next to `unrest`.
16. Technology: `research {tech}` (`EuropeData.Techs`). The player's nation carries `techs` (ids
    known), `research?`, `progress?` and `researchPoints`. Locked recruits read `needsTech:<id>`.
17. Reinforcements: a pending battle may carry `reinforcements = {attackers = {armyIds}, defenders =
    {armyIds}}` (neighbouring armies); in its tactical scenario their units carry `arrival`.
18. `forcedMarch {armyId}`: +1 move now, 3 % of the men, no moves next turn; own armies carry
    `forced` while it applies. Only with full moves. Refusals: `alreadyForced`, `alreadyMarched`.
19. Generals: `appoint {armyId}` (500 gold, a pool name at rating 2). Armies with a general carry
    `wins, losses, sieges, traits` ("Victor", "Unlucky", "Siege-master"). Refusals: `hasGeneral`,
    `noGenerals`, `insufficientFunds`.
20. `assault {provinceId}` (player phase, a siege by the player): a pending battle with
    `assault = true` (also on `pendingBattle`, whose `defenderMen` count the garrison); `retreat`
    calls it off. Refusals: `notBesieging`, `noArmyReady`.
21. Diplomacy actions `trade`, `access`, `gift` (with `amount`); offers may be of kind `trade`.
    Nations carry `trade` (an agreement with the player) and `access` (the player's armies may
    cross its land). Refusals: `alreadyTrading`, `alreadyAllowed`, `refused`, `insufficientFunds`.
22. Spies: `recruitSpy {provinceId}`, `moveSpy {agentId, provinceId}`, `sabotage {agentId}`.
    `view.agents = { {id, provinceId, movesLeft, movesMax} }` (the player's); armies within two
    marches of one carry `units`. Refusals: `needs:government:1`, `spyHere`, `tooManySpies`,
    `notYourSpy`, `tooFar`, `notBesieging`, `spyResting`, `nothingToSabotage`.
23. Navy: `view.fleets = { {id, nation, name, provinceId, line, frigates, movesLeft?, movesMax?} }`
    (the player's side's and any in sight; moves for the player's own). A sea crossing without a
    fleet of the army's side in the port is refused `noEscort`.

