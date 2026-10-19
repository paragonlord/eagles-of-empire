--!strict
-- Client-side mirror of the match: merged snapshot data, pending orders, match metadata.
-- Every other client module reads from here; nothing reads cosmetic parts for gameplay.

local Signal = require(script.Parent.Signal)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)

export type Vec = { x: number, z: number }

export type Formation = {
	id: number,
	faction: string,
	name: string?,
	corps: string?,
	class: string,
	type: string?, -- Config.UnitTypes id
	garrison: string?, -- strongpoint id while inside a building
	colour: string?,
	x: number,
	z: number,
	heading: number,
	shape: string,
	state: string,
	strength: number,
	startStrength: number,
	morale: number?,
	moraleBand: string,
	fatigue: number?,
	ammo: number?,
	reload: number?,
	cohesion: number?,
	width: number,
	depth: number,
	orderKind: string?,
	running: boolean?,
	fireByRank: boolean?,
	targetId: number?,
	fireAtWill: boolean?,
	limbered: boolean?,
	status: string?,
	rallyCd: number?,
	commander: boolean?,
	dest: Vec?,
	destHeading: number?,
	experience: number?,
	ammoMode: string?,
	queue: { Vec }?,
}

export type LastKnown = {
	id: number,
	faction: string,
	class: string,
	x: number,
	z: number,
	heading: number,
	shape: string,
	ageSeconds: number,
	name: string?,
	colour: string?,
	width: number,
	depth: number,
}

export type Objective = {
	id: string,
	name: string,
	x: number,
	z: number,
	radius: number,
	owner: string?,
	contested: boolean,
	progress: number,
	capturing: string?,
}

export type Event = {
	kind: string,
	x: number?,
	z: number?,
	id: number?,
	targetId: number?,
	faction: string?,
	text: string?,
	tick: number,
	tx: number?,
	tz: number?,
	n: number?,
}

export type Pending = {
	requestId: string,
	kind: string,
	ids: { number },
	pos: Vec?,
	heading: number?,
	frontage: number?,
	issuedAt: number,
}

local BattleState = {}

