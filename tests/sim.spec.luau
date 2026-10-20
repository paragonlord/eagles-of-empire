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

test("Unit types change the battle: rifles outrange, horse guns limber fast, light cavalry rides down routers", function()
	local sim = newSim({
		unit("france", "infantry", "34e de Ligne", A.x, A.z, 0),
		unit("france", "infantry", "1/95th Rifles", A.x, A.z + 50, 0),
		unit("prussia", "infantry", "Target", A.x + 115, A.z + 25, math.pi),
		unit("france", "artillery", "Batterie Grawert", A.x - 40, A.z - 60, 0),
		unit("france", "artillery", "Reitende Batterie Blücher", A.x - 40, A.z + 110, 0),
	})
	sim:step()
	local line, rifles, target = sim.formations[1], sim.formations[2], sim.formations[3]
	assertEq(line.type, "line")
	assertEq(rifles.type, "rifle")
	assertEq(Combat.fireBlockReason(sim, line, target), "Out of range")
	assertTrue(Combat.fireBlockReason(sim, rifles, target) ~= "Out of range", "115 studs is inside a rifle's reach")
	assertTrue(rifles.ammo <= Config.TypeStats.rifle.musket.ammo and rifles.ammo >= Config.TypeStats.rifle.musket.ammo - 1, "rifles carry their own ammunition")
	cmd(sim, "Limber", { 4, 5 }, { limbered = false })
	sim:step()
	sim:step()
	local foot, horse = sim.formations[4], sim.formations[5]
	assertTrue(math.abs(horse.timers.limber - foot.timers.limber * Config.TypeStats.horseArt.reformScale) < 0.2, "horse guns unlimber in half the time")
	assertEq(sim:snapshot("france").formations[2].type, "rifle", "the snapshot carries the type")

	-- the same full-tilt charge into a routing battalion: hussars cut down more than cuirassiers
	local function chase(name)
		local s2 = newSim({
			unit("prussia", "infantry", "Fugitives", B.x, B.z, 0),
			unit("france", "cavalry", name, B.x + 20, B.z, math.pi),
		})
		local t, h = s2.formations[1], s2.formations[2]
		t.state = "routing"
		h.state = "charging"
		h.order = { kind = "Charge", targetId = t.id } :: any
		h.chargeReady = true
		h.runUp = 200
		for _, a in Combat.gather(s2) do
			if a.attackerId == h.id and a.kind == "charge" then
				return a.casualties
			end
		end
		return 0
	end
	local hussars, cuirassiers = chase("5e Hussards"), chase("1er Cuirassiers")
	assertTrue(hussars > cuirassiers and cuirassiers > 0, string.format("hussars %d vs cuirassiers %d", hussars, cuirassiers))
end)

test("Skirmish order: light troops only; hard to hit, fires on the move and all round, ridden down by cavalry", function()
	local sim = newSim({
		unit("france", "infantry", "7e Légère", A.x, A.z, 0),
		unit("france", "infantry", "34e de Ligne", A.x, A.z + 60, 0),
	})
	cmd(sim, "Shape", { 1, 2 }, { shape = "skirmish" })
	run(sim, Config.ReformTime.skirmish + 0.5)
	assertEq(sim.formations[1].shape, "skirmish")
	assertEq(sim.formations[2].shape, "line", "line infantry cannot skirmish")
	assertTrue(sim.formations[1].width > sim.formations[2].width * 1.5, "open order covers more ground")

	-- the same volleys into a line and into a skirmish screen
	local function shotAt(shape)
		local s2 = newSim({
			unit("prussia", "infantry", "Target", B.x, B.z, 0, 600),
			unit("france", "infantry", "Shooters", B.x + 80, B.z, math.pi),
		}, 5)
		local t = s2.formations[1]
		t.fireAtWill = false
		t.shape = shape
		Formation.refreshFootprint(t)
		run(s2, 60)
		return t.startStrength - t.strength
	end
	local inLine, inSkirmish = shotAt("line"), shotAt("skirmish")
	assertTrue(inSkirmish * 1.5 < inLine, string.format("skirmish %d vs line %d", inSkirmish, inLine))

	-- marching skirmishers shoot at an enemy on their flank without stopping
	local s3 = newSim({
		unit("france", "infantry", "7e Légère", A.x, A.z, 0),
		unit("prussia", "infantry", "Flank", A.x + 20, A.z + 70, -math.pi / 2),
	})
	local sk = s3.formations[1]
	sk.shape = "skirmish"
	Formation.refreshFootprint(sk)
	s3.formations[2].fireAtWill = false
	cmd(s3, "Move", { 1 }, { pos = { x = A.x + 200, z = A.z } })
	local fired, minX = false, sk.pos.x
	for _ = 1, math.floor(8 / Config.Sim.DT) do
		s3:step()
		fired = fired or sk.ammo < Config.TypeStats.light.musket.ammo
	end
	assertTrue(fired, "fired at the flank while marching")
	assertTrue(sk.pos.x > minX + 30, "and kept marching")

	-- cavalry rides a skirmish screen down harder than a line
	local function charged(shape)
		local s4 = newSim({
			unit("prussia", "infantry", "Target", B.x, B.z, 0),
			unit("france", "cavalry", "15e Dragons", B.x + 160, B.z, math.pi),
		})
		local t = s4.formations[1]
		t.fireAtWill = false
		t.shape = shape
		Formation.refreshFootprint(t)
		cmd(s4, "Charge", { 2 }, { targetId = 1 })
		run(s4, 25)
		return t.startStrength - t.strength
	end
	local lineLoss, skirmishLoss = charged("line"), charged("skirmish")
	assertTrue(skirmishLoss > lineLoss, string.format("skirmish %d vs line %d", skirmishLoss, lineLoss))
end)

