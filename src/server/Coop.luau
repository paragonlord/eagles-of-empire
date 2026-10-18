--!strict
-- Co-op (2–4 players vs AI) and PvP (two human sides): roster roles, slots and sides, the wing
-- split, AI side and vote thresholds.
-- Pure Luau; MatchService adapts it to Roblox players. Contract: docs/coop-contract.md.

export type Role = "commander" | "officer" | "spectator"
export type Side = "player" | "enemy" -- the scenario's factions.player / factions.enemy
export type Member = { userId: number, name: string, role: Role, slot: number?, side: Side }
export type Roster = { members: { Member }, pvp: boolean } -- join order; sides count only when pvp
export type SplitFormation = { id: number, class: string, pos: { x: number, z: number } }
export type Rect = { x0: number, z0: number, x1: number, z1: number }

local Coop = {}

Coop.MaxCommanding = 4

function Coop.newRoster(): Roster
	return { members = {}, pvp = false }
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

-- The side a player commands and views. Co-op: always "player". PvP: a commanding player's own
-- side; spectators (and strangers) see the host's side, so they cannot scout for either.
function Coop.sideOf(roster: Roster, userId: number): Side
	if not roster.pvp then
		return "player"
	end
	local mem = Coop.find(roster, userId)
	if mem and mem.role ~= "spectator" then
		return mem.side
	end
	local host = Coop.commander(roster)
	return if host then host.side else "player"
end

-- Commanding players' userIds in join order, optionally only those of one side.
function Coop.commanding(roster: Roster, side: Side?): { number }
	local out = {}
	for _, mem in roster.members do
		if mem.role ~= "spectator" and (side == nil or Coop.sideOf(roster, mem.userId) == side) then
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
	-- joins the side with fewer commanding players (ties: the player side)
	local p, e = 0, 0
	for _, o in roster.members do
		if o.role ~= "spectator" then
			if o.side == "enemy" then
				e += 1
			else
				p += 1
			end
		end
	end
	mem.side = if e < p then "enemy" else "player"
	mem.role = if Coop.commander(roster) then "officer" else "commander"
	return true
end

function Coop.add(roster: Roster, userId: number, name: string): Member
	local mem = Coop.find(roster, userId)
	if mem then
		return mem
	end
	local m: Member = { userId = userId, name = name, role = "spectator", slot = nil, side = "player" }
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

-- The side's lead (its HQ, abilities and reach over every formation of the side): the host
-- when on that side, else the side's first commanding player in join order.
function Coop.lead(roster: Roster, side: Side): number?
	local host = Coop.commander(roster)
	if host and Coop.sideOf(roster, host.userId) == side then
		return host.userId
	end
	return Coop.commanding(roster, side)[1]
end

function Coop.isLead(roster: Roster, userId: number): boolean
	return Coop.roleOf(roster, userId) ~= "spectator" and Coop.lead(roster, Coop.sideOf(roster, userId)) == userId
end

-- A commanding player picks a side. False for spectators and strangers.
function Coop.setSide(roster: Roster, userId: number, side: Side): boolean
	local mem = Coop.find(roster, userId)
	if not mem or mem.role == "spectator" then
		return false
	end
	mem.side = side
	return true
end

-- A new match: everyone back on the player side; PvP players pick again.
function Coop.resetSides(roster: Roster)
	for _, mem in roster.members do
		mem.side = "player"
	end
end

-- Host force-balance: the host keeps their side, the others alternate in join order starting
-- on the other side (1v1, 2v1, 2v2).
function Coop.balance(roster: Roster)
	local host = Coop.commander(roster)
	local hs: Side = if host then host.side else "player"
	local other: Side = if hs == "player" then "enemy" else "player"
	local i = 0
	for _, mem in roster.members do
		if mem.role ~= "spectator" and mem ~= host then
			i += 1
			mem.side = if i % 2 == 1 then other else hs
		end
	end
end

-- The side the AI runs: co-op always the enemy; PvP the side without humans (nil when both
-- have some; the enemy when neither does).
function Coop.aiSide(roster: Roster): Side?
	if not roster.pvp then
		return "enemy"
	end
	local p, e = #Coop.commanding(roster, "player"), #Coop.commanding(roster, "enemy")
	if p > 0 and e > 0 then
		return nil
	end
	return if p == 0 and e > 0 then "player" else "enemy"
end

function Coop.sideFaction(factions: { player: string, enemy: string }, side: Side): string
	return if side == "enemy" then factions.enemy else factions.player
end

function Coop.sideFor(factions: { player: string, enemy: string }, faction: any): Side?
	return if faction == factions.player then "player" elseif faction == factions.enemy then "enemy" else nil
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

-- ⌈n/2⌉ in co-op; every commanding player in PvP.
function Coop.votesNeeded(n: number, pvp: boolean?): number
	return math.max(1, if pvp then n else math.ceil(n / 2))
end

-- Records a pause/resume vote. Passes at votesNeeded, or at once when `decisive` (the
-- commander's resume in co-op, anyone's resume in PvP). Returns passed, votes cast.
function Coop.vote(votes: { [number]: boolean }, userId: number, n: number, decisive: boolean, pvp: boolean?): (boolean, number)
	votes[userId] = true
	local count = 0
	for _ in votes do
		count += 1
	end
	return decisive or count >= Coop.votesNeeded(n, pvp), count
end

return Coop
