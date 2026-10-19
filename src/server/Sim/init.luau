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
local Abilities = require(script.Abilities)
local Nav = require(script.Nav)
local Edges = require(script.Edges)
local Movement = require(script.Movement)
local Combat = require(script.Combat)
local Morale = require(script.Morale)
local Visibility = require(script.Visibility)
local Objectives = require(script.Objectives)
local Moments = require(script.Moments)

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
	weather: string, -- key into Config.Weather, may change once at weatherUntil (or by a moment)
	momentsFired: { [string]: boolean }, -- scenario moments already fired (Sim/Moments)
	aiStep: ((Sim) -> ())?, -- per-instance AI hook (preferred over the module-level Sim.aiStep)
	-- methods
	deploy: (Sim, number, Vec, number) -> (boolean, string?),
	start: (Sim) -> (),
	precheck: (Sim, Types.Command) -> (boolean, string?),
	queueCommand: (Sim, Types.Command, string) -> (number, number),
	step: (Sim) -> (),
	snapshot: (Sim, string, boolean) -> Types.Snapshot,
	clearEvents: (Sim) -> (),
	buildResults: (Sim, string, string, string?) -> Types.Results,
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
	self.aiStep = nil
	self.momentsFired = {}
	self.weather = if (Config.Weather :: any)[(opts.scenario :: any).weather] then (opts.scenario :: any).weather else "clear"
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
	local zones = self.map.deployZones
	local zone = zones[faction]
	local margin = Config.Morale.RoutExitMargin + 6
	local w, d = self.map.width, self.map.depth
	local own = if zone then { x = (zone.x0 + zone.x1) / 2, z = (zone.z0 + zone.z1) / 2 } else { x = w / 2, z = d / 2 }
	local enemy: Vec? = nil
	for other, oz in zones do
		if other ~= faction and (other == self.playerFaction or other == self.enemyFaction) then
			enemy = { x = (oz.x0 + oz.x1) / 2, z = (oz.z0 + oz.z1) / 2 }
		end
	end
	return Edges.home(own, enemy, w, d, margin)
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
	if f.state == "offmap" then
		return false, "badState"
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
	-- A group order goes to the formations that can take it: one routing battalion in a box
	-- selection used to get the whole order refused, so the rest of the brigade stood still.
	if #cmd.ids > 1 and cmd.kind ~= "Deploy" then
		local able: { number } = {}
		for _, id in cmd.ids do
			local f = self.formations[id]
			if f and Formation.canTakeOrders(f) then
				able[#able + 1] = id
			end
		end
		if #able > 0 then
			cmd.ids = able
		end
	end
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
			if cmd.kind == "Ability" then
				local okA, whyA = Abilities.check(self :: any, f, cmd.data)
				if not okA then
					return false, whyA
				end
			end
		end
	end
	-- Engage/Charge on a target the faction cannot currently see leaks nothing: it is
	-- converted to an attack-move on the last-known position, or refused if there is none.
	if (cmd.kind == "Engage" or cmd.kind == "Charge") and cmd.data and type(cmd.data.targetId) == "number" then
		local f = self.formations[cmd.ids[1]]
		local target = self.formations[cmd.data.targetId]
		if not target or not Formation.isActive(target) then
			return false, "badTarget"
		end
		if f and not self:isVisibleTo(f.faction, target.id) then
			local lk = self.views[f.faction] and self.views[f.faction].lastKnown[target.id]
			if not lk then
				return false, "badTarget"
			end
			cmd.kind = "AttackMove"
			cmd.data = { pos = { x = lk.x, z = lk.z }, queue = cmd.data.queue }
			if f.class == "artillery" then
				return false, "badTarget"
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
				applyOrder(self, f, { kind = kind, pos = slots[id], heading = data.heading, issuedTick = self.tick, anchor = { x = f.pos.x, z = f.pos.z }, run = data.run == true or nil }, queue)
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
				if not f.mods.steadyRetreat then
					f.cohesion = math.max(0.3, f.cohesion - 0.2)
				end
				applyOrder(self, f, { kind = "Retreat", pos = pos, issuedTick = self.tick }, false)
			elseif kind == "Shape" then
				if Formation.legalShapes(f)[data.shape] then
					f.prevShape = nil
					Formation.beginShape(f, data.shape, false)
				end
			elseif kind == "Stance" then
				f.fireAtWill = data.fireAtWill == true
			elseif kind == "Run" then
				if f.order then
					f.order.run = data.run == true or nil
				end
			elseif kind == "Limber" then
				local wantLimbered = data.limbered == true
				if Formation.isLimbered(f) ~= wantLimbered and f.pendingLimber == nil then
					f.pendingLimber = wantLimbered
					f.timers.limber = (if wantLimbered then Config.ReformTime.limbered else Config.ReformTime.deployed) * (Formation.unitConfig(f).reformScale or 1)
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
			elseif kind == "Ability" then
				Abilities.use(self :: any, f, data)
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

-- Attack-move: engage visible enemies met on the way, then resume the march.
-- Infantry halts once a target is in musket range and fires; cavalry charges a target that is not
-- in square (or a battery / routing unit) within its charge reach.
local CAV_REACH = 180
local function autoEngage(self: Sim)
	for _, id in self.order do
		local f = self.formations[id]
		local o = f and f.order
		if f and o and o.kind == "AttackMove" and Formation.isActive(f) and (f.state == "moving" or f.state == "idle" or f.state == "firing") then
			local best: Formation? = nil
			local bestD = math.huge
			for _, eid in self.order do
				local e = self.formations[eid]
				if e and e.faction ~= f.faction and Formation.isActive(e) and self:isVisibleTo(f.faction, eid) then
					local d = Vec.dist(f.pos, e.pos)
					if d < bestD then
						best = e
						bestD = d
					end
				end
			end
			if f.class == "cavalry" then
				if best and bestD <= CAV_REACH and best.shape ~= "square" and f.timers.chargeRecover <= 0 and not f.inWoods then
					local resume = table.clone(o)
					f.order = { kind = "Charge", targetId = best.id, issuedTick = self.tick, anchor = { x = f.pos.x, z = f.pos.z } }
					f.queue = { resume }
					f.path = nil
					f.state = "charging"
					f.runUp = 0
					f.chargeReady = true
				end
			elseif f.class == "infantry" then
				local range = Formation.unitConfig(f).musket.range
				-- A travel column cannot fire, so it marches on until it can re-form (halting would
				-- also drop the path the column needs to restore its shape).
				-- Halt only where it can shoot: a line halted with the target hidden (village, crest,
				-- friends in the lane) neither fired nor marched on, and stood idle for good.
				local why = if best and bestD <= range * 0.95 then Combat.fireBlockReason(self :: any, f, best) else "Out of range"
				local canShoot = why == nil or why == "Reloading" or why == "Target not to the front"
				if best and canShoot and f.shape ~= "travel" and f.pendingShape ~= "travel" then
					if f.state == "moving" then
						f.path = nil
						f.state = "idle"
						f.targetId = best.id
					end
					-- face the target; the line wheels in place (every pass, or a target outside the
					-- arc after the first half-turn is never fired on)
					f.heading = f.heading + Vec.angleDiff(f.heading, Vec.heading(Vec.sub(best.pos, f.pos))) * 0.5
				elseif f.state == "idle" or f.state == "firing" then
					f.state = "moving" -- nothing in range any more: resume the march
					f.targetId = nil
				end
			end
		end
	end
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
	-- 0. weather clearing, reinforcements entering the field
	local until_ = (self.scenario :: any).weatherUntil
	if self.weather ~= "clear" and type(until_) == "number" and self.clock >= until_ then
		self.weather = "clear"
		self:emit({ kind = "message", tick = self.tick, text = "The weather clears" })
		self:log("Weather cleared")
	end
	for _, id in self.order do
		local f = self.formations[id]
		if f and f.state == "offmap" and f.arrivalTick and f.arrivalTick <= self.tick then
			f.state = "idle"
			f.arrivalTick = nil
			self:emit({ kind = "message", tick = self.tick, id = f.id, faction = f.faction, x = f.pos.x, z = f.pos.z, text = f.name .. " arrives on the field" })
			self:log(f.name .. " arrived")
		end
	end
	-- 1. commands
	applyQueuedCommands(self)
	if self.tick % 5 == 0 then
		autoEngage(self)
	end
	-- 2. AI
	local ai: ((Sim) -> ())? = (self :: any).aiStep or (Sim :: any).aiStep
	if ai and self.tick % Config.AI.DecisionTicks == 0 then
		ai(self)
		applyQueuedCommands(self) -- AI commands stamped for this tick apply now
	end
	Abilities.update(s) -- generals' traits and ability effects -> formation mods
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
	Moments.update(s) -- historical moments, every Moments.EveryTicks
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
		type = f.type,
		colour = f.colour,
		x = f.pos.x,
		z = f.pos.z,
		heading = f.heading,
		shape = f.shape,
		state = f.state,
		-- Enemy strength is an estimate: nearest 50, but small bodies never show as zero.
		strength = if own then f.strength elseif f.strength < 75 then math.max(10, math.floor(f.strength / 10 + 0.5) * 10) else math.floor(f.strength / 50 + 0.5) * 50,
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
		v.running = if f.order and f.order.run then true else nil
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
	return string.format("%.1f|%.1f|%.2f|%s|%s|%d|%s|%s|%s|%s|%s|%s|%d", v.x, v.z, v.heading, v.shape, v.state, v.strength, v.moraleBand, tostring(v.status), tostring(v.orderKind), tostring(v.fireAtWill) .. tostring(v.running), tostring(v.ammo), tostring(math.floor((v.morale or 0) / 2)), math.ceil(v.reload or 0)) .. (v.tags or "") .. tostring(v.abilityReadyAt) -- reload in whole seconds so cards stay current
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
				if own then
					Abilities.view(self :: any, f, v)
				end
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
	-- Own reinforcements still off the map.
	local reinforcements = {}
	for _, id in self.order do
		local f = self.formations[id]
		if f and f.faction == viewer and f.state == "offmap" and f.arrivalTick then
			reinforcements[#reinforcements + 1] = { id = f.id, name = f.name, corps = f.corps, eta = math.max(0, (f.arrivalTick - self.tick) * DT) }
		end
	end
	-- Events: hide positions of unseen enemy actors.
	local events: { Types.Event } = {}
	for _, ev in self.events do
		local copy: Types.Event = table.clone(ev)
		if (ev.kind == "message" or ev.kind == "moment") and ev.faction and ev.faction ~= viewer then
			continue -- the enemy's own order/route messages (and its own moments) are never shown to us
		end
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
		reinforcements = if #reinforcements > 0 then reinforcements else nil,
		weather = self.weather,
	}
end

-- Call after all viewers have been served for this publish.
function Sim.clearEvents(self: Sim)
	self.events = {}
end

-- Results ------------------------------------------------------------------------------------

-- `viewer` (default the player faction) is the side the outcome and feedback are written for.
function Sim.buildResults(self: Sim, winner: string, reason: string, viewer: string?): Types.Results
	local me = viewer or self.playerFaction
	local them = if me == self.playerFaction then self.enemyFaction else self.playerFaction
	local sides: { [string]: any } = {}
	for _, faction in self.factions do
		local s = { deployed = self.deployed[faction] or 0, casualties = 0, remaining = 0, surviving = 0, routed = 0, shattered = 0, destroyed = 0, exited = 0, formations = 0, routEvents = 0 }
		for _, id in self.order do
			local f = self.formations[id]
			if f and f.faction == faction then
				s.formations += 1
				s.routEvents += f.routCount -- every rout during the battle, including those that rallied
				if f.state == "offmap" then
					s.remaining += f.strength
					s.surviving += 1
				elseif f.state == "destroyed" then
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
	local outcome: "victory" | "defeat" | "draw" = if winner == "draw" then "draw" elseif winner == me then "victory" else "defeat"
	local feedback: { string } = {}
	local p = sides[me]
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
	if p.casualties > 0 and sides[them].casualties > p.casualties * 1.5 then
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
