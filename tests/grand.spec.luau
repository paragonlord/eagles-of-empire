-- Grand campaign (Europe 1805–1815): data, rules, battles, persistence. Deterministic, no Roblox.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local EuropeData = require(Shared.EuropeData)
local MapGen = require(Shared.MapGen)
local GrandCampaign = require(Server.GrandCampaign)
local ProfileStore = require(Server.Persist.ProfileStore)

local State = GrandCampaign.State
local Economy = GrandCampaign.Economy
local Movement = GrandCampaign.Movement
local Diplomacy = GrandCampaign.Diplomacy
local Battles = GrandCampaign.Battles
local Events = GrandCampaign.Events
local T = EuropeData.turnOf

local function deepEq(a, b, path)
	path = path or ""
	if type(a) ~= type(b) then
		return false, path .. ": " .. type(a) .. " vs " .. type(b)
	end
	if type(a) ~= "table" then
		return a == b, path .. ": " .. tostring(a) .. " vs " .. tostring(b)
	end
	for k, v in a do
		local ok, why = deepEq(v, b[k], path .. "." .. tostring(k))
		if not ok then
			return false, why
		end
	end
	for k in b do
		if a[k] == nil then
			return false, path .. "." .. tostring(k) .. " missing"
		end
	end
	return true
end

local function assertDeepEq(a, b, msg)
	local ok, why = deepEq(a, b)
	assertTrue(ok, (msg or "deepEq") .. ": " .. tostring(why))
end

local function results(outcome)
	return { outcome = outcome, reason = "test", clock = 0, objectives = {}, sides = {}, feedback = {}, log = {} }
end

-- A state with no armies at all, for hand-built situations.
local function empty(seed, nation)
	local s = State.new(seed or 1, nation)
	table.clear(s.armies)
	return s
end

local function army(s, nation, province, units, general)
	local a = State.newArmy(s, nation, nation .. " test army", province, general)
	State.addUnits(s, a, units or { line = 4 }, 1)
	return a
end

local function inside(poly, x, z)
	local c = false
	local j = #poly
	for i = 1, #poly do
		local a, b = poly[i], poly[j]
		if ((a.z > z) ~= (b.z > z)) and (x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x) then
			c = not c
		end
		j = i
	end
	return c
end

-- Data ---------------------------------------------------------------------------------------------

test("Grand data: provinces, symmetric neighbours, all reachable over land and sea lanes", function()
	local n = #EuropeData.Provinces
	assertTrue(n >= 35 and n <= 45, "province count " .. n)
	local byId = {}
	for _, p in EuropeData.Provinces do
		assertTrue(byId[p.id] == nil, "duplicate " .. p.id)
		byId[p.id] = p
	end
	for _, p in EuropeData.Provinces do
		assertTrue(EuropeData.Nations[p.owner1805], p.id .. " owner")
		assertTrue(p.fort >= 0 and p.fort <= 2 and p.income > 0 and p.manpower > 0, p.id .. " numbers")
		assertTrue(table.find(MapGen.list(), p.terrain) ~= nil, p.id .. " terrain " .. p.terrain)
		for _, nb in p.neighbours do
			assertTrue(byId[nb], p.id .. " -> unknown " .. nb)
			assertTrue(table.find(byId[nb].neighbours, p.id), nb .. " does not link back to " .. p.id)
			assertTrue(nb ~= p.id, p.id .. " neighbours itself")
		end
	end
	for _, l in EuropeData.SeaLanes do
		assertTrue(byId[l[1]].isPort and byId[l[2]].isPort, "sea lane between non-ports " .. l[1] .. "-" .. l[2])
		assertTrue(table.find(byId[l[1]].neighbours, l[2]), "sea lane not a neighbour " .. l[1] .. "-" .. l[2])
	end
	-- the British Isles touch the continent only by sea
	for _, isle in { "england", "ireland" } do
		for _, nb in byId[isle].neighbours do
			assertTrue(EuropeData.isSeaLane(isle, nb) or nb == "england" or nb == "ireland", isle .. " has a land border with " .. nb)
		end
	end
	assertTrue(EuropeData.isSeaLane("england", "ireland"))
	for _, id in EuropeData.ProvinceIds do
		local d = Movement.hops[id]
		for _, other in EuropeData.ProvinceIds do
			assertTrue(d[other] ~= nil, other .. " unreachable from " .. id)
		end
	end
end)

