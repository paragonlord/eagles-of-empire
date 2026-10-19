-- Custom battles: two nations, a field, a budget; the player's purchases against an AI army of the
-- same cost, on a scenario the sim and AI run like any other.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local EuropeData = require(Shared.EuropeData)
local MapGen = require(Shared.MapGen)
local Protocol = require(Shared.Protocol)
local Config = require(Shared.Config)
local CustomBattle = require(Shared.CustomBattle)
local Sim = require(Server.Sim)
local AI = require(Server.AI)

local function spec(over)
	local s = { player = "britain", enemy = "france", map = "waterloo", budget = 8000, units = { line = 6, rifles = 2, cavalry = 2, artillery = 2 } }
	for k, v in over or {} do
		s[k] = v
	end
	return s
end

test("Custom battle: your purchases against an AI army of the same budget, deployed in the zones", function()
	local sc, why = CustomBattle.build(spec())
	assertTrue(sc ~= nil, tostring(why))
	assertEq(sc.map, "waterloo")
	assertEq(sc.factions.player, "britain", "a nation with its own zone on the field keeps it")
	assertEq(sc.factionNames[sc.factions.enemy], EuropeData.Nations.france.name)
	local map = MapGen.generate(sc.map)
	local hq, n = {}, { [sc.factions.player] = 0, [sc.factions.enemy] = 0 }
	for _, u in sc.units do
		assertTrue(MapGen.inZone(map, u.faction, u.pos), u.name .. " stands in its zone")
		if u.commander then
			hq[u.faction] = true
		else
			n[u.faction] += 1
		end
	end
	assertTrue(hq[sc.factions.player] and hq[sc.factions.enemy], "an HQ a side")
	assertEq(n[sc.factions.player], 12)
	local c = EuropeData.UnitClasses
	assertEq(CustomBattle.cost({ line = 6, rifles = 2, cavalry = 2, artillery = 2 }), 6 * c.line.cost + 2 * c.rifles.cost + 2 * c.cavalry.cost + 2 * c.artillery.cost)
	local enemy = CustomBattle.enemyArmy("france", 8000)
	local spent = CustomBattle.cost(enemy)
	assertTrue(spent <= 8000 and spent >= 8000 * 0.85, "the AI spends its budget: " .. spent)
	assertTrue((enemy.cavalry or 0) + (enemy.heavy or 0) + (enemy.lancers or 0) > 0 and (enemy.artillery or 0) + (enemy.horseart or 0) > 0, "a mixed army")
	-- a province field: zones named for other nations are shared out
	local sc2 = CustomBattle.build(spec({ map = "province:lombardy", player = "austria", enemy = "russia" })) :: any
	assertTrue(sc2 ~= nil and sc2.factions.player ~= sc2.factions.enemy)
	-- refusals
	local _, w1 = CustomBattle.build(spec({ units = { oldguard = 1 } }))
	assertEq(w1, "notInRoster")
	local _, w2 = CustomBattle.build(spec({ units = { guard = 12 } }))
	assertEq(w2, "overBudget")
	local _, w6 = CustomBattle.build(spec({ units = { line = 21 }, budget = 12000 }))
	assertEq(w6, "tooManyUnits")
	local _, w3 = CustomBattle.build(spec({ map = "moon" }))
	assertEq(w3, "badMap")
	local _, w4 = CustomBattle.build(spec({ enemy = "britain" }))
	assertEq(w4, "sameNation")
	local _, w5 = CustomBattle.build(spec({ units = {} }))
	assertEq(w5, "noUnits")
	-- the control carries it
	assertTrue(Protocol.validateControl({ requestId = "r", action = "custom", value = spec() }, { matchId = "" }))
	assertTrue(not Protocol.validateControl({ requestId = "r", action = "custom", value = "jena" }, { matchId = "" }))
end)

test("Custom battle: the sim runs it and the AI fights it", function()
	local sc = CustomBattle.build(spec()) :: any
	local sim = Sim.new({ matchId = "m", scenario = sc, map = MapGen.generate(sc.map), seed = 4 })
	sim:start()
	local st = AI.new(sim, sc.factions.enemy, "normal")
	local prev = Sim.aiStep -- a module-level hook other specs set too
	Sim.aiStep = function(s)
		if s == sim then
			AI.step(st)
		elseif prev then
			prev(s)
		end
	end
	for _ = 1, math.floor(60 / Config.Sim.DT) do
		sim:step()
	end
	Sim.aiStep = prev
	assertTrue(sim.clock >= 59, "it ran")
end)
