-- Generals: traits, active abilities, validation, bounds, AI use; battle honours persistence.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local MapGen = require(Shared.MapGen)
local Protocol = require(Shared.Protocol)
local Scenarios = require(Shared.Scenarios)
local Generals = require(Shared.Generals)
local Sim = require(Server.Sim)
local Abilities = require(Server.Sim.Abilities)
local AI = require(Server.AI)
local Campaign = require(Server.Campaign)
local GrandCampaign = require(Server.GrandCampaign)

local MAP = MapGen.generate("jena")
local DT = Config.Sim.DT

local function unit(faction, class, name, x, z, heading, extra)
	local u = { name = name, class = class, corps = "test", strength = class == "hq" and 40 or (class == "artillery" and 120 or (class == "cavalry" and 400 or 600)), experience = 1, pos = { x = x, z = z }, heading = heading or math.pi / 2, faction = faction }
	for k, v in extra or {} do
		u[k] = v
	end
	return u
end

local FAR_ENEMY = unit("prussia", "infantry", "Far picket", 1250, 1150, -math.pi / 2)
local FAR_FRIEND = unit("france", "infantry", "Far reserve", 380, 90)

local function newSim(units)
	local list = table.clone(units)
	list[#list + 1] = FAR_ENEMY
	list[#list + 1] = FAR_FRIEND
	local sim = Sim.new({ matchId = "m", scenario = { id = "t", name = "t", map = "jena", briefing = "", factions = { player = "france", enemy = "prussia" }, factionNames = {}, units = list }, map = MAP, seed = 3 })
	sim.aiStep = function() end
	sim:start()
	return sim
end

local function cmd(sim, kind, ids, data, faction)
	return sim:queueCommand({ matchId = "m", requestId = "r" .. sim.seqCounter, kind = kind, ids = ids, data = data }, faction or "france")
end

local function run(sim, seconds)
	for _ = 1, math.max(1, math.floor(seconds / DT + 0.5)) do
		sim:step()
	end
end

local function rout(f)
	f.state = "routing"
	f.routCount = 1
	f.order = nil
	f.timers.routing = 0
end

local function hasTag(f, id)
	return table.find(f.mods.tags, id) ~= nil
end

local function events(sim, kind)
	local out = {}
	for _, ev in sim.events do
		if ev.kind == kind then
			out[#out + 1] = ev
		end
	end
	return out
end

-- Plateau positions on the Jena map (passable, same height band).
local X, Z = 700, 250

-- Data ---------------------------------------------------------------------------------------------

test("Generals: 21 historical commanders with two traits and an ability, every effect explained", function()
	assertTrue(#Generals.list >= 20, "at least twenty generals")
	for _, g in Generals.list do
		assertEq(#g.traits, 2, g.id .. " has two traits")
		assertTrue(type(g.ability.text) == "string" and #g.ability.text > 20 and g.ability.cooldown > 0, g.id .. " ability")
		for _, tr in g.traits do
			assertTrue(#Generals.describe(tr) > #tr.text, "described with reach")
			for k, v in tr.mods do
				local b = Abilities.Bounds[k]
				if b then
					assertTrue(v >= b[1] and v <= b[2], g.id .. "." .. tr.id .. "." .. k .. " is modest")
				end
			end
		end
	end
	assertEq(Generals.forHQ("Napoléon — Imperial HQ").id, "napoleon")
	assertEq(Generals.forHQ("Blücher — HQ").id, "blucher")
	assertEq(Generals.forHQ("French HQ").id, "generic")
	assertEq(Generals.forHQ("Anything", "kutuzov").id, "kutuzov")
	assertEq(Generals.corpsGeneral("V Corps · Lannes").id, "lannes")
	assertEq(Generals.corpsGeneral("VI Corps · Ney").id, "ney")
	assertEq(Generals.corpsGeneral("Kavallerie · Blücher").id, "blucher")
	assertTrue(Generals.corpsGeneral("Garde Impériale") == nil and Generals.corpsGeneral("HQ") == nil, "no commander named")
	assertTrue(Generals.corpsGeneral("1. Kolonne · Dokhturov") == nil, "unknown commander")
	-- every historical battle HQ is a named general
	for _, id in { "jena", "auerstedt", "austerlitz", "waterloo" } do
		for _, u in Scenarios.get(id).units do
			if u.class == "hq" then
				assertTrue(u.general and Generals.byId[u.general], id .. " HQ has a general")
			end
		end
	end
end)

-- Validation ---------------------------------------------------------------------------------------

test("Ability: only your own HQ, its own ability, once per cooldown", function()
	local sim = newSim({
		unit("france", "hq", "Napoléon — HQ", X, Z, nil, { general = "napoleon" }),
		unit("france", "infantry", "F1", X + 60, Z),
		unit("prussia", "hq", "Prussian HQ", 760, 860, -math.pi / 2),
	})
	local ctx = {
		matchId = "m", state = "running", mapWidth = 1600, mapDepth = 1200,
		isOwned = function(id) return sim.formations[id].faction == "france" end,
		classOf = function(id) return sim.formations[id].class end,
		legalShapes = function() return {} end,
	}
	local function v(ids, data)
		return select(2, Protocol.validateCommand({ matchId = "m", requestId = "x", kind = "Ability", ids = ids, data = data }, ctx))
	end
	assertEq(v({ 3 }, { abilityId = "inspire" }), Protocol.Reasons.notOwned)
	assertEq(v({ 2 }, { abilityId = "vive" }), Protocol.Reasons.wrongClass)
	assertEq(v({ 1 }, {}), Protocol.Reasons.badRequest)
	assertEq(v({ 1 }, { abilityId = string.rep("a", 40) }), Protocol.Reasons.badRequest)
	assertEq(v({ 1 }, { abilityId = "vive" }), nil)
	local function pre(data)
		return select(2, sim:precheck({ matchId = "m", requestId = "y", kind = "Ability", ids = { 1 }, data = data }))
	end
	assertEq(pre({ abilityId = "charge" }), "badRequest", "another general's ability")
	assertEq(pre({ abilityId = "vive" }), nil)
	cmd(sim, "Ability", { 1 }, { abilityId = "vive" })
	run(sim, 0.1)
	assertNear(Abilities.cooldownLeft(sim, 1), 180, 0.2)
	assertEq(pre({ abilityId = "vive" }), "cooldown")
	-- a second order that slipped through precheck is refused when it applies
	local before = sim.formations[2].morale
	cmd(sim, "Ability", { 1 }, { abilityId = "vive" })
	run(sim, 0.1)
	assertTrue(sim.formations[2].morale <= before + 0.5, "no second boost while recharging")
	run(sim, 180)
	assertEq(Abilities.cooldownLeft(sim, 1), 0)
	assertEq(pre({ abilityId = "vive" }), nil, "ready again")
	-- a dead general has no ability
	sim.formations[1].state = "destroyed"
	assertEq(pre({ abilityId = "vive" }), "destroyed")
end)

test("Ability: refused (no cooldown spent) when nobody is within reach", function()
	local sim = newSim({ unit("france", "hq", "Ney — HQ", X, Z, nil, { general = "ney" }), unit("france", "infantry", "F1", X + 60, Z) })
	assertEq(select(2, sim:precheck({ matchId = "m", requestId = "y", kind = "Ability", ids = { 1 }, data = { abilityId = "charge" } })), "noTarget", "Charge! needs cavalry")
	assertTrue(Protocol.Reasons.noTarget ~= nil)
	assertEq(Abilities.cooldownLeft(sim, 1), 0)
end)

-- Effects ------------------------------------------------------------------------------------------

test("Vive l'Empereur!: routing friends within 200 rally, everyone within 200 gains 20 morale", function()
	local sim = newSim({
		unit("france", "hq", "Napoléon — HQ", X, Z, nil, { general = "napoleon" }),
		unit("france", "infantry", "Steady", X + 60, Z),
		unit("france", "infantry", "Running", X - 60, Z),
		unit("france", "infantry", "Too far", X + 330, Z),
	})
	sim.formations[2].morale = 50
	rout(sim.formations[3])
	sim.formations[3].morale = 10
	local far = sim.formations[4].morale
	cmd(sim, "Ability", { 1 }, { abilityId = "vive" })
	run(sim, 0.1)
	assertNear(sim.formations[2].morale, 70, 0.5)
	assertEq(sim.formations[3].state, "rallying")
	assertTrue(sim.formations[3].morale >= Config.Morale.RallyMorale, "rallied with rally morale")
	assertNear(sim.formations[4].morale, far, 0.5, "outside the radius")
	local ev = events(sim, "ability")
	assertEq(#ev, 1)
	assertTrue(string.find(ev[1].text, "Vive l'Empereur", 1, true) and ev[1].id == nil and ev[1].x == nil, "announced without position")
	sim.formations[2].morale = 95
	sim.formations[1].timers.rallyCd = 0
	Abilities.state(sim).readyTick[1] = 0
	cmd(sim, "Ability", { 1 }, { abilityId = "vive" })
	run(sim, 0.1)
	assertTrue(sim.formations[2].morale <= 100, "morale stays bounded")
end)

test("Inspire (any general): +10 morale within 150", function()
	local sim = newSim({ unit("france", "hq", "Général de brigade", X, Z), unit("france", "infantry", "F1", X + 60, Z) })
	sim.formations[2].morale = 40
	cmd(sim, "Ability", { 1 }, { abilityId = "inspire" })
	run(sim, 0.1)
	assertNear(sim.formations[2].morale, 50, 0.5)
	assertNear(Abilities.cooldownLeft(sim, 1), 120, 0.2)
end)

test("Hold the line: no rout for 45 s within 150 unless below 30 % strength", function()
	local sim = newSim({
		unit("france", "hq", "Davout — HQ", X, Z, nil, { general = "davout" }),
		unit("france", "infantry", "Strong", X + 60, Z),
		unit("france", "infantry", "Remnant", X - 60, Z),
	})
	cmd(sim, "Ability", { 1 }, { abilityId = "holdline" })
	run(sim, 0.1)
	local strong, remnant = sim.formations[2], sim.formations[3]
	assertTrue(strong.mods.noRout and hasTag(strong, "holdline"), "effect shown on the formation")
	remnant.strength = 150 -- 25 %
	strong.morale, remnant.morale = 5, 5
	run(sim, 1)
	assertTrue(strong.state ~= "routing", "holds")
	assertTrue(strong.morale >= Config.Morale.RoutEnter - 0.01)
	assertEq(remnant.state, "routing", "a remnant still breaks")
	run(sim, 45)
	assertTrue(not strong.mods.noRout, "expired")
	strong.morale = 5
	run(sim, 0.2)
	assertEq(strong.state, "routing", "routs once the order lapses")
end)

test("Charge!: cavalry within 200 charges ×1.3 for 30 s", function()
	local sim = newSim({
		unit("france", "hq", "Ney — HQ", X, Z, nil, { general = "ney" }),
		unit("france", "cavalry", "Hussars", X + 60, Z),
		unit("france", "infantry", "Foot", X - 60, Z),
	})
	cmd(sim, "Ability", { 1 }, { abilityId = "charge" })
	run(sim, 0.1)
	-- Ney's HQ trait (Bravest of the Brave, +15 %) stacks with the ability
	assertNear(sim.formations[2].mods.chargeImpact, 1.3 * 1.15, 1e-6)
	assertNear(sim.formations[3].mods.chargeImpact, 1.15, 1e-6, "infantry: trait only")
	assertNear(sim.formations[3].mods.accuracy, 0.9, 1e-6, "Ney's poor fire discipline")
	run(sim, 30)
	assertNear(sim.formations[2].mods.chargeImpact, 1.15, 1e-6, "ability expired")
end)

test("Vorwärts!: +10 morale now, +20 % speed and +0.3/s recovery for 60 s", function()
	local sim = newSim({ unit("prussia", "hq", "Blücher — HQ", X, Z), unit("prussia", "infantry", "IR 1", X + 60, Z) })
	local p = sim.formations[2]
	p.morale = 40
	cmd(sim, "Ability", { 1 }, { abilityId = "vorwaerts" }, "prussia")
	run(sim, 0.1)
	assertNear(p.morale, 50, 0.6)
	assertNear(p.mods.speed, 1.2, 1e-6)
	assertTrue(p.mods.recovery >= 0.3, "recovery")
	run(sim, 60)
	assertNear(p.mods.speed, 1, 1e-6)
end)

test("Strategic withdrawal: routing units within 250 rally at once, then fall back", function()
	local sim = newSim({ unit("prussia", "hq", "Kutuzov — HQ", X, Z), unit("prussia", "infantry", "Rgt", X + 100, Z) })
	local r = sim.formations[2]
	rout(r)
	r.morale = 10
	cmd(sim, "Ability", { 1 }, { abilityId = "withdraw" }, "prussia")
	run(sim, 0.1)
	assertEq(r.state, "rallying")
	assertEq(r.order.kind, "Retreat")
	local home = sim:homeEdge("prussia")
	assertTrue(math.abs(r.order.pos.z - home.z) < math.abs(r.pos.z - home.z), "falls back toward its own edge")
end)

test("Personal example: rallies only the nearest routing formation", function()
	local sim = newSim({
		unit("prussia", "hq", "Erzherzog Carl", X, Z),
		unit("prussia", "infantry", "Near", X + 50, Z),
		unit("prussia", "infantry", "Further", X + 150, Z),
	})
	rout(sim.formations[2])
	rout(sim.formations[3])
	cmd(sim, "Ability", { 1 }, { abilityId = "example" }, "prussia")
	run(sim, 0.1)
	assertEq(sim.formations[2].state, "rallying")
	assertTrue(sim.formations[2].morale >= 45)
	assertEq(sim.formations[3].state, "routing")
	assertNear(Abilities.cooldownLeft(sim, 1), 90, 0.2)
end)

-- A halted infantry position with rising ground ahead (reverse slope), found on the real map.
local function crestSpot()
	local f = { pos = { x = 0, z = 0 }, heading = 0 }
	for z = 60, 1140, 16 do
		for x = 60, 1540, 16 do
			for _, h in { math.pi / 2, -math.pi / 2 } do
				f.pos.x, f.pos.z, f.heading = x, z, h
				local t = Grid.terrainAt(MAP.grid, x, z)
				if t.name == "open" and Abilities.behindCrest(MAP.grid, f) and Grid.fits(MAP.grid, x, z, 8) then
					return x, z, h
				end
			end
		end
	end
	return nil
end

test("Reverse slope and Up, Guards: hidden infantry rises with +50 % accuracy", function()
	local x, z, h = crestSpot()
	assertTrue(x ~= nil, "the Jena map has a crest")
	local sim = newSim({
		unit("france", "hq", "Wellington — HQ", x, z - 40 * math.sin(h), h, { general = "wellington" }),
		unit("france", "infantry", "Guards", x, z, h),
	})
	run(sim, 0.1)
	local g = sim.formations[2]
	assertTrue(hasTag(g, "reverse"), "reverse slope applies behind the crest")
	assertNear(g.mods.cover, 0.15, 1e-6)
	assertEq(g.mods.hideBeyond, Generals.HiddenRange)
	assertNear(g.mods.accuracy, 1.05, 1e-6, "Peninsula drill")
	g.reload = 9
	g.fireAtWill = false
	cmd(sim, "Ability", { 1 }, { abilityId = "upguards" })
	run(sim, 0.1)
	assertTrue(g.fireAtWill and g.reload <= 0, "muskets ready, fire at will")
	assertNear(g.mods.accuracy, 1.05 * 1.5, 1e-6)
	-- having fired, it can be seen again
	g.lastShotTick = sim.tick
	run(sim, 0.1)
	assertEq(g.mods.hideBeyond, nil)
end)

-- Traits -------------------------------------------------------------------------------------------

test("Traits: corps commanders, army-wide traits, conditions, and the bounds", function()
	local sim = newSim({
		unit("france", "hq", "Ney — HQ", X, Z, nil, { general = "ney" }),
		unit("france", "infantry", "17e Légère", X + 60, Z, nil, { corps = "V Corps · Lannes" }),
		unit("france", "cavalry", "1er Cuirassiers", X - 60, Z, nil, { corps = "Réserve de cavalerie · Murat" }),
		unit("prussia", "hq", "Kutuzov — HQ", 760, 860, -math.pi / 2, { general = "kutuzov" }),
		unit("prussia", "infantry", "Far away", 1000, 1000, -math.pi / 2),
	})
	run(sim, 0.1)
	local lannes, murat, far = sim.formations[2], sim.formations[3], sim.formations[5]
	assertNear(lannes.mods.melee, 1.1, 1e-6)
	assertNear(lannes.mods.speed, 1.05, 1e-6)
	assertTrue(hasTag(lannes, "roland") and hasTag(lannes, "bravest"), "corps and HQ traits both listed")
	assertNear(murat.mods.chargeRecovery, 0.75, 1e-6)
	assertTrue(far.mods.steadyRetreat, "Kutuzov's army-wide trait reaches far formations")
	assertTrue(not hasTag(far, "oldfox"), "his local trait does not")
	-- Retreat costs no cohesion under Kutuzov, 0.2 otherwise
	cmd(sim, "Retreat", { 5 }, {}, "prussia")
	cmd(sim, "Retreat", { 2 }, {})
	run(sim, 0.1)
	assertTrue(far.cohesion > 0.99, "no cohesion lost")
	assertNear(lannes.cohesion, 0.8, 0.01)
	-- stacking is clamped: Charge! ×1.3, Bravest ×1.15, Panache ×1.1 = 1.64 -> 1.5
	cmd(sim, "Ability", { 1 }, { abilityId = "charge" })
	run(sim, 0.1)
	assertEq(murat.mods.chargeImpact, Abilities.Bounds.chargeImpact[2])
end)

test("Traits: Iron Marshal floors casualty shock; Marschall Vorwärts only while advancing", function()
	local sim = newSim({
		unit("france", "hq", "Davout — HQ", X, Z, nil, { general = "davout" }),
		unit("france", "infantry", "Friant", X + 60, Z),
		unit("prussia", "hq", "Blücher — HQ", 760, 860, -math.pi / 2),
		unit("prussia", "infantry", "IR 2", 820, 860, -math.pi / 2),
	})
	run(sim, 0.1)
	local f = sim.formations[2]
	f.morale = 40
	f.strength -= 300
	f.casualtiesThisTick = 300 -- half the battalion in one tick: shock of 50
	run(sim, 0.05)
	assertTrue(f.morale >= 25 - 0.01 and f.state ~= "routing", "casualties alone stop at 25")
	local p = sim.formations[4]
	assertTrue(not hasTag(p, "vorwarts"), "standing still")
	cmd(sim, "Move", { 4 }, { pos = { x = 820, z = 700 } }, "prussia") -- toward the French edge
	run(sim, 0.5)
	assertTrue(hasTag(p, "vorwarts") and p.mods.speed > 1, "advancing")
	cmd(sim, "Move", { 4 }, { pos = { x = 820, z = 1000 } }, "prussia")
	run(sim, 0.5)
	assertTrue(not hasTag(p, "vorwarts"), "falling back is not advancing")
end)

test("Snapshots show the general, readiness and modifiers to the owner only", function()
	local sim = newSim({ unit("france", "hq", "Napoléon — HQ", X, Z, nil, { general = "napoleon" }), unit("france", "infantry", "F1", X + 60, Z), unit("prussia", "infantry", "P1", X + 120, Z, -math.pi / 2) })
	run(sim, 0.4)
	local own = sim:snapshot("france", true)
	local byId = {}
	for _, v in own.formations do
		byId[v.id] = v
	end
	assertEq(byId[1].general, "napoleon")
	assertEq(byId[1].abilityReadyAt, 0)
	assertTrue(string.find(byId[2].tags or "", "emperor", 1, true) ~= nil, "trait listed on the card")
	local theirs = sim:snapshot("prussia", true)
	for _, v in theirs.formations do
		if v.faction == "france" then
			assertTrue(v.general == nil and v.tags == nil, "enemy modifiers stay private")
		end
	end
end)

-- AI -----------------------------------------------------------------------------------------------

test("AI uses its general's ability when two formations near the HQ waver", function()
	local units = {
		unit("prussia", "hq", "Prussian HQ", 760, 860, -math.pi / 2),
		unit("prussia", "infantry", "IR 1", 700, 820, -math.pi / 2),
		unit("prussia", "infantry", "IR 2", 820, 820, -math.pi / 2),
	}
	local sim = newSim(units)
	local st = AI.new(sim, "prussia", "normal")
	sim.aiStep = function()
		AI.step(st)
	end
	run(sim, 2)
	assertEq(Abilities.cooldownLeft(sim, 1), 0, "steady line: no ability")
	sim.formations[2].moraleBand, sim.formations[2].morale = "shaken", 35
	sim.formations[3].moraleBand, sim.formations[3].morale = "shaken", 35
	local used = false
	for _ = 1, 40 do
		sim:step()
		used = used or #events(sim, "ability") > 0
		sim:clearEvents()
	end
	assertTrue(used, "ability announced")
	assertTrue(Abilities.cooldownLeft(sim, 1) > 100, "cooldown respected")
	assertTrue(sim.formations[2].morale >= 44, "Inspire applied")
end)

-- Battle honours -----------------------------------------------------------------------------------

local function results(outcome)
	return { outcome = outcome, reason = "test", clock = 0, objectives = {}, sides = {}, feedback = {}, log = {} }
end

test("Honours (Thuringia): winners carry 'Jena 1806', bounded at five, survive save and load", function()
	local state = Campaign.new(5)
	assertTrue(Campaign.command(state, { kind = "move", armyId = 1, regionId = "jena" }))
	local _, battles = Campaign.endTurn(state)
	assertTrue(Campaign.applyBattleResult(state, battles[1].battleId, results("victory"), {}))
	local a1 = state.armies[1]
	assertEq(a1.units[2].honours[1], "Jena 1806")
	local chronicled = false
	for _, l in state.log do
		chronicled = chronicled or string.find(l, "battle honour", 1, true) ~= nil
	end
	assertTrue(chronicled, "chronicle line")
	for _, a in state.armies do
		if a.faction == "prussia" then
			for _, u in a.units do
				assertTrue(u.honours == nil, "losers earn none")
			end
		end
	end
	local u = a1.units[2]
	u.honours = { "A 1806", "B 1806", "C 1806", "D 1806", "Jena 1806" }
	local back = Campaign.deserialize(Campaign.serialize(state))
	assertTrue(back ~= nil, "round trip")
	assertEq(table.concat(back.armies[1].units[2].honours, "|"), "A 1806|B 1806|C 1806|D 1806|Jena 1806")
	local p = Campaign.serialize(state)
	p.armies[1].units[2].honours = { "1", "2", "3", "4", "5", "6" }
	assertTrue(Campaign.deserialize(p) == nil, "more than five rejected")
	p.armies[1].units[2].honours = { string.rep("x", 80) }
	assertTrue(Campaign.deserialize(p) == nil, "overlong honour rejected")
end)

test("Honours (grand campaign): set-piece name and year, oldest gives way, round trip", function()
	local State = GrandCampaign.State
	local u = { key = "u1", type = "line", name = "1er", strength = 100, maxStrength = 100, experience = 0 }
	for i = 1, 7 do
		State.addHonour(u, "Battle " .. i)
	end
	State.addHonour(u, "Battle 7")
	assertEq(table.concat(u.honours, ","), "Battle 3,Battle 4,Battle 5,Battle 6,Battle 7", "five most recent, no repeats")
	local b = { battleId = "b", provinceId = "bohemia", turn = 1, attacker = "france", defender = "austria", attackers = { "france" }, defenders = { "austria" }, scenarioId = "austerlitz", player = true }
	assertEq(GrandCampaign.Battles.honourName(b), "Austerlitz 1805")
	local s = State.new(1, "france")
	local a = s.armies[1]
	a.units[1].honours = { "Austerlitz 1805" }
	local back = GrandCampaign.deserialize(GrandCampaign.serialize(s))
	assertTrue(back ~= nil and back.armies[1].units[1].honours[1] == "Austerlitz 1805", "round trip")
	local p = GrandCampaign.serialize(s)
	p.armies[1].units[1].honours = { "1", "2", "3", "4", "5", "6" }
	assertTrue(GrandCampaign.deserialize(p) == nil, "bounded")
end)
