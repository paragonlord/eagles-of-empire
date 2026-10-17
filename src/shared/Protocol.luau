--!strict
-- Client ↔ server protocol: remote names, command kinds, limits and the pure validator.
-- The server is the only authority; the client may run the same validator for early feedback.

local Config = require(script.Parent.Config)
local Vec = require(script.Parent.Vec)

type Vec = Vec.Vec

local Protocol = {}

Protocol.Remotes = {
	Command = "Command",
	Control = "Control",
	CommandResult = "CommandResult",
	Snapshot = "Snapshot",
	MatchState = "MatchState",
	Campaign = "Campaign",
	Debug = "Debug",
}

-- kind -> allowed unit classes (false = any class)
Protocol.CommandKinds = {
	Move = false,
	AttackMove = { infantry = true, cavalry = true },
	Engage = { infantry = true, cavalry = true, artillery = true },
	Stop = false,
	Hold = false,
	Face = false,
	Retreat = false,
	Shape = { infantry = true, cavalry = true },
	Stance = { infantry = true, artillery = true },
	Charge = { infantry = true, cavalry = true },
	Rally = { hq = true },
	Limber = { artillery = true },
	Deploy = false, -- pre-battle placement
	Ammo = { artillery = true }, -- choose roundShot / canister preference
} :: { [string]: { [string]: boolean } | false }

Protocol.ControlActions = {
	start = true,
	pause = true,
	resume = true,
	speed = true,
	restart = true,
	ready = true,
	difficulty = true,
	quit = true,
	spectate = true,
	tutorialStep = true, -- tutorial scenario: value = step number reached (MatchService validates)
}

Protocol.Reasons = {
	ok = "ok",
	badRequest = "Malformed request",
	wrongMatch = "Request is for a different match",
	notCommander = "Only the commander may issue orders",
	badKind = "Unknown command",
	badIds = "Formation list is empty or too long",
	notOwned = "That formation is not yours",
	wrongClass = "That unit cannot take this order",
	badPosition = "Position is off the battlefield",
	badHeading = "Invalid facing",
	badTarget = "Invalid target",
	badShape = "That formation cannot adopt this shape",
	badState = "Not available in this match state",
	rateLimited = "Too many requests",
	duplicate = "Duplicate request",
	routing = "A routing formation cannot take orders",
	destroyed = "That formation is no longer in the field",
	cooldown = "Ability is recharging",
	noSpace = "Not enough room there",
	unreachable = "No route to that position",
	deployZone = "Outside your deployment zone",
	notPaused = "Only the commander may pause",
}

export type ValidateContext = {
	matchId: string,
	state: string, -- deployment | running | paused | ...
	mapWidth: number,
	mapDepth: number,
	isOwned: (id: number) -> boolean,
	classOf: (id: number) -> string?,
	legalShapes: (id: number) -> { [string]: boolean }?,
}

local MAX_REQUEST_ID = 48

local function finiteNumber(n: any): boolean
	return type(n) == "number" and n == n and math.abs(n) ~= math.huge
end

local function checkIds(ids: any, ctx: ValidateContext, kind: string): (boolean, string?)
	if type(ids) ~= "table" then
		return false, Protocol.Reasons.badIds
	end
	local n = #ids
	if n < 1 or n > Config.Net.MaxBatch then
		return false, Protocol.Reasons.badIds
	end
	local allowed = Protocol.CommandKinds[kind]
	local seen: { [number]: boolean } = {}
	for i = 1, n do
		local id = ids[i]
		if type(id) ~= "number" or id ~= math.floor(id) or id < 1 or seen[id] then
			return false, Protocol.Reasons.badIds
		end
		seen[id] = true
		if not ctx.isOwned(id) then
			return false, Protocol.Reasons.notOwned
		end
		if type(allowed) == "table" then
			local cls = ctx.classOf(id)
			if not cls or not allowed[cls] then
				return false, Protocol.Reasons.wrongClass
			end
		end
	end
	return true, nil
end

local function checkPos(p: any, ctx: ValidateContext): (boolean, string?)
	if not Vec.isFinite(p) then
		return false, Protocol.Reasons.badPosition
	end
	if p.x < 0 or p.z < 0 or p.x >= ctx.mapWidth or p.z >= ctx.mapDepth then
		return false, Protocol.Reasons.badPosition
	end
	return true, nil
end

local function checkHeading(h: any, optional: boolean): (boolean, string?)
	if h == nil and optional then
		return true, nil
	end
	if not finiteNumber(h) then
		return false, Protocol.Reasons.badHeading
	end
	return true, nil
end

