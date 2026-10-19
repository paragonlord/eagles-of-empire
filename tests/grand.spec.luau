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
			expected += Economy.provinceIncome(s, p.id)
			expectedMp += p.manpower
		end
	end
	expected += Economy.provinceIncome(s, "hanover") * Economy.OCCUPIER_SHARE
	assertEq(income0, math.floor(expected))
	assertEq(mp0, expectedMp)
	assertEq(Economy.income(s, "britain"), math.floor(Economy.provinceIncome(s, "england") + Economy.provinceIncome(s, "ireland")), "Hanover pays the occupier, not the owner")
	local a = army(s, "france", "paris", { line = 2 })
	local before = s.nations.france.treasury
	Economy.run(s, "france")
	assertEq(s.nations.france.treasury, before + income0 - 2 * EuropeData.UnitClasses.line.upkeep)
	-- recruitment: costs up front, rules by province, arrives after `turns`
	local ok, why = Economy.recruit(s, "france", "normandy", "guard")
	assertTrue(not ok and why == "needsCapital")
	ok, why = Economy.recruit(s, "france", "normandy", "heavy")
	assertEq(why, "needs:stables:2", "heavy cavalry needs a cavalry school")
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

test("Grand buildings: 1805 start, one construction a province, effects, recruits need them, saves", function()
	local s = empty(4)
	local paris, normandy = s.provinces.paris.buildings, s.provinces.normandy.buildings
	assertEq(paris.barracks, 3, "a great power's capital trains its guard")
	assertTrue((paris.government or 0) >= 1 and (paris.stables or 0) >= 2)
	assertEq(normandy.barracks, 1, "every province has a drill ground")
	-- build farms in Normandy: paid up front, done in its turns, income rises
	local before = Economy.provinceIncome(s, "normandy")
	local level = (normandy.farms or 0) + 1
	local t0 = s.nations.france.treasury
	assertTrue(Economy.build(s, "france", "normandy", "farms"))
	assertEq(s.nations.france.treasury, t0 - EuropeData.Buildings.farms.cost[level])
	local ok, why = Economy.build(s, "france", "normandy", "trade")
	assertTrue(not ok and why == "building", "one construction at a time")
	ok, why = Economy.build(s, "france", "hanover", "farms")
	assertTrue(not ok and why == "notYourProvince")
	for _ = 1, EuropeData.Buildings.farms.turns[level] do
		Economy.run(s, "france")
	end
	assertEq(s.provinces.normandy.buildings.farms, level)
	assertEq(s.provinces.normandy.construction, nil)
	assertTrue(Economy.provinceIncome(s, "normandy") > before, "farms raise income")
	-- heavy cavalry needs a cavalry school: build stables twice in Normandy
	s.nations.france.treasury = 10000
	for i = 1, 2 do
		local lvl = (s.provinces.normandy.buildings.stables or 0)
		if lvl < 2 then
			assertTrue(Economy.build(s, "france", "normandy", "stables"))
			for _ = 1, EuropeData.Buildings.stables.turns[lvl + 1] do
				Economy.run(s, "france")
			end
		end
	end
	assertTrue(Economy.canRecruit(s, "france", "normandy", "heavy"), "now it can")
	-- fortifications lengthen sieges
	assertEq(State.fortLevel(s, "normandy"), s.provinces.normandy.buildings.fort or 0)
	-- saves keep them; a save from before buildings gets the 1805 start
	local back = GrandCampaign.deserialize(ProfileStore.clone(GrandCampaign.serialize(s)))
	assertTrue(back ~= nil)
	assertEq(back.provinces.normandy.buildings.stables, 2)
	local old = GrandCampaign.serialize(s)
	for _, ps in old.provinces do
		ps.buildings = nil
		ps.construction = nil
	end
	local migrated = GrandCampaign.deserialize(ProfileStore.clone(old))
	assertTrue(migrated ~= nil, "an old save still loads")
	assertEq(migrated.provinces.paris.buildings.barracks, 3)
	old.provinces.paris.buildings = { palace = 2 }
	assertEq(GrandCampaign.deserialize(ProfileStore.clone(old)), nil, "an unknown building is refused")
end)

