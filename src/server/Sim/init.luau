--!strict
-- The authoritative battle simulation. Pure Luau: no Roblox APIs, no wall-clock time.
-- Owns formations, commands, the fixed tick, visibility, objectives, victory and snapshots.
-- Tick order is documented in docs/architecture.md and implemented in Sim:step().

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local RNG = require(Shared.RNG)
local Grid = require(Shared.Grid)
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)
local Types = require(Shared.Types)

local Formation = require(script.Formation)
local Nav = require(script.Nav)
local Movement = require(script.Movement)
local Combat = require(script.Combat)
local Morale = require(script.Morale)
local Visibility = require(script.Visibility)
local Objectives = require(script.Objectives)

type Vec = Vec.Vec
type Formation = Formation.Formation

export type Options = {
	matchId: string,
	scenario: Scenarios.Scenario,
	map: MapGen.MapData,
	seed: number,
	difficulty: string?,
	timeLimit: number?,
}

export type QueuedCommand = {
	matchId: string,
	requestId: string,
	kind: string,
	ids: { number },
	data: { [string]: any }?,
	seq: number,
	effectiveTick: number,
	faction: string,
}

export type Sim = {
	matchId: string,
	scenario: Scenarios.Scenario,
	map: MapGen.MapData,
	grid: Grid.Grid,
	nav: Nav.NavGrid,
	rng: RNG.RNG,
	seed: number,
	tick: number,
	clock: number,
	timeLimit: number,
	state: "deployment" | "running" | "ended",
	formations: { [number]: Formation },
	order: { number },
	factions: { string },
	playerFaction: string,
	enemyFaction: string,
	views: { [string]: Visibility.FactionView },
	objectives: { Objectives.ObjectiveState },
	commands: { QueuedCommand },
	seqCounter: number,
	events: { Types.Event },
	logLines: { string },
	deployed: { [string]: number },
	stats: { [string]: any },
	result: Types.Results?,
	winner: string?,
	lastSent: { [string]: { [number]: string } },
	difficulty: string,
	-- hooks implemented below
	emit: (Sim, Types.Event) -> (),
	log: (Sim, string) -> (),
	homeEdge: (Sim, string) -> Vec,
	findFormation: (Sim, number) -> Formation?,
	isVisibleTo: (Sim, string, number) -> boolean,
	hqOf: (Sim, string) -> Formation?,
	simLag: number,
	-- methods
	deploy: (Sim, number, Vec, number) -> (boolean, string?),
	start: (Sim) -> (),
	precheck: (Sim, Types.Command) -> (boolean, string?),
	queueCommand: (Sim, Types.Command, string) -> (number, number),
	step: (Sim) -> (),
	snapshot: (Sim, string, boolean) -> Types.Snapshot,
	clearEvents: (Sim) -> (),
	buildResults: (Sim, string, string) -> Types.Results,
}

local Sim = {}
Sim.__index = Sim

local DT = Config.Sim.DT