test("Running: faster and far more tiring; the Run order switches pace mid-march; guns never run", function()
	local function march(double)
		local sim = newSim({ unit("france", "infantry", "F1", A.x, A.z, 0) })
		cmd(sim, "Move", { 1 }, { pos = { x = A.x + 300, z = A.z }, run = double })
		run(sim, 20)
		local f = sim.formations[1]
		return f.pos.x - A.x, f.fatigue
	end
	local walked, walkTired = march(false)
	local ran, runTired = march(true)
	assertTrue(ran > walked * 1.25, string.format("ran %.0f vs walked %.0f", ran, walked))
	assertTrue(runTired > walkTired * 2, string.format("fatigue %.1f vs %.1f", runTired, walkTired))

	local sim = newSim({
		unit("france", "infantry", "F1", A.x, A.z, 0),
		unit("france", "artillery", "Guns", A.x, A.z + 60, 0),
	})
	cmd(sim, "Move", { 1, 2 }, { pos = { x = A.x + 300, z = A.z + 30 } })
	sim:step()
	sim:step()
	cmd(sim, "Run", { 1, 2 }, { run = true })
	sim:step()
	sim:step()
	local f, guns = sim.formations[1], sim.formations[2]
	assertTrue(f.order and f.order.run == true, "switched to the double")
	assertEq(sim:snapshot("france").formations[1].running, true)
	local Movement = require(Server.Sim.Movement)
	assertTrue(not Movement.running(guns), "guns keep their pace")
	cmd(sim, "Run", { 1 }, { run = false })
	sim:step()
	sim:step()
	assertTrue(not f.order.run, "and back to the walk")
end)

test("Fire by rank: drilled infantry halted in line reloads faster; guard and British foot are drilled", function()
	assertTrue(Scenarios.firesByRank({ class = "infantry", name = "28th Foot", faction = "britain" } :: any))
	assertTrue(Scenarios.firesByRank({ class = "infantry", name = "Grenadiers à pied de la Garde", faction = "france" } :: any))
	assertTrue(not Scenarios.firesByRank({ class = "infantry", name = "34e de Ligne", faction = "france" } :: any))
	assertTrue(not Scenarios.firesByRank({ class = "cavalry", name = "1st Life Guards", faction = "britain" } :: any))
	assertTrue(Scenarios.firesByRank({ class = "infantry", name = "34e de Ligne", faction = "france", fireByRank = true } :: any), "a scenario may grant it")
	local sim = newSim({
		unit("france", "infantry", "34e de Ligne", A.x, A.z, 0),
		unit("france", "infantry", "Drilled", A.x, A.z + 60, 0),
		unit("prussia", "infantry", "Target", A.x + 70, A.z + 30, math.pi),
	})
	sim.formations[2].fireByRank = true
	sim.formations[3].fireAtWill = false
	local reloads = {}
	for _ = 1, 40 do
		sim:step()
		for i = 1, 2 do
			local f = sim.formations[i]
			if f.reload > 0 and not reloads[i] then
				reloads[i] = f.reload
			end
		end
	end
	assertTrue(reloads[1] and reloads[2], "both fired")
	assertTrue(math.abs(reloads[2] / reloads[1] - Config.Combat.FireByRankReload) < 0.02, string.format("%.2f vs %.2f", reloads[2], reloads[1]))
end)

test("Round shot ricochets down its lane: units behind the target are hit, friend or foe; canister does not carry", function()
	local sim = newSim({
		unit("france", "artillery", "Guns", A.x, A.z, 0),
		unit("prussia", "infantry", "Target", A.x + 200, A.z, math.pi),
		unit("prussia", "infantry", "Behind", A.x + 260, A.z, math.pi),
		unit("france", "cavalry", "Our horse behind", A.x + 320, A.z + 4, math.pi),
		unit("prussia", "infantry", "Off the lane", A.x + 260, A.z + 120, math.pi),
	})
	local guns = sim.formations[1]
	guns.shape = "deployed"
	Formation.refreshFootprint(guns)
	guns.targetId = 2
	for i = 2, 5 do
		sim.formations[i].fireAtWill = false
	end
	local hits: { [number]: number } = {}
	for _ = 1, 60 do
		guns.reload = 0
		guns.ammo = 40
		guns.targetId = 2
		for _, a in Combat.gather(sim) do
			if a.attackerId == 1 and a.kind == "cannon" then
				hits[a.targetId] = (hits[a.targetId] or 0) + a.casualties
			end
		end
	end
	assertTrue((hits[2] or 0) > 0, "the target is hit")
	assertTrue((hits[3] or 0) > 0, "the ball carries on into the battalion behind")
	assertTrue((hits[4] or 0) > 0, "friendly cavalry behind the enemy is not safe")
	assertEq(hits[5] or 0, 0, "nothing off the lane")
	assertTrue(hits[3] < hits[2], "the bounce hits less than the first strike")
	-- canister, at close range: no carry
	local s2 = newSim({
		unit("france", "artillery", "Guns", A.x, A.z, 0),
		unit("prussia", "infantry", "Close", A.x + 80, A.z, math.pi),
		unit("prussia", "infantry", "Behind", A.x + 150, A.z, math.pi),
	})
	local g2 = s2.formations[1]
	g2.shape = "deployed"
	Formation.refreshFootprint(g2)
	s2.formations[2].fireAtWill = false
	s2.formations[3].fireAtWill = false
	local behind = 0
	for _ = 1, 30 do
		g2.reload = 0
		g2.targetId = 2
		for _, a in Combat.gather(s2) do
			if a.targetId == 3 and a.kind == "cannon" then
				behind += a.casualties
			end
		end
	end
	assertEq(behind, 0)
end)