test("Grand public order: taxes trade income for unrest, foreign rule needs a government, revolts rise and settle", function()
	local s = empty(6)
	local normal = Economy.income(s, "france")
	assertTrue(GrandCampaign.command(s, { kind = "tax", level = 4 }))
	assertTrue(Economy.income(s, "france") > normal, "very high taxes pay more")
	assertEq(GrandCampaign.view(s).nations.france.tax, 4)
	assertTrue(not GrandCampaign.command(s, { kind = "tax", level = 7 }), "no such level")
	-- Normandy (French in 1805, no government): very high tax = unrest 2; Paris has one
	assertEq(Economy.unrest(s, "normandy"), 2)
	assertEq(Economy.unrest(s, "paris"), math.max(0, 2 - s.provinces.paris.buildings.government))
	-- a conquest (Bavaria handed to France): foreign rule 3 + tax 2 = 5, and it rises in two turns
	s.provinces.bavaria.owner = "france"
	s.provinces.bavaria.buildings.government = nil
	assertEq(Economy.unrest(s, "bavaria"), 5)
	local a = army(s, "france", "bavaria", { line = 1 }) -- 600 men: too few to keep order
	Economy.run(s, "france")
	assertTrue(not s.provinces.bavaria.revolt, "not yet")
	Economy.run(s, "france")
	assertTrue(s.provinces.bavaria.revolt, "Bavaria rises")
	assertTrue(a.units[1].strength < a.units[1].maxStrength, "the garrison bleeds")
	local inRevolt = Economy.income(s, "france")
	s.provinces.bavaria.revolt = nil
	assertTrue(Economy.income(s, "france") > inRevolt, "a revolted province pays nothing")
	s.provinces.bavaria.revolt = true
	-- lower taxes and a prefecture settle it
	assertTrue(GrandCampaign.command(s, { kind = "tax", level = 1 }))
	s.provinces.bavaria.buildings.government = 1
	Economy.run(s, "france")
	assertTrue(not s.provinces.bavaria.revolt, "order restored")
	-- a strong garrison keeps order too
	assertTrue(GrandCampaign.command(s, { kind = "tax", level = 4 }))
	s.provinces.bavaria.buildings.government = nil
	State.addUnits(s, a, { line = 3 }, 0)
	assertEq(Economy.unrest(s, "bavaria"), 5 - math.min(2, math.floor(State.men(a) / 1000)), "troops keep order")
	-- saves keep taxes and revolts
	s.provinces.bavaria.revolt = true
	local back = GrandCampaign.deserialize(ProfileStore.clone(GrandCampaign.serialize(s)))
	assertTrue(back ~= nil and back.nations.france.tax == 4 and back.provinces.bavaria.revolt == true)
end)

test("Grand armies: refit at a depot a tenth a turn; winter in the harsh lands bleeds armies far from home", function()
	local s = empty(8)
	local home = army(s, "france", "paris", { line = 1 })
	local away = army(s, "france", "normandy", { line = 1 })
	home.units[1].strength, away.units[1].strength = 300, 300
	s.nations.france.treasury, s.nations.france.manpower = 5000, 5000
	Economy.run(s, "france")
	assertEq(home.units[1].strength, 300 + math.ceil(home.units[1].maxStrength * Economy.REFILL), "Paris has a depot")
	assertEq(away.units[1].strength, 300, "Normandy only a drill ground")
	-- an enemy next door stops it
	Diplomacy.declareWar(s, "france", "britain")
	army(s, "britain", "normandy", { line = 1 })
	local before = home.units[1].strength
	Economy.run(s, "france")
	assertEq(home.units[1].strength, before, "no refit with the enemy next door")
	-- winter: a French army in Moscow (Russian ground, at war) loses men; the Russians do not
	Diplomacy.declareWar(s, "france", "russia")
	local invader = army(s, "france", "moscow", { line = 2 })
	local native = army(s, "russia", "moscow", { line = 2 })
	s.turn = EuropeData.turnOf(1, 1813)
	assertTrue(EuropeData.isWinter(s.turn) and not EuropeData.isWinter(EuropeData.turnOf(5, 1813)))
	Economy.run(s, "france")
	Economy.run(s, "russia")
	assertTrue(invader.units[1].strength < invader.units[1].maxStrength, "General Winter")
	assertEq(native.units[1].strength, native.units[1].maxStrength, "at home with its depots")
end)

