-- Shared foundation: Vec, RNG, Grid, MapGen, Protocol.
local Shared = game:GetService("ReplicatedStorage").EoE
local Vec = require(Shared.Vec)
local RNG = require(Shared.RNG)
local Grid = require(Shared.Grid)
local MapGen = require(Shared.MapGen)
local Protocol = require(Shared.Protocol)
local Config = require(Shared.Config)
local Scenarios = require(Shared.Scenarios)

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
