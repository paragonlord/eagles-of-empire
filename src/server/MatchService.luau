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
	tutorialStep: number?, -- tutorial scenario only: last step the commander reached
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
				date = (m.scenario :: any).date,
				summary = (m.scenario :: any).summary,
				weather = m.sim.weather,
				difficultyNote = (m.scenario :: any).difficultyNote,
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

-- ------------------------------------------------------------------ tutorial
-- The tutorial enemy is scripted, not AI-driven: it starts passive and the client's step
-- progress (Control "tutorialStep") releases it lesson by lesson through sim:queueCommand.
local TUTORIAL_FINAL = 12 -- "finish": accepted only once the player holds Ebersdorf
local TUTORIAL_RELEASE = 11 -- the brigade fights in earnest (also what "Skip tutorial" sends)
local TUTORIAL_UNITS = {
	skirmishers = "Grenz-Infanterie Nr. 1",
	cavalry = "Chevaulegers Nr. 3",
	conscripts = "Conscrits de 1809",
	garrison = "IR 49 Kerpen",
}
local TUTORIAL_CAV_REPEAT = 10 -- s between renewed cavalry attacks while lesson 9 runs
local TUTORIAL_GRENZ_BREAK = 0.75 -- Grenzers withdraw below this fraction of their strength
local TUTORIAL_GRENZ_FALLBACK = { x = 430, z = 650 } -- over the Mühlbach, west of Ebersdorf
local TUTORIAL_GARRISON_FALLBACK = { x = 900, z = 760 } -- out of Ebersdorf to the north-east