test("Grand technology: 1805 knowledge, research by points, unlocks and effects, saves", function()
	local s = empty(9)
	assertTrue(State.hasTech(s, "britain", "rifles") and State.hasTech(s, "france", "drill"))
	assertTrue(not State.hasTech(s, "austria", "drill"))
	-- tech-locked recruits
	local ok, why = Economy.canRecruit(s, "austria", "vienna", "rifles")
	assertEq(why, "needsTech:rifles")
	-- research: prerequisites, points a turn, completion
	ok, why = Economy.setResearch(s, "austria", "squares")
	assertTrue(not ok and why == "needsTech:drill", "Squares needs Platoon fire")
	assertTrue(GrandCampaign.command(s, { kind = "research", tech = "rotation" }))
	assertEq(s.nations.france.research, "rotation")
	local pts = Economy.researchPoints(s, "france")
	assertEq(pts, Economy.RESEARCH.major + Economy.RESEARCH.school * s.provinces.paris.buildings.school)
	local farmsIncome = function()
		s.provinces.normandy.buildings.farms = 2
		return Economy.provinceIncome(s, "normandy")
	end
	local before = farmsIncome()
	local turns = 0
	while not State.hasTech(s, "france", "rotation") and turns < 40 do
		Economy.run(s, "france")
		turns += 1
	end
	assertEq(turns, math.ceil(EuropeData.TechById.rotation.cost / pts), "done when the points add up")
	assertEq(s.nations.france.research, nil)
	assertTrue(farmsIncome() > before, "Crop rotation doubles the farms")
	-- other effects
	local mp0 = select(2, Economy.income(s, "france"))
	s.nations.france.techs.conscription = true
	assertEq(select(2, Economy.income(s, "france")), mp0 * 1.25, "Conscription")
	local cost = Economy.buildCost(s, "france", "trade", 1)
	s.nations.france.techs.ironworks = true
	assertEq(Economy.buildCost(s, "france", "trade", 1), math.floor(cost * 0.8), "Iron works")
	local u0 = Economy.unrest(s, "normandy")
	s.nations.france.tax = 4
	local u1 = Economy.unrest(s, "normandy")
	s.nations.france.techs.civilcode = true
	assertEq(Economy.unrest(s, "normandy"), math.max(0, u1 - 1), "Civil code")
	local _ = u0
	-- the view and saves
	local v = GrandCampaign.view(s)
	assertTrue(table.find(v.nations.france.techs, "rotation") ~= nil and v.nations.france.researchPoints == pts)
	assertTrue(GrandCampaign.command(s, { kind = "research", tech = "banking" }))
	Economy.run(s, "france")
	local back = GrandCampaign.deserialize(ProfileStore.clone(GrandCampaign.serialize(s)))
	assertTrue(back ~= nil and back.nations.france.techs.rotation and back.nations.france.research == "banking" and back.nations.france.progress == s.nations.france.progress)
	local old = GrandCampaign.serialize(s)
	for _, ns in old.nations do
		ns.techs, ns.research, ns.progress = nil, nil, nil
	end
	local migrated = GrandCampaign.deserialize(ProfileStore.clone(old))
	assertTrue(migrated ~= nil and migrated.nations.britain.techs.rifles, "an old save gets the 1805 knowledge")
	old.nations.france.techs = { steam = true }
	assertEq(GrandCampaign.deserialize(ProfileStore.clone(old)), nil, "an unknown tech is refused")
end)

