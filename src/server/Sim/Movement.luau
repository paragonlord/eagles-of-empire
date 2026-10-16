--!strict
-- Timed transitions (shape/limber/rally/charge recovery), navigation, movement, facing,
-- choke-point travel columns, avoidance, stuck detection and routing flight.
-- Runs in tick steps 3 and 4. Formations are processed in ascending id order.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Vec = require(Shared.Vec)
local Types = require(Shared.Types)

local Formation = require(script.Parent.Formation)
local Nav = require(script.Parent.Nav)

type Vec = Vec.Vec
type Formation = Formation.Formation

local Movement = {}

local DT = Config.Sim.DT

-- Sim surface used here (kept narrow so tests can build a fake).
export type SimLike = {
	grid: Grid.Grid,
	nav: Nav.NavGrid,
	map: any,
	tick: number,
	formations: { [number]: Formation },
	order: { number },
	events: { Types.Event },
	emit: (sim: any, ev: Types.Event) -> (),
	homeEdge: (sim: any, faction: string) -> Vec,
	findFormation: (sim: any, id: number) -> Formation?,
}

local function terrainSpeed(f: Formation, grid: Grid.Grid): number
	local t = Grid.terrainAt(grid, f.pos.x, f.pos.z)
	return if f.class == "cavalry" then t.cavalrySpeed else t.speed
end

function Movement.currentSpeed(sim: SimLike, f: Formation, dir: Vec): number
	local charging = f.state == "charging"
	local base = Formation.speedBase(f, charging)
	local shapeCfg = (Config.Shapes :: any)[f.shape]
	local shapeFactor = if charging then 1 else shapeCfg.speed
	if f.class == "artillery" and f.shape == "deployed" then
		return 0
	end
	local slope = Grid.slopeAlong(sim.grid, f.pos.x, f.pos.z, dir)
	local slopeFactor = math.max(0.25, 1 - Config.Slope.UphillPenalty * math.max(0, slope) + Config.Slope.DownhillBonus * math.max(0, -slope))
	local fatigue = Formation.fatigueFactor(f, Config.Combat.FatigueSpeedPenalty)
	local speed = base * shapeFactor * terrainSpeed(f, sim.grid) * slopeFactor * fatigue
	if f.state == "routing" then
		speed = base * terrainSpeed(f, sim.grid) * slopeFactor * Config.Morale.RoutSpeedFactor
	end
	return speed
end

local function turnToward(f: Formation, target: number, dt: number): boolean
	local rate = (Config.Shapes :: any)[f.shape].turnRate
	if f.state == "routing" then
		rate = 2.0
	end
	local diff = Vec.angleDiff(f.heading, target)
	local step = rate * dt
	if math.abs(diff) <= step then
		f.heading = target
		return true
	end
	f.heading = Vec.wrapAngle(f.heading + (if diff > 0 then step else -step))
	return false
end

-- Step 3: timers.
function Movement.updateTimers(sim: SimLike, f: Formation)
	local t = f.timers
	if t.reform > 0 then
		t.reform = math.max(0, t.reform - DT)
		if t.reform == 0 then
			Formation.completeShape(f)
		end
	end
	if t.limber > 0 then
		t.limber = math.max(0, t.limber - DT)
		if t.limber == 0 and f.pendingLimber ~= nil then
			f.shape = if f.pendingLimber then "limbered" else "deployed"
			f.pendingLimber = nil
			Formation.refreshFootprint(f)
			if f.state == "reforming" then
				f.state = if f.path then "moving" else "idle"
			end
		end
	end
	if t.chargeRecover > 0 then
		t.chargeRecover = math.max(0, t.chargeRecover - DT)
	end
	if t.rallyCd > 0 then
		t.rallyCd = math.max(0, t.rallyCd - DT)
	end
	if t.bayonet > 0 then
		t.bayonet = math.max(0, t.bayonet - DT)
	end
	if t.halt > 0 then
		t.halt = math.max(0, t.halt - DT)
	end
	if f.reload > 0 then
		f.reload = math.max(0, f.reload - DT)
	end
	t.noDamage += DT
	-- Cohesion recovers slowly when not reforming or in melee.
	if f.state ~= "reforming" and f.state ~= "melee" and f.state ~= "routing" then
		f.cohesion = math.min(1, f.cohesion + 0.03 * DT)
	end
end

-- Request a route for the formation's current order destination.
function Movement.plan(sim: SimLike, f: Formation, dest: Vec): boolean
	local path = Nav.findPath(sim.nav, f.pos, dest, f.halfRadius)
	if not path then
		f.path = nil
		return false
	end
	f.path = path
	f.pathIndex = 1
	f.lastProgressDist = math.huge
	f.timers.stuck = 0
	return true
end

