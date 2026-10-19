-- Shared foundation: Vec, RNG, Grid, MapGen, Protocol.
local Shared = game:GetService("ReplicatedStorage").EoE
local Vec = require(Shared.Vec)
local RNG = require(Shared.RNG)
local Grid = require(Shared.Grid)
local MapGen = require(Shared.MapGen)
local Protocol = require(Shared.Protocol)
local Config = require(Shared.Config)
local Scenarios = require(Shared.Scenarios)
local Nav = require(game:GetService("ServerScriptService").EoE.Sim.Nav)

test("Vec.attackSide classifies front/flank/rear from geometry", function()
	local pos = Vec.new(0, 0)
	local heading = 0 -- facing +x
	assertEq(Vec.attackSide(pos, heading, Vec.new(10, 0)), "front")
	assertEq(Vec.attackSide(pos, heading, Vec.new(0, 10)), "flank")
	assertEq(Vec.attackSide(pos, heading, Vec.new(0, -10)), "flank")
	assertEq(Vec.attackSide(pos, heading, Vec.new(-10, 0)), "rear")
	assertEq(Vec.attackSide(pos, math.pi / 2, Vec.new(0, 10)), "front")
end)

test("Vec.angleDiff wraps", function()
	assertNear(Vec.angleDiff(0, math.pi * 1.5), -math.pi / 2, 1e-9)
	assertNear(Vec.angleDiff(math.pi * 0.9, -math.pi * 0.9), math.pi * 0.2, 1e-9)
end)

test("RNG is deterministic and serializable", function()
	local a = RNG.new(42)
	local b = RNG.new(42)
	for _ = 1, 100 do
		assertEq(a:nextU32(), b:nextU32())
	end
	local state = a:serialize()
	local c = RNG.fromState(state)
	assertEq(c:float(), a:float())
	local x = RNG.hash(12, 34, 56)
	assertEq(RNG.hash(12, 34, 56), x)
	assertTrue(x >= 0 and x < 1)
	assertTrue(RNG.hash(12, 34, 57) ~= x)
end)

test("Grid height interpolation and LOS over a ridge", function()
	local g = Grid.new(50, 10, 4)
	for cz = 0, 9 do
		for cx = 0, 49 do
			g.height[Grid.index(g, cx, cz)] = (cx >= 20 and cx <= 24) and 30 or 0
		end
	end
	Grid.computeClearance(g)
	assertNear(Grid.heightAt(g, 10, 10), 0, 1e-6)
	assertNear(Grid.heightAt(g, 90, 10), 30, 1e-6)
	assertTrue(not Grid.lineOfSight(g, Vec.new(10, 20), Vec.new(190, 20)), "ridge blocks")
	assertTrue(Grid.lineOfSight(g, Vec.new(10, 20), Vec.new(60, 20)), "same side sees")
	assertTrue(Grid.lineOfSight(g, Vec.new(90, 20), Vec.new(10, 20)), "from the top sees down")
end)

test("Grid clearance measures distance from water", function()
	local g = Grid.new(40, 40, 4)
	for cz = 0, 39 do
		for cx = 18, 21 do
			g.class[Grid.index(g, cx, cz)] = Config.TerrainIds.water
		end
	end
	Grid.computeClearance(g)
	assertEq(Grid.clearanceAt(g, 19 * 4 + 2, 80), 0)
	assertEq(Grid.clearanceAt(g, 17 * 4 + 2, 80), 4)
	assertEq(Grid.clearanceAt(g, 10 * 4 + 2, 80), 8 * 4)
	assertTrue(not Grid.fits(g, 17 * 4 + 2, 80, 8), "line does not fit beside water")
	assertTrue(Grid.fits(g, 10 * 4 + 2, 80, 8), "line fits in the open")
end)