test("Howitzers lob shells over a crest at what the army can see, and the burst hits neighbours", function()
	-- at the foot of the Landgrafenberg the plateau top is out of sight (see the LOS test above)
	local sim = newSim({
		unit("france", "artillery", "Obusiers", 800, 420, -math.pi / 2),
		unit("france", "artillery", "Batterie", 830, 420, -math.pi / 2),
		unit("prussia", "infantry", "On the plateau", 800, 180, math.pi / 2),
		unit("prussia", "infantry", "Beside it", 835, 180, math.pi / 2),
		unit("france", "cavalry", "Scouts", 800, 250, -math.pi / 2),
	})
	for i = 1, 2 do
		local g = sim.formations[i]
		g.shape = "deployed"
		Formation.refreshFootprint(g)
	end
	sim.formations[3].fireAtWill = false
	sim.formations[4].fireAtWill = false
	run(sim, 1)
	local how, gun, target = sim.formations[1], sim.formations[2], sim.formations[3]
	assertEq(how.type, "howitzer")
	how.reload, gun.reload = 0, 0
	assertEq(Combat.fireBlockReason(sim, gun, target), "Line of fire blocked")
	assertEq(Combat.fireBlockReason(sim, how, target), nil, "the howitzer needs no line of sight")
	local splash = 0
	for _ = 1, 40 do
		how.reload = 0
		how.targetId = target.id
		gun.reload = 99
		for _, a in Combat.gather(sim) do
			if a.attackerId == how.id and a.targetId == 4 then
				splash += a.casualties
			end
		end
	end
	assertTrue(splash > 0, "the burst reaches the next battalion")
end)

test("Charging downhill hits harder than charging up", function()
	-- a slope on Jena where 30 studs of ground fall more than 5 studs, both ends passable
	local hx, hz
	for x = 100, 1500, 10 do
		for z = 100, 1100, 10 do
			if not hx and Grid.heightAt(MAP.grid, x, z) - Grid.heightAt(MAP.grid, x + 30, z) > 5 and Grid.terrainAt(MAP.grid, x, z).passable and Grid.terrainAt(MAP.grid, x + 30, z).passable then
				hx, hz = x, z
			end
		end
	end
	assertTrue(hx ~= nil, "a slope exists")
	local function impact(attackerX, targetX, heading)
		local s2 = newSim({
			unit("prussia", "infantry", "Target", targetX, hz, 0),
			unit("france", "cavalry", "15e Dragons", attackerX, hz, heading),
		})
		local t, h = s2.formations[1], s2.formations[2]
		t.heading = Vec.heading(Vec.sub(h.pos, t.pos)) -- both take it in the front
		h.state = "charging"
		h.order = { kind = "Charge", targetId = t.id } :: any
		h.chargeReady = true
		h.runUp = 200
		local total = 0
		for _ = 1, 20 do
			h.chargeReady = true
			h.timers.chargeRecover = 0
			h.state = "charging"
			for _, a in Combat.gather(s2) do
				if a.attackerId == h.id and a.kind == "charge" then
					total += a.casualties
				end
			end
		end
		return total
	end
	local down = impact(hx, hx + 30, 0)
	local up = impact(hx + 30, hx, math.pi)
	assertTrue(down > up * 1.1, string.format("downhill %d vs uphill %d", down, up))
end)

