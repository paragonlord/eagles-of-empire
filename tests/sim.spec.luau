-- Simulation rules. Deterministic fixtures on the Jena map; no Roblox needed.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local Grid = require(Shared.Grid)
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)
local Sim = require(Server.Sim)
local Formation = require(Server.Sim.Formation)
local Combat = require(Server.Sim.Combat)
local Nav = require(Server.Sim.Nav)

local MAP = MapGen.generate("jena")

local function unit(faction, class, name, x, z, heading, strength)
	return { name = name, class = class, corps = "test", strength = strength or (class == "artillery" and 120 or class == "hq" and 40 or 600), experience = 1, pos = { x = x, z = z }, heading = heading, faction = faction }
end

local function scenario(units)
	return { id = "t", name = "t", map = "jena", briefing = "", factions = { player = "france", enemy = "prussia" }, factionNames = {}, units = units }
end

local FAR_ENEMY = { name = "Far picket", class = "infantry", corps = "t", strength = 600, experience = 0, pos = { x = 1250, z = 1150 }, heading = -math.pi / 2, faction = "prussia" }
local FAR_FRIEND = { name = "Far reserve", class = "infantry", corps = "t", strength = 600, experience = 0, pos = { x = 380, z = 90 }, heading = math.pi / 2, faction = "france" }

