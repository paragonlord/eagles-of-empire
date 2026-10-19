--!strict
-- Match lifecycle, co-op / PvP roles, sides and wings (Coop, docs/coop-contract.md), request handling, the server loop and replication.
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
local CustomBattle = require(Shared.CustomBattle)
local Coop = require(script.Parent.Coop)
local World = require(script.Parent.World)

type Sim = Sim.Sim

export type MatchState = "menu" | "loading" | "deployment" | "running" | "paused" | "results"

type Match = {
	id: string,
	sim: Sim,
	ai: any,
	aiFaction: string?, -- the faction the AI runs (nil in PvP with humans on both sides)
	sideResults: { [string]: any }, -- results rewritten for the enemy side's players (PvP)
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
	controllers: { [number]: number }, -- formationId -> userId of the player commanding it
	splitKey: string, -- commanding players the last auto-split was made for
	ready: { [number]: boolean }, -- deployment: commanding players who sent ready
	votes: { [number]: boolean }, -- pause votes while running, resume votes while paused
}

local MatchService = {}

local remotes: { [string]: RemoteEvent }
local gate = CommandGate.new()
local match: Match? = nil
local roster = Coop.newRoster()
local lastPing: { [number]: number } = {}
local difficulty = "normal"
local mode = "coop" -- host's choice for the next match: "coop" | "pvp"
local command = "historical" -- host's choice for the next listed battle: the historical army or the other
local mapCache: { [string]: MapGen.MapData } = {}
local matchCounter = 0
local heartbeat: RBXScriptConnection? = nil
local devView = RunService:IsStudio()
local MENU_MAP = "jena" -- the field behind the menu

local function mapFor(id: string): MapGen.MapData
	local m = mapCache[id]
	if not m then
		m = MapGen.generate(id)
		mapCache[id] = m
	end
	return m
end

