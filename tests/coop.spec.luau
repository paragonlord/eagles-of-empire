-- Co-op: roster roles and slots, the wing split, vote thresholds, co-op Protocol validation.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local Config = require(Shared.Config)
local Protocol = require(Shared.Protocol)
local Coop = require(Server.Coop)

local function forms()
	-- a line along x (wide zone), listed out of order, plus an HQ in the middle
	local out = {}
	for i, x in { 500, 100, 300, 700, 200, 600, 400, 800 } do
		out[#out + 1] = { id = i, class = "infantry", pos = { x = x, z = 50 } }
	end
	out[#out + 1] = { id = 9, class = "hq", pos = { x = 450, z = 40 } }
	return out
end
local ZONE = { x0 = 0, z0 = 0, x1 = 1000, z1 = 200 }

local function owners(split: { [number]: number }, list: { any }): { number }
	-- owners in left-to-right order (HQ excluded)
	local line = {}
	for _, f in list do
		if f.class ~= "hq" then
			line[#line + 1] = f
		end
	end
	table.sort(line, function(a, b)
		return a.pos.x < b.pos.x
	end)
	local out = {}
	for _, f in line do
		out[#out + 1] = split[f.id]
	end
	return out
end

test("Coop.split: HQ to the commander, contiguous wings in join order, re-split on leave", function()
	local list = forms()
	local s = Coop.split(list, ZONE, { 11, 22, 33 }, 11)
	assertEq(s[9], 11, "HQ to commander")
	assertEq(table.concat(owners(s, list), ","), "11,11,11,22,22,22,33,33")
	local s2 = Coop.split(list, ZONE, { 11, 33 }, 11)
	assertEq(s2[9], 11)
	assertEq(table.concat(owners(s2, list), ","), "11,11,11,11,33,33,33,33")
	-- solo: everything to the one player
	local s1 = Coop.split(list, ZONE, { 11 }, 11)
	for _, f in list do
		assertEq(s1[f.id], 11)
	end
	-- a tall zone splits along z
	local tall = {
		{ id = 1, class = "infantry", pos = { x = 900, z = 10 } },
		{ id = 2, class = "infantry", pos = { x = 10, z = 900 } },
	}
	local st = Coop.split(tall, { x0 = 0, z0 = 0, x1 = 100, z1 = 1000 }, { 1, 2 }, 1)
	assertEq(st[1], 1)
	assertEq(st[2], 2)
end)

test("Coop roster: commander first, three officers, then spectators; stable slots; hand-over", function()
	local r = Coop.newRoster()
	for i = 1, 5 do
		Coop.add(r, i, "p" .. i)
	end
	assertEq(Coop.roleOf(r, 1), "commander")
	assertEq(Coop.roleOf(r, 4), "officer")
	assertEq(Coop.roleOf(r, 5), "spectator")
	assertEq(#Coop.commanding(r), 4)
	assertTrue(not Coop.join(r, 5), "no free slot")
	assertTrue(Coop.spectate(r, 3))
	assertTrue(not Coop.spectate(r, 1), "commander cannot spectate")
	assertTrue(Coop.join(r, 5))
	assertEq((Coop.find(r, 5) :: any).slot, 3, "takes the freed slot")
	assertEq((Coop.find(r, 4) :: any).slot, 4, "others keep theirs")
	assertTrue(Coop.remove(r, 1), "commander left")
	assertEq(Coop.roleOf(r, 2), "commander", "next commanding player in join order")
	assertEq((Coop.find(r, 2) :: any).slot, 2)
	assertTrue(not Coop.remove(r, 4))
	assertEq(table.concat(Coop.commanding(r), ","), "2,5")
end)

test("Coop votes: ⌈n/2⌉ to pass, solo immediate, commander resume decisive", function()
	assertEq(Coop.votesNeeded(1), 1)
	assertEq(Coop.votesNeeded(2), 1)
	assertEq(Coop.votesNeeded(3), 2)
	assertEq(Coop.votesNeeded(4), 2)
	assertTrue(Coop.vote({}, 1, 1, false), "solo")
	local v = {}
	assertTrue(not Coop.vote(v, 2, 3, false))
	assertTrue(not Coop.vote(v, 2, 3, false), "one vote per player")
	local passed, n = Coop.vote(v, 3, 3, false)
	assertTrue(passed)
	assertEq(n, 2)
	assertTrue(Coop.vote({}, 1, 4, true), "commander resume")
end)

test("Protocol: assign / ping / join / spectate validation and notYours", function()
	local function ctl(action: string, value: any): string?
		local ok, reason = Protocol.validateControl({ requestId = "r", action = action, value = value }, { matchId = "m" })
		return if ok then "ok" else reason
	end
	assertEq(ctl("join", nil), "ok")
	assertEq(ctl("spectate", nil), "ok")
	assertEq(ctl("spectate", true), "ok")
	assertEq(ctl("spectate", "x"), Protocol.Reasons.badRequest)
	assertEq(ctl("assign", { ids = { 1, 2 }, userId = 7 }), "ok")
	assertEq(ctl("assign", { ids = {}, userId = 7 }), Protocol.Reasons.badIds)
	assertEq(ctl("assign", { ids = { 1, 1 }, userId = 7 }), Protocol.Reasons.badIds)
	assertEq(ctl("assign", { ids = { 1.5 }, userId = 7 }), Protocol.Reasons.badIds)
	local big = {}
	for i = 1, Config.Net.MaxBatch + 1 do
		big[i] = i
	end
	assertEq(ctl("assign", { ids = big, userId = 7 }), Protocol.Reasons.badIds)
	assertEq(ctl("assign", { ids = { 1 }, userId = 0 / 0 }), Protocol.Reasons.badRequest)
	assertEq(ctl("assign", { ids = { 1 } }), Protocol.Reasons.badRequest)
	assertEq(ctl("ping", { x = 10, z = 20, kind = "attack" }), "ok")
	assertEq(ctl("ping", { x = 10, z = 20, kind = "dance" }), Protocol.Reasons.badRequest)
	assertEq(ctl("ping", { x = math.huge, z = 20, kind = "look" }), Protocol.Reasons.badRequest)
	assertEq(ctl("ping", { x = 0 / 0, z = 20, kind = "look" }), Protocol.Reasons.badRequest)
	assertEq(ctl("ping", nil), Protocol.Reasons.badRequest)
	assertTrue(Protocol.Reasons.notYours ~= nil)
	assertEq(Protocol.Remotes.Ping, "Ping")
end)

test("PvP roster: sides on join, leads, AI only for an empty side, balance", function()
	local r = Coop.newRoster()
	Coop.add(r, 1, "host")
	Coop.add(r, 2, "b")
	Coop.add(r, 3, "c")
	-- co-op ignores sides: everyone on the player side, the AI runs the enemy
	assertEq(Coop.sideOf(r, 2), "player")
	assertEq(#Coop.commanding(r, "player"), 3)
	assertEq(Coop.aiSide(r), "enemy")
	assertTrue(Coop.isLead(r, 1) and not Coop.isLead(r, 2), "co-op lead is the host")
	r.pvp = true
	-- joiners fill the smaller side: 1 player, 2 enemy, 3 player
	assertEq(Coop.sideOf(r, 1), "player")
	assertEq(Coop.sideOf(r, 2), "enemy")
	assertEq(Coop.sideOf(r, 3), "player")
	assertEq(Coop.aiSide(r), nil, "humans on both sides: no AI")
	assertEq(Coop.lead(r, "player"), 1)
	assertEq(Coop.lead(r, "enemy"), 2, "the other side's first player leads it")
	assertTrue(Coop.isLead(r, 2) and not Coop.isLead(r, 3))
	-- 2v1 → everyone on the player side: the AI takes the enemy
	assertTrue(Coop.setSide(r, 2, "player"))
	assertEq(Coop.aiSide(r), "enemy")
	assertEq(Coop.lead(r, "enemy"), nil)
	-- the host alone on the enemy side: the AI runs the player side
	Coop.setSide(r, 1, "enemy")
	assertEq(Coop.lead(r, "enemy"), 1)
	assertEq(Coop.lead(r, "player"), 2, "host not there: first in join order")
	Coop.setSide(r, 2, "enemy")
	Coop.setSide(r, 3, "enemy")
	assertEq(Coop.aiSide(r), "player")
	-- balance: host keeps their side, the rest alternate (2v1 with three)
	Coop.balance(r)
	assertEq(Coop.sideOf(r, 1), "enemy")
	assertEq(Coop.sideOf(r, 2), "player")
	assertEq(Coop.sideOf(r, 3), "enemy")
	Coop.add(r, 4, "d")
	assertEq(Coop.sideOf(r, 4), "player", "fourth evens it 2v2")
	assertTrue(not Coop.setSide(r, 99, "player"), "strangers have no side")
end)

test("PvP views: own side's faction; spectators the host's; per-side wing split", function()
	local r = Coop.newRoster()
	r.pvp = true
	for i = 1, 5 do
		Coop.add(r, i, "p" .. i)
	end
	local factions = { player = "france", enemy = "prussia" }
	Coop.setSide(r, 1, "enemy")
	assertEq(Coop.sideFaction(factions, Coop.sideOf(r, 1)), "prussia", "host on the Prussian side")
	assertEq(Coop.sideFaction(factions, Coop.sideOf(r, 2)), "prussia")
	assertEq(Coop.sideFaction(factions, Coop.sideOf(r, 3)), "france")
	assertEq(Coop.sideOf(r, 5), "enemy", "spectator sees the host's side only")
	assertEq(Coop.sideOf(r, 42), "enemy", "so does a stranger")
	assertEq(Coop.sideFor(factions, "prussia"), "enemy")
	assertEq(Coop.sideFor(factions, "france"), "player")
	assertEq(Coop.sideFor(factions, "russia"), nil)
	-- each side's wings split among that side's players, its HQ to its lead
	local list = forms()
	local s = Coop.split(list, ZONE, Coop.commanding(r, "enemy"), Coop.lead(r, "enemy") :: number)
	assertEq(s[9], 1, "HQ to the side's lead")
	assertEq(table.concat(owners(s, list), ","), "1,1,1,2,2,2,4,4", "enemy side is 1, 2 and 4")
	r.pvp = false
	assertEq(Coop.sideOf(r, 1), "player", "co-op: one side again")
end)

test("PvP votes: pausing is unanimous; co-op keeps ⌈n/2⌉", function()
	assertEq(Coop.votesNeeded(2, true), 2)
	assertEq(Coop.votesNeeded(3, true), 3)
	assertEq(Coop.votesNeeded(1, true), 1)
	assertEq(Coop.votesNeeded(4, false), 2)
	local v = {}
	assertTrue(not Coop.vote(v, 1, 3, false, true))
	assertTrue(not Coop.vote(v, 2, 3, false, true))
	assertTrue(Coop.vote(v, 3, 3, false, true), "third of three")
	assertTrue(Coop.vote({}, 2, 4, true, true), "a resume in PvP is decisive")
	local ok = Protocol.validateControl({ requestId = "r", action = "mode", value = "pvp" }, { matchId = "m" })
	assertTrue(ok)
	assertTrue(not (Protocol.validateControl({ requestId = "r", action = "mode", value = "war" }, { matchId = "m" })))
	assertTrue((Protocol.validateControl({ requestId = "r", action = "side", value = "prussia" }, { matchId = "m" })))
	assertTrue(not (Protocol.validateControl({ requestId = "r", action = "side", value = 3 }, { matchId = "m" })))
	assertTrue((Protocol.validateControl({ requestId = "r", action = "balance" }, { matchId = "m" })))
end)

test("PvP results: each side reads victory or defeat from its own view", function()
	local Scenarios = require(Shared.Scenarios)
	local MapGen = require(Shared.MapGen)
	local Sim = require(Server.Sim)
	local sim = Sim.new({ matchId = "r", scenario = Scenarios.jena, map = MapGen.generate(Scenarios.jena.map), seed = 3, difficulty = "normal" })
	sim:start()
	assertEq(sim:buildResults("france", "x").outcome, "victory")
	assertEq(sim:buildResults("france", "x", "prussia").outcome, "defeat")
	assertEq(sim:buildResults("prussia", "x", "prussia").outcome, "victory")
	assertEq(sim:buildResults("draw", "x", "prussia").outcome, "draw")
end)