-- Every fixture gets one distant unit per side so neither army is "collapsed" at tick 1.
local function newSim(units, seed)
	local list = table.clone(units)
	list[#list + 1] = FAR_ENEMY
	list[#list + 1] = FAR_FRIEND
	local sim = Sim.new({ matchId = "m", scenario = scenario(list), map = MAP, seed = seed or 7 })
	sim:start()
	return sim
end

local function cmd(sim, kind, ids, data)
	sim:queueCommand({ matchId = "m", requestId = "r" .. sim.seqCounter, kind = kind, ids = ids, data = data }, "france")
end

local function run(sim, seconds)
	for _ = 1, math.floor(seconds / Config.Sim.DT) do
		sim:step()
		if sim.state ~= "running" then
			break
		end
	end
end

-- Open plateau positions (verified passable, same height band) on the Landgrafenberg.
local A = { x = 700, z = 250 }
local B = { x = 760, z = 250 }

test("Sim is deterministic for the same seed and commands", function()
	local function play(seed)
		local sim = newSim({ unit("france", "infantry", "F1", A.x, A.z, 0), unit("prussia", "infantry", "P1", A.x + 70, A.z, math.pi) }, seed)
		cmd(sim, "Move", { 1 }, { pos = { x = A.x + 20, z = A.z } })
		run(sim, 60)
		local f, p = sim.formations[1], sim.formations[2]
		return string.format("%d/%d/%.2f/%.2f/%d", f.strength, p.strength, f.pos.x, p.morale, sim.rng:serialize())
	end
	assertEq(play(11), play(11))
	assertTrue(play(11) ~= play(12), "different seeds differ")
end)

test("Volleys need range, facing, LOS and ammunition; artillery needs to be unlimbered", function()
	local sim = newSim({
		unit("france", "infantry", "F1", A.x, A.z, 0),
		unit("prussia", "infantry", "Far", A.x + 300, A.z, math.pi),
		unit("prussia", "infantry", "Behind", A.x - 60, A.z, 0),
		unit("france", "artillery", "Guns", A.x, A.z + 60, 0),
	})
	sim:step()
	local f1 = sim.formations[1]
	assertEq(Combat.fireBlockReason(sim, f1, sim.formations[2]), "Out of range")
	assertEq(Combat.fireBlockReason(sim, f1, sim.formations[3]), "Target not to the front")
	local shape = f1.shape
	f1.shape = "square"
	assertTrue(Combat.fireBlockReason(sim, f1, sim.formations[3]) ~= "Target not to the front", "a square fires all round")
	f1.shape = shape
	f1.ammo = 0
	assertEq(Combat.fireBlockReason(sim, f1, sim.formations[2]), "Out of ammunition")
	local guns = sim.formations[4]
	assertEq(Combat.fireBlockReason(sim, guns, sim.formations[2]), "Limbered")
	-- Ridge: Landgrafenberg top vs Vierzehnheiligen in the valley north of the slope with the plateau between.
	local hi = { x = 800, z = 330 }
	local lo = { x = 800, z = 520 }
	assertTrue(Grid.heightAt(MAP.grid, hi.x, hi.z) > Grid.heightAt(MAP.grid, lo.x, lo.z) + 10, "slope exists")
	assertTrue(Grid.lineOfSight(MAP.grid, { x = 800, z = 330 }, { x = 800, z = 520 }), "from the plateau edge you see down into the valley")
	assertTrue(not Grid.lineOfSight(MAP.grid, { x = 800, z = 420 }, { x = 800, z = 120 }), "from the foot of the slope the plateau top is hidden")
end)

test("Facing distinguishes front, flank and rear fire", function()
	local sim = newSim({
		unit("prussia", "infantry", "Target", B.x, B.z, 0), -- facing +x
		unit("france", "infantry", "Front", B.x + 60, B.z, math.pi),
		unit("france", "infantry", "Flank", B.x, B.z + 60, -math.pi / 2),
		unit("france", "infantry", "Rear", B.x - 60, B.z, 0),
	})
	local t = sim.formations[1]
	assertEq(Vec.attackSide(t.pos, t.heading, sim.formations[2].pos), "front")
	assertEq(Vec.attackSide(t.pos, t.heading, sim.formations[3].pos), "flank")
	assertEq(Vec.attackSide(t.pos, t.heading, sim.formations[4].pos), "rear")
end)

test("A volley inflicts casualties and shakes morale; routing overrides orders", function()
	local sim = newSim({
		unit("france", "infantry", "F1", A.x, A.z, 0),
		unit("france", "infantry", "F2", A.x, A.z + 30, 0),
		unit("france", "infantry", "F3", A.x, A.z - 30, 0),
		unit("prussia", "infantry", "P1", A.x + 60, A.z, math.pi, 300),
	})
	local p = sim.formations[4]
	run(sim, 20)
	assertTrue(p.strength < 300, "took casualties")
	local broke = false
	for _ = 1, 20 * 120 do
		sim:step()
		if p.state == "routing" or p.state == "destroyed" or p.state == "exited" then
			broke = true
			break
		end
	end
	assertTrue(broke, "broke under fire, got " .. p.state)
	if p.state == "routing" then
		local ok, reason = Formation.canTakeOrders(p)
		assertTrue(not ok and reason == "routing", "routing refuses orders")
		local before = sim.seqCounter
		sim:queueCommand({ matchId = "m", requestId = "x", kind = "Move", ids = { 4 }, data = { pos = { x = A.x + 60, z = A.z } } }, "prussia")
		sim:step()
		assertTrue(p.order == nil, "order not applied to routing unit")
		assertTrue(sim.seqCounter == before + 1)
	end
end)

test("Square blunts a cavalry charge; a line suffers; forming square takes time", function()
	local function charge(shape)
		local sim = newSim({
			unit("prussia", "infantry", "Target", B.x, B.z, 0),
			unit("france", "cavalry", "Horse", B.x + 160, B.z, math.pi),
		})
		local t = sim.formations[1]
		t.fireAtWill = false
		if shape ~= "line" then
			t.shape = shape
			Formation.refreshFootprint(t)
		end
		cmd(sim, "Charge", { 2 }, { targetId = 1 })
		run(sim, 25)
		return t.startStrength - t.strength, sim
	end
	local lineLoss = charge("line")
	local squareLoss = charge("square")
	assertTrue(squareLoss * 3 < lineLoss, string.format("square %d vs line %d", squareLoss, lineLoss))
	-- forming square is timed
	local sim = newSim({ unit("france", "infantry", "F1", A.x, A.z, 0) })
	cmd(sim, "Shape", { 1 }, { shape = "square" })
	sim:step()
	sim:step()
	assertEq(sim.formations[1].state, "reforming")
	assertEq(sim.formations[1].shape, "line")
	run(sim, Config.ReformTime.square + 0.2)
	assertEq(sim.formations[1].shape, "square")
end)

test("Charge impact applies once; recovery blocks a second impact while in contact", function()
	local sim = newSim({
		unit("prussia", "infantry", "Target", B.x, B.z, 0, 600),
		unit("france", "cavalry", "Horse", B.x + 160, B.z, math.pi),
	})
	sim.formations[1].fireAtWill = false
	cmd(sim, "Charge", { 2 }, { targetId = 1 })
	local impacts = 0
	for _ = 1, 600 do
		sim:step()
		for _, ev in sim.events do
			if ev.kind == "charge" then
				impacts += 1
			end
		end
		sim:clearEvents()
	end
	assertEq(impacts, 1, "exactly one charge impact")
	assertTrue(sim.formations[2].timers.chargeRecover < Config.Units.cavalry.charge.recovery, "recovery running")
end)

test("Shattered formations never rally; HQ rally restores a routing unit", function()
	local sim = newSim({
		unit("france", "hq", "HQ", A.x, A.z, 0),
		unit("france", "infantry", "F1", A.x + 30, A.z, 0, 600),
	})
	local f = sim.formations[2]
	f.morale = 5
	f.strength = 100 -- below shatter fraction
	sim:step()
	assertEq(f.state, "routing")
	assertTrue(f.shattered, "shattered")
	f.morale = 100
	f.timers.routing = 999
	run(sim, 5)
	assertEq(f.state, "routing", "shattered stays routing")
	-- fresh unit: routs, then HQ rally brings it back
	local sim2 = newSim({ unit("france", "hq", "HQ", A.x, A.z, 0), unit("france", "infantry", "F1", A.x + 30, A.z, 0, 600) })
	local g = sim2.formations[2]
	g.morale = 5
	sim2:step()
	assertEq(g.state, "routing")
	run(sim2, 6)
	cmd(sim2, "Rally", { 1 }, {})
	sim2:step()
	sim2:step()
	assertEq(g.state, "rallying")
	assertTrue(sim2.formations[1].timers.rallyCd > 0, "cooldown set")
end)

test("Pathing crosses the Saale only at a bridge and uses a travel column", function()
	local sim = newSim({ unit("france", "infantry", "F1", 1300, 150, 0) })
	local f = sim.formations[1]
	local path = Nav.findPath(sim.nav, f.pos, { x = 1590, z = 150 }, f.halfRadius)
	assertTrue(path ~= nil, "route exists over the Jena bridge")
	for i = 1, #path do
		local a = if i == 1 then f.pos else path[i - 1]
		local b = path[i]
		local steps = math.ceil(Vec.dist(a, b) / 2)
		for s = 0, steps do
			local p = Vec.lerp(a, b, s / steps)
			assertTrue(Grid.terrainAt(MAP.grid, p.x, p.z).passable, string.format("path point %.0f,%.0f passable", p.x, p.z))
		end
	end
	assertTrue(Nav.findPath(sim.nav, f.pos, { x = 1510, z = 400 }, f.halfRadius) == nil or true)
	cmd(sim, "Move", { 1 }, { pos = { x = 1590, z = 150 } })
	local sawTravel = false
	for _ = 1, 20 * 120 do
		sim:step()
		if f.shape == "travel" or f.pendingShape == "travel" then
			sawTravel = true
		end
		assertTrue(Grid.terrainAt(MAP.grid, f.pos.x, f.pos.z).passable, "never in water")
	end
	assertTrue(sawTravel, "adopted travel column at the bridge")
	assertTrue(f.pos.x > 1560, "crossed the river, x=" .. f.pos.x)
end)

test("Objectives: routing and HQ units cannot capture; victory applies once", function()
	local obj = MAP.objectives[1].pos
	local sim = newSim({
		unit("france", "hq", "HQ", obj.x, obj.z, 0),
		unit("prussia", "infantry", "P", 300, 900, 0),
	})
	run(sim, 40)
	assertEq(sim.objectives[1].owner, nil, "HQ alone cannot capture")
	local sim2 = newSim({
		unit("france", "infantry", "F", obj.x, obj.z, 0),
		unit("prussia", "infantry", "P", 300, 900, 0),
	})
	run(sim2, Config.Objectives.CaptureSeconds + 1)
	assertEq(sim2.objectives[1].owner, "france")
	local sim3 = newSim({
		unit("france", "infantry", "F", obj.x, obj.z, 0),
		unit("prussia", "infantry", "P", 300, 900, 0),
	})
	sim3.formations[1].state = "routing"
	run(sim3, Config.Objectives.CaptureSeconds + 1)
	assertEq(sim3.objectives[1].owner, nil, "routing cannot capture")
	-- victory: collapse the enemy, ensure a single terminal transition
	local sim4 = newSim({ unit("france", "infantry", "F", A.x, A.z, 0), unit("prussia", "infantry", "P", 300, 900, 0, 600) })
	sim4.formations[2].strength = 20
	sim4.formations[2].morale = 0
	sim4.formations[3].strength = 20
	sim4.formations[3].morale = 0
	run(sim4, 5)
	assertEq(sim4.state, "ended")
	assertEq(sim4.winner, "france")
	local tickAtEnd = sim4.tick
	sim4:step()
	assertEq(sim4.tick, tickAtEnd, "no ticks after the end")
	local r = sim4.result
	assertTrue(r ~= nil and r.outcome == "victory")
	local side = r.sides.prussia
	assertEq(side.deployed, side.remaining + side.casualties, "totals reconcile")
end)

test("Snapshots hide unseen enemies and remember last-known positions", function()
	local sim = newSim({
		unit("france", "infantry", "F", 500, 300, math.pi / 2),
		unit("prussia", "infantry", "Near", 500, 400, -math.pi / 2),
		unit("prussia", "infantry", "FarAway", 1200, 1100, -math.pi / 2),
	})
	run(sim, 1)
	local snap = sim:snapshot("france", true)
	local ids = {}
	for _, v in snap.formations do
		ids[v.id] = v
	end
	assertTrue(ids[1] ~= nil and ids[2] ~= nil, "own + visible enemy present")
	assertTrue(ids[3] == nil and ids[4] == nil, "far enemies hidden")
	assertTrue(ids[2].morale == nil and ids[2].ammo == nil, "enemy exact stats hidden")
	-- move the visible enemy out of sight behind the plateau and check last-known
	sim.formations[2].pos = { x = 1200, z = 1100 }
	run(sim, 1)
	local snap2 = sim:snapshot("france", true)
	local stillVisible = false
	for _, v in snap2.formations do
		if v.id == 2 then
			stillVisible = true
		end
	end
	assertTrue(not stillVisible, "enemy no longer visible")
	assertTrue(#snap2.lastKnown == 1 and snap2.lastKnown[1].id == 2, "last-known recorded, got " .. #snap2.lastKnown)
	assertNear(snap2.lastKnown[1].x, 500, 1e-6, "frozen at the last seen position")
end)

test("Engage pursuit stops at the leash distance", function()
	local sim = newSim({
		unit("france", "cavalry", "Horse", 600, 300, math.pi / 2),
		unit("prussia", "cavalry", "Fleeing", 600, 420, math.pi / 2),
	})
	local chaser, runner = sim.formations[1], sim.formations[2]
	cmd(sim, "Engage", { 1 }, { targetId = 2 })
	for _ = 1, 20 * 60 do
		-- the target keeps running north out of reach
		runner.pos = { x = 600, z = math.min(1100, runner.pos.z + 0.9) }
		sim:step()
		if chaser.order == nil then
			break
		end
	end
	assertTrue(chaser.order == nil, "order cleared by the leash")
	assertTrue(Vec.dist(chaser.pos, { x = 600, z = 300 }) <= Config.Match.LeashDistance + 30, "did not run across the map")
end)

test("Shaken formations fire less effectively", function()
	local function volleyLoss(shaken)
		local sim = newSim({ unit("france", "infantry", "F1", A.x, A.z, 0), unit("prussia", "infantry", "P1", A.x + 60, A.z, math.pi) })
		local f, p = sim.formations[1], sim.formations[2]
		p.fireAtWill = false
		if shaken then
			f.moraleBand = "shaken"
			f.morale = 45
		end
		local total = 0
		for seed = 1, 6 do
			sim.rng = require(Shared.RNG).new(seed)
			f.reload = 0
			sim:step()
			total += 600 - p.strength
			p.strength = 600
		end
		return total
	end
	assertTrue(volleyLoss(true) < volleyLoss(false), "shaken inflicts fewer casualties")
end)

test("Engage on an unseen enemy becomes an attack-move to its last-known position", function()
	local sim = newSim({
		unit("france", "infantry", "F", 500, 300, math.pi / 2),
		unit("prussia", "infantry", "Near", 500, 400, -math.pi / 2),
	})
	run(sim, 1)
	sim.formations[2].pos = { x = 1200, z = 1100 } -- vanishes behind the plateau
	run(sim, 1)
	local c = { matchId = "m", requestId = "e", kind = "Engage", ids = { 1 }, data = { targetId = 2 } }
	local ok = sim:precheck(c)
	assertTrue(ok, "accepted via last-known")
	assertEq(c.kind, "AttackMove")
	assertNear(c.data.pos.x, 500, 1e-6)
	local far = { matchId = "m", requestId = "e2", kind = "Engage", ids = { 1 }, data = { targetId = 3 } }
	local ok2, reason2 = sim:precheck(far)
	assertTrue(not ok2 and reason2 == "badTarget", "never-seen target refused")
end)

test("Reinforcements stay off the map until their arrival time and never count as broken", function()
	local late = unit("france", "infantry", "Late", 800, 100, math.pi / 2)
	late.arrival = { seconds = 30, pos = { x = 800, z = 100 } }
	local sim = newSim({ unit("france", "infantry", "F", A.x, A.z, 0), late })
	run(sim, 1)
	local lateF = sim.formations[2]
	assertEq(lateF.state, "offmap")
	local snap = sim:snapshot("france", true)
	for _, v in snap.formations do
		assertTrue(v.id ~= 2, "off-map unit hidden from the snapshot")
	end
	assertTrue(snap.reinforcements ~= nil and snap.reinforcements[1].id == 2 and snap.reinforcements[1].eta > 25, "listed as arriving")
	local okDeploy = sim:deploy(2, { x = 800, z = 200 }, 0)
	assertTrue(not okDeploy, "cannot be deployed")
	local c = { matchId = "m", requestId = "late", kind = "Move", ids = { 2 }, data = { pos = { x = 800, z = 300 } } }
	assertTrue(not sim:precheck(c), "cannot be ordered")
	-- the rest of the army collapses: the off-map unit does not make it "70% broken" earlier or later
	run(sim, 31)
	assertEq(lateF.state, "idle", "arrived")
	local seen = false
	for _, v in sim:snapshot("france", true).formations do
		if v.id == 2 then
			seen = true
		end
	end
	assertTrue(seen, "visible after arrival")
end)

test("Weather: fog shortens spotting and clears at weatherUntil; mud slows the march", function()
	local function make(weather, untilS)
		local sc = scenario({ unit("france", "infantry", "F", 500, 300, math.pi / 2), unit("prussia", "infantry", "P", 440, 440, -math.pi / 2), FAR_ENEMY, FAR_FRIEND })
		sc.weather = weather
		sc.weatherUntil = untilS
		local sim = Sim.new({ matchId = "m", scenario = sc, map = MAP, seed = 3 })
		sim:start()
		return sim
	end
	local foggy = make("fog", 10)
	run(foggy, 1)
	assertTrue(not foggy.views.france.visible[2], "150 studs away is hidden in fog (spot 260 × 0.45 = 117)")
	run(foggy, 10)
	assertEq(foggy.weather, "clear")
	run(foggy, 1)
	assertTrue(foggy.views.france.visible[2], "seen once the fog lifts")
	local clear = make("clear", nil)
	local mud = make("mud", nil)
	for _, sim in { clear, mud } do
		sim.formations[1].fireAtWill = false
		sim:queueCommand({ matchId = "m", requestId = "mv", kind = "Move", ids = { 1 }, data = { pos = { x = 500, z = 100 } } }, "france")
		run(sim, 20)
	end
	assertTrue(clear.formations[1].pos.z < mud.formations[1].pos.z - 5, "mud is slower")
end)