test("MapGen jena is deterministic and well formed", function()
	local t0 = os.clock()
	local a = MapGen.generate("jena")
	local genMs = (os.clock() - t0) * 1000
	local b = MapGen.generate("jena")
	assertEq(#a.grid.height, a.grid.cols * a.grid.rows)
	for i = 1, #a.grid.height, 997 do
		assertEq(a.grid.height[i], b.grid.height[i], "height " .. i)
		assertEq(a.grid.class[i], b.grid.class[i], "class " .. i)
	end
	local counts = {}
	for _, c in a.grid.class do
		counts[c] = (counts[c] or 0) + 1
	end
	local ids = Config.TerrainIds
	assertTrue((counts[ids.water] or 0) > 2000, "has a river")
	assertTrue((counts[ids.woods] or 0) > 2000, "has woods")
	assertTrue((counts[ids.village] or 0) > 500, "has villages")
	assertTrue((counts[ids.road] or 0) > 1000, "has roads")
	assertTrue((counts[ids.bridge] or 0) > 20, "has bridges")
	-- Bridges are passable and connect banks.
	for _, br in a.bridges do
		local mid = Vec.lerp(br.a, br.b, 0.5)
		assertEq(Grid.classAt(a.grid, mid.x, mid.z), ids.bridge, "bridge mid is bridge class")
	end
	-- Landgrafenberg is higher than Vierzehnheiligen.
	assertTrue(Grid.heightAt(a.grid, 800, 230) > Grid.heightAt(a.grid, 760, 760) + 15, "plateau rises")
	-- Deployment zones are mostly passable.
	local zone = a.deployZones.france
	local passable, total = 0, 0
	for x = zone.x0, zone.x1, 20 do
		for z = zone.z0, zone.z1, 20 do
			total += 1
			if Grid.terrainAt(a.grid, x, z).passable then
				passable += 1
			end
		end
	end
	assertTrue(passable / total > 0.9, "french zone passable")
	assertTrue(#a.villages[1].buildings >= 20, "Jena has houses")
	assertTrue(#a.woods[1].trees > 100, "Isserstedt wood has trees")
	print(string.format("   (jena generated in %.0f ms, %d trees, %d buildings)", genMs, #a.woods[1].trees, #a.villages[1].buildings))
end)

test("Scenario units start inside their deployment zones on passable ground", function()
	local map = MapGen.generate("jena")
	for _, s in { Scenarios.jena, Scenarios.skirmish } do
		for _, unit in s.units do
			assertTrue(MapGen.inZone(map, unit.faction, unit.pos), s.id .. ": " .. unit.name .. " in zone")
			assertTrue(Grid.terrainAt(map.grid, unit.pos.x, unit.pos.z).passable, unit.name .. " on passable ground")
		end
	end
end)

-- The four battles: map well-formedness, deployment, bridges, objectives and reachability.
local BATTLES = { "jena", "auerstedt", "austerlitz", "waterloo" }

test("Scenarios.list is the four battles in display order with display fields", function()
	local list = {}
	for _, e in Scenarios.list() do
		if e.mode == "full" then
			list[#list + 1] = e
		end
	end
	assertEq(#list, 4)
	for i, id in BATTLES do
		assertEq(list[i].id, id)
		local s = Scenarios.get(id)
		assertTrue(s ~= nil, id .. " exists")
		assert(s)
		assertEq(list[i].map, s.map)
		assertTrue(type(list[i].date) == "string" and type(list[i].summary) == "string" and type(list[i].difficultyNote) == "string", id .. " display fields")
		assertTrue(type(s.briefing) == "string" and #s.briefing > 100, id .. " briefing")
		assertTrue(type(s.year) == "number", id .. " year")
		assertTrue(s.weather == nil or Config.Weather[s.weather] ~= nil, id .. " weather key")
		assertTrue(s.factions.player == "france", id .. " player is France")
		assertTrue(Config.Visual.Palette[string.upper(string.sub(s.factions.enemy, 1, 1)) .. string.sub(s.factions.enemy, 2)] ~= nil, id .. " enemy faction has a palette colour")
	end
	assertTrue(Scenarios.get("stress") ~= nil and Scenarios.get("skirmish") ~= nil, "fixtures still reachable")
end)

for _, id in BATTLES do
	test("Battle " .. id .. ": map is deterministic, bridges wide, objectives and deployment sound", function()
		local scenario = Scenarios.get(id)
		assert(scenario)
		local t0 = os.clock()
		local map = MapGen.generate(scenario.map)
		local genMs = (os.clock() - t0) * 1000
		local again = MapGen.generate(scenario.map)
		local g = map.grid
		assertEq(map.width % 16, 0, "width multiple of 16")
		assertEq(map.depth % 16, 0, "depth multiple of 16")
		assertEq(#g.height, g.cols * g.rows)
		for i = 1, #g.height, 991 do
			assertEq(g.height[i], again.grid.height[i], "height " .. i)
			assertEq(g.class[i], again.grid.class[i], "class " .. i)
		end
		local ids = Config.TerrainIds
		for _, br in map.bridges do
			local mid = Vec.lerp(br.a, br.b, 0.5)
			assertEq(Grid.classAt(g, mid.x, mid.z), ids.bridge, id .. " bridge midpoint is bridge class")
			assertTrue(br.width >= 24, id .. " bridge >= 24 wide")
			assertTrue(Grid.clearanceAt(g, mid.x, mid.z) >= 8, id .. " bridge fits a travel column")
		end
		for _, o in map.objectives do
			assertTrue(Grid.terrainAt(g, o.pos.x, o.pos.z).passable, id .. " objective " .. o.id .. " passable")
		end
		-- Units: inside their zone, on passable ground, clearance >= 8 (Sim.deploy's own rule).
		local seen = {}
		for _, unit in scenario.units do
			assertTrue(not seen[unit.name], id .. " duplicate unit name " .. unit.name)
			seen[unit.name] = true
			assertTrue(unit.colour == nil or Config.Visual.Palette[unit.colour] ~= nil, id .. " palette key " .. tostring(unit.colour))
			local p = if unit.arrival then unit.arrival.pos else unit.pos
			if not unit.arrival then
				assertTrue(MapGen.inZone(map, unit.faction, p), id .. ": " .. unit.name .. " in zone")
			end
			assertTrue(Grid.inBounds(g, p.x, p.z), id .. ": " .. unit.name .. " on the map")
			assertTrue(Grid.terrainAt(g, p.x, p.z).passable, id .. ": " .. unit.name .. " on passable ground")
			assertTrue(Grid.clearanceAt(g, p.x, p.z) >= 8, id .. ": " .. unit.name .. " has clearance")
		end
		-- Reachability: from the player's zone centre to every objective, as a column.
		local nav = Nav.build(g)
		local zone = map.deployZones[scenario.factions.player]
		local from = { x = (zone.x0 + zone.x1) / 2, z = (zone.z0 + zone.z1) / 2 }
		for _, o in map.objectives do
			local path = Nav.findPath(nav, from, o.pos, 8)
			assertTrue(path ~= nil and #path > 0, id .. ": path to " .. o.id)
			assert(path)
			assertTrue(Vec.dist(path[#path], o.pos) < Config.Map.NavCellSize * 2, id .. ": path reaches " .. o.id)
		end
		print(string.format("   (%s %dx%d generated in %.0f ms, %d units, %d bridges)", scenario.map, map.width, map.depth, genMs, #scenario.units, #map.bridges))
	end)
end

test("Protocol.validateCommand rejects bad input and accepts good", function()
	local owned = { [1] = "infantry", [2] = "cavalry", [3] = "artillery", [4] = "hq" }
	local ctx = {
		matchId = "m1",
		state = "running",
		mapWidth = 1600,
		mapDepth = 1200,
		isOwned = function(id)
			return owned[id] ~= nil
		end,
		classOf = function(id)
			return owned[id]
		end,
		legalShapes = function(id)
			return Config.Units[owned[id]].legalShapes
		end,
	}
	local function cmd(kind, ids, data)
		return { matchId = "m1", requestId = "r1", kind = kind, ids = ids, data = data }
	end
	assertTrue(Protocol.validateCommand(cmd("Move", { 1, 2 }, { pos = { x = 100, z = 100 } }), ctx))
	assertEq(select(2, Protocol.validateCommand(cmd("Move", { 1 }, { pos = { x = 0 / 0, z = 1 } }), ctx)), Protocol.Reasons.badPosition)
	assertEq(select(2, Protocol.validateCommand(cmd("Move", { 1 }, { pos = { x = 5000, z = 1 } }), ctx)), Protocol.Reasons.badPosition)
	assertEq(select(2, Protocol.validateCommand(cmd("Move", { 99 }, { pos = { x = 1, z = 1 } }), ctx)), Protocol.Reasons.notOwned)
	assertTrue(Protocol.validateCommand(cmd("Move", { 1 }, { pos = { x = 100, z = 100 }, run = true }), ctx))
	assertEq(select(2, Protocol.validateCommand(cmd("Move", { 1 }, { pos = { x = 100, z = 100 }, run = "yes" }), ctx)), Protocol.Reasons.badRequest)
	assertTrue(Protocol.validateCommand(cmd("Run", { 1 }, { run = false }), ctx))
	assertEq(select(2, Protocol.validateCommand(cmd("Run", { 1 }, {}), ctx)), Protocol.Reasons.badRequest)
	assertEq(select(2, Protocol.validateCommand(cmd("Move", {}, { pos = { x = 1, z = 1 } }), ctx)), Protocol.Reasons.badIds)
	assertEq(select(2, Protocol.validateCommand(cmd("Teleport", { 1 }, {}), ctx)), Protocol.Reasons.badKind)
	assertEq(select(2, Protocol.validateCommand(cmd("Shape", { 3 }, { shape = "line" }), ctx)), Protocol.Reasons.wrongClass)
	assertEq(select(2, Protocol.validateCommand(cmd("Shape", { 2 }, { shape = "square" }), ctx)), Protocol.Reasons.badShape)
	assertTrue(Protocol.validateCommand(cmd("Shape", { 1 }, { shape = "square" }), ctx))
	assertEq(select(2, Protocol.validateCommand(cmd("Engage", { 1 }, { targetId = 2 }), ctx)), Protocol.Reasons.badTarget)
	assertTrue(Protocol.validateCommand(cmd("Engage", { 1 }, { targetId = 50 }), ctx))
	assertEq(select(2, Protocol.validateCommand(cmd("Rally", { 1 }, {}), ctx)), Protocol.Reasons.wrongClass)
	assertTrue(Protocol.validateCommand(cmd("Rally", { 4 }, {}), ctx))
	local big = {}
	for i = 1, Config.Net.MaxBatch + 1 do
		big[i] = 1
	end
	assertEq(select(2, Protocol.validateCommand(cmd("Stop", big, {}), ctx)), Protocol.Reasons.badIds)
	local other = { matchId = "m2", requestId = "r1", kind = "Stop", ids = { 1 } }
	assertEq(select(2, Protocol.validateCommand(other, ctx)), Protocol.Reasons.wrongMatch)
	ctx.state = "deployment"
	assertEq(select(2, Protocol.validateCommand(cmd("Move", { 1 }, { pos = { x = 1, z = 1 } }), ctx)), Protocol.Reasons.badState)
	assertTrue(Protocol.validateCommand(cmd("Deploy", { 1 }, { pos = { x = 1, z = 1 }, heading = 0 }), ctx))
end)

test("Unit types: every unit of every battle has a type of its own class, inferred from its name", function()
	local Config = require(Shared.Config)
	local ids = { "tutorial", "skirmish", "stress" }
	for _, e in Scenarios.list() do
		table.insert(ids, e.id)
	end
	local seen = {}
	for _, id in ids do
		for _, u in Scenarios.get(id).units do
			local t = Scenarios.typeOf(u)
			assertTrue(Config.UnitTypes[t] ~= nil, id .. ": " .. u.name .. " has no type")
			assertEq(Config.UnitTypes[t].class, u.class, id .. ": " .. u.name .. " is a " .. t)
			seen[t] = true
		end
	end
	local function typeOf(class, name)
		return Scenarios.typeOf({ class = class, name = name } :: any)
	end
	local cases = {
		{ "infantry", "17e Légère", "light" }, { "infantry", "1er Tirailleurs", "light" },
		{ "infantry", "Füsilier-Bataillon Pelet", "light" }, { "infantry", "Grenz-Infanterie Nr. 1", "light" },
		{ "infantry", "1/95th Rifles", "rifle" }, { "infantry", "5th Jägers", "rifle" },
		{ "infantry", "Grenadier-Bataillon Hahn", "grenadier" }, { "infantry", "Kiev Grenadiers", "grenadier" },
		{ "infantry", "Grenadiers à pied de la Garde", "guard" }, { "infantry", "2/2nd Coldstream Guards", "guard" },
		{ "infantry", "Preobrazhensky Guards", "guard" }, { "infantry", "IR Nr. 15 Garde", "guard" },
		{ "infantry", "Schlesisches Landwehr-Regiment", "militia" }, { "infantry", "Conscrits de 1809", "militia" },
		{ "infantry", "34e de Ligne", "line" }, { "infantry", "92nd Gordon Highlanders", "line" },
		{ "cavalry", "1er Cuirassiers", "heavyCav" }, { "cavalry", "Kürassier-Regiment Henckel", "heavyCav" },
		{ "cavalry", "1st Life Guards", "heavyCav" }, { "cavalry", "Grenadiers à cheval de la Garde", "heavyCav" },
		{ "cavalry", "1er Carabiniers", "heavyCav" }, { "cavalry", "Garde du Corps Nr. 13", "heavyCav" },
		{ "cavalry", "5e Hussards", "lightCav" }, { "cavalry", "9e Chasseurs à cheval", "lightCav" },
		{ "cavalry", "6e Lanciers", "lancer" }, { "cavalry", "Uhlans Grand Duke Constantine", "lancer" },
		{ "cavalry", "12th Light Dragoons", "lightCav" }, { "cavalry", "Chevaulegers Nr. 3", "lightCav" },
		{ "cavalry", "15e Dragons", "dragoon" }, { "cavalry", "Scots Greys", "dragoon" },
		{ "artillery", "Mercer's Troop RHA", "horseArt" }, { "artillery", "Reitende Batterie Blücher", "horseArt" },
		{ "artillery", "Batterie à cheval Bijleveld", "horseArt" }, { "artillery", "Batterie Grawert", "footArt" },
		{ "artillery", "Obusiers du 2e Corps", "howitzer" },
		{ "hq", "Napoléon — Imperial HQ", "hq" },
	}
	for _, c in cases do
		assertEq(typeOf(c[1], c[2]), c[3], c[2])
	end
	assertEq(Scenarios.typeOf({ class = "infantry", name = "34e de Ligne", type = "rifle" } :: any), "rifle", "an explicit type wins")
	assertEq(Scenarios.typeOf({ class = "cavalry", name = "34e de Ligne", type = "rifle" } :: any), "dragoon", "a type of another class is ignored")
	for _, t in { "line", "light", "rifle", "grenadier", "guard", "militia", "lightCav", "lancer", "dragoon", "heavyCav", "footArt", "horseArt", "howitzer", "hq" } do
		assertTrue(seen[t], "the battles use " .. t)
	end
end)

test("Unit types: stats merge over the class and differ where they should", function()
	local Config = require(Shared.Config)
	local S = Config.TypeStats
	local function same(a, b): boolean
		if type(a) ~= "table" or type(b) ~= "table" then
			return a == b
		end
		for k, v in a do
			if not same(v, b[k]) then
				return false
			end
		end
		for k in b do
			if a[k] == nil then
				return false
			end
		end
		return true
	end
	local function assertDeepEq(a, b, msg)
		assertTrue(same(a, b), msg)
	end
	for id, t in Config.UnitTypes do
		assertTrue(S[id] ~= nil and S[id].baseMorale ~= nil, id)
		for shape in Config.Units[t.class].legalShapes do
			assertTrue(S[id].legalShapes[shape], id .. " keeps its class's " .. shape)
		end
		assertEq(S[id].legalShapes.skirmish == true, id == "light" or id == "rifle", id .. ": only light troops skirmish")
	end
	assertDeepEq(S.line, Config.Units.infantry, "line is the plain class")
	assertTrue(S.rifle.musket.range > S.line.musket.range and S.rifle.musket.accuracy > S.line.musket.accuracy)
	assertEq(S.rifle.musket.minReadiness, S.line.musket.minReadiness, "untouched keys keep the class value")
	assertTrue(S.guard.baseMorale > S.grenadier.baseMorale and S.grenadier.baseMorale > S.line.baseMorale)
	assertTrue(S.militia.baseMorale < S.line.baseMorale)
	assertTrue(S.light.speed > S.line.speed)
	assertTrue(S.lightCav.speed > S.dragoon.speed and S.dragoon.speed > S.heavyCav.speed)
	assertTrue(S.heavyCav.charge.base > S.dragoon.charge.base and S.dragoon.charge.base > S.lightCav.charge.base)
	assertTrue(S.horseArt.speed > S.footArt.speed and S.horseArt.reformScale < 1)
	assertTrue(Config.Units.infantry.musket.range == 90, "merging never writes into the class table")
end)

test("Province maps: every province of the grand campaign has its own field, deterministic and passable", function()
	local EuropeData = require(Shared.EuropeData)
	assertTrue(MapGen.provinceMaps == true)
	local t0 = os.clock()
	for i, p in EuropeData.Provinces do
		local m = MapGen.generate("province:" .. p.id)
		assertEq(m.name, p.name)
		assertEq(#m.objectives, 3)
		if p.towns and p.towns[1] then
			assertEq(m.villages[1].name, p.towns[1], p.id .. ": its own town at the centre")
			assertEq(m.objectives[1].name, p.towns[1])
		end
		assertTrue(m.deployZones.france and m.deployZones.prussia)
		for _, o in m.objectives do
			assertTrue(Grid.terrainAt(m.grid, o.pos.x, o.pos.z).passable, p.id .. ": " .. o.name .. " stands on passable ground")
		end
		-- a sample of the provinces (every archetype) gets the full reachability check
		if i % 4 == 1 then
			local nav = Nav.build(m.grid)
			for _, key in { "france", "prussia" } do
				local z = m.deployZones[key]
				local from = Nav.nearestWalkable(nav, { x = (z.x0 + z.x1) / 2, z = (z.z0 + z.z1) / 2 }, 10)
				assertTrue(from ~= nil, p.id .. ": the " .. key .. " zone has open ground")
				for _, o in m.objectives do
					assertTrue(Nav.findPath(nav, from :: any, o.pos, 8) ~= nil, p.id .. ": " .. key .. " can reach " .. o.name)
				end
			end
		end
	end
	local a, b = MapGen.generate("province:vienna"), MapGen.generate("province:vienna")
	assertEq(a.grid.height[5000], b.grid.height[5000], "the same field every time")
	print(string.format("   (%d province maps in %.1f s)", #EuropeData.Provinces, os.clock() - t0))
end)

test("Either side: a listed battle can be fought from the other army, briefed from its side", function()
	local base = Scenarios.waterloo
	assertEq(Scenarios.forSide(base, "historical"), base)
	local other = Scenarios.forSide(base, "other")
	assertEq(other.factions.player, "britain")
	assertEq(other.factions.enemy, "france")
	assertEq(other.attacker, "france", "roles stay with the armies")
	assertTrue(other.units == base.units and other.map == base.map, "the same field and order of battle")
	assertTrue(string.find(other.briefing, "You command Anglo-allied", 1, true) ~= nil, other.briefing)
	assertTrue(string.find(other.briefing, "hold", 1, true) ~= nil, "the defender is told to hold")
	assertEq(other.difficultyNote, nil, "the note was written for the French side")
	assertEq(base.factions.player, "france", "the listed scenario is untouched")
	local jena = Scenarios.forSide(Scenarios.jena, "other")
	assertTrue(string.find(jena.briefing, "You command Prussia", 1, true) ~= nil)
	-- the control that picks it
	assertTrue(Protocol.validateControl({ requestId = "r", action = "command", value = "other" }, { matchId = "" }))
	local ok = Protocol.validateControl({ requestId = "r", action = "command", value = "both" }, { matchId = "" })
	assertTrue(not ok)
end)

test("Results in history: every listed battle names its historical winner, and the verdict reads it", function()
	for _, e in Scenarios.list() do
		local sc = Scenarios.get(e.id) :: any
		assertTrue(sc.historicalWinner ~= nil and sc.factionNames[sc.historicalWinner] ~= nil, e.id .. " has a historical winner")
	end
	assertEq(Scenarios.waterloo.historicalWinner, "britain")
	assertEq(Scenarios.historyVerdict(Scenarios.jena, "france"), "As in history, France carried the day.")
	assertEq(Scenarios.historyVerdict(Scenarios.jena, "prussia"), "History went otherwise: France carried the day.")
	assertEq(Scenarios.historyVerdict(Scenarios.jena, nil), "A draw; in history France carried the day.")
	assertEq(Scenarios.historyVerdict(Scenarios.forSide(Scenarios.waterloo, "other"), "britain"), "As in history, Anglo-allied carried the day.")
	assertEq(Scenarios.historyVerdict({ id = "custom", factionNames = {} } :: any, "france"), nil, "a custom battle has no history")
end)

test("Loading tips: a score of short, distinct lines", function()
	local Tips = require(Shared.Tips)
	assertTrue(#Tips >= 15)
	local seen = {}
	for _, tip in Tips do
		assertTrue(#tip <= 140, "short: " .. tip)
		assertTrue(not seen[tip], "distinct: " .. tip)
		seen[tip] = true
	end
end)
