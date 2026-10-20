--!strict
-- Enemy commander. Pure Luau, deterministic: reads its own formations fully, the enemy only
-- through sim.views[faction] (visible ids + last-known memory), randomness only via sim.rng.
-- Orders go through sim:queueCommand with the same command kinds the player uses.
--
-- Hierarchy: army plan (posture, wing roles, gun/HQ/reserve positions, every ~20 s or on a
-- trigger) -> per-formation decisions each decision tick with commitment so goals do not flap.
-- Postures: defend (hold own-side objectives, shifting toward the one under attack), advance
-- (holding no more objectives than the enemy would lose on the clock: attack-move on the nearest
-- objective not ours), attack (a seen enemy outnumbered 1.5:1), withdraw (half the army broken).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local Grid = require(Shared.Grid)
local Protocol = require(Shared.Protocol)
local MapGen = require(Shared.MapGen)

local Sim = require(script.Parent.Sim)
local Formation = require(script.Parent.Sim.Formation)
local Combat = require(script.Parent.Sim.Combat)
local Nav = require(script.Parent.Sim.Nav)
local Abilities = require(script.Parent.Sim.Abilities)
local Objectives = require(script.Parent.Sim.Objectives)

type Vec = Vec.Vec
type Formation = Formation.Formation
type SimLike = Sim.Sim

-- What the AI knows about one enemy: live when visible (age 0), otherwise a stale memory.
type Known = { id: number, pos: Vec, class: string, heading: number, shape: string, age: number, strength: number }

type Unit = {
	goal: string,
	reason: string,
	role: string, -- left | centre | right | reserve | guns | hq
	placed: boolean, -- infantry: given its role (the first plan, or on arriving as a reinforcement)
	commitUntil: number,
	squareUntil: number,
	withdrawUntil: number,
	nextMove: number, -- throttle for maintenance moves / facing
	orderedStep: number, -- decision step of the last command that included this unit
	point: Vec?, -- goal point for guard / exploit goals
	lastPos: Vec?, -- artillery: where it was at lastPosAt (progress check while limbered)
	lastPosAt: number,
	guardId: number?, -- infantry on guard: the battery it covers
}

export type AIState = {
	sim: SimLike,
	faction: string,
	enemy: string,
	reaction: number,
	planQuality: number,
	n: number,
	steps: number,
	budget: number,
	posture: string,
	forward: Vec,
	right: Vec,
	facing: number,
	reserve: Vec,
	hqPos: Vec,
	wingPos: { [string]: Vec },
	gunPos: { [number]: Vec },
	nextPlan: number,
	rolesAssigned: boolean,
	held: { [string]: boolean }, -- objectives this side has held: worth taking back
	units: { [number]: Unit },
	mine: { Formation },
	visible: { Formation },
	known: { Known },
}

local AI = {}

local PATH_CMDS = { Move = true, AttackMove = true, Engage = true, Charge = true, Retreat = true, Garrison = true }
local MAX_PATH_CMDS = 8
local WINGS = { "centre", "left", "right" }
local MUSKET = Config.Units.infantry.musket.range

-- Helpers ------------------------------------------------------------------------------------

local function unitOf(state: AIState, id: number): Unit
	local u = state.units[id]
	if u then
		return u
	end
	local fresh: Unit = { goal = "idle", reason = "", role = "reserve", placed = false, commitUntil = 0, squareUntil = 0, withdrawUntil = 0, nextMove = 0, orderedStep = -1, point = nil, lastPos = nil, lastPosAt = 0, guardId = nil }
	state.units[id] = fresh
	return fresh
end

local function setGoal(state: AIState, id: number, goal: string, reason: string, commit: number?)
	local u = unitOf(state, id)
	u.goal = goal
	u.reason = reason
	u.commitUntil = state.sim.clock + (commit or Config.AI.CommitSeconds) * state.reaction
end

local function committed(state: AIState, u: Unit): boolean
	return state.sim.clock < u.commitUntil
end

-- planQuality < 1: deterministically skip some good choices.
local function quality(state: AIState): boolean
	if state.planQuality >= 1 then
		return true
	end
	return state.sim.rng:chance(state.planQuality)
end

local function walkable(state: AIState, p: Vec): Vec
	local sim = state.sim
	local c = Vec.clamp(p, 16, 16, sim.grid.width - 16, sim.grid.depth - 16)
	return Nav.nearestWalkable(sim.nav, c, 8) or c
end

local function inCover(state: AIState, p: Vec): boolean
	return Grid.terrainAt(state.sim.grid, p.x, p.z).blocksSight
end

local function healthy(f: Formation): boolean
	return not Formation.isBroken(f) and f.moraleBand ~= "shaken"
end

local function damaged(f: Formation): boolean
	return f.strength < f.startStrength * 0.5 or f.moraleBand == "shaken"
end

-- Issue one command the way the player would. Returns true when queued.
local function issue(state: AIState, kind: string, ids: { number }, data: { [string]: any }?): boolean
	local sim = state.sim
	if #ids == 0 or #ids > Config.Net.MaxBatch then
		return false
	end
	local allowed = Protocol.CommandKinds[kind]
	for _, id in ids do
		local f = sim.formations[id]
		if not f or f.faction ~= state.faction or (type(allowed) == "table" and not allowed[f.class]) then
			return false
		end
		if kind == "Shape" and data and not Formation.legalShapes(f)[data.shape] then
			return false
		end
	end
	if PATH_CMDS[kind] and state.budget <= 0 then
		return false
	end
	local cmd = { matchId = sim.matchId, requestId = "ai-" .. (state.n + 1), kind = kind, ids = ids, data = data or {} }
	if not (sim :: any):precheck(cmd) then
		return false
	end
	state.n += 1
	if PATH_CMDS[kind] then
		state.budget -= 1
	end
	for _, id in ids do
		unitOf(state, id).orderedStep = state.steps
	end
	(sim :: any):queueCommand(cmd, state.faction)
	return true
end

local function nearestVisible(state: AIState, pos: Vec, maxDist: number, pred: ((Formation) -> boolean)?): (Formation?, number)
	local best: Formation? = nil
	local bestD = maxDist
	for _, e in state.visible do
		if not pred or pred(e) then
			local d = Vec.dist(pos, e.pos)
			if d < bestD then
				best, bestD = e, d
			end
		end
	end
	return best, bestD
end

local function nearestKnownDist(state: AIState, pos: Vec, maxAge: number): number
	local best = math.huge
	for _, k in state.known do
		if k.age <= maxAge then
			best = math.min(best, Vec.dist(pos, k.pos))
		end
	end
	return best
end

local function nearestOwn(state: AIState, pos: Vec, pred: (Formation) -> boolean): (Formation?, number)
	local best: Formation? = nil
	local bestD = math.huge
	for _, f in state.mine do
		if pred(f) then
			local d = Vec.dist(pos, f.pos)
			if d < bestD then
				best, bestD = f, d
			end
		end
	end
	return best, bestD
end

local function isCav(e: Formation): boolean
	return e.class == "cavalry" and e.state ~= "routing"
end

-- Perception: only what the faction's view exposes. ----------------------------------------------