local function orderDestination(sim: SimLike, f: Formation): Vec?
	local o = f.order
	if not o then
		return nil
	end
	if o.kind == "Move" or o.kind == "AttackMove" or o.kind == "Retreat" or (o.kind == "Charge" and o.targetId == nil) then
		return o.pos
	end
	if (o.kind == "Engage" or o.kind == "Charge") and o.targetId then
		local target = sim.findFormation(sim, o.targetId)
		if target and Formation.isActive(target) then
			return target.pos
		end
	end
	return nil
end

local function startNextQueued(sim: SimLike, f: Formation)
	local nextOrder = table.remove(f.queue, 1)
	f.order = nextOrder
	f.path = nil
	f.pathIndex = 1
	if nextOrder then
		local dest = orderDestination(sim, f)
		if dest and not Movement.plan(sim, f, dest) then
			sim.emit(sim, { kind = "message", tick = sim.tick, id = f.id, faction = f.faction, text = f.name .. ": no route to that position" })
			f.order = nil
		end
		if f.order then
			f.state = if nextOrder.kind == "Charge" then "charging" else "moving"
		end
	end
	if not f.order then
		f.state = "idle"
	end
end

-- Arrival: settle facing, then hold or take the next queued order.
local function arrive(sim: SimLike, f: Formation)
	f.path = nil
	local o = f.order
	local wantHeading = o and o.heading
	if wantHeading then
		if not turnToward(f, wantHeading, DT) then
			f.state = "moving"
			return
		end
	end
	if o and o.kind == "Retreat" then
		f.state = "idle"
		f.order = nil
		f.queue = {}
		return
	end
	if o and o.kind == "Engage" and o.targetId then
		-- Reached the target's vicinity: stop here; combat decides the rest.
		f.state = "idle"
		return
	end
	startNextQueued(sim, f)
end

-- Advance along the path by one tick.
local function followPath(sim: SimLike, f: Formation, speedScale: number)
	local path = f.path
	if not path then
		return
	end
	local wp = path[f.pathIndex]
	if not wp then
		arrive(sim, f)
		return
	end
	local toWp = Vec.sub(wp, f.pos)
	local dist = Vec.len(toWp)
	local dir = Vec.normalize(toWp)
	local wantHeading = Vec.heading(dir)
	-- Lines wheel before marching; columns and cavalry turn on the move.
	local aligned = turnToward(f, wantHeading, DT)
	if f.shape == "line" and not aligned and math.abs(Vec.angleDiff(f.heading, wantHeading)) > 0.6 then
		return
	end
	local speed = Movement.currentSpeed(sim, f, dir) * speedScale
	if f.timers.halt > 0 then
		speed = 0
	end
	local step = speed * DT
	if f.state == "charging" then
		f.runUp += step
	end
	if step >= dist then
		f.pos = { x = wp.x, z = wp.z }
		f.pathIndex += 1
		f.lastProgressDist = math.huge
		if f.pathIndex > #path then
			arrive(sim, f)
		end
	else
		f.pos = Vec.add(f.pos, Vec.scale(dir, step))
	end
	-- Fatigue from marching.
	local unit = Formation.unitConfig(f)
	local terrain = Grid.terrainAt(sim.grid, f.pos.x, f.pos.z)
	local rate = if f.state == "charging" then unit.fatigueCharge else unit.fatigueMove
	f.fatigue = math.min(100, f.fatigue + rate * terrain.fatigue * DT)
	f.cohesion = math.max(0.3, f.cohesion - terrain.cohesion * DT)
	-- Stuck detection.
	if dist < f.lastProgressDist - 0.01 then
		f.lastProgressDist = dist
		f.timers.stuck = 0
	else
		f.timers.stuck += DT
		if f.timers.stuck > Config.Match.StuckSeconds then
			local dest = orderDestination(sim, f)
			if not dest or not Movement.plan(sim, f, dest) then
				sim.emit(sim, { kind = "message", tick = sim.tick, id = f.id, faction = f.faction, text = f.name .. ": route blocked" })
				Formation.clearOrder(f)
			end
		end
	end
end

