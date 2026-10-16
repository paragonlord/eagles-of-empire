--!strict
-- Client-side mirror of the match: merged snapshot data, pending orders, match metadata.
-- Every other client module reads from here; nothing reads cosmetic parts for gameplay.

local Signal = require(script.Parent.Signal)

export type Vec = { x: number, z: number }

export type Formation = {
	id: number,
	faction: string,
	name: string?,
	corps: string?,
	class: string,
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
BattleState.pending = {} :: { [string]: Pending }

BattleState.updated = Signal.new() -- (snapshot) after merge
BattleState.event = Signal.new() -- (event) one per snapshot event
BattleState.pendingChanged = Signal.new()
BattleState.orderRejected = Signal.new() -- (reason)

function BattleState.reset()
	table.clear(BattleState.formations)
	table.clear(BattleState.lastKnown)
	BattleState.objectives = {}
	table.clear(BattleState.pending)
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
		isOwned = function(id: number): boolean
			local f = BattleState.formations[id]
			return f ~= nil and f.faction == BattleState.viewerFaction
		end,
		classOf = function(id: number): string?
			local f = BattleState.formations[id]
			return if f then f.class else nil
		end,
		legalShapes = function(id: number): { [string]: boolean }?
			local f = BattleState.formations[id]
			if not f then
				return nil
			end
			if f.class == "infantry" then
				return { line = true, column = true, square = true }
			elseif f.class == "cavalry" then
				return { wedge = true, line = true }
			end
			return nil
		end,
	}
end

return BattleState
