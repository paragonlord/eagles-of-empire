-- Historical moments (conditions, effects, once-only firing, determinism) and the quick-battle
-- episodes (deployment, objectives, reachability, moment references).
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Vec = require(Shared.Vec)
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)
local MomentDefs = require(Shared.Moments)
local Sim = require(Server.Sim)
local Moments = require(Server.Sim.Moments)
local Nav = require(Server.Sim.Nav)

local maps = {}
local function mapOf(id)
	maps[id] = maps[id] or MapGen.generate(id)
	return maps[id]
end

local function unit(faction, class, name, corps, x, z, extra)
	local d = { name = name, class = class, corps = corps, strength = class == "hq" and 40 or 600, experience = 1, pos = { x = x, z = z }, heading = faction == "france" and math.pi / 2 or -math.pi / 2, faction = faction }
	for k, v in extra or {} do
		d[k] = v
	end
	return d
end

-- Jena fixture: a French line on the Landgrafenberg, Prussians beyond Closewitz, one held
-- Prussian reinforcement, and whatever moments the test passes.
local function fixture(moments, seed)
	local sc = {
		id = "t",
		name = "t",
		map = "jena",
		briefing = "",
		factions = { player = "france", enemy = "prussia" },
		factionNames = {},
		weather = "fog",
		weatherUntil = 30,
		moments = moments,
		units = {
			unit("france", "hq", "French HQ", "HQ", 800, 200, { commander = true }),
			unit("france", "infantry", "34e de Ligne", "V Corps · Lannes", 760, 320),
			unit("france", "infantry", "6e Légère", "VI Corps · Ney", 900, 320),
			unit("prussia", "hq", "Prussian HQ", "HQ", 760, 860, { commander = true }),
			unit("prussia", "infantry", "IR Nr. 49 Müffling", "Grawert", 740, 700),
			unit("prussia", "cavalry", "Kürassier Henckel", "Kavallerie", 1000, 820, { arrival = { seconds = 3600, pos = { x = 1000, z = 820 } } }),
		},
	}
	local sim = Sim.new({ matchId = "m", scenario = sc, map = mapOf("jena"), seed = seed or 3 })
	sim:start()
	return sim
end

local function tickTo(sim, tick)
	sim.tick = tick
	sim.clock = tick * Config.Sim.DT
end