-- Choke points: adopt / restore the travel column based on clearance ahead.
local function updateTravelShape(sim: SimLike, f: Formation)
	if f.class ~= "infantry" and f.class ~= "cavalry" then
		return
	end
	local path = f.path
	if not path or not path[f.pathIndex] then
		return
	end
	local ahead = Nav.segmentMinClearance(sim.nav, f.pos, path[f.pathIndex])
	if f.shape ~= "travel" and f.pendingShape ~= "travel" and ahead < f.width / 2 then
		Formation.beginShape(f, "travel", true)
	elseif f.shape == "travel" and f.prevShape and f.pendingShape == nil then
		-- Restore only when the remaining path has room for the previous shape.
		local prev: Types.Shape = f.prevShape :: Types.Shape
		local tmpShape: Types.Shape = f.shape
		f.shape = prev
		local w = Formation.footprint(f)
		f.shape = tmpShape
		local minAhead = math.huge
		for i = f.pathIndex, #path do
			local a = if i == f.pathIndex then f.pos else path[i - 1]
			local c = Nav.segmentMinClearance(sim.nav, a, path[i])
			if c < minAhead then
				minAhead = c
			end
		end
		if minAhead >= w / 2 and Grid.clearanceAt(sim.grid, f.pos.x, f.pos.z) >= w / 2 then
			Formation.beginShape(f, prev, false)
			f.prevShape = nil
		end
	end
end

-- Separation between friendly footprints; the lower id has priority at choke points.
local function avoid(sim: SimLike, f: Formation): number
	local scale = 1
	for _, otherId in sim.order do
		if otherId ~= f.id then
			local o = sim.formations[otherId]
			if o and o.faction == f.faction and Formation.isActive(o) and o.state ~= "melee" and f.state ~= "melee" then
				local minDist = f.halfRadius + o.halfRadius
				local d2 = Vec.dist2(f.pos, o.pos)
				if d2 < minDist * minDist and d2 > 0.01 then
					local d = math.sqrt(d2)
					local push = (minDist - d) * 0.5
					local dir = Vec.normalize(Vec.sub(f.pos, o.pos))
					if f.state == "moving" or f.state == "charging" or f.state == "routing" then
						if o.state == "moving" and o.id < f.id and Grid.clearanceAt(sim.grid, f.pos.x, f.pos.z) < 24 then
							scale = 0.5 -- yield at the choke point
						end
						local np = Vec.add(f.pos, Vec.scale(dir, math.min(push, 2) * DT * 10))
						if Nav.isWalkable(sim.nav, np) then
							f.pos = np
						end
					end
				end
			end
		end
	end
	return scale
end

local function routeToHome(sim: SimLike, f: Formation)
	if not f.path or not f.path[f.pathIndex] then
		local home = sim.homeEdge(sim, f.faction)
		local target = { x = math.clamp(f.pos.x + (home.x - f.pos.x) * 0.2, 8, sim.grid.width - 8), z = home.z }
		if not Movement.plan(sim, f, target) then
			-- No route: drift straight toward home and let the edge rule remove the unit.
			f.path = { target }
			f.pathIndex = 1
		end
	end
end

-- Step 4 for one formation.
function Movement.update(sim: SimLike, f: Formation)
	if not Formation.isActive(f) then
		return
	end
	f.inWoods = Grid.terrainAt(sim.grid, f.pos.x, f.pos.z).blocksSight
	if f.state == "routing" then
		routeToHome(sim, f)
		followPath(sim, f, 1)
		-- Exited the field?
		local m = Config.Morale.RoutExitMargin
		if f.pos.x < -m or f.pos.z < -m or f.pos.x > sim.grid.width + m or f.pos.z > sim.grid.depth + m then
			f.state = "exited"
			sim.emit(sim, { kind = "destroyed", tick = sim.tick, id = f.id, faction = f.faction, text = f.name .. " has fled the field" })
		end
		return
	end
	if f.state == "reforming" or f.state == "rallying" or f.state == "melee" then
		-- Resting cohesion/fatigue handled elsewhere; no movement.
		return
	end
	local o = f.order
	if f.state == "idle" then
		if o and (o.kind == "Face") and o.heading then
			if turnToward(f, o.heading, DT) then
				f.order = nil
			end
		elseif o and o.kind == "Hold" then
			-- holding: nothing
		elseif o == nil and #f.queue > 0 then
			startNextQueued(sim, f)
		end
		local unit = Formation.unitConfig(f)
		f.fatigue = math.max(0, f.fatigue - unit.rest * DT)
		return
	end
	if f.state == "moving" or f.state == "charging" or f.state == "retreating" then
		if not f.path then
			local dest = orderDestination(sim, f)
			if not dest or not Movement.plan(sim, f, dest) then
				Formation.clearOrder(f)
				return
			end
		end
		-- Engage/Charge targets move: re-aim the path tail at the target periodically.
		if o and (o.kind == "Engage" or o.kind == "Charge") and o.targetId and sim.tick % 20 == 0 then
			local target = sim.findFormation(sim, o.targetId)
			if target and Formation.isActive(target) then
				local path = f.path
				if path then
					path[#path] = { x = target.pos.x, z = target.pos.z }
				end
			else
				Formation.clearOrder(f)
				return
			end
		end
		updateTravelShape(sim, f)
		local scale = avoid(sim, f)
		followPath(sim, f, scale)
	end
end

return Movement