test("Grand data: outlines are simple non-degenerate polygons around their centres, inside the map", function()
	local total = 0
	for _, p in EuropeData.Provinces do
		assertTrue(#p.outline >= 3, p.id .. " outline")
		local area = EuropeData.area(p.outline)
		assertTrue(area > 5000, p.id .. " area " .. area)
		total += area
		assertTrue(inside(p.outline, p.centre.x, p.centre.z), p.id .. " centre outside its outline")
		for _, v in p.outline do
			assertTrue(v.x >= 0 and v.x <= EuropeData.Width and v.z >= 0 and v.z <= EuropeData.Depth, p.id .. " vertex out of map")
		end
	end
	-- outlines tile without overlaps: sample points belong to at most one province
	for x = 10, 1990, 40 do
		for z = 10, 1490, 40 do
			local hits = 0
			for _, p in EuropeData.Provinces do
				if inside(p.outline, x, z) then
					hits += 1
				end
			end
			assertTrue(hits <= 1, string.format("overlap at %d,%d", x, z))
		end
	end
	assertTrue(total > 0.5 * EuropeData.Width * EuropeData.Depth, "land covers too little of the map")
end)

test("Grand data: January 1805 ownership, capitals, nations, armies and wars", function()
	local s = GrandCampaign.new(1, "france")
	local function owner(id)
		return s.provinces[id].owner
	end
	for id, expected in { paris = "france", belgium = "france", rhineland = "france", piedmont = "france", holland = "netherlands", lombardy = "italy", england = "britain", venetia = "austria", tyrol = "austria", bohemia = "austria", galicia = "austria", hungary = "austria", brandenburg = "prussia", silesia = "prussia", eastprussia = "prussia", westphalia = "prussia", moscow = "russia", madrid = "spain", lisbon = "portugal", naples = "naples", bavaria = "bavaria", saxony = "saxony", wurttemberg = "wurttemberg", stockholm = "sweden", denmark = "denmark", constantinople = "ottoman" } do
		assertEq(owner(id), expected, id)
	end
	assertEq(owner("hanover"), "britain")
	assertEq(s.provinces.hanover.occupiedBy, "france")
	for _, m in EuropeData.Majors do
		assertTrue(EuropeData.Nations[m].major and EuropeData.Nations[m].playable, m)
	end
	for _, id in EuropeData.NationOrder do
		local n = EuropeData.Nations[id]
		local cap = EuropeData.province(n.capital)
		assertTrue(cap and cap.isCapital and cap.owner1805 == id, id .. " capital " .. n.capital)
	end
	assertTrue(State.atWar(s, "britain", "france"), "Britain at war with France since 1803")
	assertTrue(State.allied(s, "france", "spain"), "Spain allied to France until 1808")
	assertTrue(not State.atWar(s, "austria", "france") and not State.atWar(s, "prussia", "france"))
	local generals = {}
	for _, a in s.armies do
		if a.general then
			generals[a.general.name] = a.nation
		end
		assertTrue(State.friendly(s, a.nation, State.controller(s, a.provinceId)) or a.provinceId == "hanover", a.name .. " starts outside friendly land")
	end
	for name, nation in { ["Napoléon"] = "france", Davout = "france", Lannes = "france", Soult = "france", Ney = "france", Murat = "france", ["Archduke Charles"] = "austria", Mack = "austria", Kutuzov = "russia", Bagration = "russia", Brunswick = "prussia", Hohenlohe = "prussia", ["Blücher"] = "prussia", Wellington = "britain" } do
		assertEq(generals[name], nation, name)
	end
	assertEq(EuropeData.dateOf(1), "Jan 1805")
	assertEq(EuropeData.dateOf(3), "May 1805")
	assertEq(EuropeData.dateOf(EuropeData.EndTurn), "Nov 1815")
	assertEq(T(10, 1806), 11)
end)

-- Economy --------------------------------------------------------------------------------------------

test("Grand economy: owners collect, occupiers requisition half, upkeep is paid, recruits arrive", function()
	local s = empty(2)
	local income0, mp0 = Economy.income(s, "france")
	local expected, expectedMp = 0, 0
	for _, p in EuropeData.Provinces do
		if p.owner1805 == "france" then
			expected += p.income
			expectedMp += p.manpower
		end
	end
	expected += math.floor(EuropeData.province("hanover").income * Economy.OCCUPIER_SHARE)
	assertEq(income0, expected)
	assertEq(mp0, expectedMp)
	assertEq(Economy.income(s, "britain"), EuropeData.province("england").income + EuropeData.province("ireland").income, "Hanover pays the occupier, not the owner")
	local a = army(s, "france", "paris", { line = 2 })
	local before = s.nations.france.treasury
	Economy.run(s, "france")
	assertEq(s.nations.france.treasury, before + income0 - 2 * EuropeData.UnitClasses.line.upkeep)
	-- recruitment: costs up front, rules by province, arrives after `turns`
	local ok, why = Economy.recruit(s, "france", "normandy", "guard")
	assertTrue(not ok and why == "needsCapital")
	ok, why = Economy.recruit(s, "france", "normandy", "heavy")
	assertTrue(not ok and why == "needsFortress")
	ok, why = Economy.recruit(s, "france", "hanover", "line")
	assertTrue(not ok and why == "notYourProvince")
	local t0, m0 = s.nations.france.treasury, s.nations.france.manpower
	assertTrue(Economy.recruit(s, "france", "paris", "cavalry"))
	assertEq(s.nations.france.treasury, t0 - EuropeData.UnitClasses.cavalry.cost)
	assertEq(s.nations.france.manpower, m0 - EuropeData.UnitClasses.cavalry.manpower)
	Economy.run(s, "france")
	assertEq(#a.units, 2, "not yet")
	Economy.run(s, "france")
	assertEq(#a.units, 3, "cavalry joined the army at Paris")
	assertEq(a.units[3].type, "cavalry")
	-- a shortfall empties the treasury and costs every unit men, never goes negative
	s.nations.france.treasury = -0
	for _ = 1, 30 do
		Economy.recruit(s, "france", "paris", "line")
	end
	a.units[1].strength = 600
	s.nations.france.treasury = 0
	State.addUnits(s, a, { line = 15 }, 0)
	for _, p in EuropeData.Provinces do
		if p.owner1805 == "france" then
			s.provinces[p.id].occupiedBy = "britain"
		end
	end
	Economy.run(s, "france")
	assertEq(s.nations.france.treasury, 0)
	assertTrue(a.units[1].strength < 600, "attrition on shortfall")
	-- replenish costs treasury and manpower and stops at authorised strength
	s.provinces.paris.occupiedBy = nil
	s.nations.france.treasury, s.nations.france.manpower = 10000, 10000
	local restored = Economy.replenish(s, a)
	assertTrue(restored > 0)
	for _, u in a.units do
		assertEq(u.strength, u.maxStrength)
	end
	assertEq(s.nations.france.manpower, 10000 - restored)
end)

-- Movement --------------------------------------------------------------------------------------------

test("Grand movement: paths, movement points, stops in enemy land, zone of control, no neutral access", function()
	local s = empty(3)
	local a = army(s, "france", "paris", { line = 2 })
	assertEq(a.movesLeft, 2)
	assertTrue(Movement.move(s, "france", a.id, { "champagne", "rhineland" }))
	assertEq(a.provinceId, "rhineland")
	assertEq(a.movesLeft, 0)
	local ok, why = Movement.move(s, "france", a.id, { "belgium" })
	assertTrue(not ok and why == "noMovesLeft")
	-- Prussia is neutral in 1805: no access
	a.movesLeft = 2
	ok, why = Movement.move(s, "france", a.id, { "westphalia" })
	assertTrue(not ok and why == "noAccess")
	-- at war: entering enemy land ends the march
	Diplomacy.declareWar(s, "france", "prussia")
	ok = Movement.move(s, "france", a.id, { "westphalia", "hanover" })
	assertTrue(ok)
	assertEq(a.provinceId, "westphalia")
	assertEq(a.movesLeft, 0)
	-- ZOC: a province next to a hostile army costs 2
	local b = army(s, "france", "paris", { line = 1 })
	army(s, "prussia", "westphalia", { line = 1 })
	local cost, stops = Movement.step(s, "france", "belgium", "holland", 2, 2)
	assertEq(cost, 2, "holland borders the Prussian army in Westphalia")
	assertEq(stops, false)
	cost = Movement.step(s, "france", "paris", "normandy", 2, 2)
	assertEq(cost, 1)
	-- a general rated 4+ marches three provinces
	local c = army(s, "france", "provence", { line = 1 }, { name = "Davout", rating = 4 })
	assertEq(c.movesLeft, 3)
	assertTrue(Movement.move(s, "france", c.id, { "paris", "normandy", "aquitaine" }))
	assertEq(c.provinceId, "aquitaine")
	local _ = b
end)

test("Grand movement: sea lanes need ports and a full allowance; Trafalgar closes them to Britain's enemies", function()
	local s = empty(4)
	local a = army(s, "france", "normandy", { line = 2 })
	local cost, stops, err = Movement.step(s, "france", "normandy", "england", 1, 2)
	assertEq(err, "seaNeedsFullMoves")
	cost, stops, err = Movement.step(s, "france", "normandy", "england", 2, 2)
	assertEq(err, nil)
	assertEq(cost, 2)
	assertTrue(stops)
	s.flags.navalSupremacy = true
	local ok, why = Movement.move(s, "france", a.id, { "england" })
	assertTrue(not ok and why == "navalSupremacy")
	local w = army(s, "britain", "england", { line = 2 })
	ok = Movement.move(s, "britain", w.id, { "ireland" })
	assertTrue(ok, "Britain still sails")
	assertEq(w.provinceId, "ireland")
	ok, why = Movement.move(s, "france", a.id, { "paris", "england" })
	assertTrue(ok)
	assertEq(a.provinceId, "paris", "stopped before the sea")
end)

-- Sieges and occupation -------------------------------------------------------------------------------

test("Grand sieges: fort + 1 turns, broken by a relieving army, then occupation and war score", function()
	local s = empty(5)
	Diplomacy.declareWar(s, "france", "prussia")
	local a = army(s, "france", "brandenburg", { line = 4 })
	assertEq(EuropeData.province("brandenburg").fort, 1)
	Battles.sieges(s)
	assertEq(s.provinces.brandenburg.siege.by, "france")
	assertEq(s.provinces.brandenburg.siege.turnsLeft, 1)
	assertEq(s.provinces.brandenburg.occupiedBy, nil)
	Battles.sieges(s)
	assertEq(s.provinces.brandenburg.siege, nil)
	assertEq(s.provinces.brandenburg.occupiedBy, "france")
	assertEq(Diplomacy.score(s, "france", "prussia"), Diplomacy.SCORE.capital)
	-- no fort: taken at once
	a.provinceId = "westphalia"
	Battles.sieges(s)
	assertEq(s.provinces.westphalia.occupiedBy, "france")
	-- a defended province is not besieged; a fort 2 takes three turns
	local d = army(s, "prussia", "eastprussia", { line = 1 })
	a.provinceId = "eastprussia"
	Battles.sieges(s)
	assertEq(s.provinces.eastprussia.siege, nil)
	State.removeArmy(s, d.id)
	for i = 1, 3 do
		assertEq(s.provinces.eastprussia.occupiedBy, nil, "turn " .. i)
		Battles.sieges(s)
	end
	assertEq(s.provinces.eastprussia.occupiedBy, "france")
	-- the owner liberates its province
	local p = army(s, "prussia", "westphalia", { line = 1 })
	Battles.sieges(s)
	assertEq(s.provinces.westphalia.occupiedBy, nil)
	assertEq(State.controller(s, "westphalia"), "prussia")
	local _ = p
end)

-- Peace -------------------------------------------------------------------------------------------------

test("Grand peace: the winner keeps floor(score/20) occupied provinces, never the capital; truce; strays go home", function()
	local s = empty(6)
	Diplomacy.declareWar(s, "france", "austria")
	for _, id in { "vienna", "venetia", "tyrol", "bohemia" } do
		s.provinces[id].occupiedBy = "france"
	end
	s.provinces.provence.occupiedBy = "austria"
	local a = army(s, "france", "tyrol", { line = 2 })
	local w = s.wars[State.pair("france", "austria")]
	Diplomacy.addScore(s, "france", "austria", 45)
	assertEq(Diplomacy.score(s, "austria", "france"), -45)
	assertTrue(Diplomacy.aiAccepts(s, "austria", "france"), "losing and the capital is occupied")
	local transfers = Diplomacy.makePeace(s, "france", "austria")
	assertEq(#transfers, 2)
	assertEq(transfers[1], "bohemia", "richest first (120)")
	assertEq(transfers[2], "venetia")
	assertEq(s.provinces.bohemia.owner, "france")
	assertEq(s.provinces.venetia.owner, "france")
	assertEq(s.provinces.vienna.owner, "austria")
	assertEq(s.provinces.vienna.occupiedBy, nil, "capital returned")
	assertEq(s.provinces.tyrol.occupiedBy, nil, "rest reverts")
	assertEq(s.provinces.provence.occupiedBy, nil)
	assertTrue(not State.atWar(s, "france", "austria"))
	local pe = s.peaces[State.pair("france", "austria")]
	assertEq(pe.winner, "france")
	assertTrue(pe.dictated, "Vienna was in French hands")
	assertTrue(Diplomacy.inTruce(s, "france", "austria"))
	assertEq(Diplomacy.propose(s, "france", "austria", "war"), false)
	assertTrue(State.friendly(s, "france", State.controller(s, a.provinceId)), "French army left Austrian Tyrol")
	local _ = w
	-- small war score: white peace
	Diplomacy.declareWar(s, "prussia", "russia")
	Diplomacy.addScore(s, "prussia", "russia", 10)
	assertEq(#Diplomacy.makePeace(s, "prussia", "russia"), 0)
	assertEq(s.peaces[State.pair("prussia", "russia")].winner, "")
end)

test("Grand diplomacy: war brings allies in, coalitions ally their members, player offers", function()
	local s = empty(7, "austria")
	Diplomacy.declareWar(s, "austria", "france")
	assertTrue(State.atWar(s, "italy", "austria"), "France's ally defends it")
	assertTrue(not State.atWar(s, "spain", "austria"), "a distant minor stays out")
	Diplomacy.coalition(s, { "russia", "prussia" }, "france")
	assertTrue(State.allied(s, "russia", "austria") and State.allied(s, "prussia", "austria") and State.allied(s, "russia", "britain"))
	-- France losing badly to the player offers peace
	Diplomacy.addScore(s, "austria", "france", 40)
	Diplomacy.aiTurn(s, "france")
	assertEq(#s.offers, 1)
	assertEq(s.offers[1].kind, "peace")
	assertEq(s.offers[1].terms.winner, "austria")
	assertTrue(GrandCampaign.command(s, { kind = "diplomacy", action = "accept", nation = "france", offerId = s.offers[1].id }))
	assertTrue(not State.atWar(s, "austria", "france"))
	local ok, why = GrandCampaign.command(s, { kind = "diplomacy", action = "peace", nation = "russia" })
	assertTrue(not ok and why == "notAtWar")
end)

-- Events -------------------------------------------------------------------------------------------

test("Grand events: fire on their date when conditions hold, once, with the chooser's default", function()
	local s = State.new(8, "france")
	s.turn = T(5, 1805)
	Events.run(s)
	assertTrue(not s.fired.thirdCoalition, "too early")
	s.turn = T(7, 1805)
	Events.run(s)
	assertTrue(s.fired.thirdCoalition)
	assertTrue(State.atWar(s, "austria", "france") and State.atWar(s, "russia", "france"))
	assertTrue(State.allied(s, "france", "bavaria"))
	assertTrue(not s.fired.trafalgar)
	s.turn = T(9, 1805)
	Events.run(s)
	assertTrue(s.fired.trafalgar and s.flags.navalSupremacy)
	-- the Confederation needs Austria beaten and at peace
	s.turn = T(7, 1806)
	Events.run(s)
	assertTrue(not s.fired.confederation, "Austria still fighting")
	Diplomacy.addScore(s, "france", "austria", 40)
	Diplomacy.makePeace(s, "france", "austria")
	Events.run(s)
	assertTrue(s.fired.confederation)
	-- France's player gets the choice; nothing applied until answered
	local entry
	for _, e in s.inbox do
		if e.id == "confederation" then
			entry = e
		end
	end
	assertTrue(entry and entry.choices and #entry.choices == 2)
	assertTrue(not s.flags.confederation)
	assertTrue(GrandCampaign.command(s, { kind = "eventChoice", eventId = "confederation", choice = "spare" }))
	assertTrue(not s.flags.confederation)
	-- choiceless news can be acknowledged
	assertTrue(GrandCampaign.command(s, { kind = "eventChoice", eventId = "trafalgar" }))
	-- the Fourth Coalition then lacks its cause (no Confederation, Hanover not French)
	s.provinces.hanover.occupiedBy = nil
	s.turn = T(9, 1806)
	Events.run(s)
	assertTrue(not s.fired.fourthCoalition)
	-- out of window: never fires
	s.turn = T(5, 1807)
	s.provinces.hanover.occupiedBy = "france"
	Events.run(s)
	assertTrue(not s.fired.fourthCoalition)
end)

test("Grand events: Dos de Mayo choice, the Niemen, winter attrition, abdication", function()
	local s = empty(9, "russia")
	s.turn = T(5, 1808)
	Events.run(s)
	assertTrue(s.fired.peninsularWar)
	assertTrue(State.atWar(s, "spain", "france") and State.allied(s, "spain", "britain"), "AI France crowns Joseph")
	assertTrue(s.flags.guerrilla)
	s.turn = T(5, 1812)
	Events.run(s)
	assertTrue(State.atWar(s, "france", "russia"))
	assertTrue(State.allied(s, "france", "prussia") and State.allied(s, "france", "austria"), "contingents")
	local a = army(s, "france", "smolensk", { line = 4 })
	s.turn = T(11, 1812)
	Events.run(s)
	assertTrue(s.fired.russianWinter)
	assertTrue(a.units[1].strength < 600)
	-- Paris taken: abdication, dictated peace, the coalition player wins
	s.provinces.paris.occupiedBy = "russia"
	s.turn = T(3, 1813) - 1
	Events.run(s)
	assertTrue(s.flags.abdicated)
	assertTrue(not State.atWar(s, "france", "russia"))
	local v = GrandCampaign.victory(s)
	assertEq(v.outcome, "victory")
end)

test("Grand victory: France wins by dictated peace on every major, or capitals in 1815; loses with Paris", function()
	local s = empty(10)
	for _, m in { "britain", "austria", "prussia", "russia" } do
		s.peaces[State.pair("france", m)] = { winner = "france", dictated = true, turn = 1 }
		s.wars[State.pair("france", m)] = nil
	end
	assertEq(GrandCampaign.victory(s).outcome, "victory")
	s = empty(11)
	s.turn = EuropeData.Victory.CapitalsFromTurn
	for _, c in { "vienna", "brandenburg", "stpetersburg" } do
		s.provinces[c].occupiedBy = "france"
	end
	assertEq(GrandCampaign.victory(s).outcome, "victory")
	s.turn -= 1
	assertEq(GrandCampaign.victory(s), nil, "only from 1815")
	s = empty(12)
	s.flags.abdicated = true
	assertEq(GrandCampaign.victory(s).outcome, "defeat")
end)

-- Battles ---------------------------------------------------------------------------------------------

test("Grand battles: contacts become battles; set pieces by province, window and sides", function()
	local s = empty(13)
	Diplomacy.coalition(s, { "austria", "russia" }, "france")
	s.turn = T(11, 1805)
	army(s, "france", "moravia", { line = 6 }, { name = "Napoléon", rating = 5 })
	army(s, "russia", "moravia", { line = 6 }, { name = "Kutuzov", rating = 3 })
	army(s, "austria", "moravia", { line = 2 })
	local bs = Battles.detect(s)
	assertEq(#bs, 1)
	local b = bs[1]
	assertEq(b.defender, "austria", "the owner defends")
	assertTrue(table.find(b.defenders, "russia"))
	assertEq(b.attacker, "france")
	assertEq(b.scenarioId, "austerlitz")
	assertTrue(b.player)
	assertEq(Battles.matchSetPiece(s, "moravia", T(9, 1806), b.attackers, b.defenders), nil, "after the window")
	assertEq(Battles.matchSetPiece(s, "bohemia", T(11, 1805), b.attackers, b.defenders), nil, "elsewhere")
	-- Jena first, then Auerstedt in Thuringia, Oct 1806
	Diplomacy.declareWar(s, "france", "prussia")
	assertEq(Battles.matchSetPiece(s, "thuringia", T(10, 1806), { "france" }, { "prussia" }), "jena")
	s.usedSetPieces.jena = true
	assertEq(Battles.matchSetPiece(s, "thuringia", T(10, 1806), { "prussia" }, { "france" }), "auerstedt")
	assertEq(Battles.matchSetPiece(s, "thuringia", T(10, 1806), { "austria" }, { "russia" }), nil, "wrong sides")
end)

test("Grand battles: set-piece scenario keeps the historical OOB, scaled, sides mapped to the player", function()
	local s = empty(14, "russia")
	Diplomacy.coalition(s, { "austria", "russia" }, "france")
	s.turn = T(11, 1805)
	army(s, "france", "moravia", { line = 4 })
	army(s, "russia", "moravia", { line = 10 })
	local b = Battles.detect(s)[1]
	assertEq(b.scenarioId, "austerlitz")
	local sc = GrandCampaign.battleScenario(s, b.battleId)
	assertEq(sc.map, "austerlitz")
	assertEq(sc.factions.player, "russia", "the Russian player commands the Russian side")
	assertEq(sc.factions.enemy, "france")
	for _, u in sc.units do
		assertTrue(string.sub(u.key, 1, 2) == "h:", "set-piece key " .. tostring(u.key))
	end
	-- results by side fraction land on the campaign armies
	local survivors = {}
	for _, u in sc.units do
		local side = string.match(u.key, "^h:(%a+):")
		survivors[u.key] = { strength = if side == "attackers" then 0 else u.strength / 2, experience = 1, initial = u.strength, destroyed = side == "attackers" }
	end
	assertTrue(GrandCampaign.applyBattleResult(s, b.battleId, results("victory"), survivors))
	assertEq(#State.armiesOf(s, "france"), 0, "the French army was destroyed")
	local r = State.armiesOf(s, "russia")[1]
	assertEq(r.units[1].strength, 300)
	assertTrue(s.usedSetPieces.austerlitz)
end)

test("Grand battles: generic scenario on the province map with keys, zones and one HQ a side", function()
	local s = empty(15)
	Diplomacy.declareWar(s, "france", "austria")
	army(s, "france", "venetia", { line = 3, cavalry = 1, artillery = 1 }, { name = "Masséna", rating = 4 })
	army(s, "austria", "venetia", { line = 4, cavalry = 1 }, { name = "Archduke Charles", rating = 4 })
	local b = Battles.detect(s)[1]
	assertEq(b.scenarioId, nil)
	local sc = GrandCampaign.battleScenario(s, b.battleId)
	assertEq(sc.map, EuropeData.province("venetia").terrain)
	local map = MapGen.generate(sc.map)
	assertTrue(map.deployZones[sc.factions.player] and map.deployZones[sc.factions.enemy])
	assertEq(sc.factions.player, "france")
	local hq, keyed = {}, 0
	for _, u in sc.units do
		assertTrue(MapGen.inZone(map, u.faction, u.pos), u.name .. " outside its zone")
		if u.commander then
			hq[u.faction] = (hq[u.faction] or 0) + 1
		else
			keyed += 1
			assertTrue(string.sub(u.key, 1, 1) == "u")
		end
	end
	assertEq(keyed, 10)
	assertEq(hq[sc.factions.player], 1)
	assertEq(hq[sc.factions.enemy], 1)
	local aus
	for _, u in sc.units do
		if u.faction == sc.factions.enemy and not u.commander then
			aus = u
		end
	end
	assertEq(aus.colour, "Austria")
end)

test("Grand battles: auto-resolve is deterministic, the loser retreats, war score moves", function()
	local function setup()
		local s = empty(16)
		Diplomacy.declareWar(s, "france", "prussia")
		army(s, "france", "westphalia", { line = 8, artillery = 2 })
		army(s, "prussia", "westphalia", { line = 3 })
		return s, Battles.detect(s)[1]
	end
	local s1, b1 = setup()
	local s2, b2 = setup()
	assertTrue(GrandCampaign.autoResolve(s1, b1.battleId))
	assertTrue(GrandCampaign.autoResolve(s2, b2.battleId))
	assertDeepEq(GrandCampaign.serialize(s1), GrandCampaign.serialize(s2))
	local winner = s1.appliedBattles[1].winner
	local loser = if winner == "france" then "prussia" else "france"
	for _, a in State.armiesOf(s1, loser) do
		assertTrue(a.provinceId ~= "westphalia", "loser left the field")
	end
	assertTrue(Diplomacy.score(s1, winner, loser) >= Diplomacy.SCORE.battle)
	assertEq(#s1.pendingBattles, 0)
	local ok, why = GrandCampaign.autoResolve(s1, b1.battleId)
	assertTrue(ok and why == "alreadyApplied")
end)

test("Grand battles: retreat avoids the battle at a small cost", function()
	local s = empty(17)
	Diplomacy.declareWar(s, "france", "prussia")
	local a = army(s, "france", "westphalia", { line = 2 })
	army(s, "prussia", "westphalia", { line = 8 })
	s.phase = "battle"
	Battles.detect(s)
	assertTrue(GrandCampaign.command(s, { kind = "retreat" }))
	assertTrue(a.provinceId == "holland" or a.provinceId == "rhineland", a.provinceId)
	assertEq(a.units[1].strength, 570)
	assertEq(#s.pendingBattles, 0)
	assertEq(s.phase, "player")
end)

test("Grand persistence: battle results commit exactly once; stale and foreign sessions refused", function()
	local store = ProfileStore.new({ name = "EoEGrand", scope = "dev", sleep = function() end })
	local s = empty(18)
	Diplomacy.declareWar(s, "france", "prussia")
	army(s, "france", "westphalia", { line = 4 })
	army(s, "prussia", "westphalia", { line = 4 })
	local b = Battles.detect(s)[1]
	s.phase = "battle"
	assertTrue(store:claimSession(42, "sess", 0))
	local p0 = store:load(42)
	s.revision = p0.revision
	assertTrue(GrandCampaign.checkpoint(store, 42, "sess", s))
	local sc = GrandCampaign.battleScenario(s, b.battleId)
	local survivors = {}
	for _, u in sc.units do
		if u.key then
			survivors[u.key] = { strength = math.floor(u.strength * 0.7), experience = u.experience, initial = u.strength }
		end
	end
	local ok, s2, why = GrandCampaign.commitBattle(store, 42, "other", s, b.battleId, results("victory"), survivors)
	assertTrue(not ok and why == "notOwner")
	ok, s2, why = GrandCampaign.commitBattle(store, 42, "sess", s, b.battleId, results("victory"), survivors)
	assertTrue(ok and why == nil)
	assertEq(#s2.pendingBattles, 0)
	assertEq(s2.phase, "player")
	local french = State.armiesOf(s2, "france")[1]
	assertEq(french.provinceId, "westphalia")
	assertEq(french.units[1].strength, 420)
	-- retry with the pre-battle state: same committed state, not applied twice
	local ok2, s3, why2 = GrandCampaign.commitBattle(store, 42, "sess", s, b.battleId, results("defeat"), survivors)
	assertTrue(ok2 and why2 == "alreadyApplied")
	assertDeepEq(GrandCampaign.serialize(s3), GrandCampaign.serialize(s2))
	assertEq(State.armiesOf(s3, "france")[1].units[1].experience, french.units[1].experience)
	-- a checkpoint from an outdated revision is stale
	local okC, whyC = GrandCampaign.checkpoint(store, 42, "sess", s)
	assertTrue(not okC and whyC == "stale")
end)

-- Determinism and serialization -------------------------------------------------------------------

test("Grand determinism: same seed, same AI turns; serialize round trip continues identically", function()
	local a = GrandCampaign.new(99, "france")
	local b = GrandCampaign.new(99, "france")
	for _ = 1, 6 do
		assertTrue(GrandCampaign.endTurn(a, { autoplay = true }))
		assertTrue(GrandCampaign.endTurn(b, { autoplay = true }))
	end
	assertDeepEq(GrandCampaign.serialize(a), GrandCampaign.serialize(b), "same seed")
	local saved = ProfileStore.clone(GrandCampaign.serialize(a))
	local c = GrandCampaign.deserialize(saved)
	assertTrue(c ~= nil, "round trip")
	assertDeepEq(GrandCampaign.serialize(c), GrandCampaign.serialize(a), "round trip equal")
	for _ = 1, 4 do
		GrandCampaign.endTurn(a, { autoplay = true })
		GrandCampaign.endTurn(c, { autoplay = true })
	end
	assertDeepEq(GrandCampaign.serialize(c), GrandCampaign.serialize(a), "continues identically")
	-- corrupt profiles are refused
	local bad = ProfileStore.clone(saved)
	bad.provinces.paris.owner = "atlantis"
	assertEq(GrandCampaign.deserialize(bad), nil)
	bad = ProfileStore.clone(saved)
	bad.armies[1].units[1].strength = 1e6
	assertEq(GrandCampaign.deserialize(bad), nil)
	assertEq(GrandCampaign.deserialize({ version = 1, kind = "small" }), nil)
end)

test("Grand view: contract fields, fog of war, player-only treasury, recruitment options", function()
	local s = GrandCampaign.new(20, "france")
	local v = GrandCampaign.view(s)
	assertEq(v.date, "Jan 1805")
	assertEq(v.playerNation, "france")
	assertTrue(v.nations.france.treasury ~= nil and v.nations.austria.treasury == nil)
	assertTrue(table.find(v.nations.france.atWarWith, "britain"))
	assertTrue(v.provinces.paris.owner == "france" and v.provinces.hanover.occupiedBy == "france")
	local kutuzov, napoleon
	for _, a in s.armies do
		if a.general and a.general.name == "Kutuzov" then
			kutuzov = a.id
		elseif a.general and a.general.name == "Napoléon" then
			napoleon = a.id
		end
	end
	assertEq(v.armies[kutuzov], nil, "Kutuzov is far beyond sight")
	assertTrue(v.armies[napoleon].units and v.armies[napoleon].movesMax == 3)
	assertEq(v.armies[napoleon].general, "Napoléon")
	local seenEnemy = false
	for _, a in s.armies do
		if a.nation == "britain" and v.armies[a.id] then
			seenEnemy = true
			assertEq(v.armies[a.id].units, nil, "no enemy unit detail")
		end
	end
	assertTrue(seenEnemy, "the Channel army sees England")
	local opts = v.recruitment.options.paris
	assertTrue(opts and #opts == 6)
	for _, o in opts do
		assertTrue(o.unitType and o.name and o.cost and o.turns and type(o.available) == "boolean")
	end
	assertEq(#v.recruitment.options.normandy, 6)
	assertTrue(#v.objectives >= 5)
	assertEq(v.pendingBattle, nil)
end)

-- Full campaign --------------------------------------------------------------------------------------------

local function holdings(s)
	local held = {}
	for _, id in EuropeData.ProvinceIds do
		local c = State.controller(s, id)
		held[c] = held[c] or {}
		table.insert(held[c], id)
	end
	local lines = {}
	for _, n in EuropeData.NationOrder do
		if held[n] then
			lines[#lines + 1] = string.format("    %-12s %2d  %s", n, #held[n], table.concat(held[n], " "))
		end
	end
	return table.concat(lines, "\n")
end

test("Grand: 30 turns of AI-vs-AI with France on autoplay end cleanly and plausibly", function()
	local s = GrandCampaign.new(1805, "france")
	local t0 = os.clock()
	for _ = 1, 30 do
		if s.phase == "ended" then
			break
		end
		assertTrue(GrandCampaign.endTurn(s, { autoplay = true }))
		assertEq(#s.pendingBattles, 0, "autoplay leaves no battle pending")
		for _, a in s.armies do
			assertTrue(#a.units > 0 and #a.units <= State.MAX_UNITS)
		end
		for _, n in EuropeData.NationOrder do
			assertTrue(s.nations[n].treasury >= 0, n .. " treasury negative")
		end
	end
	print(string.format("  grand 30-turn run: %s, %.2f s, %d battles applied (last %d kept)", EuropeData.dateOf(s.turn), os.clock() - t0, #s.appliedBattles, State.APPLIED_MAX))
	print(holdings(s))
	local fired = {}
	for _, e in EuropeData.Events do
		if s.fired[e.id] then
			fired[#fired + 1] = e.id
		end
	end
	print("    events: " .. table.concat(fired, ", "))
	assertTrue(s.fired.thirdCoalition and s.fired.trafalgar, "1805 happened")
	assertEq(State.controller(s, "england"), "britain", "no crossing after Trafalgar")
	assertTrue(s.turn >= 25 or s.phase == "ended")
	-- the view stays buildable and serialisable at the end
	ProfileStore.clone(GrandCampaign.view(s))
	assertTrue(GrandCampaign.deserialize(ProfileStore.clone(GrandCampaign.serialize(s))) ~= nil)
end)
