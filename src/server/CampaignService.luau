--!strict
-- Campaign session for the commander: profile load/continue, turns, battle hand-off to the
-- tactical match and exactly-once result commits. Talks to clients over the Campaign remote.
--
-- Client → server: { requestId, action, data }  actions: open | new | command | battle | skip | return
-- Server → client: { kind = "view", view, sessionOnly, battleId? } | { kind = "error", requestId, reason }

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("EoE")
local Scenarios = require(Shared.Scenarios)
local Types = require(Shared.Types)

local Campaign = require(script.Parent.Campaign)
local ProfileStore = require(script.Parent.Persist.ProfileStore)

type State = Campaign.State

type Session = {
	userId: number,
	sessionId: string,
	state: State?,
	activeBattleId: string?,
	activeScenario: Scenarios.Scenario?,
	committed: { [string]: boolean },
	renewAt: number,
}

export type Hooks = {
	isCommander: (Player) -> boolean,
	startBattle: (scenario: Scenarios.Scenario, battleId: string) -> (),
}

local CampaignService = {}

local remote: RemoteEvent
local hooks: Hooks
local store: ProfileStore.Store
local session: Session? = nil

local function send(player: Player, payload: any)
	remote:FireClient(player, payload)
end

local function sendError(player: Player, requestId: string, reason: string)
	send(player, { kind = "error", requestId = requestId, reason = reason })
end

local function sendView(player: Player, s: Session)
	if s.state then
		send(player, { kind = "view", view = Campaign.view(s.state), sessionOnly = store.sessionOnly, battleId = s.activeBattleId })
	end
end

local function newSessionId(): string
	return string.format("%s-%d-%d", game.JobId ~= "" and game.JobId or "studio", os.time(), math.random(1, 1e6))
end

-- Load or create the commander's session. Returns nil + reason on failure (never defaults
-- over a profile that could not be read).
local function ensureSession(player: Player): (Session?, string?)
	local s = session
	if s and s.userId == player.UserId then
		return s, nil
	end
	local sessionId = newSessionId()
	local okClaim, whyClaim = store:claimSession(player.UserId, sessionId, os.time())
	if not okClaim then
		return nil, if whyClaim == "locked" then "Your campaign is open in another server; try again in a minute" else "Could not claim your campaign: " .. tostring(whyClaim)
	end
	local profile, status = store:load(player.UserId)
	if status == "error" then
		store:releaseSession(player.UserId, sessionId)
		return nil, "Could not load your campaign. Nothing was changed; try again"
	end
	local state: State? = nil
	if profile then
		state = Campaign.deserialize(profile)
	end
	if not state then
		state = Campaign.new(os.time())
		if profile and type(profile.revision) == "number" then
			state.revision = profile.revision
		end
	end
	local created: Session = { userId = player.UserId, sessionId = sessionId, state = state, activeBattleId = nil, activeScenario = nil, committed = {}, renewAt = os.clock() + 60 }
	session = created
	return created, nil
end

local function checkpoint(player: Player, s: Session, requestId: string): boolean
	local ok, reason = Campaign.checkpoint(store, s.userId, s.sessionId, s.state :: State)
	if not ok then
		sendError(player, requestId, "Could not save the campaign (" .. tostring(reason) .. ")" .. (if store.sessionOnly then "" else "; progress since the last save may be lost"))
	end
	return ok
end