local function tutorialIds(sim: Sim, faction: string, name: string?): { number }
	local ids = {}
	for _, id in sim.order do
		local f = sim.formations[id]
		if f and f.faction == faction and (name == nil or f.name == name) and f.state ~= "destroyed" and f.state ~= "exited" then
			ids[#ids + 1] = id
		end
	end
	return ids
end

local function tutorialOrder(sim: Sim, kind: string, ids: { number }, data: { [string]: any })
	if #ids > 0 then
		sim:queueCommand({ matchId = sim.matchId, requestId = "tutorial", kind = kind, ids = ids, data = data }, sim.enemyFaction)
	end
end

local function tutorialStart(m: any)
	m.tutorialStep = 0
	m.sim.aiStep = nil
	local all = tutorialIds(m.sim, m.sim.enemyFaction, nil)
	tutorialOrder(m.sim, "Stance", all, { fireAtWill = false })
	tutorialOrder(m.sim, "Hold", all, {})
end

-- Scripted enemy for entering `step`. One-shot events (the cavalry threat, the broken
-- conscripts) run only on the step itself; releases also run when steps are skipped past.
local function tutorialScript(m: any, step: number, target: number)
	local sim: Sim = m.sim
	local enemy = sim.enemyFaction
	if step == 6 then
		tutorialOrder(sim, "Stance", tutorialIds(sim, enemy, TUTORIAL_UNITS.skirmishers), { fireAtWill = true })
	elseif step == 9 and target == 9 then
		m.tutorialCavAt = 0 -- tutorialTick sends the cavalry now and renews the attack
	elseif step == 10 and target == 10 then
		-- the conscripts break (a scripted shock, so the rally lesson always has a subject)
		for _, id in tutorialIds(sim, sim.playerFaction, TUTORIAL_UNITS.conscripts) do
			local f = sim.formations[id]
			if f.state ~= "routing" then
				f.morale = math.min(f.morale, 10)
			end
		end
	elseif step == TUTORIAL_RELEASE then
		tutorialOrder(sim, "Stance", tutorialIds(sim, enemy, nil), { fireAtWill = true })
		local ai = m.ai
		if ai then
			sim.aiStep = function(_s)
				AI.step(ai)
				-- a battalion that abandoned Ebersdorf stays gone: drop the AI's orders for it
				local out = m.tutorialOut
				if out then
					local keep = {}
					for _, c in sim.commands do
						if string.sub(c.requestId, 1, 3) == "ai-" then
							local ids = {}
							for _, id in c.ids do
								if not out[id] then
									ids[#ids + 1] = id
								end
							end
							c.ids = ids
						end
						if #c.ids > 0 then
							keep[#keep + 1] = c
						end
					end
					sim.commands = keep
				end
			end
		end
	end
end

-- The cavalry rides at the nearest French battalion it can see (any, if it sees none).
local function tutorialCavalryAttack(sim: Sim)
	local cav = tutorialIds(sim, sim.enemyFaction, TUTORIAL_UNITS.cavalry)
	local c = cav[1] and sim.formations[cav[1]]
	if not c or c.state == "routing" then
		return
	end
	local best, bestD, bestSeen = nil, math.huge, false
	for _, id in tutorialIds(sim, sim.playerFaction, nil) do
		local f = sim.formations[id]
		local seen = sim:isVisibleTo(sim.enemyFaction, id)
		local d = (f.pos.x - c.pos.x) ^ 2 + (f.pos.z - c.pos.z) ^ 2
		if f.class == "infantry" and f.state ~= "routing" and ((seen and not bestSeen) or (seen == bestSeen and d < bestD)) then
			best, bestD, bestSeen = f, d, seen
		end
	end
	if best then
		tutorialOrder(sim, "AttackMove", cav, { pos = { x = best.pos.x, z = best.pos.z } })
	end
end

local function tutorialWithdraw(sim: Sim, f: any, pos: { x: number, z: number }, text: string)
	tutorialOrder(sim, "Stance", { f.id }, { fireAtWill = false })
	tutorialOrder(sim, "Retreat", { f.id }, { pos = pos })
	sim:emit({ kind = "message", tick = sim.tick, text = text })
end

-- Per-frame upkeep of the scripted enemy (pure; exposed for tests): renews the cavalry attack
-- while lesson 9 runs, pulls the Grenzers back once bloodied so lesson 6 ends in a win, and
-- has the Kerpen battalion abandon Ebersdorf when two French battalions are in its streets.
local function tutorialTick(m: any)
	local step = m.tutorialStep
	local sim: Sim = m.sim
	if step == nil or sim.state ~= "running" then
		return
	end
	if step == 9 and m.tutorialCavAt and sim.clock >= m.tutorialCavAt then
		m.tutorialCavAt = sim.clock + TUTORIAL_CAV_REPEAT
		tutorialCavalryAttack(sim)
	end
	if step >= 6 and not m.tutorialGrenzOut then
		for _, id in tutorialIds(sim, sim.enemyFaction, TUTORIAL_UNITS.skirmishers) do
			local f = sim.formations[id]
			if f.state ~= "routing" and f.strength < f.startStrength * TUTORIAL_GRENZ_BREAK then
				m.tutorialGrenzOut = true
				tutorialWithdraw(sim, f, TUTORIAL_GRENZ_FALLBACK, "The Grenzers give ground and fall back over the Mühlbach")
			end
		end
	end
	if step >= TUTORIAL_RELEASE and not m.tutorialGarrisonOut then
		for _, id in tutorialIds(sim, sim.enemyFaction, TUTORIAL_UNITS.garrison) do
			local g = sim.formations[id]
			local close = 0
			for _, fid in tutorialIds(sim, sim.playerFaction, nil) do
				local f = sim.formations[fid]
				if f.class == "infantry" and f.state ~= "routing" and (f.pos.x - g.pos.x) ^ 2 + (f.pos.z - g.pos.z) ^ 2 <= 80 * 80 then
					close += 1
				end
			end
			if close >= 2 and g.state ~= "routing" then
				m.tutorialGarrisonOut = true
				m.tutorialOut = { [g.id] = true }
				tutorialWithdraw(sim, g, TUTORIAL_GARRISON_FALLBACK, g.name .. " abandons Ebersdorf")
			end
		end
	end
end

-- Pure handler: validates and applies one tutorial step request. Exposed for tests.
local function tutorialStep(m: any, commander: boolean, step: any): (boolean, string?)
	if not commander then
		return false, Protocol.Reasons.notCommander
	end
	if not m or m.tutorialStep == nil or m.scenario.id ~= "tutorial" or m.sim.state ~= "running" then
		return false, Protocol.Reasons.badState
	end
	if type(step) ~= "number" or step ~= math.floor(step) or step <= m.tutorialStep or step > TUTORIAL_FINAL then
		return false, Protocol.Reasons.badRequest
	end
	local sim: Sim = m.sim
	if step == TUTORIAL_FINAL then
		for _, o in sim.objectives do
			if o.owner ~= sim.playerFaction then
				return false, Protocol.Reasons.badState
			end
		end
		sim.state = "ended"
		sim.winner = sim.playerFaction
		sim.result = sim:buildResults(sim.playerFaction, "Ebersdorf is taken: the training is complete")
		m.tutorialStep = step
		return true, nil
	end
	for s = m.tutorialStep + 1, step do
		tutorialScript(m, s, step)
	end
	m.tutorialStep = step
	return true, nil
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
	if scenario.id == "tutorial" then
		tutorialStart(match)
	end
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
	print(string.format("[EoE server] control %s from %s (commander=%s)", tostring(action), player.Name, tostring(isCommander(player))))
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
		if m and m.state == "deployment" and m.tutorialStep == nil then
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
	elseif action == "tutorialStep" then
		local tok, treason = tutorialStep(m, isCommander(player), msg.value)
		result(player, msg.requestId, tok, treason)
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
		if m.tutorialStep then
			tutorialTick(m)
		end
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
	-- The first player present is the commander; later joiners spectate until they leave.
	if commanderUserId == nil or Players:GetPlayerByUserId(commanderUserId) == nil then
		commanderUserId = player.UserId
	end
	if commanderUserId == player.UserId then
		local m = match
		if m then
			m.leftAt = nil
		end
	end
	print(string.format("[EoE server] player %s (%d) joined; commander=%s", player.Name, player.UserId, tostring(isCommander(player))))
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
	elseif not m and isCommander(player) then
		-- No match in progress: hand command to whoever is still here.
		commanderUserId = nil
		for _, p in Players:GetPlayers() do
			if p ~= player then
				commanderUserId = p.UserId
				break
			end
		end
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
	print("[EoE server] match service started")
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
MatchService._internal = { createMatch = createMatch, destroyMatch = destroyMatch, tutorialStart = tutorialStart, tutorialStep = tutorialStep, tutorialTick = tutorialTick, getMatch = function()
	return match
end }

return MatchService