-- Returns ok, reason. Structural + ownership validation only; game-state validity
-- (reachability, cooldowns, routing) is decided by the simulation when the command applies.
function Protocol.validateCommand(cmd: any, ctx: ValidateContext): (boolean, string?)
	if type(cmd) ~= "table" then
		return false, Protocol.Reasons.badRequest
	end
	if type(cmd.requestId) ~= "string" or #cmd.requestId == 0 or #cmd.requestId > MAX_REQUEST_ID then
		return false, Protocol.Reasons.badRequest
	end
	if cmd.matchId ~= ctx.matchId then
		return false, Protocol.Reasons.wrongMatch
	end
	local kind = cmd.kind
	if type(kind) ~= "string" or Protocol.CommandKinds[kind] == nil then
		return false, Protocol.Reasons.badKind
	end
	local okIds, reasonIds = checkIds(cmd.ids, ctx, kind)
	if not okIds then
		return false, reasonIds
	end
	local data = cmd.data
	if data ~= nil and type(data) ~= "table" then
		return false, Protocol.Reasons.badRequest
	end
	data = data or {}
	if data.queue ~= nil and type(data.queue) ~= "boolean" then
		return false, Protocol.Reasons.badRequest
	end

	if kind == "Deploy" then
		if ctx.state ~= "deployment" then
			return false, Protocol.Reasons.badState
		end
		local okP, rP = checkPos(data.pos, ctx)
		if not okP then
			return false, rP
		end
		return checkHeading(data.heading, false)
	end

	if ctx.state ~= "running" and ctx.state ~= "paused" then
		return false, Protocol.Reasons.badState
	end

	if kind == "Move" or kind == "AttackMove" or kind == "Retreat" then
		if kind ~= "Retreat" or data.pos ~= nil then
			local okP, rP = checkPos(data.pos, ctx)
			if not okP then
				return false, rP
			end
		end
		local okH, rH = checkHeading(data.heading, true)
		if not okH then
			return false, rH
		end
		if data.frontage ~= nil and (not finiteNumber(data.frontage) or data.frontage < 0 or data.frontage > ctx.mapWidth) then
			return false, Protocol.Reasons.badRequest
		end
		return true, nil
	elseif kind == "Engage" or kind == "Charge" then
		local t = data.targetId
		if kind == "Charge" and t == nil then
			-- bayonet/cavalry charge toward a position is allowed
			local okP, rP = checkPos(data.pos, ctx)
			if not okP then
				return false, rP
			end
			return true, nil
		end
		if type(t) ~= "number" or t ~= math.floor(t) or t < 1 then
			return false, Protocol.Reasons.badTarget
		end
		if ctx.isOwned(t) then
			return false, Protocol.Reasons.badTarget
		end
		return true, nil
	elseif kind == "Face" then
		return checkHeading(data.heading, false)
	elseif kind == "Shape" then
		if type(data.shape) ~= "string" then
			return false, Protocol.Reasons.badShape
		end
		for _, id in cmd.ids do
			local legal = ctx.legalShapes(id)
			if not legal or not legal[data.shape] then
				return false, Protocol.Reasons.badShape
			end
		end
		return true, nil
	elseif kind == "Stance" then
		if type(data.fireAtWill) ~= "boolean" then
			return false, Protocol.Reasons.badRequest
		end
		return true, nil
	elseif kind == "Limber" then
		if type(data.limbered) ~= "boolean" then
			return false, Protocol.Reasons.badRequest
		end
		return true, nil
	elseif kind == "Ammo" then
		if data.ammo ~= "roundShot" and data.ammo ~= "canister" and data.ammo ~= "auto" then
			return false, Protocol.Reasons.badRequest
		end
		return true, nil
	elseif kind == "Rally" then
		return true, nil
	elseif kind == "Stop" or kind == "Hold" then
		return true, nil
	end
	return false, Protocol.Reasons.badKind
end

function Protocol.validateControl(msg: any, ctx: { matchId: string }): (boolean, string?)
	if type(msg) ~= "table" then
		return false, Protocol.Reasons.badRequest
	end
	if type(msg.requestId) ~= "string" or #msg.requestId == 0 or #msg.requestId > MAX_REQUEST_ID then
		return false, Protocol.Reasons.badRequest
	end
	if type(msg.action) ~= "string" or not Protocol.ControlActions[msg.action] then
		return false, Protocol.Reasons.badKind
	end
	-- spectate / quit are state requests that do not depend on knowing the current match id
	if msg.action ~= "spectate" and msg.action ~= "quit" and msg.matchId ~= nil and msg.matchId ~= ctx.matchId then
		return false, Protocol.Reasons.wrongMatch
	end
	if msg.action == "speed" then
		local ok = false
		for _, s in Config.Sim.Speeds do
			if msg.value == s then
				ok = true
			end
		end
		if not ok then
			return false, Protocol.Reasons.badRequest
		end
	elseif msg.action == "difficulty" then
		if type(msg.value) ~= "string" or not (Config.AI.Difficulties :: any)[msg.value] then
			return false, Protocol.Reasons.badRequest
		end
	elseif msg.action == "tutorialStep" then
		if type(msg.value) ~= "number" or msg.value ~= math.floor(msg.value) or msg.value < 1 or msg.value > 64 then
			return false, Protocol.Reasons.badRequest
		end
	elseif msg.action == "start" or msg.action == "restart" then
		if msg.value ~= nil and type(msg.value) ~= "string" then
			return false, Protocol.Reasons.badRequest
		end
	end
	return true, nil
end

return Protocol