local function onRemote(player: Player, msg: any)
	if type(msg) ~= "table" or type(msg.requestId) ~= "string" or #msg.requestId > 48 or type(msg.action) ~= "string" then
		return
	end
	local requestId: string = msg.requestId
	if not hooks.isCommander(player) then
		sendError(player, requestId, "Only the commander may run the campaign")
		return
	end
	local s, why = ensureSession(player)
	if not s then
		sendError(player, requestId, why or "Campaign unavailable")
		return
	end
	local state = s.state :: State
	local action = msg.action
	local data = if type(msg.data) == "table" then msg.data else {}
	if action == "open" or action == "return" then
		sendView(player, s)
	elseif action == "new" then
		local fresh = Campaign.new(os.time())
		fresh.revision = state.revision
		s.state = fresh
		s.activeBattleId = nil
		s.activeScenario = nil
		s.committed = {}
		checkpoint(player, s, requestId)
		sendView(player, s)
	elseif action == "command" then
		if s.activeBattleId then
			sendError(player, requestId, "Finish the pending battle first")
			return
		end
		local cmd: Campaign.Command = { kind = tostring(data.kind), armyId = if type(data.armyId) == "number" then data.armyId else nil, regionId = if type(data.regionId) == "string" then data.regionId else nil, unitType = if type(data.unitType) == "string" then data.unitType else nil }
		local ok, reason = Campaign.command(state, cmd)
		if not ok then
			sendError(player, requestId, reason or "Not allowed")
		elseif cmd.kind == "endTurn" or cmd.kind == "restart" then
			checkpoint(player, s, requestId)
		end
		sendView(player, s)
	elseif action == "battle" then
		local pending = state.pendingBattles[1]
		if not pending then
			sendError(player, requestId, "No battle is pending")
			return
		end
		local scenario = Campaign.battleScenario(state, pending.battleId)
		if not scenario then
			sendError(player, requestId, "Could not build the battle")
			return
		end
		if not checkpoint(player, s, requestId) and not store.sessionOnly then
			return
		end
		s.activeBattleId = pending.battleId
		s.activeScenario = scenario
		hooks.startBattle(scenario, pending.battleId)
		sendView(player, s)
	elseif action == "skip" then
		local pending = state.pendingBattles[1]
		if not pending then
			sendError(player, requestId, "No battle is pending")
			return
		end
		local ok, reason = Campaign.autoResolve(state, pending.battleId)
		if not ok then
			sendError(player, requestId, reason or "Could not resolve the battle")
		else
			checkpoint(player, s, requestId)
		end
		sendView(player, s)
	else
		sendError(player, requestId, "Unknown campaign action")
	end
end

-- Called by the match layer once, when a campaign battle reaches results.
function CampaignService.onBattleEnded(battleId: string, scenario: Scenarios.Scenario, results: Types.Results, formations: { [number]: any }): (boolean, string?)
	local s = session
	if not s or s.activeBattleId ~= battleId or not s.state then
		return false, "no active campaign battle"
	end
	if s.committed[battleId] then
		return true, "alreadyApplied"
	end
	local survivors: { [string]: Campaign.Survivor } = {}
	for i, def in scenario.units do
		local f = formations[i]
		if def.key and f then
			survivors[def.key] = { strength = f.strength :: number, experience = f.experience :: number, destroyed = f.state == "destroyed" or f.state == "exited" }
		end
	end
	local ok, newState, reason = Campaign.commitBattle(store, s.userId, s.sessionId, s.state :: State, battleId, results, survivors)
	if ok and newState then
		s.state = newState
		s.committed[battleId] = true
		s.activeBattleId = nil
		s.activeScenario = nil
	elseif reason == "stale" or reason == "notOwner" or reason == "campaignMismatch" then
		-- Resume from the stored checkpoint; the battle stays pending there.
		local profile, status = store:load(s.userId)
		if status == "ok" and profile then
			s.state = Campaign.deserialize(profile) or s.state
		end
		s.activeBattleId = nil
		s.activeScenario = nil
	end
	local player = Players:GetPlayerByUserId(s.userId)
	if player then
		if not ok then
			sendError(player, "battle-end", "Battle result not saved (" .. tostring(reason) .. ")")
		end
		sendView(player, s)
	end
	return ok, reason
end

function CampaignService.isBattleCommitted(battleId: string): boolean
	local s = session
	return s ~= nil and s.committed[battleId] == true
end

function CampaignService.activeBattle(): (string?, Scenarios.Scenario?)
	local s = session
	if s then
		return s.activeBattleId, s.activeScenario
	end
	return nil, nil
end

local function onPlayerRemoving(player: Player)
	local s = session
	if s and s.userId == player.UserId then
		store:releaseSession(s.userId, s.sessionId)
		session = nil
	end
end

function CampaignService.start(campaignRemote: RemoteEvent, h: Hooks)
	remote = campaignRemote
	hooks = h
	store = ProfileStore.new({ name = "EoE", scope = if RunService:IsStudio() then "dev" else "live", dataStoreService = DataStoreService })
	remote.OnServerEvent:Connect(onRemote)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	RunService.Heartbeat:Connect(function()
		local s = session
		if s and os.clock() >= s.renewAt then
			s.renewAt = os.clock() + 60
			store:claimSession(s.userId, s.sessionId, os.time())
		end
	end)
end

function CampaignService.sessionOnly(): boolean
	return store ~= nil and store.sessionOnly
end

return CampaignService
