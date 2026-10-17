# Grand campaign: Europe 1805–1815

Rules of the grand campaign (`src/server/GrandCampaign/`, data in `src/shared/EuropeData.luau`,
interface in `docs/grand-campaign-contract.md`). The small Thuringian campaign
(`src/server/Campaign/`) is unchanged and stays available as "Thuringian Campaign".

**Historical**: start ownership (January 1805), nations, capitals, starting commanders and roughly
where their armies stood, the wars and alliances of 1805, the event dates and what the events do.
**Gameplay**: every number (income, manpower, unit strengths and costs, movement, war score,
peace terms), the map geometry, the AI, and the conditions that let the timeline bend.

## Map

- 45 provinces on a 2000 × 1500 map (+z north), centres from real towns (`x = (lon + 10) · 40`,
  `z = (lat − 36) · 62.5`). Outlines are Voronoi cells of the centres plus unlisted sea sites,
  clipped to the map: they tile the land with no gaps or overlaps and leave the seas open. Rough by
  design.
- Neighbours are authored land borders plus 10 sea lanes between ports (England–Ireland/Normandy/
  Belgium/Holland/Denmark/Portugal, Naples–Sicily, Sweden–Denmark/St Petersburg/East Prussia).
  Britain and Ireland are reachable only by sea.
- Each province has a tactical map (`terrain`: jena, auerstedt, austerlitz, waterloo, bridge,
  village), income 40–450 and manpower 300–1500 per turn, port flag and fort 0–2.
- January 1805: France with Belgium, the left bank of the Rhine and Piedmont; Hanover (British)
  occupied by France; Holland (Batavian Republic) and Lombardy (Kingdom of Italy) as French
  satellites; Austria with Venetia, Dalmatia, Tyrol, Bohemia, Moravia, Hungary, Galicia; Prussia
  with Brandenburg-Pomerania, Silesia, East Prussia, Westphalia, South Prussia (Warsaw); Russia
  west of Moscow; Spain allied to France; Portugal, Naples, Bavaria, Saxony, Württemberg, Sweden,
  Denmark–Norway, the Ottoman Balkans.

## Turn

Two months a turn, Jan 1805 (turn 1) to Nov–Dec 1815 (turn 66).

1. Player phase: move, recruit, merge, split, replenish, diplomacy, event choices.
2. End turn: unanswered event choices take the first (historical) option; every other nation in
   turn order (France, Britain, Austria, Prussia, Russia, then the minors) runs its AI.
3. Contacts become battles; battles without the player's armies are auto-resolved at once.
4. Sieges and occupation.
5. Economy for every nation.
6. Turn + 1, movement restored, scripted events, victory check. If the player has battles pending
   the phase is "battle" until each is fought, auto-resolved or avoided (retreat).

With `endTurn(state, {autoplay = true})` the player's nation is also run by the AI (tests).

## Economy

| | |
|---|---|
| Owner, not occupied | full income and manpower |
| Occupier | half the income, no manpower; the owner gets nothing |
| Continental System | Britain income × 0.8; France and allies at war with Britain × 0.95 |
| British subsidies | 60 a turn to each major at war with France (while Britain has 300+) |
| Upkeep shortfall | treasury to 0, every unit of the nation loses 5 % |
| Guerrilla (after Dos de Mayo) | armies in Spanish/Portuguese provinces at war with the owner lose 3 % a turn |
| Replenish | 0.5 treasury and 1 manpower per man, in own or allied provinces |
| Caps | 50 000 treasury, 30 000 manpower, 20 units an army, 16 armies a nation |

