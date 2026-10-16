--!strict
-- Per-player request gate: rate limiting and request-id de-duplication. Pure Luau; the
-- caller injects real elapsed time (never the paused battle clock).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Protocol = require(Shared.Protocol)

export type PlayerGate = {
	stamps: { number }, -- recent request times (ring)
	head: number,
	seen: { [string]: boolean },
	seenOrder: { string },
	seenHead: number,
}

export type Gate = { players: { [any]: PlayerGate } }

local CommandGate = {}

local WINDOW = Config.Net.RequestsPerSecond
local DEDUPE = Config.Net.DedupeWindow

function CommandGate.new(): Gate
	return { players = {} }
end

local function playerGate(gate: Gate, key: any): PlayerGate
	local pg = gate.players[key]
	if not pg then
		pg = { stamps = table.create(WINDOW, -math.huge), head = 1, seen = {}, seenOrder = table.create(DEDUPE, ""), seenHead = 1 }
		gate.players[key] = pg
	end
	return pg
end

-- Returns ok, reason. Records the request when accepted.
function CommandGate.check(gate: Gate, key: any, requestId: string, now: number): (boolean, string?)
	local pg = playerGate(gate, key)
	if pg.seen[requestId] then
		return false, Protocol.Reasons.duplicate
	end
	-- Sliding window: the oldest of the last WINDOW requests must be more than 1 s ago.
	local oldest = pg.stamps[pg.head]
	if now - oldest < 1 then
		return false, Protocol.Reasons.rateLimited
	end
	pg.stamps[pg.head] = now
	pg.head = pg.head % WINDOW + 1
	-- Remember the id (bounded).
	local evict = pg.seenOrder[pg.seenHead]
	if evict ~= "" then
		pg.seen[evict] = nil
	end
	pg.seenOrder[pg.seenHead] = requestId
	pg.seen[requestId] = true
	pg.seenHead = pg.seenHead % DEDUPE + 1
	return true, nil
end

function CommandGate.forget(gate: Gate, key: any)
	gate.players[key] = nil
end

return CommandGate
