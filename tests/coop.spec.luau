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