BattleState.matchId = ""
BattleState.state = "menu"
BattleState.viewerFaction = ""
BattleState.enemyFaction = ""
BattleState.isCommander = false
-- co-op (docs/coop-contract.md). Absent from an old server / solo: everything is yours.
BattleState.role = "spectator" -- commander | officer | spectator
BattleState.lead = nil :: boolean? -- server's word on leading this side; nil (older server): the commander
BattleState.mode = "coop" -- "coop" | "pvp" (PvP: viewerFaction is this player's side)
BattleState.players = {} :: { { userId: number, name: string, role: string, ready: boolean?, slot: number?, side: string? } }
BattleState.controllers = {} :: { [string]: number } -- formation id (string) -> userId
BattleState.pauseVotes = 0
BattleState.pauseNeeded = 0
BattleState.pings = {} :: { { x: number, z: number, slot: number, kind: string, t0: number } } -- for the minimap
BattleState.userId = 0 -- the local player's, set by Main at boot
BattleState.difficulty = "normal"
BattleState.speed = 1
BattleState.scenario = nil :: any
BattleState.campaignBattle = nil :: any -- {battleId, name} when the match belongs to the campaign
BattleState.map = nil :: any -- MapGen.MapData once built
BattleState.clock = 0
BattleState.timeLimit = 0
BattleState.simLag = 0
BattleState.tick = 0
BattleState.lastSnapshotAt = 0

BattleState.formations = {} :: { [number]: Formation }
BattleState.lastKnown = {} :: { [number]: LastKnown }
BattleState.objectives = {} :: { Objective }
BattleState.reinforcements = {} :: { { id: number, name: string, corps: string, eta: number } } -- own side, off-map
BattleState.pending = {} :: { [string]: Pending }

BattleState.updated = Signal.new() -- (snapshot) after merge
BattleState.event = Signal.new() -- (event) one per snapshot event
BattleState.pendingChanged = Signal.new()
BattleState.orderRejected = Signal.new() -- (reason)

function BattleState.reset()
	table.clear(BattleState.formations)
	table.clear(BattleState.lastKnown)
	BattleState.objectives = {}
	BattleState.reinforcements = {}
	table.clear(BattleState.pending)
	table.clear(BattleState.pings)
	BattleState.clock = 0
	BattleState.tick = 0
	BattleState.simLag = 0
	BattleState.lastSnapshotAt = 0
end

function BattleState.applyMatchState(msg: any)
	BattleState.matchId = msg.matchId or ""
	BattleState.state = msg.state or "menu"
	BattleState.viewerFaction = msg.viewerFaction or ""
	BattleState.isCommander = msg.isCommander == true
	BattleState.role = if type(msg.role) == "string" then msg.role elseif BattleState.isCommander then "commander" else "spectator"
	BattleState.lead = if type(msg.lead) == "boolean" then msg.lead else nil
	BattleState.mode = if msg.mode == "pvp" then "pvp" else "coop"
	BattleState.players = if type(msg.players) == "table" then msg.players else {}
	BattleState.controllers = if type(msg.controllers) == "table" then msg.controllers else {}
	BattleState.pauseVotes = tonumber(msg.pauseVotes) or 0
	BattleState.pauseNeeded = tonumber(msg.pauseNeeded) or 0
	BattleState.difficulty = msg.difficulty or "normal"
	BattleState.speed = msg.speed or 1
	BattleState.scenario = msg.scenario
	BattleState.campaignBattle = msg.campaignBattle
	if msg.scenario and msg.scenario.factions then
		local f = msg.scenario.factions
		BattleState.enemyFaction = if f.player == BattleState.viewerFaction then f.enemy else f.player
	end
end

function BattleState.applySnapshot(snap: any)
	if snap.matchId ~= BattleState.matchId then
		return
	end
	BattleState.tick = snap.tick
	BattleState.clock = snap.clock or 0
	BattleState.timeLimit = snap.timeLimit or 0
	BattleState.speed = snap.speed or BattleState.speed
	BattleState.simLag = snap.simLag or 0
	BattleState.lastSnapshotAt = os.clock()
	if snap.state then
		BattleState.state = snap.state
	end
	local forms = BattleState.formations
	if snap.kind == "full" then
		table.clear(forms)
	elseif snap.removed then
		for _, id in snap.removed do
			forms[id] = nil
		end
	end
	for _, f in snap.formations do
		forms[f.id] = f
	end
	-- lastKnown is sent whole each snapshot
	table.clear(BattleState.lastKnown)
	for _, lk in snap.lastKnown or {} do
		if forms[lk.id] == nil then
			BattleState.lastKnown[lk.id] = lk
		end
	end
	if snap.objectives then
		BattleState.objectives = snap.objectives
	end
	if snap.reinforcements then
		BattleState.reinforcements = snap.reinforcements
	elseif snap.kind == "full" then
		BattleState.reinforcements = {}
	end
	BattleState.updated:Fire(snap)
	for _, ev in snap.events or {} do
		BattleState.event:Fire(ev)
	end
end

function BattleState.addPending(p: Pending)
	BattleState.pending[p.requestId] = p
	BattleState.pendingChanged:Fire()
end

function BattleState.applyResult(res: any)
	local p = BattleState.pending[res.requestId]
	if not p then
		return
	end
	BattleState.pending[res.requestId] = nil
	if not res.accepted then
		BattleState.orderRejected:Fire(res.reason or "Order refused")
	end
	BattleState.pendingChanged:Fire()
end

-- Drop pending ghosts that never got an answer (lost packet, server restart).
function BattleState.expirePending(maxAge: number)
	local now = os.clock()
	local changed = false
	for id, p in BattleState.pending do
		if now - p.issuedAt > maxAge then
			BattleState.pending[id] = nil
			changed = true
		end
	end
	if changed then
		BattleState.pendingChanged:Fire()
	end
end

function BattleState.isOwn(f: { faction: string }): boolean
	return f.faction == BattleState.viewerFaction
end

-- ------------------------------------------------------------------ co-op

-- More than one player in the match: co-op UI shows; otherwise it stays inert.
function BattleState.coop(): boolean
	return #BattleState.players > 1
end

-- Leads this side: its HQ and reach over every own formation (co-op: the commander).
function BattleState.isLead(): boolean
	if BattleState.lead ~= nil then
		return BattleState.lead
	end
	return BattleState.role == "commander"
end

function BattleState.pvp(): boolean
	return BattleState.mode == "pvp"
end

-- The two sides, own first, each with its commanding players: { { faction, players } }.
-- Players without a side (co-op, older server) count for the scenario's player faction.
function BattleState.sides(): { { faction: string, players: { any } } }
	local sc = BattleState.scenario
	local f = if type(sc) == "table" then sc.factions else nil
	if type(f) ~= "table" then
		return {}
	end
	local out = { { faction = f.player, players = {} }, { faction = f.enemy, players = {} } }
	for _, p in BattleState.players do
		if p.role ~= "spectator" then
			table.insert(out[if p.side == f.enemy then 2 else 1].players, p)
		end
	end
	if BattleState.viewerFaction == f.enemy then
		out[1], out[2] = out[2], out[1]
	end
	return out
end

-- May this client give orders at all (commander or officer)?
function BattleState.canOrder(): boolean
	return BattleState.role == "commander" or BattleState.role == "officer"
end

function BattleState.controllerOf(id: number): number?
	return BattleState.controllers[tostring(id)]
end

-- Own faction and in this player's wing. Solo, or no wings sent: every own formation.
function BattleState.isMine(id: number): boolean
	local f = BattleState.formations[id]
	if not f or f.faction ~= BattleState.viewerFaction then
		return false
	end
	if not BattleState.coop() or next(BattleState.controllers) == nil then
		return true
	end
	local c = BattleState.controllerOf(id)
	if c == nil then
		return BattleState.isLead() -- unassigned stays with the side's lead
	end
	return c == BattleState.userId
end

-- Selectable / orderable: your wing, or any own formation for the commander.
function BattleState.canCommand(id: number): boolean
	if BattleState.isMine(id) then
		return true
	end
	local f = BattleState.formations[id]
	return BattleState.isLead() and f ~= nil and f.faction == BattleState.viewerFaction
end

function BattleState.player(userId: number?): any
	for _, p in BattleState.players do
		if p.userId == userId then
			return p
		end
	end
	return nil
end

-- The ally commanding a formation that is not ours (nil when it is ours or solo).
function BattleState.allyOf(id: number): any
	local f = BattleState.formations[id]
	if not BattleState.coop() or not f or f.faction ~= BattleState.viewerFaction or BattleState.isMine(id) then
		return nil -- the other side's officers stay anonymous
	end
	return BattleState.player(BattleState.controllerOf(id))
end

-- Pause button text in co-op ("Vote pause (1/2)"); nil solo.
function BattleState.pauseLabel(): string?
	local n = 0
	for _, p in BattleState.players do
		if p.role ~= "spectator" then
			n += 1
		end
	end
	if n <= 1 then
		return nil
	end
	local need = if BattleState.pauseNeeded > 0 then BattleState.pauseNeeded else math.ceil(n / 2)
	local verb = if BattleState.state == "paused" then "resume" else "pause"
	return string.format("Vote %s (%d/%d)", verb, BattleState.pauseVotes, need)
end

function BattleState.ownFormations(): { Formation }
	local out = {}
	for _, f in BattleState.formations do
		if f.faction == BattleState.viewerFaction then
			table.insert(out, f)
		end
	end
	table.sort(out, function(a: Formation, b: Formation)
		return a.id < b.id
	end)
	return out
end

-- Camera yaw for this side: from its deploy zone toward the enemy's, snapped to 90° so the
-- ground labels line up. Nil when a zone is missing (the camera keeps looking north).
function BattleState.sideYaw(): number?
	local m = BattleState.map
	local zones = if m then m.deployZones else nil
	local own = zones and zones[BattleState.viewerFaction]
	local foe = zones and zones[BattleState.enemyFaction]
	if not own or not foe then
		return nil
	end
	local dx = (foe.x0 + foe.x1 - own.x0 - own.x1) / 2
	local dz = (foe.z0 + foe.z1 - own.z0 - own.z1) / 2
	return math.round(math.atan2(dz, dx) / (math.pi / 2)) * (math.pi / 2)
end

-- Centre of the viewer's army (or the map centre when nothing is fielded).
function BattleState.armyCentre(): Vec
	local sx, sz, n = 0, 0, 0
	for _, f in BattleState.formations do
		if f.faction == BattleState.viewerFaction then
			sx += f.x
			sz += f.z
			n += 1
		end
	end
	if n == 0 then
		local m = BattleState.map
		return { x = if m then m.width / 2 else 800, z = if m then m.depth / 2 else 600 }
	end
	return { x = sx / n, z = sz / n }
end

-- Validation context for Protocol.validateCommand.
function BattleState.validateContext(): any
	return {
		matchId = BattleState.matchId,
		state = BattleState.state,
		mapWidth = if BattleState.map then BattleState.map.width else 1600,
		mapDepth = if BattleState.map then BattleState.map.depth else 1200,
		isOwned = BattleState.canCommand,
		classOf = function(id: number): string?
			local f = BattleState.formations[id]
			return if f then f.class else nil
		end,
		legalShapes = function(id: number): { [string]: boolean }?
			local f = BattleState.formations[id]
			if not f then
				return nil
			end
			local stats = f.type and Config.TypeStats[f.type]
			if stats and (f.class == "infantry" or f.class == "cavalry") then
				return stats.legalShapes
			elseif f.class == "infantry" then
				return { line = true, column = true, square = true }
			elseif f.class == "cavalry" then
				return { wedge = true, line = true }
			end
			return nil
		end,
	}
end

return BattleState
