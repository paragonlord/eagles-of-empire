--!strict
-- Remote wrapper. Owns requestId generation, client-side validation and a send queue
-- throttled under the server rate limit. Everything else talks to Net, never to remotes.

local Players = game:GetService("Players") :: Players
local RunService = game:GetService("RunService") :: RunService

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Protocol = require(Shared.Protocol)
local Signal = require(script.Parent.Signal)

local Net = {}

Net.onSnapshot = Signal.new()
Net.onMatchState = Signal.new()
Net.onResult = Signal.new()
Net.onDebug = Signal.new()
Net.onCampaign = Signal.new() -- ({kind="view"|"error", ...})
Net.onPing = Signal.new() -- ({userId, name, x, z, kind, tick}) co-op map pings

local remotes: { [string]: RemoteEvent } = {}
local connections: { RBXScriptConnection } = {}
local counter = 0
local matchId: string = ""
local ctxFn: (() -> any)? = nil -- builds a Protocol.ValidateContext at send time
local queue: { { remote: RemoteEvent, payload: any } } = {}
local sentThisSecond = 0
local secondStart = 0
local initialised = false

local playerId: string = tostring((Players.LocalPlayer :: Player).UserId)

local function nextRequestId(): string
	counter += 1
	return playerId .. ":" .. counter
end

local function drain()
	local now = os.clock()
	if now - secondStart >= 1 then
		secondStart = now
		sentThisSecond = 0
	end
	-- leave headroom under Config.Net.RequestsPerSecond for control messages
	while #queue > 0 and sentThisSecond < Config.Net.RequestsPerSecond - 4 do
		local item = table.remove(queue, 1) :: any
		item.remote:FireServer(item.payload)
		sentThisSecond += 1
	end
end

function Net.init()
	if initialised then
		return
	end
	initialised = true
	local folder = Shared:WaitForChild("Remotes")
	for _, name in { "Command", "Control", "CommandResult", "Snapshot", "MatchState", "Campaign", "Debug" } do
		local r = folder:WaitForChild(name, 30)
		if r then
			remotes[name] = r :: RemoteEvent
		else
			warn("[EoE] remote missing: " .. name)
		end
	end
	local function hook(name: string, sig: Signal.Signal)
		local r = remotes[name]
		if r then
			table.insert(connections, r.OnClientEvent:Connect(function(payload: any)
				sig:Fire(payload)
			end))
		end
	end
	hook(Protocol.Remotes.Snapshot, Net.onSnapshot)
	hook(Protocol.Remotes.MatchState, Net.onMatchState)
	hook(Protocol.Remotes.CommandResult, Net.onResult)
	hook(Protocol.Remotes.Debug, Net.onDebug)
	hook(Protocol.Remotes.Campaign, Net.onCampaign)
	table.insert(connections, RunService.Heartbeat:Connect(drain))
	-- co-op remote: an older server has none, so never block start-up on it
	task.spawn(function()
		local r = folder:WaitForChild("Ping", 60) :: RemoteEvent?
		if r then
			table.insert(connections, r.OnClientEvent:Connect(function(payload: any)
				Net.onPing:Fire(payload)
			end))
		end
	end)
end

function Net.setMatch(id: string, validateCtx: (() -> any)?)
	matchId = id
	ctxFn = validateCtx
end

function Net.matchId(): string
	return matchId
end

-- Returns requestId on success, or nil plus the validation reason.
function Net.send(kind: string, ids: { number }, data: { [string]: any }?): (string?, string?)
	local cmd = { matchId = matchId, requestId = nextRequestId(), kind = kind, ids = ids, data = data or {} }
	if ctxFn then
		local ok, reason = Protocol.validateCommand(cmd, ctxFn())
		if not ok then
			return nil, reason
		end
	end
	local r = remotes[Protocol.Remotes.Command]
	if not r then
		return nil, "No connection"
	end
	table.insert(queue, { remote = r, payload = cmd })
	return cmd.requestId, nil
end

function Net.control(action: string, value: any): string?
	local r = remotes[Protocol.Remotes.Control]
	if not r then
		return nil
	end
	local msg = { matchId = matchId, requestId = nextRequestId(), action = action, value = value }
	local ok, reason = Protocol.validateControl(msg, { matchId = matchId })
	if not ok then
		warn("[EoE] control rejected locally: " .. tostring(reason))
		return nil
	end
	r:FireServer(msg)
	return msg.requestId
end

-- Campaign remote: open | new | command | battle | skip | return. Returns the requestId.
function Net.campaign(action: string, data: { [string]: any }?): string?
	local r = remotes[Protocol.Remotes.Campaign]
	if not r then
		return nil
	end
	local msg = { requestId = nextRequestId(), action = action, data = data or {} }
	r:FireServer(msg)
	return msg.requestId
end

return Net
