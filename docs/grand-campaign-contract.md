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