function Sim.new(opts: Options): Sim
	local self: any = setmetatable({}, Sim)
	self.matchId = opts.matchId
	self.scenario = opts.scenario
	self.map = opts.map
	self.grid = opts.map.grid
	self.nav = Nav.build(opts.map.grid)
	self.seed = opts.seed
	self.rng = RNG.new(opts.seed)
	self.tick = 0
	self.clock = 0
	self.timeLimit = opts.timeLimit or opts.scenario.timeLimit or Config.Victory.TimeLimitSeconds
	self.state = "deployment"
	self.formations = {}
	self.order = {}
	self.factions = { opts.scenario.factions.player, opts.scenario.factions.enemy }
	self.playerFaction = opts.scenario.factions.player
	self.enemyFaction = opts.scenario.factions.enemy
	self.views = {}
	for _, faction in self.factions do
		self.views[faction] = Visibility.newView()
	end
	self.objectives = Objectives.init(opts.map.objectives)
	self.commands = {}
	self.seqCounter = 0
	self.events = {}
	self.logLines = {}
	self.deployed = {}
	self.stats = {}
	self.result = nil
	self.winner = nil
	self.lastSent = {}
	self.difficulty = opts.difficulty or "normal"
	self.simLag = 0
	for i, def in opts.scenario.units do
		local f = Formation.fromDef(i, def)
		self.formations[i] = f
		self.order[#self.order + 1] = i
	end
	table.sort(self.order)
	return self
end

-- Hooks used by the submodules ---------------------------------------------------------------

function Sim.emit(self: Sim, ev: Types.Event)
	self.events[#self.events + 1] = ev
end

function Sim.log(self: Sim, text: string)
	local m = math.floor(self.clock / 60)
	local s = math.floor(self.clock % 60)
	self.logLines[#self.logLines + 1] = string.format("%02d:%02d %s", m, s, text)
end

function Sim.findFormation(self: Sim, id: number): Formation?
	return self.formations[id]
end

function Sim.isVisibleTo(self: Sim, viewer: string, id: number): boolean
	return Visibility.isVisibleTo(self :: any, viewer, id)
end

function Sim.hqOf(self: Sim, faction: string): Formation?
	for _, id in self.order do
		local f = self.formations[id]
		if f and f.faction == faction and f.class == "hq" and Formation.isActive(f) then
			return f
		end
	end
	return nil
end

-- A faction's home edge is the map edge nearest its deployment zone.
function Sim.homeEdge(self: Sim, faction: string): Vec
	local zone = self.map.deployZones[faction]
	local margin = Config.Morale.RoutExitMargin + 6
	if zone and (zone.z0 + zone.z1) / 2 > self.map.depth / 2 then
		return { x = (zone.x0 + zone.x1) / 2, z = self.map.depth + margin }
	end
	return { x = if zone then (zone.x0 + zone.x1) / 2 else self.map.width / 2, z = -margin }
end

-- Deployment --------------------------------------------------------------------------------

function Sim.deploy(self: Sim, id: number, pos: Vec, heading: number): (boolean, string?)
	if self.state ~= "deployment" then
		return false, "badState"
	end
	local f = self.formations[id]
	if not f then
		return false, "destroyed"
	end
	if not MapGen.inZone(self.map, f.faction, pos) then
		return false, "deployZone"
	end
	if not Grid.terrainAt(self.grid, pos.x, pos.z).passable or not Grid.fits(self.grid, pos.x, pos.z, 8) then
		return false, "noSpace"
	end
	for _, oid in self.order do
		local o = self.formations[oid]
		if o and oid ~= id and o.faction == f.faction then
			local minD = o.halfRadius + f.halfRadius + Config.Match.DeploymentMinSpacing
			if Vec.dist2(o.pos, pos) < minD * minD then
				return false, "noSpace"
			end
		end
	end
	f.pos = { x = pos.x, z = pos.z }
	f.heading = Vec.wrapAngle(heading)
	return true, nil
end

function Sim.start(self: Sim)
	if self.state ~= "deployment" then
		return
	end
	self.state = "running"
	for _, faction in self.factions do
		self.deployed[faction] = 0
	end
	for _, id in self.order do
		local f = self.formations[id]
		if f then
			self.deployed[f.faction] += f.strength
			Formation.refreshFootprint(f)
		end
	end
	Visibility.update(self :: any)
	self:log("The battle begins")
end

-- Commands ----------------------------------------------------------------------------------

-- Synchronous legality that the network layer can report immediately.
function Sim.precheck(self: Sim, cmd: Types.Command): (boolean, string?)
	for _, id in cmd.ids do
		local f = self.formations[id]
		if not f then
			return false, "destroyed"
		end
		if cmd.kind ~= "Deploy" then
			local ok, reason = Formation.canTakeOrders(f)
			if not ok then
				return false, reason
			end
			if cmd.kind == "Rally" and f.timers.rallyCd > 0 then
				return false, "cooldown"
			end
		end
	end
	return true, nil
end

function Sim.queueCommand(self: Sim, cmd: Types.Command, faction: string): (number, number)
	self.seqCounter += 1
	local q: any = table.clone(cmd)
	q.seq = self.seqCounter
	q.effectiveTick = self.tick + Config.Sim.CommandDelayTicks
	q.faction = faction
	self.commands[#self.commands + 1] = q
	return q.seq, q.effectiveTick
end

-- Group move: assign slots along a line perpendicular to the heading, ordered by each
-- formation's current lateral position so units do not cross over.
local function groupSlots(self: Sim, ids: { number }, pos: Vec, heading: number?, frontage: number?): { [number]: Vec }
	local out: { [number]: Vec } = {}
	if #ids == 1 then
		out[ids[1]] = pos
		return out
	end
	local centroid = { x = 0, z = 0 }
	local n = 0
	for _, id in ids do
		local f = self.formations[id]
		if f then
			centroid = Vec.add(centroid, f.pos)
			n += 1
		end
	end
	centroid = Vec.scale(centroid, 1 / math.max(1, n))
	local h = heading or Vec.heading(Vec.sub(pos, centroid))
	local right = Vec.right(Vec.fromHeading(h))
	local sorted = table.clone(ids)
	table.sort(sorted, function(a, b)
		local fa, fb = self.formations[a], self.formations[b]
		return Vec.dot(fa.pos, right) < Vec.dot(fb.pos, right)
	end)
	local total = 0
	for _, id in sorted do
		total += self.formations[id].width + 6
	end
	if frontage and frontage > total then
		total = frontage
	end
	local gap = (total - (function()
		local s = 0
		for _, id in sorted do
			s += self.formations[id].width
		end
		return s
	end)()) / #sorted
	local cursor = -total / 2
	for _, id in sorted do
		local w = self.formations[id].width
		local centre = cursor + gap / 2 + w / 2
		local p = Vec.add(pos, Vec.scale(right, centre))
		p = Vec.clamp(p, 4, 4, self.map.width - 4, self.map.depth - 4)
		out[id] = p
		cursor += w + gap
	end
	return out
end

local function applyOrder(self: Sim, f: Formation, order: Types.Order, queue: boolean)
	if queue and (f.order ~= nil) then
		if #f.queue < Config.Match.MaxQueue then
			f.queue[#f.queue + 1] = order
		end
		return
	end
	f.order = order
	f.queue = {}
	f.path = nil
	f.pathIndex = 1
	f.targetId = order.targetId
	f.timers.stuck = 0
	if f.state == "melee" then
		-- Disengaging: allowed but costs cohesion; combat continues until out of contact.
		f.cohesion = math.max(0.3, f.cohesion - 0.15)
	end
	if order.kind == "Charge" then
		f.state = "charging"
		f.runUp = 0
		f.chargeReady = f.timers.chargeRecover <= 0
	elseif order.kind == "Face" or order.kind == "Hold" then
		if f.state == "moving" or f.state == "charging" then
			f.state = "idle"
		end
	elseif order.kind == "Engage" and f.class == "artillery" then
		f.state = if f.state == "moving" then "idle" else f.state
	else
		if f.state ~= "reforming" then
			f.state = if order.kind == "Retreat" then "retreating" else "moving"
		end
	end
end

local function applyCommand(self: Sim, cmd: QueuedCommand)
	local kind = cmd.kind
	local data: any = cmd.data or {}
	local queue = data.queue == true
	if kind == "Move" or kind == "AttackMove" or kind == "Charge" and data.targetId == nil then
		local slots = groupSlots(self, cmd.ids, data.pos, data.heading, data.frontage)
		for _, id in cmd.ids do
			local f = self.formations[id]
			if f and Formation.canTakeOrders(f) then
				applyOrder(self, f, { kind = kind, pos = slots[id], heading = data.heading, issuedTick = self.tick, anchor = { x = f.pos.x, z = f.pos.z } }, queue)
			end
		end
		return
	end
	for _, id in cmd.ids do
		local f = self.formations[id]
		if f and Formation.canTakeOrders(f) then
			if kind == "Engage" or kind == "Charge" then
				local target = self.formations[data.targetId]
				if target and Formation.isActive(target) and target.faction ~= f.faction then
					applyOrder(self, f, { kind = kind, targetId = target.id, issuedTick = self.tick, anchor = { x = f.pos.x, z = f.pos.z } }, queue)
				else
					self:emit({ kind = "message", tick = self.tick, id = f.id, faction = f.faction, text = f.name .. ": target is gone" })
				end
			elseif kind == "Stop" then
				Formation.clearOrder(f)
			elseif kind == "Hold" then
				applyOrder(self, f, { kind = "Hold", issuedTick = self.tick }, false)
			elseif kind == "Face" then
				applyOrder(self, f, { kind = "Face", heading = Vec.wrapAngle(data.heading), issuedTick = self.tick }, queue)
			elseif kind == "Retreat" then
				local pos = data.pos
				if not pos then
					local home = self:homeEdge(f.faction)
					local dir = Vec.normalize(Vec.sub(home, f.pos))
					pos = Vec.clamp(Vec.add(f.pos, Vec.scale(dir, 200)), 8, 8, self.map.width - 8, self.map.depth - 8)
				end
				f.cohesion = math.max(0.3, f.cohesion - 0.2)
				applyOrder(self, f, { kind = "Retreat", pos = pos, issuedTick = self.tick }, false)
			elseif kind == "Shape" then
				if Formation.legalShapes(f)[data.shape] then
					f.prevShape = nil
					Formation.beginShape(f, data.shape, false)
				end
			elseif kind == "Stance" then
				f.fireAtWill = data.fireAtWill == true
			elseif kind == "Limber" then
				local wantLimbered = data.limbered == true
				if Formation.isLimbered(f) ~= wantLimbered and f.pendingLimber == nil then
					f.pendingLimber = wantLimbered
					f.timers.limber = if wantLimbered then Config.ReformTime.limbered else Config.ReformTime.deployed
					f.state = "reforming"
					f.path = nil
					if wantLimbered then
						f.targetId = nil
					end
				end
			elseif kind == "Ammo" then
				f.ammoMode = data.ammo
			elseif kind == "Rally" then
				Morale.hqRally(self :: any, f)
			end
		end
	end
end

local function applyQueuedCommands(self: Sim)
	if #self.commands == 0 then
		return
	end
	table.sort(self.commands, function(a: QueuedCommand, b: QueuedCommand)
		if a.effectiveTick ~= b.effectiveTick then
			return a.effectiveTick < b.effectiveTick
		end
		return a.seq < b.seq
	end)
	local remaining = {}
	for _, cmd in self.commands do
		if cmd.effectiveTick <= self.tick then
			applyCommand(self, cmd)
		else
			remaining[#remaining + 1] = cmd
		end
	end
	self.commands = remaining
end

-- Tick ----------------------------------------------------------------------------------------

-- AI hook: assigned by the match layer; called on schedule with the sim.
Sim.aiStep = nil :: ((Sim) -> ())?

function Sim.step(self: Sim)
	if self.state ~= "running" then
		return
	end
	self.tick += 1
	self.clock = self.tick * DT
	local s: any = self
	-- 1. commands
	applyQueuedCommands(self)
	-- 2. AI
	local ai: ((Sim) -> ())? = (Sim :: any).aiStep
	if ai and self.tick % Config.AI.DecisionTicks == 0 then
		ai(self)
		applyQueuedCommands(self) -- AI commands stamped for this tick apply now
	end
	-- 3/4. timers, navigation, movement
	for _, id in self.order do
		local f = self.formations[id]
		if f and Formation.isActive(f) then
			Movement.updateTimers(s, f)
		end
	end
	for _, id in self.order do
		local f = self.formations[id]
		if f then
			Movement.update(s, f)
		end
	end
	-- 5. visibility
	if self.tick % Config.Sim.VisibilityEveryTicks == 0 then
		Visibility.update(s)
	end
	-- 6/7. combat
	local attacks = Combat.gather(s)
	Combat.apply(s, attacks)
	-- 8. morale
	for _, id in self.order do
		local f = self.formations[id]
		if f then
			Morale.update(s, f)
		end
	end
	-- 9. objectives
	Objectives.update(s)
	-- 10. victory
	local winner, reason = Objectives.evaluate(s)
	if winner then
		self.state = "ended"
		self.winner = winner
		self.result = (self :: any):buildResults(winner, reason or "")
		self:log("Battle over: " .. (reason or ""))
	end
end

-- Snapshots -----------------------------------------------------------------------------------

local function viewOf(f: Formation, own: boolean): Types.FormationView
	local v: Types.FormationView = {
		id = f.id,
		faction = f.faction,
		name = f.name,
		corps = f.corps,
		class = f.class,
		colour = f.colour,
		x = f.pos.x,
		z = f.pos.z,
		heading = f.heading,
		shape = f.shape,
		state = f.state,
		strength = if own then f.strength else math.floor(f.strength / 50 + 0.5) * 50,
		startStrength = f.startStrength,
		moraleBand = Formation.moraleBandOf(f),
		width = f.width,
		depth = f.depth,
		commander = f.commander,
		experience = f.experience,
	}
	if own then
		v.morale = f.morale
		v.fatigue = f.fatigue
		v.ammo = f.ammo
		v.reload = f.reload
		v.cohesion = f.cohesion
		v.orderKind = if f.order then f.order.kind else nil
		v.targetId = f.targetId
		v.fireAtWill = f.fireAtWill
		v.limbered = if f.class == "artillery" then Formation.isLimbered(f) else nil
		v.status = f.status
		if f.state == "reforming" then
			v.status = "Reforming"
		elseif f.state == "routing" then
			v.status = "Routing"
		elseif f.state == "rallying" then
			v.status = "Rallying"
		elseif f.fatigue > Config.Morale.FatigueThreshold then
			v.status = v.status or "Exhausted"
		elseif f.hitSide then
			v.status = "Flanked"
		end
		v.rallyCd = if f.class == "hq" then f.timers.rallyCd else nil
		if f.order and f.order.pos then
			v.dest = f.order.pos
			v.destHeading = f.order.heading
		end
		v.ammoMode = if f.class == "artillery" then f.ammoMode else nil
		if #f.queue > 0 then
			local q = {}
			for _, o in f.queue do
				if o.pos then
					q[#q + 1] = o.pos
				end
			end
			v.queue = q
		end
	end
	return v
end

local function viewKey(v: Types.FormationView): string
	return string.format("%.1f|%.1f|%.2f|%s|%s|%d|%s|%s|%s|%s|%s|%s", v.x, v.z, v.heading, v.shape, v.state, v.strength, v.moraleBand, tostring(v.status), tostring(v.orderKind), tostring(v.fireAtWill), tostring(v.ammo), tostring(math.floor((v.morale or 0) / 2)))
end

-- Build the snapshot for one viewer faction. Pass full=true for keyframes.
function Sim.snapshot(self: Sim, viewer: string, full: boolean): Types.Snapshot
	local view = self.views[viewer]
	local formations: { Types.FormationView } = {}
	local removed: { number } = {}
	local last = self.lastSent[viewer]
	if not last or full then
		last = {}
		full = true
	end
	local nowKeys: { [number]: string } = {}
	for _, id in self.order do
		local f = self.formations[id]
		if f then
			local own = f.faction == viewer
			local show = Formation.isActive(f) and (own or (view and view.visible[id]))
			if show then
				local v = viewOf(f, own)
				local key = viewKey(v)
				nowKeys[id] = key
				if full or last[id] ~= key then
					formations[#formations + 1] = v
				end
			elseif last[id] then
				removed[#removed + 1] = id
			end
		end
	end
	self.lastSent[viewer] = nowKeys
	local lastKnown: { Types.LastKnown } = {}
	if view then
		for _, lk in view.lastKnown do
			lastKnown[#lastKnown + 1] = lk
		end
		table.sort(lastKnown, function(a: Types.LastKnown, b: Types.LastKnown)
			return a.id < b.id
		end)
	end
	-- Events: hide positions of unseen enemy actors.
	local events: { Types.Event } = {}
	for _, ev in self.events do
		local copy: Types.Event = table.clone(ev)
		if ev.id and ev.faction and ev.faction ~= viewer and not self:isVisibleTo(viewer, ev.id) then
			if ev.targetId and self.formations[ev.targetId] and self.formations[ev.targetId].faction == viewer then
				copy.x = nil
				copy.z = nil
				copy.id = nil
			else
				continue
			end
		end
		events[#events + 1] = copy
	end
	return {
		matchId = self.matchId,
		tick = self.tick,
		seq = self.tick,
		kind = if full then "full" else "delta",
		state = self.state,
		formations = formations,
		lastKnown = lastKnown,
		events = events,
		objectives = Objectives.view(self :: any),
		clock = self.clock,
		timeLimit = self.timeLimit,
		speed = 1,
		simLag = self.simLag,
		viewer = viewer,
		removed = if #removed > 0 then removed else nil,
	}
end

-- Call after all viewers have been served for this publish.
function Sim.clearEvents(self: Sim)
	self.events = {}
end

-- Results ------------------------------------------------------------------------------------

function Sim.buildResults(self: Sim, winner: string, reason: string): Types.Results
	local sides: { [string]: any } = {}
	for _, faction in self.factions do
		local s = { deployed = self.deployed[faction] or 0, casualties = 0, remaining = 0, surviving = 0, routed = 0, shattered = 0, destroyed = 0, exited = 0, formations = 0 }
		for _, id in self.order do
			local f = self.formations[id]
			if f and f.faction == faction then
				s.formations += 1
				if f.state == "destroyed" then
					s.destroyed += 1
					s.casualties += f.startStrength
				elseif f.state == "exited" then
					s.exited += 1
					s.casualties += f.startStrength
				else
					s.remaining += f.strength
					s.casualties += f.startStrength - f.strength
					if f.shattered then
						s.shattered += 1
					elseif f.state == "routing" or f.state == "rallying" then
						s.routed += 1
					else
						s.surviving += 1
					end
				end
			end
		end
		sides[faction] = s
	end
	local outcome: "victory" | "defeat" | "draw" = if winner == "draw" then "draw" elseif winner == self.playerFaction then "victory" else "defeat"
	local feedback: { string } = {}
	local p = sides[self.playerFaction]
	if p.routed + p.shattered > p.formations / 3 then
		feedback[#feedback + 1] = "More than a third of your formations broke. Keep the general close to the line and rest shaken units behind it."
	end
	local charges, squares = 0, 0
	for _, line in self.logLines do
		if string.find(line, "square", 1, true) then
			squares += 1
		end
		if string.find(line, "charged", 1, true) then
			charges += 1
		end
	end
	if squares > 0 then
		feedback[#feedback + 1] = "Cavalry charged a formed square. Charge flanks, guns or broken troops instead."
	end
	if p.casualties > 0 and sides[self.enemyFaction].casualties > p.casualties * 1.5 then
		feedback[#feedback + 1] = "Your fire was far more effective than the enemy's: good use of ground and facing."
	end
	if #feedback == 0 then
		feedback[#feedback + 1] = "A balanced action. Concentrate fire on one formation at a time to break it faster."
	end
	return {
		outcome = outcome,
		reason = reason,
		clock = self.clock,
		objectives = Objectives.view(self :: any),
		sides = sides,
		feedback = feedback,
		log = self.logLines,
	}
end

return Sim