test("Grand national rosters: each great power raises its own, nobody else's", function()
	local s = empty(10)
	s.nations.france.treasury, s.nations.prussia.treasury, s.nations.russia.treasury = 5000, 5000, 5000
	assertTrue(Economy.canRecruit(s, "prussia", "brandenburg", "landwehr"), "Landwehr at a drill ground")
	local ok, why = Economy.canRecruit(s, "france", "paris", "landwehr")
	assertTrue(not ok and why == "notInRoster")
	assertTrue(Economy.canRecruit(s, "france", "paris", "oldguard"), "the Old Guard at Paris")
	assertTrue(Economy.canRecruit(s, "russia", "stpetersburg", "cossacks"))
	local u = State.newUnit(s, "prussia", "landwehr", nil)
	assertTrue(string.find(u.name, "Landwehr") ~= nil, u.name)
	assertEq(EuropeData.UnitClasses.landwehr.sim, "militia")
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

test("Grand movement: an order beyond this turn's reach keeps its route and marches on next turn", function()
	local s = empty(5, "france")
	local a = army(s, "france", "provence", { line = 2 })
	assertTrue(GrandCampaign.command(s, { kind = "move", armyId = a.id, path = { "paris", "champagne", "rhineland" } }))
	assertEq(a.provinceId, "champagne")
	assertDeepEq(a.path, { "rhineland" }, "the rest of the route is kept")
	assertDeepEq(GrandCampaign.view(s).armies[a.id].path, { "rhineland" }, "and shown to the player")
	local back = GrandCampaign.deserialize(ProfileStore.clone(GrandCampaign.serialize(s)))
	assertTrue(back ~= nil, "a kept route survives a save")
	assertDeepEq(State.armyById(back, a.id).path, { "rhineland" })
	assertTrue(GrandCampaign.endTurn(s))
	assertEq(a.provinceId, "rhineland", "it marches on at the start of the next turn")
	assertEq(a.path, nil, "the order is done")
	assertEq(a.movesLeft, 1)
	-- a march that ends in a stop (enemy land) keeps nothing; a new order replaces an old one
	local b = army(s, "france", "provence", { line = 1 })
	assertTrue(GrandCampaign.command(s, { kind = "move", armyId = b.id, path = { "paris", "champagne", "rhineland" } }))
	assertTrue(GrandCampaign.command(s, { kind = "move", armyId = a.id, path = { "champagne" } }))
	assertEq(a.path, nil)
	b.movesLeft = 2
	assertTrue(GrandCampaign.command(s, { kind = "move", armyId = b.id, path = { "rhineland" } }))
	assertEq(b.path, nil, "a fresh order replaces the kept route")
	-- AI marches never keep routes
	local c = army(s, "austria", "vienna", { line = 1 })
	Movement.move(s, "austria", c.id, { "bohemia", "saxony", "thuringia" })
	assertEq(c.path, nil)
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
	assertEq(transfers[1], "venetia", "richest bordering allied land (Italian Lombardy)")
	assertEq(transfers[2], "tyrol", "Bohemia (richer) would be an exclave")
	assertEq(s.provinces.bohemia.owner, "austria")
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
	-- historical moments come through; off-map units keep their historical strength
	local titles = {}
	for _, m in sc.moments or {} do
		titles[m.title] = true
	end
	assertTrue(titles["The Sun of Austerlitz"], "Sun of Austerlitz kept")
	for _, u in sc.units do
		if u.name == "Life Guard Horse Regiment" then
			assertEq(u.strength, 400, "off-map unit not scaled")
			assertTrue(u.arrival ~= nil)
		end
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
			assertEq(u.type, if u.class == "infantry" then "line" elseif u.class == "cavalry" then "lightCav" else "footArt", u.name .. ": the campaign type maps onto the battle type")
			if u.faction == sc.factions.player and u.class == "infantry" then
				assertTrue(u.fireByRank == true and u.quickSquare == true, "France's drill and squares reach the battle")
			elseif u.faction == sc.factions.player and u.class == "artillery" then
				assertEq(u.canisterBonus, 1.25, "and its canister")
			elseif u.faction == sc.factions.enemy and u.class == "infantry" then
				assertTrue(u.fireByRank == false and u.quickSquare == nil, "Austria has neither in 1805")
			end
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
	local roster = 0
	for _, t in EuropeData.UnitTypeOrder do
		if EuropeData.inRoster(t, "france") then
			roster += 1
		end
	end
	local opts = v.recruitment.options.paris
	assertTrue(opts and #opts == roster, "France's whole roster, the locked ones with their reason")
	for _, o in opts do
		assertTrue(o.unitType and o.name and o.cost and o.turns and type(o.available) == "boolean")
	end
	assertEq(#v.recruitment.options.normandy, roster)
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

test("Grand AI: strategic target is the reachable enemy capital; armies stay in their theatre", function()
	local s = GrandCampaign.new(21, "france")
	Diplomacy.coalition(s, { "prussia", "russia" }, "france")
	s.flags.navalSupremacy = true
	assertEq(GrandCampaign.AI.strategicTarget(s, "france"), "brandenburg", "Berlin, next to French-held Hanover")
	-- a lone Russian army in Lithuania has no business in Holland
	table.clear(s.armies)
	Diplomacy.declareWar(s, "russia", "netherlands")
	local r = army(s, "russia", "lithuania", { line = 10 }, { name = "Bagration", rating = 3 })
	for _ = 1, 4 do
		r.movesLeft = 3
		GrandCampaign.AI.turn(s, "russia", true)
		assertTrue((Movement.hops[r.provinceId].lithuania or 99) <= 4, "wandered to " .. r.provinceId)
	end
end)

test("Grand AI: Prussia sues for peace and cedes provinces when Berlin falls (autoplay France)", function()
	local s = empty(22, "france")
	Diplomacy.declareWar(s, "prussia", "france")
	for _, id in { "brandenburg", "silesia", "westphalia" } do
		s.provinces[id].occupiedBy = "france"
	end
	Diplomacy.addScore(s, "france", "prussia", 50)
	GrandCampaign.AI.turn(s, "prussia", true)
	assertTrue(not State.atWar(s, "prussia", "france"), "peace signed")
	assertEq(s.provinces.westphalia.owner, "france", "borders French Rhineland")
	assertEq(s.provinces.silesia.owner, "prussia", "no exclaves: Silesia does not border French land")
	assertEq(s.provinces.silesia.occupiedBy, nil)
	assertEq(s.provinces.brandenburg.owner, "prussia", "the capital is returned")
	assertTrue(s.peaces[State.pair("prussia", "france")].dictated)
end)

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
	local prussiaHurt = false
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
		for k in s.wars do
			assertTrue(not s.alliances[k], "allied and at war: " .. k)
		end
		if not s.fired.peninsularWar then
			assertTrue(not State.atWar(s, "spain", "france"), "Spain fights France before Dos de Mayo")
		end
		for _, id in EuropeData.ProvinceIds do
			local c = State.controller(s, id)
			if s.provinces[id].owner == "prussia" and c ~= "prussia" then
				prussiaHurt = true
			end
		end
		if s.turn == T(1, 1807) or s.turn == T(1, 1810) then
			print("  " .. EuropeData.dateOf(s.turn) .. ":")
			print(holdings(s))
		end
	end
	print(string.format("  grand 30-turn run: %s, %.2f s, %d battles applied (last %d kept)", EuropeData.dateOf(s.turn), os.clock() - t0, #s.appliedBattles, State.APPLIED_MAX))
	local fired = {}
	for _, e in EuropeData.Events do
		if s.fired[e.id] then
			fired[#fired + 1] = e.id
		end
	end
	print("    events: " .. table.concat(fired, ", "))
	for _, l in s.log do
		if string.find(l, "peace") then
			print("    " .. l)
		end
	end
	assertTrue(s.fired.thirdCoalition and s.fired.trafalgar, "1805 happened")
	assertEq(State.controller(s, "england"), "britain", "no crossing after Trafalgar")
	assertTrue(prussiaHurt, "Prussia lost ground to France after 1806")
	assertTrue(s.turn >= 25 or s.phase == "ended")
	ProfileStore.clone(GrandCampaign.view(s))
	assertTrue(GrandCampaign.deserialize(ProfileStore.clone(GrandCampaign.serialize(s))) ~= nil)
end)

test("Grand AI: outcomes across eight seeds stay history-plausible (1805-1809)", function()
	local beatAustria, beatPrussia, parisHeld = 0, 0, 0
	local rows = {}
	for _, seed in { 1805, 1, 2, 3, 4, 5, 6, 7 } do
		local s = GrandCampaign.new(seed, "france")
		local prussianLost = 0 -- most Prussian provinces France held at once
		for _ = 1, 24 do
			if s.phase == "ended" then
				break
			end
			GrandCampaign.endTurn(s, { autoplay = true })
			local held = 0
			for _, id in EuropeData.ProvinceIds do
				if s.provinces[id].owner == "prussia" and State.controller(s, id) == "france" then
					held += 1
				end
			end
			prussianLost = math.max(prussianLost, held)
		end
		local function lost(major)
			local p = s.peaces[State.pair(major, "france")]
			return p ~= nil and p.winner == "france"
		end
		beatAustria += if lost("austria") then 1 else 0
		beatPrussia += if lost("prussia") or prussianLost >= 2 then 1 else 0
		parisHeld += if not s.flags.abdicated then 1 else 0
		local n = 0
		for _, id in EuropeData.ProvinceIds do
			n += if State.controller(s, id) == "france" then 1 else 0
		end
		local function status(major)
			if State.atWar(s, major, "france") then
				return "at war (score " .. Diplomacy.score(s, "france", major) .. ")"
			end
			local p = s.peaces[State.pair(major, "france")]
			return if p == nil then "never fought" elseif p.winner == "" then "white peace" else "peace won by " .. p.winner
		end
		rows[#rows + 1] = string.format("seed %4d: France %2d provinces in %s%s; Austria: %s; Prussia: %s, at most %d provinces lost to France", seed, n, EuropeData.dateOf(s.turn), if s.flags.abdicated then " (abdicated)" else "", status("austria"), status("prussia"), prussianLost)
	end
	print("    " .. table.concat(rows, "\n    "))
	assertTrue(beatAustria >= 5, "France beats Austria in most seeds: " .. beatAustria)
	assertTrue(beatPrussia >= 3, "Prussia is in real danger (beaten, or two provinces lost at once): " .. beatPrussia)
	assertTrue(parisHeld >= 7, "Paris rarely falls before 1809: " .. parisHeld)
end)

test("Grand QA r7: contact in Tyrol becomes a battle; the prompt lists every army and both sides' men", function()
	local s = empty(23)
	Diplomacy.declareWar(s, "france", "austria")
	local a1 = army(s, "france", "bavaria", { line = 4 }, { name = "Ney", rating = 3 })
	local a2 = army(s, "france", "bavaria", { line = 3 })
	local au = army(s, "austria", "tyrol", { line = 6 }, { name = "Archduke John", rating = 2 })
	assertTrue(State.allied(s, "france", "bavaria") == false)
	Diplomacy.makeAlliance(s, "france", "bavaria")
	assertTrue(GrandCampaign.command(s, { kind = "move", armyId = a1.id, path = { "tyrol" } }))
	assertTrue(GrandCampaign.command(s, { kind = "move", armyId = a2.id, path = { "tyrol" } }))
	-- an army may refuse battle by marching off on its own turn; that is logged
	local probe = GrandCampaign.deserialize(GrandCampaign.serialize(s))
	assertTrue(Movement.move(probe, "austria", au.id, { "vienna" }))
	assertTrue(string.find(probe.log[#probe.log], "withdraws from Tyrol", 1, true) ~= nil, probe.log[#probe.log])
	-- an army still there when every nation has moved (here: out of movement) is attacked
	au.movesLeft = 0
	assertTrue(GrandCampaign.endTurn(s))
	assertEq(s.phase, "battle")
	local v = GrandCampaign.view(s)
	local pb = v.pendingBattle
	assertEq(pb.provinceId, "tyrol")
	assertEq(#pb.armies.attacker, 2, "both French armies")
	assertEq(#pb.armies.defender, 1)
	assertEq(pb.attackerMen, State.men(a1) + State.men(a2))
	assertEq(pb.defenderMen, State.men(au))
	-- the briefing is dated by the campaign turn the battle is fought in
	local sc = GrandCampaign.battleScenario(s, pb.battleId)
	assertTrue(string.find(sc.briefing, EuropeData.dateOf(s.turn), 1, true) == 1, sc.briefing)
	assertEq(sc.date, EuropeData.dateOf(s.turn))
end)

test("Grand QA r7: every province names its own towns for its battle map", function()
	local seen = {}
	for _, p in EuropeData.Provinces do
		assertTrue(#p.towns == 3, p.id .. " towns")
		for _, t in p.towns do
			assertTrue(not seen[t] or t == "Danube", "town reused: " .. t)
			seen[t] = true
		end
		local id = Battles.mapId(p)
		assertTrue(id == "province:" .. p.id or id == p.terrain)
	end
end)