-- The faction a player commands and sees (PvP: their side; spectators: the host's side).
local function viewFaction(m: Match?, userId: number): string
	return if m then Coop.sideFaction(m.scenario.factions, Coop.sideOf(roster, userId)) else "france"
end

-- PvP is off for the tutorial (scripted enemy) and campaign battles (one nation's campaign).
local function pvpAllowed(m: Match): boolean
	return m.tutorialStep == nil and m.campaignBattleId == nil and m.scenario.id ~= "tutorial"
end

-- Runs the AI for the side without humans (Coop.aiSide); none in a full PvP match. The tutorial
-- drives its own enemy. `force` rebuilds it (a new difficulty).
local function refreshAI(m: Match, force: boolean?)
	if m.tutorialStep ~= nil then
		return
	end
	local side = Coop.aiSide(roster)
	local faction = if side then Coop.sideFaction(m.scenario.factions, side) else nil
	if faction == m.aiFaction and not force then
		return
	end
	m.aiFaction = faction
	if faction then
		local ai = AI.new(m.sim, faction, m.difficulty)
		m.ai = ai
		m.sim.aiStep = function(_s)
			AI.step(ai)
		end
	else
		AI.steady(m.sim, nil, 0)
		m.ai = nil
		m.sim.aiStep = nil
	end
end

local function resultsFor(m: Match, faction: string): any
	local r = m.sim.result
	if not r or faction == m.sim.playerFaction or not m.sim.winner then
		return r
	end
	local cached = m.sideResults[faction]
	if not cached then
		cached = m.sim:buildResults(m.sim.winner :: string, r.reason, faction)
		m.sideResults[faction] = cached
	end
	return cached
end

local function isCommander(player: Player): boolean
	return Coop.roleOf(roster, player.UserId) == "commander"
end

local function count(t: { [number]: boolean }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function playersPayload(m: Match?)
	local out = {}
	for _, mem in roster.members do
		if mem.role ~= "spectator" then
			out[#out + 1] = { userId = mem.userId, name = mem.name, role = mem.role, ready = m ~= nil and m.ready[mem.userId] == true, slot = mem.slot, side = if m then viewFaction(m, mem.userId) else nil }
		end
	end
	return out
end

-- Wings of the viewer's own faction only: the other side's wing split is not ours to know.
local function controllersPayload(m: Match?, faction: string): { [string]: number }
	local out: { [string]: number } = {}
	if m then
		for id, uid in m.controllers do
			local f = m.sim.formations[id]
			if f and f.faction == faction then
				out[tostring(id)] = uid
			end
		end
	end
	return out
end

local function matchStatePayload(player: Player)
	local m = match
	local faction = viewFaction(m, player.UserId)
	local n = #Coop.commanding(roster)
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
		viewerFaction = faction,
		isCommander = isCommander(player),
		role = Coop.roleOf(roster, player.UserId),
		lead = Coop.isLead(roster, player.UserId),
		mode = if m then (if roster.pvp then "pvp" else "coop") else mode,
		players = playersPayload(m),
		controllers = controllersPayload(m, faction),
		pauseVotes = if m then count(m.votes) else 0,
		pauseNeeded = if roster.pvp and m and m.state == "paused" then 1 else Coop.votesNeeded(n, roster.pvp),
		difficulty = if m then m.difficulty else difficulty,
		speed = if m then m.clock.speed else 1,
		results = if m then resultsFor(m, faction) else nil,
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
	local snap = m.sim:snapshot(viewFaction(m, player.UserId), full)
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
	local byFaction: { [string]: { Player } } = {}
	for _, p in players do
		local f = viewFaction(m, p.UserId)
		byFaction[f] = byFaction[f] or {}
		table.insert(byFaction[f], p)
	end
	for _, faction in { m.scenario.factions.player, m.scenario.factions.enemy } do
		local list = byFaction[faction]
		if list then
			local snap = m.sim:snapshot(faction, full)
			snap.speed = m.clock.speed
			snap.simLag = m.clock.simLag
			snap.state = m.state
			for _, p in list do
				remotes.Snapshot:FireClient(p, snap)
			end
		else
			m.sim.lastSent[faction] = nil -- nobody watching: the next viewer starts from a keyframe
		end
	end
	m.sim:clearEvents()
end

local function destroyMatch()
	local m = match
	if m then
		m.sim.aiStep = nil
	end
	match = nil
	roster.pvp = false
	World.ensure(mapFor(MENU_MAP)) -- the menu shows Jena; a match on another map is cleared
end

-- Commanding players and their sides: a change re-splits the wings.
local function rosterKey(): string
	local parts = {}
	for _, uid in Coop.commanding(roster) do
		parts[#parts + 1] = uid .. Coop.sideOf(roster, uid)
	end
	return table.concat(parts, ",") .. (if roster.pvp then "|pvp" else "")
end

-- Auto-split each human side into wings, one per commanding player of that side (Coop.split);
-- the side's lead keeps its HQ. The player side is always split (co-op as before).
local function resplit(m: Match)
	m.controllers = {}
	for _, side: Coop.Side in { "player", "enemy" } do
		local players = Coop.commanding(roster, side)
		if side == "player" or #players > 0 then
			local faction = Coop.sideFaction(m.scenario.factions, side)
			local forms: { Coop.SplitFormation } = {}
			for _, id in m.sim.order do
				local f = m.sim.formations[id]
				if f and f.faction == faction then
					forms[#forms + 1] = f :: any
				end
			end
			for id, uid in Coop.split(forms, m.sim.map.deployZones[faction], players, Coop.lead(roster, side) or 0) do
				m.controllers[id] = uid
			end
		end
	end
	m.splitKey = rosterKey()
end

-- After any join, leave or role change: re-split when the commanding set changed, drop votes
-- and ready flags of players who no longer command, and tell everyone.
local function onRoster()
	local m = match
	if m then
		local commanding: { [number]: boolean } = {}
		for _, uid in Coop.commanding(roster) do
			commanding[uid] = true
		end
		for uid in m.votes do
			if not commanding[uid] then
				m.votes[uid] = nil
			end
		end
		for uid in m.ready do
			if not commanding[uid] then
				m.ready[uid] = nil
			end
		end
		if rosterKey() ~= m.splitKey then
			resplit(m)
			refreshAI(m)
			if roster.pvp then
				-- someone's side (and so their view) may have changed
				broadcastState()
				publish(true)
				return
			end
		end
	end
	broadcastState()
end

-- A player claims command when nobody holds it (the first player in, or after everyone left).
local function claim(player: Player)
	if not Coop.commander(roster) and Coop.claim(roster, player.UserId) then
		onRoster()
	end
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
	World.ensure(map) -- built once per map, replicated; clients gate on its WorldReady attribute
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
		aiFaction = scenario.factions.enemy,
		sideResults = {},
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
		controllers = {},
		splitKey = "",
		ready = {},
		votes = {},
	}
	local m = match :: Match
	Coop.resetSides(roster) -- sides do not carry over between battles
	roster.pvp = mode == "pvp" and pvpAllowed(m)
	if roster.pvp then
		MatchClock.setSpeed(m.clock, 1)
	end
	resplit(m)
	refreshAI(m)
	if scenario.id == "tutorial" then
		tutorialStart(match)
	end
end

local function createMatch(scenarioId: string)
	local base = Scenarios.get(scenarioId) or Scenarios.jena
	-- only listed battles change sides; the tutorial is always fought as written
	createMatchFrom(if base.mode then Scenarios.forSide(base, command) else base, nil)
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
	local uid = player.UserId
	print(string.format("[EoE server] control %s from %s (role=%s)", tostring(action), player.Name, Coop.roleOf(roster, uid)))
	if action == "spectate" then
		if msg.value == true then
			-- step down to spectator (the commander cannot)
			if not Coop.spectate(roster, uid) then
				result(player, msg.requestId, false, Protocol.Reasons.badState)
				return
			end
			onRoster()
		else
			-- plain state request
			remotes.MatchState:FireClient(player, matchStatePayload(player))
		end
		if m then
			sendSnapshot(player, true)
		end
		result(player, msg.requestId, true)
		return
	end
	claim(player)
	if action == "join" then
		if Coop.join(roster, uid) then
			result(player, msg.requestId, true)
			onRoster()
		else
			result(player, msg.requestId, false, Protocol.Reasons.badState)
		end
		return
	end
	local role = Coop.roleOf(roster, uid)
	local anyone = action == "ready" or action == "pause" or action == "resume" or action == "ping" or action == "side" or action == "assign"
	if role == "spectator" or (role ~= "commander" and not anyone) then
		result(player, msg.requestId, false, Protocol.Reasons.notCommander)
		return
	end
	if action == "command" then
		command = msg.value
		result(player, msg.requestId, true)
	elseif action == "custom" then
		local sc, why = CustomBattle.build(msg.value)
		if not sc then
			result(player, msg.requestId, false, why)
			return
		end
		destroyMatch()
		createMatchFrom(sc, nil)
		result(player, msg.requestId, true)
		broadcastState()
		publish(true)
	elseif action == "difficulty" then
		difficulty = msg.value
		if m and m.state == "deployment" and m.tutorialStep == nil then
			m.difficulty = difficulty
			m.sim.difficulty = difficulty
			refreshAI(m, true)
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
		elseif action == "restart" and m and m.scenario.id == "custom" then
			local scenario = m.scenario -- a custom battle is fought again as built
			destroyMatch()
			createMatchFrom(scenario, nil)
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
			-- Starts once every commanding player is ready, or on the commander's second ready
			-- (co-op only: in PvP the other side must be ready too).
			local force = role == "commander" and m.ready[uid] == true and not roster.pvp
			m.ready[uid] = true
			local all = true
			for _, id in Coop.commanding(roster) do
				all = all and m.ready[id] == true
			end
			result(player, msg.requestId, true)
			if force or all then
				m.sim:start()
				m.state = "running"
				m.clock.paused = false
				m.votes = {}
				broadcastState()
				publish(true)
			else
				broadcastState()
			end
		else
			result(player, msg.requestId, false, Protocol.Reasons.badState)
		end
	elseif action == "pause" or action == "resume" then
		if m and (m.state == "running" or m.state == "paused") then
			local target: MatchState = if action == "pause" then "paused" else "running"
			if m.state ~= target then
				-- A vote: ⌈n/2⌉ commanding players, or the commander's resume alone. Solo acts at once.
				-- PvP: pausing needs everyone, any one player may resume.
				local decisive = action == "resume" and (role == "commander" or roster.pvp)
				local passed = Coop.vote(m.votes, uid, #Coop.commanding(roster), decisive, roster.pvp)
				if passed then
					m.state = target
					m.clock.paused = target == "paused"
					m.votes = {}
				end
			end
			result(player, msg.requestId, true)
			broadcastState()
		else
			result(player, msg.requestId, false, Protocol.Reasons.badState)
		end
	elseif action == "speed" then
		if roster.pvp and msg.value ~= 1 then
			result(player, msg.requestId, false, Protocol.Reasons.badState) -- PvP runs at 1×
		elseif m and MatchClock.setSpeed(m.clock, msg.value) then
			result(player, msg.requestId, true)
			broadcastState()
		else
			result(player, msg.requestId, false, Protocol.Reasons.badRequest)
		end
	elseif action == "assign" then
		local v = msg.value
		if not m then
			result(player, msg.requestId, false, Protocol.Reasons.badState)
			return
		end
		-- the side's lead hands formations of that side to an officer of the same side
		if not Coop.isLead(roster, uid) then
			result(player, msg.requestId, false, Protocol.Reasons.notCommander)
			return
		end
		if Coop.roleOf(roster, v.userId) == "spectator" or Coop.sideOf(roster, v.userId) ~= Coop.sideOf(roster, uid) then
			result(player, msg.requestId, false, Protocol.Reasons.badTarget)
			return
		end
		local faction = viewFaction(m, uid)
		for _, id in v.ids do
			local f = m.sim.formations[id]
			if not f or f.faction ~= faction then
				result(player, msg.requestId, false, Protocol.Reasons.notOwned)
				return
			end
		end
		for _, id in v.ids do
			m.controllers[id] = v.userId
		end
		result(player, msg.requestId, true)
		broadcastState()
	elseif action == "ping" then
		local v = msg.value
		local now = os.clock()
		if not m then
			result(player, msg.requestId, false, Protocol.Reasons.badState)
		elseif now - (lastPing[uid] or -math.huge) < 1 then
			result(player, msg.requestId, false, Protocol.Reasons.rateLimited)
		elseif v.x < 0 or v.z < 0 or v.x >= m.sim.map.width or v.z >= m.sim.map.depth then
			result(player, msg.requestId, false, Protocol.Reasons.badPosition)
		else
			lastPing[uid] = now
			local ping = { userId = uid, name = player.Name, x = v.x, z = v.z, kind = v.kind, tick = m.sim.tick }
			local side = Coop.sideOf(roster, uid)
			for _, p in Players:GetPlayers() do
				if Coop.roleOf(roster, p.UserId) ~= "spectator" and Coop.sideOf(roster, p.UserId) == side then
					remotes.Ping:FireClient(p, ping)
				end
			end
			result(player, msg.requestId, true)
		end
	elseif action == "mode" then
		-- host: co-op vs AI or PvP, from the menu (next match) or during deployment
		if m and (m.state ~= "deployment" or (msg.value == "pvp" and not pvpAllowed(m))) then
			result(player, msg.requestId, false, Protocol.Reasons.badState)
			return
		end
		mode = msg.value
		result(player, msg.requestId, true)
		if m then
			roster.pvp = mode == "pvp"
			m.ready = {}
			m.votes = {}
			if roster.pvp then
				MatchClock.setSpeed(m.clock, 1)
			end
			onRoster() -- re-splits and swaps the AI
			publish(true) -- views may have changed side
		else
			broadcastState()
		end
	elseif action == "side" or action == "balance" then
		-- PvP deployment: pick a side (value = faction id), or the host balances them
		if not m or not roster.pvp or m.state ~= "deployment" then
			result(player, msg.requestId, false, Protocol.Reasons.badState)
			return
		end
		if action == "balance" then
			Coop.balance(roster)
			m.ready = {}
		else
			local side = Coop.sideFor(m.scenario.factions, msg.value)
			if not side then
				result(player, msg.requestId, false, Protocol.Reasons.badRequest)
				return
			end
			Coop.setSide(roster, uid, side)
			m.ready[uid] = nil
		end
		result(player, msg.requestId, true)
		onRoster()
	elseif action == "tutorialStep" then
		local tok, treason = tutorialStep(m, true, msg.value)
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
	local faction = viewFaction(m, player.UserId)
	local role = Coop.roleOf(roster, player.UserId)
	local ctx: Protocol.ValidateContext = {
		matchId = m.id,
		state = m.state,
		mapWidth = sim.map.width,
		mapDepth = sim.map.depth,
		isOwned = function(id: number): boolean
			local f = sim.formations[id]
			return f ~= nil and f.faction == faction and role ~= "spectator"
		end,
		classOf = function(id: number): string?
			local f = sim.formations[id]
			return if f then f.class else nil
		end,
		legalShapes = function(id: number): { [string]: boolean }?
			local f = sim.formations[id]
			return if f then Config.TypeStats[f.type].legalShapes else nil
		end,
	}
	local ok, reason = Protocol.validateCommand(cmd, ctx)
	if not ok then
		if type(cmd) == "table" and type(cmd.requestId) == "string" then
			result(player, cmd.requestId, false, if role == "spectator" then Protocol.Reasons.notCommander else reason)
		end
		return
	end
	-- Officers command only their own wing; the side's lead may command any of its formations.
	if not Coop.isLead(roster, player.UserId) then
		for _, id in cmd.ids do
			if m.controllers[id] ~= player.UserId then
				result(player, cmd.requestId, false, Protocol.Reasons.notYours)
				return
			end
		end
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
	if devView and m.ai and not roster.pvp then
		m.devTimer += realDt
		if m.devTimer >= 1 then
			m.devTimer = 0
			local cmd = Coop.commander(roster)
			local commander = if cmd then Players:GetPlayerByUserId(cmd.userId) else nil
			if commander then
				remotes.Debug:FireClient(commander, { aiGoals = AI.debugView(m.ai) })
			end
		end
	end
	-- Everyone left: pause, then reset after the grace period.
	if m.leftAt and os.clock() - m.leftAt > Config.Match.ReconnectGrace then
		destroyMatch()
		broadcastState()
	end
end

local function onPlayerAdded(player: Player)
	-- The first player in commands; the next three are officers; later joiners spectate.
	local mem = Coop.add(roster, player.UserId, player.Name)
	local m = match
	if m and mem.role == "commander" then
		m.leftAt = nil
	end
	print(string.format("[EoE server] player %s (%d) joined as %s", player.Name, player.UserId, mem.role))
	onRoster()
	if match then
		sendSnapshot(player, true)
	end
end

local function onPlayerRemoving(player: Player)
	CommandGate.forget(gate, player.UserId)
	lastPing[player.UserId] = nil
	-- A departing commander hands command on (Coop.remove); their wing returns via the re-split.
	local wasCommander = Coop.remove(roster, player.UserId)
	local m = match
	if m and wasCommander and not Coop.commander(roster) then
		-- Nobody left: pause, and reset after the grace period unless they come back.
		if m.state == "running" then
			m.state = "paused"
			m.clock.paused = true
		end
		m.votes = {}
		m.leftAt = os.clock()
	end
	onRoster()
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
	World.ensure(mapFor(MENU_MAP))
	print("[EoE server] match service started")
	CampaignService.start(remotes.Campaign, {
		isCommander = function(player: Player): boolean
			claim(player)
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