Unit types (mapped onto the tactical sim classes; names per nation, e.g. "3e de Ligne", "2nd Light
Dragoons", "4. Musketier-Regiment"):

| Type | Sim class | Men | Cost | Manpower | Turns | Upkeep | Where |
|---|---|---|---|---|---|---|---|
| line | infantry | 600 | 300 | 600 | 1 | 12 | any owned province |
| light | infantry | 600 | 350 | 600 | 1 | 14 | any |
| guard | infantry | 700 | 700 | 700 | 3 | 25 | capital, majors only, experience 3 |
| cavalry | cavalry | 400 | 450 | 400 | 2 | 18 | any |
| heavy | cavalry | 400 | 600 | 400 | 2 | 24 | fort or capital |
| artillery | artillery | 120 | 400 | 120 | 2 | 20 | fort or capital |

Recruiting needs an owned, unoccupied, unbesieged province; two orders per province, six queued per
major and two per minor. Recruits join an army of the nation in that province or form a garrison.

## Armies and movement

- An army has a general (`rating` 1–5) or none. Movement: 2 provinces a turn, 3 under a general
  rated 4+ (Napoleon, Davout, Lannes, Masséna, Archduke Charles, Wellington).
- Entering a province costs 1, 2 inside an enemy zone of control (a neighbouring province holds an
  army at war with the mover). Entering a province with a hostile army or one controlled by an enemy
  ends the march. Neutral territory is closed: declare war first.
- Sea lanes join ports, need the full allowance and use it all. After Trafalgar no nation at war
  with Britain may use them.
- Fog: the player sees its own and allied armies, and others only in or next to provinces the player's
  side controls or stands in; foreign armies show strength, never units.

## Battles

- One battle per province with armies at war (provinces in fixed order). Defender: the controller if
  it has troops there, else the earliest army's side; its side is everyone present friendly to it;
  attackers are everyone present at war with it.
- Set pieces: Austerlitz (Moravia, Sep 1805–Apr 1806, France vs Russia or her allies), Jena then
  Auerstedt (Thuringia, Jul 1806–Apr 1807, France vs Prussia), Waterloo (Belgium, 1815, France vs
  Britain or her allies). The historical scenario is offered with its own OOB, strengths scaled by
  campaign men / historical men (0.5–1.5); each set piece is used once.
- Otherwise the battle uses the province's map: up to 24 strongest units a side plus one HQ for the
  best general, placed in the map's deploy zones.
- Auto-resolve: strength = Σ men × type power (line 1, light 1.1, guard 1.5, cavalry 1.3, heavy 1.6,
  artillery 3) × (1 + 0.1 experience) × (1 + 0.05 general rating) × nation quality (gameplay:
  France 1.15 for the corps system, Britain 1.1, others 1); defenders holding the province
  × (1.15 + 0.1 fort). p(attacker wins) = A^1.5 / (A^1.5 + D^1.5). Loser loses 25–40 %, winner
  8–18 %; units under 15 % of authorised strength are gone. Winners gain 1 experience (max 3).
- Tactical results: survivors by unit key; set-piece units and undeployed units take their side's
  overall survival fraction. Results commit once per battle id against the stored profile
  (`GrandCampaign.commitBattle`, same pattern as the small campaign).
- The loser falls back to a neighbouring land province its side controls with no enemy in it
  (own provinces first, then nearest the capital), or surrenders. Retreating before a battle costs
  5 % and 3 war score; allies left behind fight it out (auto-resolved).

## Sieges and occupation

An uncontested army at war with a province's controller besieges it for fort + 1 turns (fort 0:
taken at once). The province is then occupied (or liberated, if the besieger's side owns it).
Occupation changes control, not ownership: ownership moves only by treaty.

## War, peace, alliances

- War score per pair, −100..100: battle won +8 (+4 if an enemy army is destroyed), province taken
  +5, capital taken +20.
- Peace: the side ahead by ≥ 20 takes floor(score / 20) of the loser's provinces it occupies,
  richest first, never the capital, and each bordering by land the winner's own land (a major's:
  or its allies') or a province already ceded, so treaties make no exclaves; everything else
  occupied reverts. When a major makes peace, its minor allies at war with the same enemy make
  peace too. ≥ 50, or the loser's capital
  in the winner's hands, makes it a dictated peace. Truce 6 turns (10 after a dictated peace);
  scripted events may break it. Armies left in now-closed territory march to the nearest friendly
  province.
- Declaring war brings the target's allies in (minors only when their capital is within four
  marches of the aggressor's). Coalition events make every member ally the other enemies of France.
- AI acceptance: capital occupied; or war score ≤ −resolve (20, France 25, Russia 35, Britain 60);
  or it gains land (≥ 20 after two turns; never Britain against France); or a 14-turn stalemate
  (|score| < 15, not Britain). AIs losing to the player offer peace with the terms above.
  Alliances: relation ≥ 70, or ≥ 30 with a common enemy.
- Dominant France: each turn a major at peace with France (no truce, relation < 20) joins the war
  with probability clamp((share − 0.4) · 0.6, 0, 0.2), share = provinces controlled by France and
  her allies / 45.

## AI

Per nation, in turn order: diplomacy (above; under autoplay the player's nation answers offers like
any AI), replenish when the treasury allows, merge small armies in the same province, then move.

- **Theatre**: no army considers a province more than 4 marches from land its nation controls
  (allied land does not extend this), so armies stay at their front. Ordinary attacks reach at most
  2 marches beyond that land. Only Britain's AI uses sea lanes, and only into friendly ports (it
  ferries troops; it never makes opposed landings).
- **Strategic target** (majors): the enemy capital within the theatre of the enemy whose field
  strength is at most 1.25 × ours, a major's before any minor's, then ours / (theirs + 5000) per
  march. Field armies (a general or 6+ units) score every reachable province nearer to it,
  70 − 4 × marches still to go, wherever the stack they march with (plus our troops already there)
  is not outnumbered 1 : 1.25; an assault on a defended province takes the whole stack along.
  In 1806 this sends France at Berlin once the Fourth Coalition fires.
- **Main army** (majors): the strongest army with a general; other field armies within 3 marches
  follow it (50 − 6 per march), so a major fights in one stack.
- Other scores per army, for provinces within 3 marches: hold 20 (+50 at a capital threatened
  beyond the other troops there, +35 while besieging, +40 for a garrison of the capital in wartime,
  or for any army there while the garrison cannot cover the threat 1.2 : 1); defend a threatened
  own/allied province 30 (+40 capital) if it can face the threat; clear a hostile army inside our
  side's land that we outnumber 1.3 : 1, 60 (+80 next to the capital); attack an enemy-held province
  45 + income / 10 (+30 capital, +10 undefended) when 1.3 : 1 stronger (detachments without a
  general and under 4 units never attack); go home 15 at peace. −8 per march, up to +5 seeded noise.
  Minors only look within 3 marches of their capital.
