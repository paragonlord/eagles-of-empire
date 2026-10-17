-- Tutorial: map and scenario are sound, and the server step handler is commander-only,
-- tutorial-only and monotonic.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local Grid = require(Shared.Grid)
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)
local Nav = require(Server.Sim.Nav)
local Sim = require(Server.Sim)
local MatchService = require(Server.MatchService)

local MAP = MapGen.generate("tutorial")

test("Tutorial scenario is unlisted, units start in zone on passable ground", function()
	local s = Scenarios.get("tutorial")
	assert(s)
	for _, e in Scenarios.list() do
		assertTrue(e.id ~= "tutorial", "tutorial is not in the battle list")
	end
	assertEq(MAP.width, 1024)
	assertEq(MAP.depth, 800)
	local g = MAP.grid
	local seen = {}
	for _, unit in s.units do
		assertTrue(not seen[unit.name], "duplicate " .. unit.name)
		seen[unit.name] = true
		assertTrue(MapGen.inZone(MAP, unit.faction, unit.pos), unit.name .. " in zone")
		assertTrue(Grid.terrainAt(g, unit.pos.x, unit.pos.z).passable, unit.name .. " passable")
		assertTrue(Grid.clearanceAt(g, unit.pos.x, unit.pos.z) >= 8, unit.name .. " clearance")
	end
	-- names the server script relies on
	for _, name in { "Grenz-Infanterie Nr. 1", "Chevaulegers Nr. 3", "Conscrits de 1809" } do
		assertTrue(seen[name], "scripted unit " .. name)
	end
	assertTrue(Config.Visual.Palette.Austria ~= nil, "austria palette")
end)

