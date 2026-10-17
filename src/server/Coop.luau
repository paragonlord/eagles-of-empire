--!strict
-- Co-op (2–4 players vs AI): roster roles and slots, the wing split and vote thresholds.
-- Pure Luau; MatchService adapts it to Roblox players. Contract: docs/coop-contract.md.

export type Role = "commander" | "officer" | "spectator"
export type Member = { userId: number, name: string, role: Role, slot: number? }
export type Roster = { members: { Member } } -- join order
export type SplitFormation = { id: number, class: string, pos: { x: number, z: number } }
export type Rect = { x0: number, z0: number, x1: number, z1: number }

local Coop = {}

Coop.MaxCommanding = 4

function Coop.newRoster(): Roster
	return { members = {} }
end

function Coop.find(roster: Roster, userId: number): Member?
	for _, mem in roster.members do
		if mem.userId == userId then
			return mem
		end
	end
	return nil
end

function Coop.roleOf(roster: Roster, userId: number): Role
	local mem = Coop.find(roster, userId)
	return if mem then mem.role else "spectator"
end

function Coop.commander(roster: Roster): Member?
	for _, mem in roster.members do
		if mem.role == "commander" then
			return mem
		end
	end
	return nil
end

-- Commanding players' userIds in join order.
function Coop.commanding(roster: Roster): { number }
	local out = {}
	for _, mem in roster.members do
		if mem.role ~= "spectator" then
			out[#out + 1] = mem.userId
		end
	end
	return out
end

local function freeSlot(roster: Roster): number?
	local used: { [number]: boolean } = {}
	for _, mem in roster.members do
		if mem.slot then
			used[mem.slot] = true
		end
	end
	for s = 1, Coop.MaxCommanding do
		if not used[s] then
			return s
		end
	end
	return nil
end

-- Makes `mem` commanding (commander if nobody commands). False when all four slots are taken.
local function enlist(roster: Roster, mem: Member): boolean
	if mem.role ~= "spectator" then
		return true
	end
	local slot = freeSlot(roster)
	if not slot then
		return false
	end
	mem.slot = slot
	mem.role = if Coop.commander(roster) then "officer" else "commander"
	return true
end

function Coop.add(roster: Roster, userId: number, name: string): Member
	local mem = Coop.find(roster, userId)
	if mem then
		return mem
	end
	local m: Member = { userId = userId, name = name, role = "spectator", slot = nil }
	table.insert(roster.members, m)
	enlist(roster, m)
	return m
end

-- spectator → officer (or commander when nobody commands). False when no slot is free.
function Coop.join(roster: Roster, userId: number): boolean
	local mem = Coop.find(roster, userId)
	return mem ~= nil and enlist(roster, mem)
end

-- officer → spectator. The commander cannot step down this way.
function Coop.spectate(roster: Roster, userId: number): boolean
	local mem = Coop.find(roster, userId)
	if not mem or mem.role == "commander" then
		return false
	end
	mem.role = "spectator"
	mem.slot = nil
	return true
end

-- Makes `userId` commander when nobody commands (a player claiming an empty seat).
function Coop.claim(roster: Roster, userId: number): boolean
	if Coop.commander(roster) then
		return Coop.roleOf(roster, userId) == "commander"
	end
	local mem = Coop.find(roster, userId)
	if not mem then
		return false
	end
	mem.slot = mem.slot or freeSlot(roster) or 1
	mem.role = "commander"
	return true
end

-- Removes a player; a departing commander hands command to the next commanding player in join
-- order, else to the first remaining spectator. Returns true when the commander left.
function Coop.remove(roster: Roster, userId: number): boolean
	local wasCommander = false
	for i, mem in roster.members do
		if mem.userId == userId then
			wasCommander = mem.role == "commander"
			table.remove(roster.members, i)
			break
		end
	end
	if wasCommander then
		local nextId = Coop.commanding(roster)[1] or (roster.members[1] and roster.members[1].userId)
		if nextId then
			Coop.claim(roster, nextId)
		end
	end
	return wasCommander
end

-- Wings: formations sorted along the deploy zone's long axis, cut into one contiguous wing per
-- commanding player (join order). HQs always go to the commander. Returns { [formationId]: userId }.
function Coop.split(forms: { SplitFormation }, zone: Rect?, players: { number }, commanderId: number): { [number]: number }
	local out: { [number]: number } = {}
	local alongX = zone == nil or (zone.x1 - zone.x0) >= (zone.z1 - zone.z0)
	local line: { SplitFormation } = {}
	for _, f in forms do
		if f.class == "hq" or #players == 0 then
			out[f.id] = commanderId
		else
			line[#line + 1] = f
		end
	end
	table.sort(line, function(a: SplitFormation, b: SplitFormation): boolean
		local ka = if alongX then a.pos.x else a.pos.z
		local kb = if alongX then b.pos.x else b.pos.z
		if ka ~= kb then
			return ka < kb
		end
		return a.id < b.id
	end)
	local n, k = #players, #line
	for i, f in line do
		out[f.id] = players[math.floor((i - 1) * n / k) + 1]
	end
	return out
end

function Coop.votesNeeded(n: number): number
	return math.max(1, math.ceil(n / 2))
end

-- Records a pause/resume vote. Passes at ⌈n/2⌉ votes, or at once when `decisive` (the
-- commander's resume). Returns passed, votes cast.
function Coop.vote(votes: { [number]: boolean }, userId: number, n: number, decisive: boolean): (boolean, number)
	votes[userId] = true
	local count = 0
	for _ in votes do
		count += 1
	end
	return decisive or count >= Coop.votesNeeded(n), count
end

return Coop