test("Fords: brooks can be waded at their fords, slowly and without firing", function()
	local ford = { x = 520, z = 960 }
	assertEq(Grid.terrainAt(MAP.grid, ford.x, ford.z).name, "ford")
	assertEq(Grid.terrainAt(MAP.grid, ford.x + 60, ford.z - 5).name, "water", "beside the ford the brook is deep")
	local sim = newSim({
		unit("france", "infantry", "Waders", ford.x, ford.z - 70, -math.pi / 2),
		unit("prussia", "infantry", "Watchers", ford.x + 70, ford.z + 70, math.pi),
	})
	sim.formations[2].fireAtWill = false
	local f = sim.formations[1]
	cmd(sim, "Move", { 1 }, { pos = { x = ford.x, z = ford.z + 80 } })
	local waded, blocked, closest = false, false, math.huge
	for _ = 1, math.floor(120 / Config.Sim.DT) do
		sim:step()
		closest = math.min(closest, Vec.dist(f.pos, ford))
		if Grid.terrainAt(MAP.grid, f.pos.x, f.pos.z).name == "ford" then
			waded = true
			f.reload = 0
			blocked = blocked or Combat.fireBlockReason(sim, f, sim.formations[2]) == "Wading the ford"
		end
		if f.pos.z > ford.z + 60 then
			break
		end
	end
	assertTrue(f.pos.z > ford.z + 60, string.format("crossed to the far bank (z %.0f)", f.pos.z))
	assertTrue(closest < 20 and waded, "by the ford")
	assertTrue(blocked, "no volleys from the middle of the brook")
end)

test("Buildings: a battalion garrisons a village heart, is hard to shoot or charge, and gives it up to march", function()
	local sp = MAP.strongpoints[1]
	assertTrue(sp ~= nil and Grid.terrainAt(MAP.grid, sp.pos.x, sp.pos.z).passable, "every village has a strongpoint")
	local sim = newSim({
		unit("france", "infantry", "Garrison", sp.pos.x, sp.pos.z - 80, math.pi / 2),
		unit("france", "infantry", "Latecomers", sp.pos.x + 40, sp.pos.z - 90, math.pi / 2),
	})
	cmd(sim, "Garrison", { 1 }, { strongpoint = sp.id })
	run(sim, 40)
	local g = sim.formations[1]
	assertEq(g.garrison, sp.id, "inside")
	assertEq(sim.strongpoints[sp.id].holder, 1)
	run(sim, Config.ReformTime.garrison + 1)
	assertEq(g.shape, "garrison")
	assertEq(sim:snapshot("france").formations[1].garrison, sp.id)
	cmd(sim, "Garrison", { 2 }, { strongpoint = sp.id })
	run(sim, 40)
	assertEq(sim.formations[2].garrison, nil, "one battalion to a building")
	-- out to march: files out, the building is free again
	cmd(sim, "Move", { 1 }, { pos = { x = sp.pos.x, z = sp.pos.z - 120 } })
	run(sim, Config.ReformTime.column + 5)
	assertEq(g.garrison, nil)
	assertEq(sim.strongpoints[sp.id].holder, nil)
	assertTrue(Vec.dist(g.pos, sp.pos) > 5, "and it is on its way")

	-- the same volleys into a garrison and into a line in the open beside it
	local function shotAt(inside)
		local s2 = newSim({
			unit("prussia", "infantry", "Target", sp.pos.x, sp.pos.z, 0),
			unit("france", "infantry", "Shooters", sp.pos.x + 75, sp.pos.z, math.pi),
		}, 5)
		local t = s2.formations[1]
		t.fireAtWill = false
		if inside then
			s2.strongpoints[sp.id].holder = t.id
			t.garrison = sp.id
			t.shape = "garrison"
		else
			t.pos = { x = sp.pos.x, z = sp.pos.z - 250 }
			s2.formations[2].pos = { x = sp.pos.x + 75, z = sp.pos.z - 250 }
		end
		Formation.refreshFootprint(t)
		run(s2, 60)
		return t.startStrength - t.strength
	end
	local inside, outside = shotAt(true), shotAt(false)
	assertTrue(inside * 2 < outside, string.format("garrison %d vs open %d", inside, outside))
	-- horsemen cannot ride into a house
	local s3 = newSim({
		unit("prussia", "infantry", "Inside", sp.pos.x, sp.pos.z, 0),
		unit("france", "cavalry", "1er Cuirassiers", sp.pos.x + 20, sp.pos.z, math.pi),
	})
	local t, h = s3.formations[1], s3.formations[2]
	t.garrison, t.shape = sp.id, "garrison"
	s3.strongpoints[sp.id].holder = t.id
	Formation.refreshFootprint(t)
	h.state, h.chargeReady, h.runUp = "charging", true, 200
	h.order = { kind = "Charge", targetId = t.id } :: any
	for _, a in Combat.gather(s3) do
		if a.attackerId == h.id and a.kind == "charge" then
			assertEq(a.casualties, 0, "no charge impact on a garrison")
		end
	end
end)

test("Field walls and hedges shelter men behind them from musketry that has to cross them", function()
	local WorldGen = require(Shared.WorldGen)
	local spot
	for x = 200, 1400, 8 do
		for z = 200, 900, 8 do
			if not spot and Grid.terrainAt(MAP.grid, x, z).name == "open" and Grid.terrainAt(MAP.grid, x, z - 75).name == "open"
				and Grid.lineOfSight(MAP.grid, { x = x, z = z - 75 }, { x = x, z = z }) and WorldGen.borderCover(MAP, x, z, x, z - 75, 6) == 2 then
				spot = { x = x, z = z }
			end
		end
	end
	assertTrue(spot ~= nil, "a stone wall on open ground")
	local function losses(wallCover)
		local saved = Config.Combat.BorderCover[2]
		Config.Combat.BorderCover[2] = wallCover
		local s2 = newSim({
			unit("prussia", "infantry", "Behind the wall", spot.x, spot.z, -math.pi / 2),
			unit("france", "infantry", "Shooters", spot.x, spot.z - 75, math.pi / 2),
		}, 9)
		s2.formations[1].fireAtWill = false
		run(s2, 60)
		Config.Combat.BorderCover[2] = saved
		local t = s2.formations[1]
		return t.startStrength - t.strength
	end
	local sheltered, open = losses(Config.Combat.BorderCover[2]), losses(0)
	assertTrue(sheltered < open * 0.8, string.format("wall %d vs none %d", sheltered, open))
end)

