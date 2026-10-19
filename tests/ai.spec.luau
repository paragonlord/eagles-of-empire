-- Enemy AI. Deterministic fixtures on the Jena map; the AI plays Prussia, the player France.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)
local Objectives = require(Server.Sim.Objectives)
local Formation = require(Server.Sim.Formation)
local Sim = require(Server.Sim)
local AI = require(Server.AI)

local MAP = MapGen.generate("jena")
local DT = Config.Sim.DT

local function unit(faction, class, name, x, z, heading, strength)
	return { name = name, class = class, corps = "test", strength = strength or (class == "artillery" and 120 or class == "hq" and 40 or 600), experience = 1, pos = { x = x, z = z }, heading = heading, faction = faction }
end

local function scenario(units)
	return { id = "t", name = "t", map = "jena", briefing = "", factions = { player = "france", enemy = "prussia" }, factionNames = {}, units = units }
end

-- Padding so neither side is "collapsed" at tick 1 (far from everything on the map).
local FAR_FRIEND = unit("france", "infantry", "Far reserve", 380, 90, math.pi / 2)
local FAR_ENEMY = unit("prussia", "infantry", "Far picket", 1250, 1150, -math.pi / 2)

-- Sim.aiStep is a module-level hook; dispatch per sim so several sims can coexist in a test.
local states = setmetatable({}, { __mode = "k" })
Sim.aiStep = function(sim)
	local st = states[sim]
	if st then
		AI.step(st)
	end
end