local function momentEvents(sim)
	local out = {}
	for _, ev in sim.events do
		if ev.kind == "moment" then
			out[#out + 1] = ev
		end
	end
	return out
end

test("Moments: each condition kind evaluates against sim state", function()
	local sim = fixture({})
	local holds = Moments.holds
	tickTo(sim, 200) -- 10 s
	assertTrue(holds(sim, { time = 10 }) and not holds(sim, { time = 11 }), "time")
	assertTrue(holds(sim, { before = 11 }) and not holds(sim, { before = 10 }), "before")
	assertTrue(holds(sim, { weatherCleared = false }) and not holds(sim, { weatherCleared = true }), "fog has not cleared")
	sim.weather = "clear"
	assertTrue(holds(sim, { weatherCleared = true }), "weather cleared")
	-- objectives: owner, then held long enough
	local obj = sim.objectives[1]
	assertTrue(not holds(sim, { objectiveTaken = { id = obj.def.id, by = "france" } }), "neutral objective")
	obj.owner = "france"
	obj.heldSince = 100
	assertTrue(holds(sim, { objectiveTaken = { id = obj.def.id, by = "france" } }), "taken")
	assertTrue(holds(sim, { objectiveTaken = { id = obj.def.id, by = "france", seconds = 5 } }), "held 5 s")
	assertTrue(not holds(sim, { objectiveTaken = { id = obj.def.id, by = "france", seconds = 6 } }), "not held 6 s")
	assertTrue(not holds(sim, { objectiveTaken = { id = obj.def.id, by = "prussia" } }), "wrong owner")
	assertTrue(not holds(sim, { objectiveTaken = { id = "nowhere", by = "france" } }), "unknown objective")
	-- routs, by name substring, corps, class and faction
	local ney = sim.formations[3]
	assertTrue(not holds(sim, { formationRouted = { faction = "france", corps = "VI Corps" } }), "no rout yet")
	ney.state = "routing"
	assertTrue(holds(sim, { formationRouted = { faction = "france", corps = "VI Corps" } }), "VI Corps routing")
	assertTrue(holds(sim, { formationRouted = { name = "Légère", class = "infantry" } }), "by name and class")
	assertTrue(not holds(sim, { formationRouted = { faction = "prussia" } }), "other side steady")
	assertTrue(not holds(sim, { formationRouted = { faction = "france", class = "cavalry" } }), "class filters")
	ney.state = "idle"
	-- strength
	local hq = sim.formations[4]
	assertTrue(not holds(sim, { strengthBelow = { faction = "prussia", name = "Prussian HQ", fraction = 0.95 } }), "HQ intact")
	hq.strength = 30
	assertTrue(holds(sim, { strengthBelow = { faction = "prussia", name = "Prussian HQ", fraction = 0.95 } }), "HQ hit")
	assertTrue(not holds(sim, { strengthBelow = { faction = "prussia", fraction = 0.9 } }), "army barely touched")
	assertTrue(not holds(sim, { strengthBelow = { faction = "prussia", name = "Nobody", fraction = 0.9 } }), "empty selection never holds")
	-- proximity: to a point or an objective; off-map formations do not count
	assertTrue(holds(sim, { formationNear = { faction = "france", pos = { x = 900, z = 330 }, radius = 20 } }), "near a point")
	assertTrue(not holds(sim, { formationNear = { faction = "france", pos = { x = 900, z = 400 }, radius = 20 } }), "too far")
	assertTrue(not holds(sim, { formationNear = { faction = "prussia", class = "cavalry", pos = { x = 1000, z = 820 }, radius = 50 } }), "off-map does not count")
	local o = sim.objectives[1].def
	sim.formations[2].pos = { x = o.pos.x + 30, z = o.pos.z }
	assertTrue(holds(sim, { formationNear = { faction = "france", objective = o.id, radius = 40 } }), "near an objective")
	-- combinations: keys AND, any ORs, all groups
	assertTrue(holds(sim, { time = 5, weatherCleared = true }), "keys AND")
	assertTrue(not holds(sim, { time = 50, weatherCleared = true }), "keys AND (one false)")
	assertTrue(holds(sim, { any = { { time = 50 }, { weatherCleared = true } } }), "any")
	assertTrue(not holds(sim, { any = { { time = 50 }, { before = 1 } } }), "any (none)")
	assertTrue(holds(sim, { all = { { time = 5 }, { any = { { before = 1 }, { weatherCleared = true } } } } }), "nested all/any")
end)

test("Moments fire once, emit an event to both sides (or one faction) and enter the chronicle", function()
	local sim = fixture({
		{ id = "dawn", title = "Dawn", text = "The sun rises.", when = { time = 1 }, camera = { x = 800, z = 500 } },
		{ id = "secret", title = "Secret", text = "Only the French know.", when = { time = 1 }, faction = "france" },
	})
	for _ = 1, 40 do
		sim:step()
	end
	local evs = momentEvents(sim)
	assertEq(#evs, 2, "two moments, once each")
	assertEq(evs[1].momentId, "dawn")
	assertEq(evs[1].title, "Dawn")
	assertEq(evs[1].x, 800)
	assertTrue(sim.momentsFired.dawn and sim.momentsFired.secret, "recorded")
	local logged = false
	for _, line in sim.logLines do
		logged = logged or string.find(line, "Dawn", 1, true) ~= nil
	end
	assertTrue(logged, "in the results chronicle")
	-- the faction-only moment reaches France, not Prussia
	local function titles(viewer)
		local t = {}
		for _, ev in sim:snapshot(viewer, true).events do
			if ev.kind == "moment" then
				t[#t + 1] = ev.title
			end
		end
		return table.concat(t, ",")
	end
	assertEq(titles("france"), "Dawn,Secret")
	assertEq(titles("prussia"), "Dawn")
	sim:clearEvents()
	for _ = 1, 40 do
		sim:step()
	end
	assertEq(#momentEvents(sim), 0, "never again")
end)

test("Moment effects: morale bounded to ±15, release brings a held unit on, weather set", function()
	local sim = fixture({
		{ id = "boost", title = "b", text = "b.", when = { time = 0 }, effect = { morale = { { faction = "france", amount = 80 } } } },
		{ id = "shock", title = "s", text = "s.", when = { time = 0 }, effect = { morale = { { faction = "prussia", name = "Müffling", amount = -80 } }, release = "Henckel", weather = "rain" } },
	})
	local f, p, cav = sim.formations[2], sim.formations[5], sim.formations[6]
	assertEq(cav.state, "offmap")
	for _ = 1, MomentDefs.EveryTicks - 1 do
		sim:step()
	end
	assertEq(#momentEvents(sim), 0, "not before the evaluation tick")
	-- the tick that evaluates moments: morale regenerates first (step 8), then the moment lands
	f.morale, p.morale = 50, 50
	sim:step()
	assertEq(#momentEvents(sim), 2)
	assertTrue(f.morale > 50 + MomentDefs.MoraleLimit - 1 and f.morale <= 50 + MomentDefs.MoraleLimit + 0.5, "boost bounded: " .. f.morale)
	assertTrue(p.morale >= 50 - MomentDefs.MoraleLimit - 0.5 and p.morale < 50 - MomentDefs.MoraleLimit + 1, "shock bounded: " .. p.morale)
	assertEq(sim.weather, "rain", "weather set")
	sim:step()
	assertTrue(cav.state ~= "offmap", "released at once")
end)

test("Moments are deterministic: same seed, same moments at the same ticks", function()
	local function play()
		local sim = fixture({
			{ id = "near", title = "Near", text = "n.", when = { formationNear = { faction = "france", name = "34e", objective = "closewitz", radius = 200 } } },
			{ id = "late", title = "Late", text = "l.", when = { time = 20, weatherCleared = true } },
		}, 11)
		sim:queueCommand({ matchId = "m", requestId = "r", kind = "Move", ids = { 2 }, data = { pos = { x = 950, z = 470 } } }, "france")
		local out = {}
		for _ = 1, 60 / Config.Sim.DT do
			sim:step()
			for _, ev in momentEvents(sim) do
				out[#out + 1] = ev.momentId .. "@" .. ev.tick
			end
			sim:clearEvents()
		end
		return table.concat(out, ",")
	end
	local a = play()
	assertEq(play(), a)
	assertTrue(string.find(a, "near@", 1, true) ~= nil and string.find(a, "late@", 1, true) ~= nil, "both fired: " .. a)
end)