- **Capital defence**: when hostile armies are within two land marches of the capital, armies within
  four land marches rally to it until it is covered 1.2 : 1.
- **Recruitment** follows a cycle (line, line, cavalry, line, artillery, light, line, heavy) while the
  treasury exceeds a reserve (300 majors, 150 minors) and income still covers the new upkeep; at
  peace only up to 12 units (4 for minors). Event choices: AIs take the first (historical) option.

Outcomes across eight seeds of autoplay to Jan 1809 are printed by the test suite: France beats
Austria in most seeds (dictated peace in 1806 in several), Prussia falls in about half, Paris holds.

## Events

Each fires once, at the first turn of its window whose conditions hold. Choices go to the chooser:
the player gets a pop-up, an AI takes the first option.

| Event | Window | Conditions | Effect (first choice) | Other choice |
|---|---|---|---|---|
| Third Coalition | Jul–Dec 1805 | Austria at peace with France, Britain at war with France | Bavaria, Württemberg ally France; Austria, Russia, Britain, Sweden, Naples at war with France (Austria chooses) | Austria stays out; Russia, Britain, Sweden fight on |
| Trafalgar | Sep–Oct 1805 | Britain at war with France, France does not hold England | naval supremacy: Britain's enemies cannot use sea lanes | — |
| Confederation of the Rhine | Jul–Dec 1806 | Austria's last peace with France dictated or won by France, at peace | flag, Bavaria and Württemberg allied, +300 treasury, Prussia −40 relation (France chooses) | leave the Empire standing: Prussia and Austria +20 |
| Fourth Coalition | Sep 1806–Apr 1807 | Prussia at peace with France; the Confederation exists or France holds Hanover | Prussia + Saxony allied; Prussia, Saxony, Russia, Britain at war with France (Prussia chooses) | keep the peace |
| Continental System | Nov 1806–Dec 1807 | at war with Britain; France holds Berlin or has beaten Prussia or Austria | blockade flag (incomes above) | — |
| Kingdom of Saxony | Nov 1806–Dec 1807 | Saxony at war with France, France holds Saxony | peace, Saxony leaves Prussia, allies France | — |
| Invasion of Portugal | Sep 1807–Feb 1808 | Continental System, Spain allied to France, Portugal not | France and Spain at war with Portugal; Britain allies Portugal | — |
| Dos de Mayo | May–Dec 1808 | Spain allied to France | Joseph crowned: Spain changes sides, allies Britain and Portugal, guerrilla, Castaños's army appears in Andalusia (France chooses) | restore the Bourbons: Spain −30 relation, France −400 treasury |
| Fifth Coalition | Mar–Oct 1809 | Austria at peace with France and holds Vienna; Britain at war with France | Austria and Britain at war with France (Austria chooses) | bide our time |
| The Niemen | May–Oct 1812 | France at peace with Russia, holds Paris | war with Russia; Prussia and Austria, if at peace with France, become her allies (France chooses) | keep the peace: the Continental System lapses |
| General Winter | Nov 1812–Feb 1813 | France at war with Russia | French armies in Russian provinces lose 35 % | — |
| Sixth Coalition | Mar–Aug 1813 | France at war with Russia | Russia, Britain, Sweden; Prussia rises (Prussia chooses) | Prussia stays loyal |
| Metternich's Ultimatum | Jul–Dec 1813 | Austria at peace with France; France at war with Russia or Prussia | Austria joins the coalition (Austria chooses) | armed neutrality |
| Treaty of Ried | Sep 1813–Apr 1814 | France at war with Austria and Russia | Bavaria and Württemberg change sides | — |
| The Hundred Days | Mar–Jun 1815 | France holds Paris | Britain, Prussia, Austria, Russia at war with France; Wellington's Anglo-Allied army (Belgium/Holland/England), Blücher's (Rhineland/Westphalia/Brandenburg) and the Armée du Nord at Paris appear | — |
| The Emperor Abdicates | any turn | a nation at war with France controls Paris | France makes dictated peace with every enemy | — |

A general already commanding an army is not duplicated by a spawned army.

## Victory

- France: every other major has signed a peace dictated by France, or France controls 3 foreign
  major capitals (Vienna, Berlin, St Petersburg, London) on or after Jan 1815
  (`EuropeData.Victory`). Defeat: Paris falls and the Emperor abdicates, or France is wiped out.
  Reaching 1816 otherwise is a draw.
- Other majors: victory when France abdicates while at war with you (draw if you were at peace);
  defeat if France wins, if you are wiped out, or if Napoleon still rules in 1816.

## Persistence

Same pattern as the small campaign: the state is pure data with a serialisable RNG; checkpoints
are revision-checked and session-owned; battle results commit exactly once by battle id; corrupt
profiles are refused. The grand campaign uses its own DataStore (`EoEGrand`) and session claim.