local function perceive(state: AIState)
	local sim = state.sim
	local view = sim.views[state.faction]
	local mine: { Formation } = {}
	local visible: { Formation } = {}
	local known: { Known } = {}
	for _, id in sim.order do
		local f = sim.formations[id]
		if f and Formation.isActive(f) then
			if f.faction == state.faction then
				mine[#mine + 1] = f
			elseif view.visible[id] then
				visible[#visible + 1] = f
				-- strength as the player sees it (rounded)
				known[#known + 1] = { id = id, pos = f.pos, class = f.class, heading = f.heading, shape = f.shape, age = 0, strength = math.floor(f.strength / 50 + 0.5) * 50 }
			end
		end
	end
	local ids: { number } = {}
	for id in view.lastKnown do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ids do
		local lk = view.lastKnown[id]
		known[#known + 1] = { id = id, pos = { x = lk.x, z = lk.z }, class = lk.class, heading = lk.heading, shape = lk.shape, age = lk.ageSeconds, strength = 0 }
	end
	state.mine, state.visible, state.known = mine, visible, known
end

-- Army plan ----------------------------------------------------------------------------------------

-- An objective we hold, or a neutral one on our side of the field (defend walks onto it anyway).
local function onOurSide(state: AIState, o: any): boolean
	local sim = state.sim
	local p = o.def.pos
	return o.owner == state.faction or (o.owner == nil and (MapGen.inZone((sim :: any).map, state.faction, p) or Vec.dist(p, sim:homeEdge(state.faction)) < Vec.dist(p, sim:homeEdge(state.enemy))))
end

local function desiredPosture(state: AIState): string
	local sim = state.sim
	local ownStr, broken, total, seen = 0, 0, 0, 0
	for _, f in state.mine do
		total += 1
		if Formation.isBroken(f) then
			broken += 1
		else
			ownStr += f.strength
		end
	end
	for _, k in state.known do
		seen += k.strength
	end
	if total == 0 or broken >= total * 0.5 or ownStr < Objectives.fieldDeployed(sim :: any, state.faction) * 0.45 then
		return "withdraw"
	end
	-- The battle's roles (Scenario.attacker): the defender holds its ground, whatever part of the
	-- attacker's army it sees; the attacker keeps coming while the enemy holds any objective.
	local attacker = (sim.scenario :: any).attacker
	if attacker == state.enemy then
		return "defend"
	end
	if seen >= ownStr * 0.4 and ownStr > seen * 1.5 then
		return "attack"
	end
	-- Holding no more objectives than the enemy loses (or draws) on the clock: go and take one.
	-- Neutral objectives on our side of the field count as ours (defend walks onto them anyway).
	local mineN, theirs = 0, 0
	for _, o in sim.objectives do
		if onOurSide(state, o) then
			mineN += 1
		else
			theirs += 1
		end
	end
	if attacker == state.faction and theirs > 0 then
		return "advance"
	end
	local deployed, deployedEnemy = sim.deployed[state.faction] or 1, sim.deployed[state.enemy] or 0
	if theirs > 0 and (mineN < theirs or (mineN == theirs and deployed >= deployedEnemy)) then
		return "advance"
	end
	return "defend"
end

local function lateral(state: AIState, p: Vec): number
	return Vec.dot(p, state.right)
end

-- Gun position: high ground with LOS forward, on a flank of the wing's line (its own infantry
-- would otherwise stand in the fire lane); an attacking line stands at musket range of the
-- enemy, so its guns stand `standoff` further back.
local function pickGunPos(state: AIState, wing: Vec, taken: { Vec }, from: Vec, standoff: number): Vec
	local grid = state.sim.grid
	local probe = Vec.add(wing, Vec.scale(state.forward, 200))
	local best = Vec.sub(wing, Vec.scale(state.forward, 35 + standoff))
	local bestScore = -math.huge
	for _, d in { 10 + standoff, 25 + standoff } do
		for _, s in { -35, 0, 35 } do
			local p = walkable(state, Vec.add(Vec.sub(wing, Vec.scale(state.forward, d)), Vec.scale(state.right, s)))
			local ok = Vec.dist(p, wing) <= 55 + standoff
			for _, t in taken do
				if Vec.dist(t, p) < 24 then
					ok = false
				end
			end
			if ok then
				local score = Grid.heightAt(grid, p.x, p.z) + (if Grid.lineOfSight(grid, p, probe) then 20 else 0) - Vec.dist(p, from) / 20 - (if Vec.distToSegment(wing, p, probe) < 30 then 30 else 0)
				if score > bestScore then
					best, bestScore = p, score
				end
			end
		end
	end
	return best
end

local function plan(state: AIState)
	local sim = state.sim
	local clock = sim.clock
	local home, enemyHome = sim:homeEdge(state.faction), sim:homeEdge(state.enemy)
	local forward = Vec.normalize(Vec.sub(enemyHome, home))
	state.forward, state.right, state.facing = forward, Vec.right(forward), Vec.heading(forward)
	local posture = desiredPosture(state)
	state.posture = posture
	state.nextPlan = clock + 20 * state.reaction

	-- Line of battle: three wing points.
	local zone = (sim :: any).map.deployZones[state.faction]
	local base: Vec = if zone then { x = (zone.x0 + zone.x1) / 2, z = (zone.z0 + zone.z1) / 2 } else { x = sim.grid.width / 2, z = sim.grid.depth / 2 }
	local wing: { [string]: Vec } = {}
	if posture == "attack" then
		local c, n = { x = 0, z = 0 }, 0
		for _, k in state.known do
			if k.age < 90 then
				c, n = Vec.add(c, k.pos), n + 1
			end
		end
		local target = if n > 0 then Vec.scale(c, 1 / n) else enemyHome
		local ownC, m = { x = 0, z = 0 }, 0
		for _, f in state.mine do
			ownC, m = Vec.add(ownC, f.pos), m + 1
		end
		ownC = Vec.scale(ownC, 1 / math.max(1, m))
		local dir = Vec.normalize(Vec.sub(target, ownC))
		state.facing = Vec.heading(dir)
		local centre = Vec.sub(target, Vec.scale(dir, 70))
		local r = Vec.right(dir)
		wing.centre, wing.left, wing.right = centre, Vec.sub(centre, Vec.scale(r, 150)), Vec.add(centre, Vec.scale(r, 150))
	elseif posture == "advance" then
		-- Nearest objective not ours, approached from the army's centre, line 70 short of it.
		local ownC, m = { x = 0, z = 0 }, 0
		for _, f in state.mine do
			ownC, m = Vec.add(ownC, f.pos), m + 1
		end
		ownC = Vec.scale(ownC, 1 / math.max(1, m))
		local target, best = enemyHome, math.huge
		for _, o in sim.objectives do
			local d = Vec.dist(o.def.pos, ownC)
			if o.owner ~= state.faction and d < best then
				target, best = o.def.pos, d
			end
		end
		local dir = Vec.normalize(Vec.sub(target, ownC))
		state.facing = Vec.heading(dir)
		local centre = Vec.sub(target, Vec.scale(dir, 70))
		local r = Vec.right(dir)
		wing.centre, wing.left, wing.right = centre, Vec.sub(centre, Vec.scale(r, 150)), Vec.add(centre, Vec.scale(r, 150))
	elseif posture == "withdraw" then
		local centre = Vec.sub(base, Vec.scale(forward, 200))
		wing.centre, wing.left, wing.right = centre, Vec.sub(centre, Vec.scale(state.right, 140)), Vec.add(centre, Vec.scale(state.right, 140))
	else
		local objs: { Vec } = {}
		for _, o in sim.objectives do
			if onOurSide(state, o) then
				objs[#objs + 1] = Vec.add(o.def.pos, Vec.scale(forward, 25))
			end
		end
		-- A concentrated attack on one objective pulls the unthreatened wings halfway toward it.
		local hot, hotN = nil, 0
		local threat: { number } = {}
		for i, p in objs do
			threat[i] = 0
			for _, k in state.known do
				if k.age < 90 and k.class == "infantry" and Vec.dist(k.pos, p) < 300 then
					threat[i] += 1
				end
			end
			if threat[i] > hotN then
				hot, hotN = p, threat[i]
			end
		end
		if hot then
			for i, p in objs do
				if threat[i] == 0 then
					objs[i] = Vec.lerp(p, hot :: Vec, 0.5)
				end
			end
		end
		-- Objectives with a building are outposts its garrison holds (garrisonBuildings): when the
		-- army has an objective in the open as well, the line stands level with that, behind them,
		-- but no more than 150 back (in support, not on a bridge far in the rear).
		local outpost: { boolean } = {}
		local mainDepth, mainN = 0, 0
		for i, p in objs do
			for _, sp in sim.strongpoints do
				if Vec.dist(sp.pos, Vec.sub(p, Vec.scale(forward, 25))) < 90 then
					outpost[i] = true
				end
			end
			if not outpost[i] then
				mainDepth, mainN = mainDepth + Vec.dot(p, forward), mainN + 1
			end
		end
		local spaced = mainN > 0 and mainN < #objs
		if spaced then
			mainDepth /= mainN
			for i, p in objs do
				local ahead = Vec.dot(p, forward) - mainDepth
				if outpost[i] and ahead > 0 then
					objs[i] = Vec.sub(p, Vec.scale(forward, math.min(ahead, 150)))
				end
			end
		end
		table.sort(objs, function(a, b)
			return lateral(state, a) < lateral(state, b)
		end)
		if #objs >= 3 then
			wing.left, wing.centre, wing.right = objs[1], objs[math.ceil(#objs / 2)], objs[#objs]
		elseif #objs == 2 then
			wing.left, wing.right = objs[1], objs[2]
			wing.centre = Vec.lerp(objs[1], objs[2], 0.5)
		else
			local centre = objs[1] or base
			wing.centre, wing.left, wing.right = centre, Vec.sub(centre, Vec.scale(state.right, 140)), Vec.add(centre, Vec.scale(state.right, 140))
		end
		if spaced then
			-- a line drawn back from its outposts keeps a frontage: wings at least 200 apart
			local gap = lateral(state, wing.centre) - lateral(state, wing.left)
			if gap < 200 then
				wing.left = Vec.sub(wing.left, Vec.scale(state.right, 200 - gap))
			end
			gap = lateral(state, wing.right) - lateral(state, wing.centre)
			if gap < 200 then
				wing.right = Vec.add(wing.right, Vec.scale(state.right, 200 - gap))
			end
		end
	end
	local lineInf = 0
	for _, f in state.mine do
		if f.class == "infantry" and unitOf(state, f.id).role ~= "reserve" then
			lineInf += 1
		end
	end
	if (posture == "attack" or posture == "advance") and lineInf >= 6 and state.planQuality >= 1 then
		-- pin and turn: the wing on the side the enemy has fewer men swings wide round his flank
		local c = wing.centre
		local dir = Vec.fromHeading(state.facing)
		local r = Vec.right(dir)
		local leftN, rightN = 0, 0
		for _, k in state.known do
			if k.age < 90 then
				if Vec.dot(Vec.sub(k.pos, c), r) < 0 then
					leftN += 1
				else
					rightN += 1
				end
			end
		end
		local side = if leftN <= rightN then -1 else 1
		local w = if side < 0 then "left" else "right"
		wing[w] = Vec.add(Vec.add(c, Vec.scale(r, side * 240)), Vec.scale(dir, 90))
	elseif posture == "defend" then
		-- reverse slope: stand just behind a crest when one is there (out of sight of the guns)
		local grid = sim.grid
		for _, w in WINGS do
			local p = wing[w]
			for _, back in { 0, 20, 40 } do
				local cand = walkable(state, Vec.sub(p, Vec.scale(forward, back)))
				local ahead = Vec.add(cand, Vec.scale(forward, 45))
				if Grid.heightAt(grid, ahead.x, ahead.z) > Grid.heightAt(grid, cand.x, cand.z) + 3 then
					wing[w] = cand
					break
				end
			end
		end
	end
	for _, w in WINGS do
		wing[w] = walkable(state, wing[w])
	end
	local moved: { [string]: boolean } = {}
	for _, w in WINGS do
		moved[w] = state.wingPos[w] == nil or Vec.dist(state.wingPos[w], wing[w]) > 20
	end
	state.wingPos = wing
	state.reserve = walkable(state, Vec.sub(wing.centre, Vec.scale(forward, 150)))

	-- HQ: behind the centre, covering as many formations as possible.
	local bestCover, hqPos = -1, state.reserve
	for _, d in { 60, 100, 140 } do
		local p = walkable(state, Vec.sub(wing.centre, Vec.scale(forward, d)))
		local cover = 0
		for _, f in state.mine do
			if Vec.dist(f.pos, p) <= Config.Units.hq.influence.radius then
				cover += 1
			end
		end
		if cover > bestCover then
			bestCover, hqPos = cover, p
		end
	end
	state.hqPos = hqPos

	-- Roles are sticky. First plan: >= 20 % of infantry (those nearest home) in reserve, the rest
	-- split by lateral position into wings; cavalry all reserve. A battalion arriving later tops
	-- the reserve up to that 20 % or joins the wing nearest its road. Later plans only rotate a
	-- badly damaged line unit to the reserve and promote a healthy reserve unit into its place.
	local inf: { Formation } = {}
	for _, f in state.mine do
		local u = unitOf(state, f.id)
		if f.class == "infantry" then
			inf[#inf + 1] = f
		elseif f.class == "cavalry" then
			u.role = "reserve"
		elseif f.class == "artillery" then
			u.role = "guns"
		else
			u.role = "hq"
		end
	end
	if not state.rolesAssigned then
		state.rolesAssigned = true
		local nRes = math.ceil(0.2 * #inf)
		table.sort(inf, function(a: Formation, b: Formation)
			local ha, hb = Vec.dot(a.pos, forward), Vec.dot(b.pos, forward)
			if ha ~= hb then
				return ha < hb -- nearer home first
			end
			return a.id < b.id
		end)
		local line: { Formation } = {}
		for i, f in inf do
			if i <= nRes then
				unitOf(state, f.id).role = "reserve"
			else
				line[#line + 1] = f
			end
		end
		table.sort(line, function(a: Formation, b: Formation)
			local la, lb = lateral(state, a.pos), lateral(state, b.pos)
			if la ~= lb then
				return la < lb
			end
			return a.id < b.id
		end)
		local side = #line // 3
		for i, f in line do
			unitOf(state, f.id).role = if i <= side then "left" elseif i > #line - side then "right" else "centre"
		end
		for _, f in inf do
			unitOf(state, f.id).placed = true
		end
	end
	for _, f in inf do
		local u = unitOf(state, f.id)
		if not u.placed then
			u.placed = true
			local nRes = 0
			for _, o in inf do
				if unitOf(state, o.id).role == "reserve" and o ~= f then
					nRes += 1
				end
			end
			if nRes < math.ceil(0.2 * #inf) then
				u.role = "reserve"
			else
				local best, bestD = "centre", math.huge
				for _, w in WINGS do
					local d = math.abs(lateral(state, f.pos) - lateral(state, wing[w]))
					if d < bestD then
						best, bestD = w, d
					end
				end
				u.role = best
			end
		end
	end
	for _, f in inf do
		local u = unitOf(state, f.id)
		if u.role ~= "reserve" and damaged(f) then
			local w = u.role
			u.role = "reserve"
			local fresh = nearestOwn(state, wing[w], function(o)
				return o.class == "infantry" and unitOf(state, o.id).role == "reserve" and healthy(o) and not damaged(o)
			end)
			if fresh then
				unitOf(state, fresh.id).role = w
			end
		end
	end

	-- Gun positions: one wing each, centre first.
	local taken: { Vec } = {}
	local gi = 0
	state.gunPos = {}
	for _, f in state.mine do
		if f.class == "artillery" then
			local w = WINGS[gi % #WINGS + 1]
			gi += 1
			local p = pickGunPos(state, wing[w], taken, f.pos, if posture == "attack" or posture == "advance" then 90 else 0)
			taken[#taken + 1] = p
			state.gunPos[f.id] = p
		end
	end

	-- Group moves per wing / reserve (units that are free to move).
	local function free(f: Formation): boolean
		local u = unitOf(state, f.id)
		local engaged = nearestVisible(state, f.pos, MUSKET + 30) ~= nil
		return (f.state == "idle" or f.state == "moving") and not engaged and f.shape ~= "square" and f.pendingShape == nil and (u.goal == "idle" or string.sub(u.goal, 1, 4) == "line" or u.goal == "reserve" or u.goal == "march")
	end
	local moveKind = if posture == "attack" or posture == "advance" then "AttackMove" else "Move"
	for _, w in WINGS do
		local ids: { number } = {}
		local far = false
		for _, f in state.mine do
			local u = unitOf(state, f.id)
			if f.class == "infantry" and u.role == w and free(f) then
				ids[#ids + 1] = f.id
				far = far or Vec.dist(f.pos, wing[w]) > 90
			end
		end
		if #ids > 0 and (moved[w] or far) then
			if issue(state, moveKind, ids, { pos = wing[w], heading = state.facing }) then
				for _, id in ids do
					setGoal(state, id, "line:" .. w, posture .. ": " .. w .. " wing")
				end
			end
		end
	end
	for _, cls in { "infantry", "cavalry" } do
		local ids: { number } = {}
		local far = false
		local point = if cls == "cavalry" then walkable(state, Vec.sub(state.reserve, Vec.scale(forward, 50))) else state.reserve
		for _, f in state.mine do
			local u = unitOf(state, f.id)
			if f.class == cls and u.role == "reserve" and free(f) then
				ids[#ids + 1] = f.id
				far = far or Vec.dist(f.pos, point) > 90
			end
		end
		if #ids > 0 and far then
			if issue(state, "Move", ids, { pos = point, heading = state.facing }) then
				for _, id in ids do
					setGoal(state, id, "reserve", "held in reserve")
				end
			end
		end
	end
end

-- A replan is due on schedule, on a posture change, or when a line unit is badly damaged.
local function planTrigger(state: AIState): boolean
	if state.sim.clock >= state.nextPlan then
		return true
	end
	if state.posture ~= "withdraw" and desiredPosture(state) == "withdraw" then
		return true
	end
	for _, f in state.mine do
		local u = unitOf(state, f.id)
		if f.class == "infantry" and u.role ~= "reserve" and damaged(f) then
			return true
		end
	end
	return false
end

-- Army-level reactions each decision tick -------------------------------------------------------

local function availableInfantry(state: AIState, f: Formation): boolean
	local u = unitOf(state, f.id)
	return f.class == "infantry" and f.state == "idle" and healthy(f) and f.shape ~= "square" and (u.goal == "idle" or u.goal == "reserve" or string.sub(u.goal, 1, 4) == "line")
end

-- Every battery keeps an infantry formation within 60: beside it in position, or walking to
-- its planned position while it is still on the move.
local function gunAnchor(state: AIState, g: Formation): Vec
	return if unitOf(state, g.id).goal == "deploying" then state.gunPos[g.id] or g.pos else g.pos
end

local function guardGuns(state: AIState)
	-- Guard duty ends when the battery is gone or has moved on; the line logic takes over.
	for _, f in state.mine do
		local u = unitOf(state, f.id)
		if u.goal == "guard" then
			local g = u.guardId and state.sim.formations[u.guardId :: number]
			if not g or not Formation.isActive(g) or u.point == nil or Vec.dist(u.point :: Vec, gunAnchor(state, g)) > 60 then
				u.goal, u.reason, u.guardId = "idle", "guard duty over", nil
			end
		end
	end
	for _, g in state.mine do
		local ug = unitOf(state, g.id)
		if g.class == "artillery" and (ug.goal == "fire" or ug.goal == "guns" or ug.goal == "unlimbering" or ug.goal == "deploying") then
			local anchor = gunAnchor(state, g)
			local _, d = nearestOwn(state, anchor, function(f)
				return f.class == "infantry" and not Formation.isBroken(f) and f.id ~= g.id
			end)
			local _, en = nearestOwn(state, anchor, function(f)
				local uf = unitOf(state, f.id)
				return f.class == "infantry" and uf.goal == "guard" and uf.point ~= nil and Vec.dist(uf.point :: Vec, anchor) < 50
			end)
			if d > 50 and en == math.huge then
				local best, bd = nearestOwn(state, g.pos, function(f)
					return availableInfantry(state, f) and unitOf(state, f.id).role == "reserve"
				end)
				if not best or bd > 300 then
					best, bd = nearestOwn(state, g.pos, function(f)
						return availableInfantry(state, f)
					end)
				end
				if best and bd <= 300 then
					local u = unitOf(state, best.id)
					local p = walkable(state, Vec.add(Vec.add(anchor, Vec.scale(state.forward, 10)), Vec.scale(state.right, 35)))
					if issue(state, "Move", { best.id }, { pos = p, heading = state.facing }) then
						u.point = p
						u.guardId = g.id
						setGoal(state, best.id, "guard", "covering " .. g.name)
					end
				end
			end
		end
	end
end

-- Buildings (Sim/Garrison): a free village heart by an objective we hold, or by our line while we
-- defend, gets the nearest available battalion.
local function garrisonBuildings(state: AIState)
	local sim = state.sim
	if state.posture == "withdraw" then
		return
	end
	-- an attacker only spares a battalion for a building when it has plenty
	local infantryN = 0
	for _, f in state.mine do
		if f.class == "infantry" and not Formation.isBroken(f) then
			infantryN += 1
		end
	end
	if state.posture ~= "defend" and infantryN < 6 then
		return
	end
	for _, sp in sim.strongpoints do
		local wanted = false
		for _, o in sim.objectives do
			if (o.owner == state.faction or (state.posture == "defend" and onOurSide(state, o))) and Vec.dist(o.def.pos, sp.pos) < 90 then
				wanted = true
			end
		end
		if not wanted and state.posture == "defend" then
			for _, w in WINGS do
				local wp = state.wingPos[w]
				if wp and Vec.dist(wp, sp.pos) < 200 then
					wanted = true
				end
			end
		end
		local holder = sp.holder and sim.formations[sp.holder]
		local enRoute = false
		for _, f in state.mine do
			if f.order and f.order.kind == "Garrison" and f.order.strongpoint == sp.id then
				enRoute = true
			end
		end
		if wanted and not holder and not enRoute then
			-- a battalion still marching to its wing will do: it is not engaged
			local best, bd = nearestOwn(state, sp.pos, function(f)
				local u = unitOf(state, f.id)
				local marching = f.class == "infantry" and f.state == "moving" and healthy(f) and f.shape ~= "square" and (u.goal == "reserve" or string.sub(u.goal, 1, 4) == "line")
				return (availableInfantry(state, f) or marching) and f.garrison == nil
			end)
			if best and bd <= 250 and issue(state, "Garrison", { best.id }, { strongpoint = sp.id }) then
				setGoal(state, best.id, "garrison", "holding " .. sp.name, 600)
			end
		end
	end
end

-- Push the nearest free infantry onto an objective nobody contests.
local function exploit(state: AIState)
	-- once the objective is ours the battalion that took it rejoins its wing (a garrison holds it)
	for _, f in state.mine do
		local u = unitOf(state, f.id)
		if u.goal == "exploit" and u.point then
			for _, o in state.sim.objectives do
				if o.owner == state.faction and Vec.dist(o.def.pos, u.point :: Vec) < 40 then
					u.goal, u.reason, u.point = "idle", "objective taken", nil
					break
				end
			end
		end
	end
	for _, o in state.sim.objectives do
		local p = o.def.pos
		if o.owner ~= state.faction and not o.contested then
			local threatened = false
			for _, k in state.known do
				if k.age < 60 and Vec.dist(k.pos, p) < 120 then
					threatened = true
				end
			end
			local _, inside = nearestOwn(state, p, function(f)
				return (f.class == "infantry" or f.class == "cavalry") and not Formation.isBroken(f)
			end)
			local _, onWay = nearestOwn(state, p, function(f)
				local uf = unitOf(state, f.id)
				return uf.goal == "exploit" and uf.point ~= nil and Vec.dist(uf.point :: Vec, p) < 40 and not Formation.isBroken(f)
			end)
			if not threatened and inside > o.def.radius and onWay == math.huge and quality(state) then
				local best, bd = nearestOwn(state, p, function(f)
					return availableInfantry(state, f) and not committed(state, unitOf(state, f.id))
				end)
				if best and bd <= 400 then
					local u = unitOf(state, best.id)
					local dest = walkable(state, Vec.add(p, Vec.scale(state.forward, 15)))
					if issue(state, "Move", { best.id }, { pos = dest, heading = state.facing }) then
						u.point = dest
						setGoal(state, best.id, "exploit", "taking " .. o.def.name)
					end
				end
			end
		end
	end
end

-- Take back what the enemy took: an objective this side held, or one on its own ground, that the
-- enemy now holds gets up to two fresh reserve battalions marching on it, when they (with friends
-- already there) at least match the enemy seen round it, a garrison behind walls counting double
-- (Davout's and Wellington's reserves, not a line waiting for the next assault). They rejoin
-- the reserve once it is ours again or their two minutes are up.
local COUNTER_MAX, COUNTER_RANGE, COUNTER_COMMIT = 2, 600, 120
local COUNTER_NEAR, COUNTER_ODDS = 150, 1 -- the enemy counted round the objective; friends needed per enemy man
local GARRISON_WEIGHT = 2 -- a man behind walls counts for two
-- Strength round a point: the enemy this side knows of (a garrison counting double), and its
-- own steady horse and foot.
local function oddsAt(state: AIState, p: Vec): (number, number)
	local enemy, friends = 0, 0
	for _, k in state.known do
		if Vec.dist(k.pos, p) < COUNTER_NEAR then
			local f = state.sim.formations[k.id]
			enemy += k.strength * (if f and f.garrison then GARRISON_WEIGHT else 1)
		end
	end
	for _, f in state.mine do
		if (f.class == "infantry" or f.class == "cavalry") and not Formation.isBroken(f) and Vec.dist(f.pos, p) < COUNTER_NEAR then
			friends += f.strength
		end
	end
	return enemy, friends
end

local function counterattack(state: AIState)
	local sim = state.sim
	for _, o in sim.objectives do
		if o.owner == state.faction then
			state.held[o.def.id] = true
		end
	end
	for _, f in state.mine do
		local u = unitOf(state, f.id)
		if u.goal == "counter" and u.point then
			-- arrived and outmatched: fall back rather than die there
			local enemy, friends = oddsAt(state, u.point :: Vec)
			local outmatched = Vec.dist(f.pos, u.point :: Vec) < COUNTER_NEAR and friends < enemy * COUNTER_ODDS * 0.75
			local done = not committed(state, u) or not healthy(f) or outmatched
			for _, o in sim.objectives do
				if o.owner == state.faction and not o.contested and Vec.dist(o.def.pos, u.point :: Vec) < 40 then
					done = true
				end
			end
			if done then
				u.goal, u.reason, u.point = "idle", "counterattack over", nil
			end
		end
	end
	if state.posture == "withdraw" then
		return
	end
	for _, o in sim.objectives do
		local p = o.def.pos
		local ours = state.held[o.def.id] or MapGen.inZone((sim :: any).map, state.faction, p) or Vec.dist(p, sim:homeEdge(state.faction)) < Vec.dist(p, sim:homeEdge(state.enemy))
		if ours and o.owner == state.enemy then
			local going = 0
			for _, f in state.mine do
				local u = unitOf(state, f.id)
				if u.goal == "counter" and u.point and Vec.dist(u.point :: Vec, p) < 40 then
					going += 1
				end
			end
			-- never fed in piecemeal, nor blind: the enemy holding it has been seen, and what goes,
			-- with friends already there, must about match it
			local enemy, friends = oddsAt(state, p)
			local picks: { Formation } = {}
			for _ = going + 1, COUNTER_MAX do
				local best, bd = nearestOwn(state, p, function(f)
					-- standing in reserve, or still marching to it
					local u = unitOf(state, f.id)
					local marching = f.class == "infantry" and f.state == "moving" and healthy(f) and f.shape ~= "square" and u.goal == "reserve"
					return (availableInfantry(state, f) or marching) and u.role == "reserve" and not damaged(f) and table.find(picks, f) == nil
				end)
				if not best or bd > COUNTER_RANGE then
					break
				end
				picks[#picks + 1] = best
				friends += best.strength
			end
			if #picks > 0 and enemy > 0 and friends >= enemy * COUNTER_ODDS and quality(state) then
				local dest = walkable(state, p)
				for _, f in picks do
					if issue(state, "AttackMove", { f.id }, { pos = dest, heading = state.facing }) then
						unitOf(state, f.id).point = dest
						setGoal(state, f.id, "counter", "retaking " .. o.def.name, COUNTER_COMMIT)
					end
				end
			end
		end
	end
end

-- Formation behaviour --------------------------------------------------------------------------

local function goalPoint(state: AIState, u: Unit): Vec?
	if u.goal == "guard" or u.goal == "exploit" or u.goal == "counter" then
		return u.point
	end
	if u.role == "reserve" then
		return state.reserve
	end
	return state.wingPos[u.role]
end

-- Idle and far from the goal point: walk there (column for long marches, line near the enemy).
local function maintain(state: AIState, f: Formation, u: Unit)
	local sim = state.sim
	local p = goalPoint(state, u)
	if not p or f.state ~= "idle" or sim.clock < u.nextMove then
		return
	end
	local d = Vec.dist(f.pos, p)
	local radius = if string.sub(u.goal, 1, 4) == "line" or u.goal == "reserve" then 100 else 60
	if d <= radius then
		return
	end
	u.nextMove = sim.clock + 10
	if f.class == "infantry" and f.shape == "line" and d > 250 and nearestKnownDist(state, f.pos, 90) > 150 then
		if issue(state, "Shape", { f.id }, { shape = "column" }) then
			u.nextMove = sim.clock + Config.ReformTime.column + 1
			u.reason = "column for the march"
			return
		end
	end
	if issue(state, "Move", { f.id }, { pos = p, heading = state.facing }) then
		u.goal = if u.goal == "guard" or u.goal == "exploit" or u.goal == "counter" then u.goal elseif u.role == "reserve" then "reserve" else "line:" .. u.role
		u.reason = string.format("moving to the %s position (%.0f)", u.role, d)
	end
end

local function friendlyCavScreens(state: AIState, f: Formation, threat: Formation): boolean
	local dMe = Vec.dist(f.pos, threat.pos)
	for _, c in state.mine do
		if c.class == "cavalry" and healthy(c) and Vec.dist(c.pos, f.pos) < 120 and Vec.dist(c.pos, threat.pos) < dMe then
			return true
		end
	end
	return false
end

local function infantry(state: AIState, f: Formation)
	local sim = state.sim
	local clock = sim.clock
	local u = unitOf(state, f.id)
	if f.state == "melee" then
		u.goal, u.reason = "melee", "in contact"
		return
	end
	if f.garrison or (f.order and f.order.kind == "Garrison") then
		-- holding (or on the way to) a building: it stays until the army withdraws
		if state.posture == "withdraw" and f.garrison then
			issue(state, "Retreat", { f.id }, {})
		end
		return
	end
	-- Cavalry threat: form square unless friendly cavalry screens.
	local threat, td = nearestVisible(state, f.pos, 140, function(e)
		if not isCav(e) then
			return false
		end
		local d = Vec.dist(f.pos, e.pos)
		local approaching = Vec.dot(Vec.fromHeading(e.heading), Vec.normalize(Vec.sub(f.pos, e.pos))) > 0.3 and (e.state == "charging" or e.state == "moving")
		return d < 90 or approaching
	end)
	if threat and not friendlyCavScreens(state, f, threat) then
		if f.shape ~= "square" and f.pendingShape ~= "square" then
			issue(state, "Shape", { f.id }, { shape = "square" })
		end
		u.squareUntil = clock + Config.AI.CommitSeconds * state.reaction
		setGoal(state, f.id, "square", string.format("cavalry %s at %.0f", threat.name, td))
		return
	end
	if f.shape == "square" or f.pendingShape == "square" then
		local cav = nearestVisible(state, f.pos, 200, isCav)
		if not cav and clock >= u.squareUntil and f.state ~= "reforming" then
			if issue(state, "Shape", { f.id }, { shape = "line" }) then
				setGoal(state, f.id, "reform", "cavalry gone, back to line", 5)
			end
		else
			u.goal, u.reason = "square", "holding square"
		end
		return
	end
	if f.state == "reforming" then
		u.reason = "reforming"
		return
	end
	-- Light troops screen in open order while no horse is about, and close up when it comes.
	if Formation.legalShapes(f).skirmish and f.pendingShape == nil and quality(state) then
		local horse = nearestVisible(state, f.pos, 300, isCav)
		if not horse and f.shape ~= "skirmish" and nearestKnownDist(state, f.pos, 60) < 350 then
			if issue(state, "Shape", { f.id }, { shape = "skirmish" }) then
				u.reason = "screening in open order"
				return
			end
		elseif horse and f.shape == "skirmish" then
			if issue(state, "Shape", { f.id }, { shape = "line" }) then
				u.reason = "closing up: horse about"
				return
			end
		end
	end
	-- Broken enough: fall back on the reserve.
	if f.moraleBand == "shaken" and f.strength < f.startStrength * 0.6 and u.goal ~= "retreat" then
		if issue(state, "Retreat", { f.id }, { pos = state.reserve }) then
			setGoal(state, f.id, "retreat", "shaken with heavy losses")
			return
		end
	end
	if u.goal == "retreat" and f.state == "retreating" then
		return
	end
	-- Bayonet a shaken enemy close in front (routing ones are left to fire-at-will).
	local weak = nearestVisible(state, f.pos, 60, function(e)
		return Formation.moraleBandOf(e) == "shaken" and e.shape ~= "square" and math.abs(Vec.bearing(f.pos, f.heading, e.pos)) < math.rad(50)
	end)
	local charging = f.state == "charging" or (f.order ~= nil and f.order.kind == "Charge")
	if weak and not charging and not (u.goal == "charge" and committed(state, u)) and quality(state) then
		if issue(state, "Charge", { f.id }, { targetId = weak.id }) then
			setGoal(state, f.id, "charge", "bayonets: " .. weak.name .. " is wavering")
			return
		end
	end
	if charging then
		return
	end
	local pending = (f :: any).pendingShape
	if u.goal == "charge" or (u.goal == "square" and f.shape ~= "square" and pending ~= "square") then
		u.goal = "idle"
	end
	-- Enemy in musket range: engage (attack posture) or face it and let fire-at-will work.
	local tgt, d = nearestVisible(state, f.pos, MUSKET + 10, function(e)
		return e.state ~= "routing"
	end)
	if tgt then
		local goalName = "engage:" .. tgt.id
		if (state.posture == "attack" or state.posture == "advance" or Formation.moraleBandOf(tgt) == "shaken") and u.goal ~= goalName and not committed(state, u) then
			if quality(state) and issue(state, "Engage", { f.id }, { targetId = tgt.id }) then
				setGoal(state, f.id, goalName, string.format("engaging %s at %.0f", tgt.name, d))
				return
			end
		end
		if string.sub(u.goal, 1, 6) == "engage" then
			return
		end
		local bearing = Vec.bearing(f.pos, f.heading, tgt.pos)
		if math.abs(bearing) > math.rad(50) and f.state == "idle" and clock >= u.nextMove then
			u.nextMove = clock + 5
			issue(state, "Face", { f.id }, { heading = Vec.heading(Vec.sub(tgt.pos, f.pos)) })
		end
		u.reason = string.format("firing on %s at %.0f", tgt.name, d)
		return
	end
	-- Deploy from column before contact.
	if f.shape == "column" and nearestKnownDist(state, f.pos, 60) < 110 then
		if issue(state, "Shape", { f.id }, { shape = "line" }) then
			u.reason = "deploying into line"
			return
		end
	end
	maintain(state, f, u)
end

local function gunsThreatenedBy(state: AIState, e: Formation): boolean
	for _, g in state.mine do
		if g.class == "artillery" and Vec.dist(g.pos, e.pos) < 150 then
			return true
		end
	end
	return false
end

local function cavalry(state: AIState, f: Formation)
	local u = unitOf(state, f.id)
	local recovering = f.timers.chargeRecover > 0 or (f.state == "melee" and f.timers.meleeSeconds > 15)
	if recovering then
		if u.goal ~= "recover" then
			if issue(state, "Retreat", { f.id }, { pos = state.reserve }) then
				setGoal(state, f.id, "recover", "blown; back to the reserve")
			end
		elseif f.state == "idle" then
			u.reason = "recovering"
		end
		return
	end
	if f.state == "melee" or f.state == "charging" or f.state == "retreating" then
		u.reason = f.state
		return
	end
	if u.goal == "recover" then
		u.goal = "reserve"
	end
	if healthy(f) then
		local best: Formation? = nil
		local bestScore = 0
		for _, e in state.visible do
			local d = Vec.dist(f.pos, e.pos)
			if d <= 250 and not inCover(state, e.pos) and not f.inWoods then
				local s = 0
				if e.state == "routing" then
					s = 100
				elseif e.class == "artillery" then
					s = 90
				elseif e.class == "cavalry" then
					s = if gunsThreatenedBy(state, e) then 85 else 0
				elseif e.class == "hq" then
					s = 60
				elseif e.state == "melee" and e.shape ~= "square" and e.shape ~= "garrison" then
					s = 95 -- locked in melee with our men: ride into it (worth leaving the reserve for)
				elseif e.shape ~= "square" and e.state ~= "reforming" then
					local side = Vec.attackSide(e.pos, e.heading, f.pos)
					s = if side == "rear" then 80 elseif side == "flank" then 70 else 0
				end
				if s > 0 then
					s -= d / 8
					if s > bestScore then
						best, bestScore = e, s
					end
				end
			end
		end
		local charging = f.order ~= nil and f.order.kind == "Charge"
		if best and not charging and (bestScore >= 60 or not committed(state, u)) and quality(state) then
			if issue(state, "Charge", { f.id }, { targetId = best.id }) then
				setGoal(state, f.id, "charge", string.format("charging %s (%s)", best.name, Vec.attackSide(best.pos, best.heading, f.pos)))
				return
			end
		end
	end
	if u.goal == "charge" then
		u.goal = "reserve"
	end
	u.reason = if healthy(f) then "held in reserve" else "shaken; resting"
	maintain(state, f, u)
end

local function artillery(state: AIState, f: Formation)
	local sim = state.sim
	local clock = sim.clock
	local u = unitOf(state, f.id)
	if f.state == "melee" then
		u.goal, u.reason = "melee", "overrun"
		return
	end
	local limbered = Formation.isLimbered(f)
	-- Threats: infantry within 80 with nobody in between, or cavalry within 150.
	local threat = nearestVisible(state, f.pos, 150, function(e)
		if e.state == "routing" then
			return false
		end
		if e.class == "cavalry" then
			return true
		end
		if e.class ~= "infantry" or Vec.dist(f.pos, e.pos) > 80 then
			return false
		end
		local de = Vec.dist(f.pos, e.pos)
		for _, i in state.mine do
			if i.class == "infantry" and not Formation.isBroken(i) and Vec.dist(i.pos, f.pos) < 60 and Vec.dist(i.pos, e.pos) < de then
				return false
			end
		end
		return true
	end)
	if threat and threat.class == "cavalry" and not limbered and f.pendingLimber == nil and f.ammo > 0 then
		-- Canister beats limbering up (25 s helpless, shock x3) when infantry stands beside the guns.
		local _, guard = nearestOwn(state, f.pos, function(i)
			return i.class == "infantry" and not Formation.isBroken(i)
		end)
		if guard <= 60 then
			threat = nil
		end
	end
	if threat then
		u.withdrawUntil = clock + 30 * state.reaction
	end
	if threat or (u.goal == "withdraw" and clock < u.withdrawUntil) then
		if f.pendingLimber ~= nil then
			u.reason = "limbering up"
		elseif not limbered then
			if issue(state, "Limber", { f.id }, { limbered = true }) then
				setGoal(state, f.id, "withdraw", "threatened by " .. (if threat then threat.name else "the enemy"))
			end
		elseif f.state ~= "retreating" and f.state ~= "moving" and Vec.dist(f.pos, state.reserve) > 40 then
			if issue(state, "Retreat", { f.id }, { pos = state.reserve }) then
				setGoal(state, f.id, "withdraw", "pulling back to the reserve")
			end
		end
		return
	end
	if f.state == "reforming" then
		u.reason = if f.pendingLimber == false then "unlimbering" else "limbering"
		return
	end
	local gp = state.gunPos[f.id]
	if limbered then
		-- No progress for 30 s (hemmed in by friends, a village, a wood): unlimber where it stands.
		local stuck = f.state == "moving" and u.lastPos ~= nil and clock - u.lastPosAt >= 30 and Vec.dist(f.pos, u.lastPos :: Vec) < 8
		if f.state ~= "moving" then
			u.lastPos = nil
		elseif u.lastPos == nil or clock - u.lastPosAt >= 30 then
			u.lastPos, u.lastPosAt = { x = f.pos.x, z = f.pos.z }, clock
		end
		if gp and Vec.dist(f.pos, gp) > 24 and not stuck then
			if f.state == "idle" and clock >= u.nextMove then
				u.nextMove = clock + 10
				if issue(state, "Move", { f.id }, { pos = gp, heading = state.facing }) then
					setGoal(state, f.id, "deploying", "moving into position")
				end
			end
		elseif stuck then
			if issue(state, "Limber", { f.id }, { limbered = false }) then
				setGoal(state, f.id, "unlimbering", "hemmed in: deploying here")
			end
		elseif f.state == "idle" then
			if math.abs(Vec.angleDiff(f.heading, state.facing)) > 0.3 then
				if clock >= u.nextMove then
					u.nextMove = clock + 5
					issue(state, "Face", { f.id }, { heading = state.facing })
				end
			elseif issue(state, "Limber", { f.id }, { limbered = false }) then
				setGoal(state, f.id, "unlimbering", "deploying the guns")
			end
		end
		return
	end
	if f.ammoMode ~= "auto" then
		issue(state, "Ammo", { f.id }, { ammo = "auto" })
	end
	-- Best target it can actually fire at: columns/squares first, then nearest.
	local best: Formation? = nil
	local bestScore = -math.huge
	for _, e in state.visible do
		local r = Combat.fireBlockReason(sim :: any, f, e)
		if r == nil or r == "Reloading" then
			local s = ((Config.Shapes :: any)[e.shape].artillery :: number) * 100 - Vec.dist(f.pos, e.pos) / 4
			if s > bestScore then
				best, bestScore = e, s
			end
		end
	end
	if best then
		if f.targetId ~= best.id and (u.goal ~= "fire" or not committed(state, u)) then
			if issue(state, "Engage", { f.id }, { targetId = best.id }) then
				setGoal(state, f.id, "fire", "firing on " .. best.name)
				return
			end
		end
		u.goal, u.reason = "fire", "firing on " .. best.name
	elseif gp and Vec.dist(f.pos, gp) > 120 and issue(state, "Limber", { f.id }, { limbered = true }) then
		setGoal(state, f.id, "deploying", "relocating the battery")
	else
		u.goal, u.reason = "guns", "in battery, no target"
	end
end

local function hq(state: AIState, f: Formation)
	local clock = state.sim.clock
	local u = unitOf(state, f.id)
	local threat, td = nearestVisible(state, f.pos, 110, function(e)
		return e.state ~= "routing"
	end)
	if threat then
		if f.state ~= "moving" or clock >= u.nextMove then
			u.nextMove = clock + 5
			local away = Vec.normalize(Vec.sub(f.pos, threat.pos))
			local p = walkable(state, Vec.add(f.pos, Vec.scale(away, 150)))
			if issue(state, "Move", { f.id }, { pos = p }) then
				setGoal(state, f.id, "evade", string.format("%s at %.0f", threat.name, td))
			end
		end
		return
	end
	if f.timers.rallyCd <= 0 then
		local cfg = Config.Units.hq.rally
		for _, o in state.mine do
			if o.state == "routing" and not o.shattered and o.timers.routing >= cfg.minRoutingSeconds and Vec.dist(o.pos, f.pos) <= cfg.radius then
				if issue(state, "Rally", { f.id }, {}) then
					setGoal(state, f.id, "rally", "rallying " .. o.name, 5)
					return
				end
			end
		end
	end
	-- The general's ability, through the player's command path, when the line around him wavers.
	local g = Abilities.generalOf(state.sim :: any, f.id)
	if g and Abilities.cooldownLeft(state.sim :: any, f.id) <= 0 then
		local wavering = 0
		for _, o in state.mine do
			if o.id ~= f.id and (o.moraleBand == "shaken" or o.state == "routing") and Vec.dist(o.pos, f.pos) <= g.ability.radius then
				wavering += 1
			end
		end
		if wavering >= 2 and issue(state, "Ability", { f.id }, { abilityId = g.ability.id }) then
			setGoal(state, f.id, "ability", g.ability.name, 5)
			return
		end
	end
	if u.goal == "evade" and f.state == "idle" then
		u.goal = "hq"
	end
	if f.state == "idle" and Vec.dist(f.pos, state.hqPos) > 50 and clock >= u.nextMove then
		u.nextMove = clock + 10
		if issue(state, "Move", { f.id }, { pos = state.hqPos, heading = state.facing }) then
			setGoal(state, f.id, "hq", "following the centre")
			return
		end
	end
	if u.goal ~= "hq" and f.state == "idle" then
		u.goal, u.reason = "hq", "with the centre"
	end
end

-- Public API -----------------------------------------------------------------------------------------

-- The difficulty's morale bonus goes to the AI's side only (disclosed in settings). Idempotent, so
-- rebuilding the AI (new difficulty, or the AI changing sides) never stacks it.
function AI.steady(sim: SimLike, faction: string?, bonus: number)
	for _, f in sim.formations do
		local delta = (if f.faction == faction then bonus else 0) - f.aiMoraleBonus
		f.baseMorale += delta
		f.morale += delta
		f.aiMoraleBonus += delta
	end
end

function AI.new(sim: SimLike, faction: string, difficulty: string): AIState
	local diff = (Config.AI.Difficulties :: any)[difficulty] or Config.AI.Difficulties.normal
	AI.steady(sim, faction, diff.moraleBonus)
	return {
		sim = sim,
		faction = faction,
		enemy = if faction == sim.playerFaction then sim.enemyFaction else sim.playerFaction,
		reaction = diff.reaction,
		planQuality = diff.planQuality,
		n = 0,
		steps = 0,
		budget = 0,
		posture = "defend",
		forward = { x = 0, z = -1 },
		right = { x = 1, z = 0 },
		facing = -math.pi / 2,
		reserve = { x = sim.grid.width / 2, z = sim.grid.depth / 2 },
		hqPos = { x = sim.grid.width / 2, z = sim.grid.depth / 2 },
		wingPos = {},
		gunPos = {},
		nextPlan = 0,
		rolesAssigned = false,
		held = {},
		units = {},
		mine = {},
		visible = {},
		known = {},
	}
end

-- Called by the sim every Config.AI.DecisionTicks ticks.
function AI.step(state: AIState)
	local sim = state.sim
	if sim.state ~= "running" then
		return
	end
	state.steps += 1
	state.budget = MAX_PATH_CMDS
	perceive(state)
	if planTrigger(state) then
		plan(state)
	end
	-- easy reacts slower: only every Nth decision tick
	if state.steps % math.max(1, math.floor(state.reaction)) ~= 0 then
		return
	end
	guardGuns(state)
	garrisonBuildings(state)
	exploit(state)
	counterattack(state)
	for _, f in state.mine do
		local u = unitOf(state, f.id)
		if f.state == "routing" or f.state == "rallying" then
			u.goal, u.reason = "routing", f.state
		elseif u.orderedStep == state.steps then
			-- already ordered this tick by the plan / guard / exploit pass
		elseif f.class == "infantry" then
			infantry(state, f)
		elseif f.class == "cavalry" then
			cavalry(state, f)
		elseif f.class == "artillery" then
			artillery(state, f)
		else
			hq(state, f)
		end
	end
end

-- Tests: the strength round a point as the counterattack weighs it (enemy, friends).
function AI.oddsAt(state: AIState, p: Vec): (number, number)
	return oddsAt(state, p)
end

function AI.debugView(state: AIState): { { id: number, goal: string, reason: string } }
	local out = {}
	for _, f in state.mine do
		local u = unitOf(state, f.id)
		out[#out + 1] = { id = f.id, goal = string.format("%s/%s", u.role, u.goal), reason = u.reason }
	end
	return out
end

return AI
