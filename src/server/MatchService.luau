--!strict
-- Match lifecycle, commander ownership, request handling, the server loop and replication.
-- One match per server. Everything the sim decides stays in Sim; this file only adapts it to
-- Roblox services and players.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("EoE")
local Config = require(Shared.Config)
local Protocol = require(Shared.Protocol)
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)

local Sim = require(script.Parent.Sim)
local AI = require(script.Parent.AI)
local Remotes = require(script.Parent.Net.Remotes)
local CommandGate = require(script.Parent.Net.CommandGate)
local MatchClock = require(script.Parent.Net.MatchClock)
local CampaignService = require(script.Parent.CampaignService)

type Sim = Sim.Sim

export type MatchState = "menu" | "loading" | "deployment" | "running" | "paused" | "results"

type Match = {
	id: string,
	sim: Sim,
	ai: any,
	clock: MatchClock.Clock,
	scenario: Scenarios.Scenario,
	state: MatchState,
	difficulty: string,
	ticksSincePublish: number,
	ticksSinceKeyframe: number,
	pausedPublishTimer: number,
	devTimer: number,
	leftAt: number?, -- os.clock() when the commander left
	campaignBattleId: string?,
}

local MatchService = {}

local remotes: { [string]: RemoteEvent }
local gate = CommandGate.new()
local match: Match? = nil
local commanderUserId: number? = nil
local difficulty = "normal"
local mapCache: { [string]: MapGen.MapData } = {}
local matchCounter = 0
local heartbeat: RBXScriptConnection? = nil
local devView = RunService:IsStudio()

local function mapFor(id: string): MapGen.MapData
	local m = mapCache[id]
	if not m then
		m = MapGen.generate(id)
		mapCache[id] = m
	end
	return m
end

local function playerFaction(m: Match?): string
	return if m then m.scenario.factions.player else "france"
end

local function isCommander(player: Player): boolean
	return commanderUserId == player.UserId
end

local function matchStatePayload(player: Player)
	local m = match
	return {
		matchId = if m then m.id else "",
		state = if m then m.state else "menu",
		scenario = if m
			then {
				id = m.scenario.id,
				name = m.scenario.name,
				briefing = m.scenario.briefing,
				map = m.scenario.map,
				factions = m.scenario.factions,
				factionNames = m.scenario.factionNames,
				timeLimit = m.sim.timeLimit,
			}
			else nil,
		viewerFaction = playerFaction(m),
		isCommander = isCommander(player),
		difficulty = if m then m.difficulty else difficulty,
		speed = if m then m.clock.speed else 1,
		results = if m then m.sim.result else nil,
		reason = if m and m.sim.result then m.sim.result.reason else nil,
		campaignAvailable = true,
		campaignSessionOnly = CampaignService.sessionOnly(),
		campaignBattle = if m and m.campaignBattleId then { battleId = m.campaignBattleId, name = m.scenario.name } else nil,
	}
end

local function broadcastState()
	for _, p in Players:GetPlayers() do
		remotes.MatchState:FireClient(p, matchStatePayload(p))
	end
end

local function sendSnapshot(player: Player, full: boolean)
	local m = match
	if not m then
		return
	end
	local snap = m.sim:snapshot(playerFaction(m), full)
	snap.speed = m.clock.speed
	snap.simLag = m.clock.simLag
	snap.state = m.state
	remotes.Snapshot:FireClient(player, snap)
end

local function publish(full: boolean)
	local m = match
	if not m then
		return
	end
	-- Delta tracking in Sim is per viewer faction, so publish once per faction then fan out.
	local players = Players:GetPlayers()
	if #players == 0 then
		m.sim:clearEvents()
		return
	end
	local snap = m.sim:snapshot(playerFaction(m), full)
	snap.speed = m.clock.speed
	snap.simLag = m.clock.simLag
	snap.state = m.state
	for _, p in players do
		remotes.Snapshot:FireClient(p, snap)
	end
	m.sim:clearEvents()
end

local function destroyMatch()
	local m = match
	if m then
		m.sim.aiStep = nil
	end
	match = nil
end

local function createMatchFrom(scenario: Scenarios.Scenario, campaignBattleId: string?)
	local map = mapFor(scenario.map)
	matchCounter += 1
	local id = string.format("m%d-%d", os.time() % 100000, matchCounter)
	local sim = Sim.new({ matchId = id, scenario = scenario, map = map, seed = os.time() + matchCounter * 7919, difficulty = difficulty })
	local ai = AI.new(sim, scenario.factions.enemy, difficulty)
	sim.aiStep = function(_s)
		AI.step(ai)
	end
	match = {
		id = id,
		sim = sim,
		ai = ai,
		clock = MatchClock.new(),
		scenario = scenario,
		state = "deployment",
		difficulty = difficulty,
		ticksSincePublish = 0,
		ticksSinceKeyframe = 0,
		pausedPublishTimer = 0,
		devTimer = 0,
		leftAt = nil,
		campaignBattleId = campaignBattleId,
	}