-- Every AI command is recorded as it is queued.
local function attach(sim, difficulty)
	local st = AI.new(sim, "prussia", difficulty or "normal")
	states[sim] = st
	local log = {}
	local orig = sim.queueCommand
	sim.queueCommand = function(self, cmd, faction)
		if faction == "prussia" then
			cmd.atTick = self.tick
			log[#log + 1] = cmd
		end
		return orig(self, cmd, faction)
	end
	return st, log
end

local function newSim(units, seed, pad)
	local list = table.clone(units)
	if pad ~= false then
		list[#list + 1] = FAR_ENEMY
		list[#list + 1] = FAR_FRIEND
	end
	local sim = Sim.new({ matchId = "m", scenario = scenario(list), map = MAP, seed = seed or 7 })
	sim:start()
	return sim
end

local function jena(seed)
	local sim = Sim.new({ matchId = "m", scenario = Scenarios.jena, map = MAP, seed = seed or 3 })
	sim:start()
	return sim
end

local function cmd(sim, kind, ids, data)
	sim:queueCommand({ matchId = "m", requestId = "p" .. sim.seqCounter, kind = kind, ids = ids, data = data }, "france")
end

local function run(sim, seconds, each)
	for _ = 1, math.floor(seconds / DT) do
		sim:step()
		if each then
			each()
		end
		if sim.state ~= "running" then
			break
		end
	end
end

local function cmdString(c)
	local d = c.data or {}
	local parts = { c.kind, table.concat(c.ids, ",") }
	for _, k in { "targetId", "shape", "heading", "limbered", "ammo", "fireAtWill" } do
		if d[k] ~= nil then
			parts[#parts + 1] = k .. "=" .. tostring(d[k])
		end
	end
	if d.pos then
		parts[#parts + 1] = string.format("%.1f,%.1f", d.pos.x, d.pos.z)
	end
	return table.concat(parts, " ")
end

local function byId(sim, faction, class)
	local out = {}
	for _, id in sim.order do
		local f = sim.formations[id]
		if f and f.faction == faction and (not class or f.class == class) then
			out[#out + 1] = f
		end
	end
	return out
end

test("AI is deterministic: same seed, same commands and positions", function()
	local function play(seed)
		local sim = jena(seed)
		local _, log = attach(sim)
		run(sim, 60)
		local lines = {}
		for _, c in log do
			lines[#lines + 1] = cmdString(c)
		end
		for _, f in byId(sim, "prussia") do
			lines[#lines + 1] = string.format("%d:%.2f,%.2f,%.3f,%s", f.id, f.pos.x, f.pos.z, f.heading, f.state)
		end
		return #log, sim.seqCounter, table.concat(lines, "\n")
	end
	local n1, s1, t1 = play(21)
	local n2, s2, t2 = play(21)
	assertTrue(n1 > 0, "the AI issued orders")
	assertEq(n2, n1, "command count")
	assertEq(s2, s1, "sequence counter")
	assertEq(t2, t1, "command sequence and positions")
end)

test("AI never acts on an enemy it has not seen", function()
	-- Hidden French unit in the far north-west corner, out of every Prussian spot radius.
	local hidden = unit("france", "infantry", "Hidden", 90, 1150, 0)
	local sim = newSim({
		unit("prussia", "hq", "HQ", 760, 860, -math.pi / 2),
		unit("prussia", "infantry", "P1", 700, 720, -math.pi / 2),
		unit("prussia", "infantry", "P2", 820, 720, -math.pi / 2),
		unit("prussia", "cavalry", "Horse", 600, 820, -math.pi / 2),
		unit("prussia", "artillery", "Guns", 740, 790, -math.pi / 2),
		hidden,
	}, 5, false)
	local hiddenId = 6
	local _, log = attach(sim)
	local seen, closest = false, math.huge
	run(sim, 90, function()
		seen = seen or sim.views.prussia.visible[hiddenId] == true
		if not seen then
			for _, f in byId(sim, "prussia") do
				closest = math.min(closest, Vec.dist(f.pos, sim.formations[hiddenId].pos))
			end
		end
	end)
	assertTrue(not seen, "fixture: the hidden unit stayed hidden")
	assertTrue(#log > 0, "the AI did act")
	for _, c in log do
		for _, id in c.ids do
			assertTrue(id ~= hiddenId, "never orders the hidden unit")
		end
		assertTrue((c.data or {}).targetId ~= hiddenId, "never targets the hidden unit: " .. cmdString(c))
	end
	assertTrue(closest > 80, "never approached the hidden unit, closest " .. closest)
end)

test("Infantry forms square against approaching cavalry and returns to line", function()
	local sim = newSim({
		unit("prussia", "infantry", "Line", 760, 250, 0),
		unit("france", "cavalry", "Horse", 1060, 250, math.pi),
	})
	local inf, cav = sim.formations[1], sim.formations[2]
	inf.fireAtWill = false
	local _, log = attach(sim)
	-- charge toward a point 70 short of the line: approaching, never in contact
	cmd(sim, "Charge", { 2 }, { pos = { x = 830, z = 250 } })
	local squareAt, lineAt, minDist, backInLine = nil, nil, math.huge, false
	run(sim, 90, function()
		minDist = math.min(minDist, Vec.dist(inf.pos, cav.pos))
		backInLine = backInLine or (lineAt ~= nil and inf.shape == "line")
		for i = #log, 1, -1 do
			local c = log[i]
			if c.kind == "Shape" and c.ids[1] == 1 then
				if c.data.shape == "square" and not squareAt then
					squareAt = { tick = sim.tick, dist = Vec.dist(inf.pos, cav.pos) }
				elseif c.data.shape == "line" and squareAt and not lineAt then
					lineAt = sim.tick
				end
			end
		end
		if sim.clock == 15 then
			cmd(sim, "Move", { 2 }, { pos = { x = 1250, z = 250 } }) -- withdraw
		end
	end)
	assertTrue(squareAt ~= nil, "ordered square")
	assertTrue(squareAt.dist > 50, "square ordered before contact, at " .. squareAt.dist)
	assertTrue(inf.state ~= "melee" and minDist > 40, "fixture: no contact")
	assertTrue(lineAt ~= nil and lineAt > squareAt.tick, "ordered back to line after the cavalry left")
	assertTrue(backInLine, "reformed into line")
end)

test("Jena: every battery has infantry within 60 after a minute; cavalry is held in reserve", function()
	local sim = jena(9)
	local st, log = attach(sim)
	local cavStartZ = {}
	for _, f in byId(sim, "prussia", "cavalry") do
		cavStartZ[f.id] = true
	end
	run(sim, 60)
	for _, g in byId(sim, "prussia", "artillery") do
		local best = math.huge
		for _, i in byId(sim, "prussia", "infantry") do
			best = math.min(best, Vec.dist(g.pos, i.pos))
		end
		assertTrue(best <= 60, string.format("%s has infantry within 60 (nearest %.0f)", g.name, best))
	end
	-- Reserve: at least one cavalry formation assigned reserve, none sent forward (north = -z) in 30 s.
	local reserveCav = 0
	for _, v in AI.debugView(st) do
		local f = sim.formations[v.id]
		if f.class == "cavalry" and string.sub(v.goal, 1, 7) == "reserve" then
			reserveCav += 1
		end
	end
	assertTrue(reserveCav >= 1, "a cavalry formation is in reserve")
	for _, c in log do
		for _, id in c.ids do
			if cavStartZ[id] then
				assertTrue(c.kind ~= "Charge" and c.kind ~= "AttackMove" and c.kind ~= "Engage", "cavalry not sent into action: " .. cmdString(c))
				-- any move keeps it behind the line of battle
				local behind = not c.data.pos or Vec.dot(Vec.sub(c.data.pos, st.wingPos.centre), st.forward) < -50
				assertTrue(behind, "cavalry held behind the line: " .. cmdString(c))
			end
		end
	end
	-- Objectives are its own: the defend plan occupies them.
	local owned = 0
	for _, o in sim.objectives do
		if o.owner == "prussia" then
			owned += 1
		end
	end
	assertTrue(owned >= 2, "holds its villages, owns " .. owned)
end)

test("Jena: ten minutes against an idle player runs clean at a bounded order rate", function()
	local sim = jena(13)
	local st, log = attach(sim)
	run(sim, 600)
	-- bounded rate: never more than the budget of path commands plus a few cheap ones per decision tick
	local perTick, maxPerTick = {}, 0
	for _, c in log do
		perTick[c.atTick] = (perTick[c.atTick] or 0) + 1
		maxPerTick = math.max(maxPerTick, perTick[c.atTick])
	end
	assertTrue(maxPerTick <= 16, "at most 16 commands per decision tick, got " .. maxPerTick)
	assertTrue(#log < 600 / (Config.AI.DecisionTicks * DT) * 4, "overall rate bounded, got " .. #log)
	assertTrue(sim.state == "running" or sim.winner == "prussia", "battle still on or won; winner=" .. tostring(sim.winner))
	assertTrue(not Objectives.collapsed(sim, "prussia"), "the AI army did not collapse on its own")
	local routing = 0
	for _, f in byId(sim, "prussia") do
		if f.state == "routing" or f.state == "destroyed" or f.state == "exited" then
			routing += 1
		end
	end
	assertTrue(routing < #byId(sim, "prussia") / 2, "most formations intact, broken " .. routing)
	for _, v in AI.debugView(st) do
		assertTrue(type(v.goal) == "string" and type(v.reason) == "string", "debug view strings")
	end
end)

test("Hard difficulty steadies the AI's own army by its morale bonus, once", function()
	local sim = Sim.new({ matchId = "m", scenario = scenario({ FAR_FRIEND, FAR_ENEMY }), map = MAP, seed = 3 })
	sim:start()
	local fr, pr = sim.formations[1], sim.formations[2]
	local frBase, prBase = fr.baseMorale, pr.baseMorale
	local bonus = Config.AI.Difficulties.hard.moraleBonus
	assertTrue(bonus > 0)
	AI.new(sim, "prussia", "hard")
	AI.new(sim, "prussia", "hard")
	assertEq(pr.baseMorale, prBase + bonus, "applied once even when the AI is rebuilt")
	assertEq(fr.baseMorale, frBase, "the human side is untouched")
	AI.new(sim, "prussia", "normal")
	assertEq(pr.baseMorale, prBase, "a new difficulty replaces the bonus")
	AI.new(sim, "france", "hard")
	assertEq(pr.baseMorale, prBase)
	assertEq(fr.baseMorale, frBase + bonus, "the bonus follows the AI's side")
	AI.steady(sim, nil, 0)
	assertEq(fr.baseMorale, frBase, "no AI, no bonus")
end)

test("AI garrisons a free building by an objective it holds", function()
	-- the strongpoint nearest any objective on Jena
	local sp, obj
	for _, s in MAP.strongpoints do
		for _, o in MAP.objectives do
			if Vec.dist(s.pos, o.pos) < 90 and not sp then
				sp, obj = s, o
			end
		end
	end
	assertTrue(sp ~= nil, "a village objective with a strongpoint")
	local sim = newSim({
		unit("prussia", "infantry", "IR Nr. 29", sp.pos.x + 60, sp.pos.z + 120, -math.pi / 2),
		unit("prussia", "infantry", "IR Nr. 49", sp.pos.x - 60, sp.pos.z + 120, -math.pi / 2),
	})
	for _, o in sim.objectives do
		if o.def.id == obj.id then
			o.owner = "prussia"
		end
	end
	local st = attach(sim)
	local held = false
	for _ = 1, math.floor(60 / DT) do
		sim:step()
		local h = sim.strongpoints[sp.id].holder
		if h and sim.formations[h].faction == "prussia" then
			held = true
			break
		end
	end
	assertTrue(held, sp.name .. " garrisoned by the defenders")
	local _ = st
end)

test("Battle roles: the attacking AI comes on while the enemy holds anything; the defending AI holds", function()
	local function postureAs(attacker)
		local units = {
			unit("prussia", "infantry", "IR Nr. 29", 760, 760, -math.pi / 2),
			unit("prussia", "infantry", "IR Nr. 49", 840, 760, -math.pi / 2),
			unit("france", "infantry", "34e de Ligne", 800, 300, math.pi / 2),
			unit("france", "infantry", "40e de Ligne", 880, 300, math.pi / 2),
		}
		local sc = scenario(units)
		sc.attacker = attacker
		local sim = Sim.new({ matchId = "m", scenario = sc, map = MAP, seed = 3 })
		sim:start()
		-- one objective each: a meeting battle would sit still
		sim.objectives[1].owner = "france"
		sim.objectives[2].owner = "prussia"
		local st = attach(sim)
		run(sim, 2)
		return st.posture
	end
	assertEq(postureAs("prussia"), "advance", "the attacker comes on")
	assertEq(postureAs("france"), "defend", "the defender holds")
end)

test("AI light infantry screens in skirmish order and closes up when horse appears", function()
	-- the open Landgrafenberg plateau (as in the sim tests)
	local sim = newSim({
		unit("prussia", "infantry", "Füsilier-Bataillon Pelet", 700, 250, math.pi),
		unit("france", "infantry", "34e de Ligne", 480, 250, 0),
		unit("france", "cavalry", "5e Hussards", 1300, 1150, 0),
	})
	sim.formations[2].fireAtWill = false
	attach(sim)
	run(sim, 16)
	local fus = sim.formations[1]
	assertEq(fus.type, "light")
	assertEq(fus.shape, "skirmish", "screening")
	-- the hussars appear beside them
	local horse = sim.formations[3]
	horse.pos = { x = fus.pos.x + 150, z = fus.pos.z }
	local closed = false
	for _ = 1, math.floor(8 / DT) do
		sim:step()
		closed = closed or fus.pendingShape == "line" or fus.shape == "line" or fus.pendingShape == "square" or fus.shape == "square"
	end
	assertTrue(closed, "closed up against cavalry (" .. fus.shape .. ")")
end)

test("AI cavalry rides into an enemy locked in melee with its infantry", function()
	local sim = newSim({
		unit("prussia", "infantry", "IR Nr. 29", 700, 250, math.pi),
		unit("france", "infantry", "34e de Ligne", 672, 250, 0),
		unit("prussia", "cavalry", "Dragoner-Regiment Königin Nr. 5", 880, 250, math.pi),
	})
	local st, log = attach(sim)
	run(sim, 8)
	local charged = false
	for _, c in log do
		if c.kind == "Charge" and c.data.targetId == 2 and table.find(c.ids, 3) then
			charged = true
		end
	end
	assertTrue(charged, "the dragoons charge the battalion fighting ours")
	local _ = st
end)