test("Tutorial map: bridge crosses the stream, ridge stands, village reachable over the bridge", function()
	local g = MAP.grid
	local ids = Config.TerrainIds
	local br = MAP.bridges[1]
	local mid = Vec.lerp(br.a, br.b, 0.5)
	assertEq(Grid.classAt(g, mid.x, mid.z), ids.bridge, "bridge midpoint")
	assertTrue(Grid.clearanceAt(g, mid.x, mid.z) >= 8, "bridge fits a column")
	assertEq(Grid.classAt(g, 300, 548), ids.water, "stream is water")
	assertTrue(Grid.heightAt(g, 420, 330) > Grid.heightAt(g, 420, 200) + 6, "ridge rises")
	-- the fire lesson: the ridge hides the Grenzer outpost until the crest is reached
	local grenz = { x = 420, z = 430 }
	assertTrue(not Grid.lineOfSight(g, { x = 420, z = 250 }, grenz), "ridge blocks the view")
	assertTrue(Grid.lineOfSight(g, { x = 420, z = 330 }, grenz), "crest sees the outpost")
	assertTrue(Grid.lineOfSight(g, { x = 480, z = 330 }, { x = 800, z = 430 }), "guns on the ridge see the flank battalion")
	-- the stream is a barrier everywhere but the bridge
	local nav = Nav.build(g)
	local zone = MAP.deployZones.france
	local from = { x = (zone.x0 + zone.x1) / 2, z = (zone.z0 + zone.z1) / 2 }
	for _, o in MAP.objectives do
		assertTrue(Grid.terrainAt(g, o.pos.x, o.pos.z).passable, o.id .. " passable")
		local path = Nav.findPath(nav, from, o.pos, 8)
		assert(path and #path > 0, "path to " .. o.id)
		assertTrue(Vec.dist(path[#path], o.pos) < Config.Map.NavCellSize * 2, "path reaches " .. o.id)
		local crossed = false
		for _, p in path do
			if Vec.dist(p, mid) < 48 then
				crossed = true
			end
		end
		assertTrue(crossed, "path uses the bridge")
	end
end)

local function newMatch()
	local s = Scenarios.get("tutorial")
	assert(s)
	local sim = Sim.new({ matchId = "t", scenario = s, map = MAP, seed = 5 })
	local m: any = { scenario = s, sim = sim, ai = nil }
	MatchService._internal.tutorialStart(m)
	sim:start()
	return m
end

test("Tutorial step handler: commander only, tutorial only, monotonic, finish needs the village", function()
	local step = MatchService._internal.tutorialStep
	local m = newMatch()
	local sim = m.sim
	assertEq(rawget(sim, "aiStep"), nil, "no AI in the tutorial")
	for _ = 1, 10 do
		sim:step()
	end
	for _, f in sim.formations do
		if f.faction == "austria" then
			assertEq(f.fireAtWill, false, f.name .. " starts passive")
		end
	end
	assertTrue(not step(m, false, 1), "spectator rejected")
	assertTrue(step(m, true, 1), "step 1")
	assertTrue(not step(m, true, 1), "repeat rejected")
	assertTrue(step(m, true, 3), "skipping forward allowed")
	assertTrue(not step(m, true, 2), "backwards rejected")
	assertTrue(not step(m, true, 2.5), "fraction rejected")
	assertTrue(not step(m, true, "6"), "string rejected")
	assertTrue(not step(m, true, 99), "beyond the end rejected")
	assertEq(m.tutorialStep, 3)
	-- step 6 releases the skirmishers only
	local before = #sim.commands
	assertTrue(step(m, true, 6))
	assertTrue(#sim.commands > before, "enemy commands queued")
	for _, c in sim.commands do
		assertEq(c.faction, "austria", "commands are for the enemy")
	end
	for _ = 1, 10 do
		sim:step()
	end
	for _, f in sim.formations do
		if f.faction == "austria" and f.class ~= "hq" then
			assertEq(f.fireAtWill, f.name == "Grenz-Infanterie Nr. 1", f.name .. " stance after step 6")
		end
	end
	-- finishing before the village is held is refused
	assertTrue(not step(m, true, 12), "finish needs the village")
	sim.objectives[1].owner = "france"
	assertTrue(step(m, true, 12), "finish")
	assertEq(sim.state, "ended")
	assertEq(sim.winner, "france")
	assertTrue(not step(m, true, 12), "nothing after the end")
	-- another scenario never accepts tutorial steps
	local other: any = { scenario = Scenarios.skirmish, sim = Sim.new({ matchId = "o", scenario = Scenarios.skirmish, map = MapGen.generate("jena"), seed = 1 }) }
	other.sim:start()
	assertTrue(not step(other, true, 1), "not the tutorial")
end)

test("Tutorial step 10 breaks the conscripts, who can be rallied", function()
	local step = MatchService._internal.tutorialStep
	local m = newMatch()
	assertTrue(step(m, true, 10))
	for _ = 1, 4 do
		m.sim:step()
	end
	local routed = false
	for _, f in m.sim.formations do
		if f.name == "Conscrits de 1809" then
			routed = f.state == "routing"
		end
	end
	assertTrue(routed, "conscripts rout")
end)

test("Tutorial upkeep: cavalry attack renewed, bloodied Grenzers and crowded Kerpen withdraw", function()
	local step, tick = MatchService._internal.tutorialStep, MatchService._internal.tutorialTick
	local m = newMatch()
	local sim = m.sim
	local function named(name)
		for _, f in sim.formations do
			if f.name == name then
				return f
			end
		end
		error("no " .. name)
	end
	local function ordersFor(id, kind)
		local n = 0
		for _, c in sim.commands do
			if c.kind == kind and table.find(c.ids, id) then
				n += 1
			end
		end
		return n
	end
	for _, p in { { x = 430, z = 650 }, { x = 900, z = 760 } } do
		assertTrue(Grid.terrainAt(MAP.grid, p.x, p.z).passable, "fallback point passable")
	end
	-- lesson 6: the Grenzers fall back once below three quarters strength
	assertTrue(step(m, true, 6))
	local grenz = named("Grenz-Infanterie Nr. 1")
	tick(m)
	assertEq(ordersFor(grenz.id, "Retreat"), 0, "unhurt Grenzers stand")
	grenz.strength = math.floor(grenz.startStrength * 0.7)
	tick(m)
	tick(m)
	assertEq(ordersFor(grenz.id, "Retreat"), 1, "bloodied Grenzers withdraw once")
	-- lesson 9: the cavalry is sent at once and again every 10 s
	local cav = named("Chevaulegers Nr. 3")
	assertTrue(step(m, true, 9))
	tick(m)
	assertEq(ordersFor(cav.id, "AttackMove"), 1, "cavalry sent")
	tick(m)
	assertEq(ordersFor(cav.id, "AttackMove"), 1, "not every frame")
	for _ = 1, 10 / Config.Sim.DT + 2 do
		sim:step()
	end
	tick(m)
	assertTrue(ordersFor(cav.id, "AttackMove") >= 1 and m.tutorialCavAt > sim.clock, "attack renewed after 10 s")
	-- lesson 11: Kerpen leaves the village when two French battalions are within 80
	m.ai = require(Server.AI).new(sim, "austria", "normal")
	assertTrue(step(m, true, 11))
	local kerpen = named("IR 49 Kerpen")
	local n = 0
	for _, f in sim.formations do
		if f.faction == "france" and f.class == "infantry" and f.name ~= "Conscrits de 1809" then
			n += 1
			f.pos = { x = kerpen.pos.x + (if n == 1 then 50 else 300), z = kerpen.pos.z - 30 }
		end
	end
	tick(m)
	assertEq(ordersFor(kerpen.id, "Retreat"), 0, "one battalion is not enough")
	for _, f in sim.formations do
		if f.faction == "france" and f.class == "infantry" and f.name ~= "Conscrits de 1809" then
			f.pos = { x = kerpen.pos.x - 40, z = kerpen.pos.z - 40 }
		end
	end
	tick(m)
	assertEq(ordersFor(kerpen.id, "Retreat"), 1, "Kerpen abandons Ebersdorf")
	-- and the released AI never orders it back, during the march or after it arrives
	for _ = 1, 4000 do
		sim:step()
		local o = kerpen.order
		assertTrue(o == nil or o.kind == "Retreat", "Kerpen order " .. tostring(o and o.kind))
	end
end)

test("Tutorial lesson 11 plays through: the brigade takes Ebersdorf and step 12 ends it", function()
	local AI = require(Server.AI)
	local step, tick = MatchService._internal.tutorialStep, MatchService._internal.tutorialTick
	local m = newMatch()
	local sim = m.sim
	m.ai = AI.new(sim, "austria", "normal")
	assertTrue(step(m, true, 11), "skip to the village lesson (AI released)")
	assertTrue(rawget(sim, "aiStep") ~= nil, "AI on")
	local village = MAP.objectives[1].pos
	local function attack()
		local ids = {}
		for _, f in sim.formations do
			if f.faction == "france" and (f.class == "infantry" or f.class == "cavalry") and f.name ~= "Conscrits de 1809" and f.state ~= "routing" then
				ids[#ids + 1] = f.id
			end
		end
		table.sort(ids)
		if #ids > 0 then
			sim:queueCommand({ matchId = sim.matchId, requestId = "test", kind = "Move", ids = ids, data = { pos = village } }, "france")
		end
	end
	local owned = false
	for t = 1, 20 * 60 / Config.Sim.DT do
		if t % 400 == 1 then
			attack() -- right-click the village every 20 s, as a player would (a Move)
		end
		tick(m)
		sim:step()
		if sim.objectives[1].owner == "france" then
			owned = true
			break
		end
		if sim.state ~= "running" then
			break
		end
	end
	print(string.format("   (Ebersdorf taken after %.0f s of lesson 11)", sim.clock))
	assertTrue(owned, "France owns Ebersdorf")
	assertTrue(step(m, true, 12), "step 12 accepted")
	assertEq(sim.state, "ended")
	assertEq(sim.winner, "france")
end)