end

local function createMatch(scenarioId: string)
	createMatchFrom(Scenarios.get(scenarioId) or Scenarios.jena, nil)
end

local function result(player: Player, requestId: string, accepted: boolean, reason: string?, effectiveTick: number?)
	remotes.CommandResult:FireClient(player, { requestId = requestId, accepted = accepted, reason = reason, effectiveTick = effectiveTick })
end

local function onControl(player: Player, msg: any)
	local m = match
	local ok, reason = Protocol.validateControl(msg, { matchId = if m then m.id else "" })
	if not ok then
		if type(msg) == "table" and type(msg.requestId) == "string" then
			result(player, msg.requestId, false, reason)
		end
		return
	end
	local gok, greason = CommandGate.check(gate, player.UserId, "ctl:" .. msg.requestId, os.clock())
	if not gok then
		result(player, msg.requestId, false, greason)
		return
	end
	local action = msg.action
	if action == "spectate" then
		remotes.MatchState:FireClient(player, matchStatePayload(player))
		if m then
			sendSnapshot(player, true)
		end
		result(player, msg.requestId, true)
		return
	end
	-- Claim command: the first player to start a match becomes commander for the server.
	if commanderUserId == nil or Players:GetPlayerByUserId(commanderUserId) == nil then
		commanderUserId = player.UserId
	end
	if not isCommander(player) then
		result(player, msg.requestId, false, Protocol.Reasons.notCommander)
		return
	end
	if action == "difficulty" then
		difficulty = msg.value
		if m and m.state == "deployment" then
			m.difficulty = difficulty
			m.sim.difficulty = difficulty
			m.ai = AI.new(m.sim, m.scenario.factions.enemy, difficulty)
			local ai = m.ai
			m.sim.aiStep = function(_s)
				AI.step(ai)
			end
		end
		result(player, msg.requestId, true)
		broadcastState()
	elseif action == "start" or action == "restart" then
		if action == "restart" and m and m.campaignBattleId then
			-- A campaign battle can be refought only while its result has not been committed.
			if CampaignService.isBattleCommitted(m.campaignBattleId) then
				result(player, msg.requestId, false, Protocol.Reasons.badState)
				return
			end
			local scenario, battleId = m.scenario, m.campaignBattleId
			destroyMatch()
			createMatchFrom(scenario, battleId)
		else
			local scenarioId = if type(msg.value) == "string" then msg.value elseif m then m.scenario.id else "jena"
			destroyMatch()
			createMatch(scenarioId)
		end
		result(player, msg.requestId, true)
		broadcastState()
		publish(true)
	elseif action == "ready" then
		if m and m.state == "deployment" then
			m.sim:start()
			m.state = "running"
			m.clock.paused = false
			result(player, msg.requestId, true)
			broadcastState()
			publish(true)
		else
			result(player, msg.requestId, false, Protocol.Reasons.badState)
		end
	elseif action == "pause" or action == "resume" then
		if m and (m.state == "running" or m.state == "paused") then
			m.state = if action == "pause" then "paused" else "running"
			m.clock.paused = m.state == "paused"
			result(player, msg.requestId, true)
			broadcastState()
		else
			result(player, msg.requestId, false, Protocol.Reasons.badState)
		end
	elseif action == "speed" then
		if m and MatchClock.setSpeed(m.clock, msg.value) then
			result(player, msg.requestId, true)
			broadcastState()
		else
			result(player, msg.requestId, false, Protocol.Reasons.badRequest)
		end
	elseif action == "quit" then
		destroyMatch()
		result(player, msg.requestId, true)
		broadcastState()
	end
end