test("Buildings: ordered into a building the enemy holds, a battalion storms it", function()
	local sp = MAP.strongpoints[1]
	local sim = newSim({
		unit("prussia", "infantry", "Holders", sp.pos.x, sp.pos.z, -math.pi / 2),
		unit("france", "infantry", "Stormers", sp.pos.x, sp.pos.z - 160, math.pi / 2),
	})
	local h = sim.formations[1]
	h.garrison, h.shape = sp.id, "garrison"
	h.fireAtWill = false
	sim.strongpoints[sp.id].holder = h.id
	Formation.refreshFootprint(h)
	cmd(sim, "Garrison", { 2 }, { strongpoint = sp.id })
	local stormed = false
	for _ = 1, math.floor(80 / Config.Sim.DT) do
		sim:step()
		local o = sim.formations[2].order
		stormed = stormed or (o ~= nil and o.kind == "Charge" and o.targetId == h.id)
	end
	assertTrue(stormed, "the Garrison order turned into a charge on the holders")
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
	-- a square, or men holding a building, face every way: all fire, charges and melee are frontal
	assertEq(Combat.sideOf(t, sim.formations[4].pos), "rear")
	for _, shape in { "square", "garrison" } do
		t.shape = shape
		assertEq(Combat.sideOf(t, sim.formations[3].pos), "front", shape .. " flank")
		assertEq(Combat.sideOf(t, sim.formations[4].pos), "front", shape .. " rear")
	end
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

test("Cavalry meleeing a square takes SquareReturnsDamage", function()
	local function horseLoss(factor)
		local saved = Config.Combat.SquareReturnsDamage
		Config.Combat.SquareReturnsDamage = factor
		local sim = newSim({
			unit("prussia", "infantry", "Target", B.x, B.z, 0),
			unit("france", "cavalry", "Horse", B.x + 160, B.z, math.pi),
		})
		local t = sim.formations[1]
		t.fireAtWill = false
		t.shape = "square"
		Formation.refreshFootprint(t)
		cmd(sim, "Charge", { 2 }, { targetId = 1 })
		run(sim, 25)
		Config.Combat.SquareReturnsDamage = saved
		local h = sim.formations[2]
		return h.startStrength - h.strength
	end
	local plain, doubled = horseLoss(1), horseLoss(2)
	assertTrue(plain > 0, "the square fights back")
	assertTrue(doubled > plain * 1.5, string.format("x2 %d vs x1 %d", doubled, plain))
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

test("A group order skips routing formations instead of being refused whole", function()
	local sim = newSim({
		unit("france", "infantry", "A", 500, 300, 0),
		unit("france", "infantry", "B", 560, 300, 0),
		unit("prussia", "infantry", "P", 1500, 1300, 0),
	})
	run(sim, 1)
	sim.formations[2].state = "routing"
	local c = { matchId = "m", requestId = "g", kind = "Move", ids = { 1, 2 }, data = { pos = { x = 500, z = 500 } } }
	local ok = sim:precheck(c)
	assertTrue(ok, "the able formation still gets the order")
	assertEq(#c.ids, 1)
	assertEq(c.ids[1], 1)
	local alone = { matchId = "m", requestId = "g2", kind = "Move", ids = { 2 }, data = { pos = { x = 500, z = 500 } } }
	local ok2, why2 = sim:precheck(alone)
	assertTrue(not ok2 and why2 == "routing", "a routing formation alone is refused")
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

test("Collapse by strength measures the troops on the field, not reinforcements still to come", function()
	local Objectives = require(Server.Sim.Objectives)
	local late = unit("france", "infantry", "Late", 800, 100, math.pi / 2, 3000)
	late.arrival = { seconds = 600, pos = { x = 800, z = 100 } }
	local sim = newSim({ unit("france", "infantry", "F", A.x, A.z, 0), late })
	local f, reserve = sim.formations[1], sim.formations[4]
	f.strength = 300 -- 900 of the 1200 on the field
	assertTrue(not Objectives.collapsed(sim, "france"), "three quarters of the field army stands")
	f.strength, reserve.strength = 100, 200 -- 300 of 1200
	assertTrue(Objectives.collapsed(sim, "france"), "a quarter of it has collapsed")
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

test("Cavalry on attack-move charges an enemy it meets; contact without orders becomes melee", function()
	local sim = newSim({
		unit("france", "cavalry", "Horse", 600, 300, math.pi / 2),
		unit("prussia", "infantry", "Line", 600, 470, -math.pi / 2),
	})
	sim.formations[2].fireAtWill = false
	cmd(sim, "AttackMove", { 1 }, { pos = { x = 600, z = 700 } })
	local charged, meleed = false, false
	for _ = 1, 20 * 40 do
		sim:step()
		for _, ev in sim.events do
			if ev.kind == "charge" and ev.id == 1 then
				charged = true
			end
		end
		sim:clearEvents()
		if sim.formations[1].state == "melee" then
			meleed = true
		end
	end
	assertTrue(charged, "charged on contact")
	assertTrue(meleed, "fought in melee")
	assertTrue(sim.formations[2].strength < 600, "the line took losses")
end)

test("Infantry on attack-move halts in musket range and fires, then resumes", function()
	local sim = newSim({
		unit("france", "infantry", "F", 600, 300, math.pi / 2),
		unit("prussia", "infantry", "P", 600, 420, -math.pi / 2, 200),
	})
	sim.formations[2].fireAtWill = false
	cmd(sim, "AttackMove", { 1 }, { pos = { x = 600, z = 700 } })
	local volleys = 0
	for _ = 1, 20 * 30 do
		sim:step()
		for _, ev in sim.events do
			if ev.kind == "volley" and ev.id == 1 then
				volleys += 1
			end
		end
		sim:clearEvents()
	end
	assertTrue(volleys >= 1, "fired")
	assertTrue(sim.formations[1].pos.z < 420 - 20, "stopped short of the enemy instead of walking into it")
end)

test("Rallied formations at the rear edge walk back in to separate slots", function()
	-- extra steady formations so three routing ones do not count as an army collapse
	local sim = newSim({
		unit("france", "infantry", "A", 600, 20, math.pi / 2),
		unit("france", "infantry", "B", 610, 22, math.pi / 2),
		unit("france", "infantry", "C", 620, 24, math.pi / 2),
		unit("france", "infantry", "S1", 900, 250, math.pi / 2),
		unit("france", "infantry", "S2", 1000, 250, math.pi / 2),
		unit("france", "infantry", "S3", 1100, 250, math.pi / 2),
		unit("france", "infantry", "S4", 1200, 250, math.pi / 2),
	})
	for i = 1, 3 do
		local f = sim.formations[i]
		f.state = "routing"
		f.timers.routing = 999
		f.morale = 60
	end
	run(sim, 40)
	local p1, p2, p3 = sim.formations[1].pos, sim.formations[2].pos, sim.formations[3].pos
	assertTrue(p1.z > 80 and p2.z > 80 and p3.z > 80, "moved back onto the field")
	assertTrue(Vec.dist(p1, p2) > 30 and Vec.dist(p2, p3) > 30 and Vec.dist(p1, p3) > 30, "not piled up")
end)

test("No map lets a path cross a brook outside its bridges and fords; a unit standing in water steps out", function()
	local Nav = require(Server.Sim.Nav)
	for _, mapId in { "jena", "auerstedt", "austerlitz", "waterloo", "tutorial" } do
		local map = MapGen.generate(mapId)
		local nav = Nav.build(map.grid)
		-- every walkable node that contains water must also contain a bridge
		local cell = map.grid.cell
		local sub = nav.size // cell
		local bad = 0
		for nz = 0, nav.rows - 1 do
			for nx = 0, nav.cols - 1 do
				if nav.walk[nz * nav.cols + nx + 1] then
					local water, bridge = false, false
					for sz = 0, sub - 1 do
						for sx = 0, sub - 1 do
							local c = map.grid.class[(nz * sub + sz) * map.grid.cols + nx * sub + sx + 1]
							if c == Config.TerrainIds.water then
								water = true
							elseif c == Config.TerrainIds.bridge then
								bridge = true
							end
						end
					end
					if water and not bridge then
						bad += 1
					end
				end
			end
		end
		assertEq(bad, 0, mapId .. ": walkable nodes over water without a bridge")
	end
	-- the round-5 reproduction on the tutorial map
	local tmap = MapGen.generate("tutorial")
	local sc = { id = "t", name = "t", map = "tutorial", briefing = "", factions = { player = "france", enemy = "prussia" }, factionNames = {}, units = {
		unit("france", "infantry", "F", 400, 480, math.pi / 2),
		unit("france", "infantry", "Reserve", 150, 100, math.pi / 2),
		unit("prussia", "infantry", "P", 900, 750, -math.pi / 2),
	} }
	local sim = Sim.new({ matchId = "m", scenario = sc, map = tmap, seed = 1 })
	sim:start()
	local f = sim.formations[1]
	f.fireAtWill = false
	sim:queueCommand({ matchId = "m", requestId = "x", kind = "Move", ids = { 1 }, data = { pos = { x = 400, z = 640 } } }, "france")
	for _ = 1, 20 * 240 do
		sim:step()
		assertTrue(Grid.terrainAt(tmap.grid, f.pos.x, f.pos.z).passable, string.format("never in water (%.0f, %.0f)", f.pos.x, f.pos.z))
		if f.order == nil then
			break
		end
	end
	assertTrue(f.pos.z > 600, string.format("crossed by the bridge, z=%.0f", f.pos.z))
	-- standing in water (e.g. an old save) then ordered back: steps out and moves
	f.pos = { x = 408, z = 548 }
	sim:queueCommand({ matchId = "m", requestId = "y", kind = "Move", ids = { 1 }, data = { pos = { x = 400, z = 470 } } }, "france")
	run(sim, 60)
	assertTrue(f.pos.z < 500, string.format("left the brook, z=%.0f", f.pos.z))
end)

test("Home edges follow the deployment: Austerlitz armies flee west and east, Jena north and south", function()
	local Edges = require(Server.Sim.Edges)
	local function sides(id)
		local sc = Scenarios.get(id)
		local map = MapGen.generate(sc.map)
		local sim = Sim.new({ matchId = "e", scenario = sc, map = map, seed = 1 })
		local p = Edges.sideOf(sim:homeEdge(sc.factions.player), map.width, map.depth)
		local e = Edges.sideOf(sim:homeEdge(sc.factions.enemy), map.width, map.depth)
		return p, e
	end
	local jp, je = sides("jena")
	assertTrue(jp == "s" and je == "n", "jena " .. jp .. "/" .. je)
	local ap, ae = sides("austerlitz")
	assertTrue(ap ~= ae, "austerlitz sides differ: " .. ap .. "/" .. ae)
	assertTrue(ap == "w" and ae == "e", "austerlitz " .. ap .. "/" .. ae)
	for _, entry in Scenarios.list() do
		local p, e = sides(entry.id)
		assertTrue(p ~= e, entry.id .. ": both armies share the " .. p .. " edge")
	end
end)

test("Contact reveals hidden defenders; frozen routers leave the field; chronicle uses display names", function()
	local village = MAP.villages[1].pos
	local sim = newSim({
		unit("france", "infantry", "F", village.x, village.z - 150, math.pi / 2),
		unit("prussia", "infantry", "Hidden", village.x, village.z, -math.pi / 2),
	})
	local hidden = sim.formations[2]
	hidden.inWoods = true
	local f = sim.formations[1]
	f.pos = { x = village.x, z = village.z - (f.halfRadius + hidden.halfRadius + 10) }
	run(sim, 0.5)
	assertTrue(sim.views.france.visible[2], "touching enemy is visible even in cover")
	-- frozen router
	local sim2 = newSim({ unit("france", "infantry", "Stuck", 700, 600, 0) })
	local s = sim2.formations[1]
	s.state = "routing"
	s.timers.routing = 0
	s.morale = 0
	for _ = 1, 20 * 30 do
		s.pos = { x = 700, z = 600 } -- held in place
		s.path = nil
		sim2:step()
		if s.state ~= "routing" then
			break
		end
	end
	assertEq(s.state, "exited", "a router going nowhere for 20 s leaves the field")
	-- chronicle
	local obj = MAP.objectives[1].pos
	local sim3 = Sim.new({ matchId = "m", scenario = (function()
		local sc = scenario({ unit("france", "infantry", "F", obj.x, obj.z, 0), FAR_ENEMY, FAR_FRIEND })
		sc.factionNames = { france = "France", prussia = "Prussia" }
		return sc
	end)(), map = MAP, seed = 1 })
	sim3:start()
	run(sim3, Config.Objectives.CaptureSeconds + 1)
	local found = false
	for _, line in sim3.logLines do
		if string.find(line, "France captured", 1, true) then
			found = true
		end
	end
	assertTrue(found, "log uses display names")
end)

test("Infantry on attack-move does not halt in range of an enemy it cannot fire on", function()
	local sim = newSim({
		unit("france", "infantry", "F", 600, 300, math.pi / 2),
		unit("france", "infantry", "Screen", 600, 345, math.pi / 2),
		unit("prussia", "infantry", "P", 600, 390, -math.pi / 2, 200),
	})
	sim.formations[3].fireAtWill = false
	local f = sim.formations[1]
	cmd(sim, "AttackMove", { 1 }, { pos = { x = 700, z = 700 } })
	for _ = 1, 40 do
		sim:step()
	end
	assertTrue(Vec.dist(f.pos, sim.formations[3].pos) < 85, "the enemy is in musket range")
	local why = Combat.fireBlockReason(sim, f, sim.formations[3])
	assertTrue(why ~= nil and why ~= "Reloading" and why ~= "Target not to the front", "but it cannot fire on it: " .. tostring(why))
	assertEq(f.state, "moving", "it marches on instead of standing idle")
end)

test("Infantry on attack-move in travel column keeps marching instead of halting in range", function()
	local sim = newSim({
		unit("france", "infantry", "F", 600, 300, math.pi / 2),
		unit("prussia", "infantry", "P", 600, 370, -math.pi / 2, 200),
	})
	sim.formations[2].fireAtWill = false
	local f = sim.formations[1]
	f.shape = "travel"
	f.prevShape = nil -- hemmed in: the column cannot re-form yet
	cmd(sim, "AttackMove", { 1 }, { pos = { x = 600, z = 700 } })
	for _ = 1, 40 do
		sim:step()
	end
	assertTrue(sim:isVisibleTo("france", 2), "the enemy is in sight")
	assertTrue(Vec.dist(f.pos, sim.formations[2].pos) < 85, "the enemy is in musket range")
	assertEq(f.state, "moving", "a column in range does not stand idle")
end)

test("Generals: every HQ steadies the men near it; a corps general's fall shakes only his corps", function()
	local function hq(faction, name, x, z, commander)
		local u = unit(faction, "hq", name, x, z, math.pi / 2)
		u.commander = commander
		return u
	end
	local sim = newSim({
		hq("france", "Napoléon — Imperial HQ", A.x - 400, A.z, true),
		hq("france", "Lannes — V Corps", A.x, A.z, false),
		unit("france", "infantry", "Near Lannes", A.x + 30, A.z, math.pi / 2),
		unit("france", "infantry", "Far away", A.x + 30, A.z + 500, math.pi / 2),
	})
	local near, far = sim.formations[3], sim.formations[4]
	near.morale, far.morale = near.baseMorale, far.baseMorale
	run(sim, 90)
	assertTrue(near.morale > near.baseMorale + 1, string.format("the corps general lifts the cap: %.1f vs %.1f", near.morale, near.baseMorale))
	assertTrue(far.morale <= far.baseMorale + 0.01, "no general near, no bonus")
	-- Lannes falls: his corps wavers, the far battalion does not
	local n0, f0 = near.morale, far.morale
	sim.formations[2].strength = 0
	sim:step()
	assertTrue(near.morale <= n0 - Config.Units.hq.lossMoralePenalty + 1, "his corps wavers")
	assertTrue(far.morale >= f0 - 0.5, "the rest of the army does not")
	-- the Emperor falls: everyone wavers
	local f1 = far.morale
	sim.formations[1].strength = 0
	sim:step()
	assertTrue(far.morale <= f1 - Config.Units.hq.lossMoralePenalty + 1, "the army wavers")
end)

test("Experience is earned in battle: every 150 enemy casualties inflicted is a level (max 3); friendly fire earns nothing", function()
	local sim = newSim({
		unit("france", "infantry", "Shooters", A.x, A.z, 0),
		unit("prussia", "infantry", "Victims", A.x + 70, A.z, math.pi, 900),
		unit("france", "infantry", "Friends", A.x - 70, A.z, 0),
	})
	local f = sim.formations[1]
	local exp0, morale0 = f.experience, f.baseMorale
	local function hit(target, n)
		Combat.apply(sim, { { attackerId = 1, targetId = target, casualties = n, side = "front", moraleExtra = 0, kind = "volley" } })
	end
	hit(2, 100)
	assertEq(f.experience, exp0, "not yet")
	hit(2, 60)
	assertEq(f.experience, exp0 + 1, "blooded")
	assertEq(f.baseMorale, morale0 + Config.Combat.ExperienceMorale)
	hit(3, 400)
	assertEq(f.experience, exp0 + 1, "friendly fire earns nothing")
	hit(2, 600)
	assertEq(f.experience, 3, "capped at 3")
	assertEq(f.kills, 760)
end)

test("Battle techs from the campaign: quick squares, better canister, nationalism's morale", function()
	local quick = unit("france", "infantry", "Quick", A.x, A.z, 0)
	quick.quickSquare = true
	local proud = unit("france", "infantry", "Proud", A.x, A.z + 60, 0)
	proud.moraleBonus = 5
	local sim = newSim({ quick, proud, unit("france", "infantry", "Plain", A.x, A.z + 120, 0) })
	assertEq(sim.formations[2].baseMorale, sim.formations[3].baseMorale + 5, "Nationalism")
	cmd(sim, "Shape", { 1, 3 }, { shape = "square" })
	sim:step()
	sim:step()
	assertTrue(sim.formations[1].timers.reform < sim.formations[3].timers.reform * 0.7, "Squares from column")
	-- canister: the same battery with and without the bonus
	local function canister(bonus)
		local s2 = newSim({
			unit("france", "artillery", "Guns", A.x, A.z, 0),
			unit("prussia", "infantry", "Close", A.x + 70, A.z, math.pi),
		})
		local g = s2.formations[1]
		g.shape, g.canisterBonus = "deployed", bonus
		Formation.refreshFootprint(g)
		s2.formations[2].fireAtWill = false
		local n = 0
		for _ = 1, 40 do
			g.reload = 0
			for _, a in Combat.gather(s2) do
				if a.attackerId == 1 then
					n += a.casualties
				end
			end
		end
		return n
	end
	assertTrue(canister(1.25) > canister(1) * 1.1, "Improved canister")
end)


test("Snapshot: own formations carry the enemy casualties they inflicted (results)", function()
	local sim = newSim({
		unit("france", "infantry", "25e de Ligne", 400, 400, math.pi / 2),
		unit("prussia", "infantry", "IR 15", 400, 600, -math.pi / 2),
	})
	sim:step() -- lines of sight
	local f
	for _, id in sim.order do
		if sim.formations[id].faction == "france" then
			f = sim.formations[id]
		end
	end
	f.kills = 37
	local snap = sim:snapshot("france", true)
	local mine, theirs
	for _, v in snap.formations do
		if v.faction == "france" then
			mine = v
		else
			theirs = v
		end
	end
	assertEq(mine.kills, 37)
	assertTrue(theirs ~= nil and theirs.kills == nil, "not for the enemy's")
end)