local function onCommand(player: Player, cmd: any)
	local m = match
	if not m then
		if type(cmd) == "table" and type(cmd.requestId) == "string" then
			result(player, cmd.requestId, false, Protocol.Reasons.badState)
		end
		return
	end
	local sim = m.sim
	local faction = playerFaction(m)
	local ctx: Protocol.ValidateContext = {
		matchId = m.id,
		state = m.state,
		mapWidth = sim.map.width,
		mapDepth = sim.map.depth,
		isOwned = function(id: number): boolean
			local f = sim.formations[id]
			return f ~= nil and f.faction == faction and isCommander(player)
		end,
		classOf = function(id: number): string?
			local f = sim.formations[id]
			return if f then f.class else nil
		end,
		legalShapes = function(id: number): { [string]: boolean }?
			local f = sim.formations[id]
			return if f then (Config.Units :: any)[f.class].legalShapes else nil
		end,
	}
	local ok, reason = Protocol.validateCommand(cmd, ctx)
	if not ok then
		if type(cmd) == "table" and type(cmd.requestId) == "string" then
			result(player, cmd.requestId, false, if not isCommander(player) then Protocol.Reasons.notCommander else reason)
		end
		return
	end
	local gok, greason = CommandGate.check(gate, player.UserId, cmd.requestId, os.clock())
	if not gok then
		result(player, cmd.requestId, false, greason)
		return
	end
	if cmd.kind == "Deploy" then
		local dok, dreason = sim:deploy(cmd.ids[1], cmd.data.pos, cmd.data.heading)
		result(player, cmd.requestId, dok, if dok then nil else (Protocol.Reasons :: any)[dreason or "badRequest"] or dreason)
		if dok then
			publish(false)
		end
		return
	end
	local pok, preason = sim:precheck(cmd)
	if not pok then
		result(player, cmd.requestId, false, (Protocol.Reasons :: any)[preason or "badRequest"] or preason)
		return
	end
	local _seq, effectiveTick = sim:queueCommand(cmd, faction)
	result(player, cmd.requestId, true, nil, effectiveTick)
end

local function onHeartbeat(realDt: number)
	local m = match
	if not m then
		return
	end
	if m.state == "running" then
		local ticks = MatchClock.advance(m.clock, realDt, function()
			m.sim:step()
		end)
		m.ticksSincePublish += ticks
		m.ticksSinceKeyframe += ticks
		if m.sim.state == "ended" then
			m.state = "results"
			m.clock.paused = true
			publish(true)
			if m.campaignBattleId and m.sim.result then
				-- Exactly-once commit happens inside CampaignService (idempotent by battle id).
				CampaignService.onBattleEnded(m.campaignBattleId, m.scenario, m.sim.result, m.sim.formations)
			end
			broadcastState()
			return
		end
		if m.ticksSincePublish >= Config.Sim.SnapshotEveryTicks then
			m.ticksSincePublish = 0
			local keyframe = m.ticksSinceKeyframe >= 100
			if keyframe then
				m.ticksSinceKeyframe = 0
			end
			publish(keyframe)
		end
	elseif m.state == "paused" or m.state == "deployment" then
		-- Orders accepted while paused change dest/shape ghosts: publish deltas at 2 Hz.
		m.pausedPublishTimer += realDt
		if m.pausedPublishTimer >= 0.5 then
			m.pausedPublishTimer = 0
			publish(false)
		end
	end
	if devView and m.ai then
		m.devTimer += realDt
		if m.devTimer >= 1 then
			m.devTimer = 0
			local commander = if commanderUserId then Players:GetPlayerByUserId(commanderUserId) else nil
			if commander then
				remotes.Debug:FireClient(commander, { aiGoals = AI.debugView(m.ai) })
			end
		end
	end
	-- Commander departure: pause, then reset after the grace period.
	if m.leftAt and os.clock() - m.leftAt > Config.Match.ReconnectGrace then
		destroyMatch()
		commanderUserId = nil
		broadcastState()
	end
end

local function onPlayerAdded(player: Player)
	if commanderUserId == player.UserId then
		local m = match
		if m then
			m.leftAt = nil
		end
	end
	remotes.MatchState:FireClient(player, matchStatePayload(player))
	if match then
		sendSnapshot(player, true)
	end
end

local function onPlayerRemoving(player: Player)
	CommandGate.forget(gate, player.UserId)
	local m = match
	if m and isCommander(player) then
		if m.state == "running" then
			m.state = "paused"
			m.clock.paused = true
		end
		m.leftAt = os.clock()
		broadcastState()
	end
end

function MatchService.start()
	remotes = Remotes.create()
	Players.CharacterAutoLoads = false
	remotes.Control.OnServerEvent:Connect(onControl)
	remotes.Command.OnServerEvent:Connect(onCommand)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		onPlayerAdded(p)
	end
	if heartbeat then
		heartbeat:Disconnect()
	end
	heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
	CampaignService.start(remotes.Campaign, {
		isCommander = function(player: Player): boolean
			if commanderUserId == nil or Players:GetPlayerByUserId(commanderUserId) == nil then
				commanderUserId = player.UserId
			end
			return isCommander(player)
		end,
		startBattle = function(scenario: Scenarios.Scenario, battleId: string)
			destroyMatch()
			createMatchFrom(scenario, battleId)
			broadcastState()
			publish(true)
		end,
	})
end

-- Exposed for tests / tooling.
MatchService._internal = { createMatch = createMatch, destroyMatch = destroyMatch, getMatch = function()
	return match
end }

return MatchService
