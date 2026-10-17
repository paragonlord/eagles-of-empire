--!strict
-- Morale, fatigue effects, rout / rally / shatter transitions, destruction. Step 8.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local Types = require(Shared.Types)

local Formation = require(script.Parent.Formation)

type Formation = Formation.Formation

export type SimLike = {
	tick: number,
	formations: { [number]: Formation },
	order: { number },
	emit: (sim: any, ev: Types.Event) -> (),
	log: (sim: any, text: string) -> (),
	hqOf: (sim: any, faction: string) -> Formation?,
	stats: { [string]: any },
	homeEdge: ((sim: any, faction: string) -> { x: number, z: number })?,
	grid: { width: number, depth: number }?,
}

local Morale = {}

local DT = Config.Sim.DT
local M = Config.Morale

local function nearestFriendDist(sim: SimLike, f: Formation): number
	local best = math.huge
	for _, id in sim.order do
		if id ~= f.id then
			local o = sim.formations[id]
			if o and o.faction == f.faction and Formation.isActive(o) and o.state ~= "routing" then
				local d = Vec.dist(f.pos, o.pos)
				if d < best then
					best = d
				end
			end
		end
	end
	return best
end

local function routingFriendsNear(sim: SimLike, f: Formation): number
	local n = 0
	for _, id in sim.order do
		if id ~= f.id then
			local o = sim.formations[id]
			if o and o.faction == f.faction and o.state == "routing" and Vec.dist(f.pos, o.pos) < M.FriendRoutRadius then
				n += 1
			end
		end
	end
	return n
end

local function enemyNear(sim: SimLike, f: Formation, radius: number): boolean
	for _, id in sim.order do
		local o = sim.formations[id]
		if o and o.faction ~= f.faction and Formation.isActive(o) and o.state ~= "routing" and Vec.dist(f.pos, o.pos) < radius then
			return true
		end
	end
	return false
end

local function startRout(sim: SimLike, f: Formation, why: string)
	f.state = "routing"
	f.routCount += 1
	f.order = nil
	f.queue = {}
	f.path = nil
	f.pathIndex = 1
	f.targetId = nil
	f.meleeWith = {}
	f.timers.routing = 0
	f.chargeReady = false
	if f.class == "artillery" then
		-- Crews abandon the guns: the battery is lost.
		f.state = "destroyed"
		f.destroyedTick = sim.tick
		sim.emit(sim, { kind = "destroyed", tick = sim.tick, id = f.id, faction = f.faction, x = f.pos.x, z = f.pos.z, text = f.name .. ": guns abandoned" })
		sim.log(sim, string.format("%s abandoned its guns (%s)", f.name, why))
		for _, id in sim.order do
			local o = sim.formations[id]
			if o and o.faction == f.faction and Formation.isActive(o) then
				o.morale = math.max(0, o.morale - M.CapturedGunsMorale)
			end
		end
		return
	end
	if f.strength < f.startStrength * M.ShatterStrengthFraction or f.routCount > M.MaxRouts then
		f.shattered = true
	end
	sim.emit(sim, { kind = "rout", tick = sim.tick, id = f.id, faction = f.faction, x = f.pos.x, z = f.pos.z, text = f.name .. (if f.shattered then " is shattered" else " is routing") })
	sim.log(sim, string.format("%s broke (%s)%s", f.name, why, if f.shattered then ", shattered" else ""))
end

function Morale.rally(sim: SimLike, f: Formation, by: string)
	f.state = "rallying"
	f.timers.rallying = 5
	f.morale = math.max(f.morale, M.RallyMorale)
	f.moraleBand = "shaken"
	f.path = nil
	-- Rallied at the rear edge: walk back onto the field to a slot spread by id, so rallied
	-- formations do not pile on top of each other.
	local home = if sim.homeEdge then sim.homeEdge(sim, f.faction) else nil
	local grid = sim.grid
	if home and grid then
		local edgeZ = if home.z < 0 then 0 else grid.depth
		if math.abs(f.pos.z - edgeZ) < 80 then
			local inward = if home.z < 0 then 1 else -1
			local x = math.clamp(f.pos.x + ((f.id % 5) - 2) * 45, 30, grid.width - 30)
			local z = edgeZ + inward * (110 + (f.id % 3) * 30)
			f.order = { kind = "Move", pos = { x = x, z = z }, heading = if inward > 0 then math.pi / 2 else -math.pi / 2, issuedTick = sim.tick }
			f.queue = {}
		end
	end
	sim.emit(sim, { kind = "rally", tick = sim.tick, id = f.id, faction = f.faction, x = f.pos.x, z = f.pos.z, text = f.name .. " rallies" .. by })
end

local function destroy(sim: SimLike, f: Formation)
	f.state = "destroyed"
	f.destroyedTick = sim.tick
	f.order = nil
	f.path = nil
	f.meleeWith = {}
	sim.emit(sim, { kind = "destroyed", tick = sim.tick, id = f.id, faction = f.faction, x = f.pos.x, z = f.pos.z, text = f.name .. " is destroyed" })
	sim.log(sim, f.name .. " was destroyed")
	if f.class == "hq" then
		for _, id in sim.order do
			local o = sim.formations[id]
			if o and o.faction == f.faction and Formation.isActive(o) then
				o.morale = math.max(0, o.morale - Config.Units.hq.lossMoralePenalty)
			end
		end
		sim.log(sim, f.name .. " fell; the army wavers")
	end
	if f.class == "artillery" then
		for _, id in sim.order do
			local o = sim.formations[id]
			if o and o.faction == f.faction and Formation.isActive(o) then
				o.morale = math.max(0, o.morale - M.CapturedGunsMorale)
			end
		end
	end
end

-- Step 8 for one formation.
function Morale.update(sim: SimLike, f: Formation)
	if not Formation.isActive(f) then
		return
	end
	-- Destruction from casualties.
	if f.strength <= 0 or (f.class ~= "hq" and f.strength < Config.Visual.SoldiersPerFigure * 0.5) then
		destroy(sim, f)
		return
	end
	local t = f.timers
	-- Casualty shock.
	if f.casualtiesThisTick > 0 then
		local frac = f.casualtiesThisTick / math.max(1, f.strength + f.casualtiesThisTick)
		f.morale -= frac * 100 * M.CasualtyFactor
		f.casualtiesThisTick = 0
	end
	-- Flank / rear shock: one-shot per volley/cannonade/charge, sustained per second in melee.
	if f.hitSide == "flank" then
		f.morale -= M.FlankHitPenalty
	elseif f.hitSide == "rear" then
		f.morale -= M.RearHitPenalty
	end
	if f.meleeSide == "flank" then
		f.morale -= M.FlankMeleePerSecond * DT
	elseif f.meleeSide == "rear" then
		f.morale -= M.RearMeleePerSecond * DT
	end
	f.hitSide = nil
	f.meleeSide = nil
	-- Friends routing nearby (a formation that is itself routing is past caring).
	t.friendRout += DT
	if t.friendRout >= M.FriendRoutInterval then
		t.friendRout = 0
		if f.state ~= "routing" then
			local n = routingFriendsNear(sim, f)
			if n > 0 then
				f.morale -= math.min(M.FriendRoutMax, n * M.FriendRoutPenalty)
			end
		end
	end
	-- Isolation.
	t.isolation += DT
	if t.isolation >= M.IsolationInterval then
		t.isolation = 0
		if nearestFriendDist(sim, f) > M.IsolationRadius then
			f.morale -= M.IsolationPenalty
		end
	end
	-- Fatigue.
	if f.fatigue > M.FatigueThreshold then
		f.morale -= M.FatiguePenaltyPerSecond * DT
	end
	-- Recovery (HQ influence raises the cap and the rate).
	local hq = sim.hqOf(sim, f.faction)
	local cap = f.baseMorale
	local rate = 0
	if t.noDamage >= M.RecoveryDelay then
		-- Routing formations recover too: that is how they come back to rally.
		rate = M.RecoveryPerSecond
	end
	if hq and hq.id ~= f.id and Vec.dist(hq.pos, f.pos) <= Config.Units.hq.influence.radius then
		cap += Config.Units.hq.influence.moraleBonus
		rate += Config.Units.hq.influence.recoveryBonus
	end
	if f.morale < cap then
		f.morale = math.min(cap, f.morale + rate * DT)
	end
	f.morale = math.clamp(f.morale, 0, 100)

	-- Transitions.
	if f.state == "routing" then
		t.routing += DT
		if not f.shattered and t.routing >= M.MinRoutSeconds and f.morale >= M.RallyMorale and not enemyNear(sim, f, M.RallyNoEnemyRadius) then
			Morale.rally(sim, f, "")
		end
		return
	end
	if f.state == "rallying" then
		t.rallying -= DT
		if t.rallying <= 0 then
			f.state = if f.order and f.order.pos then "moving" else "idle"
		end
		return
	end
	if f.morale < M.RoutEnter then
		startRout(sim, f, "morale collapsed")
		return
	end
	if f.moraleBand == "steady" and f.morale < M.ShakenEnter then
		f.moraleBand = "shaken"
	elseif f.moraleBand == "shaken" and f.morale >= M.ShakenExit then
		f.moraleBand = "steady"
	end
end

-- HQ Rally order: restore routing friends within radius that have routed for a minimum time.
function Morale.hqRally(sim: SimLike, hq: Formation): (boolean, string?)
	if hq.timers.rallyCd > 0 then
		return false, "cooldown"
	end
	local cfg = Config.Units.hq.rally
	local any = false
	for _, id in sim.order do
		local o = sim.formations[id]
		if o and o.faction == hq.faction and o.state == "routing" and not o.shattered and o.timers.routing >= cfg.minRoutingSeconds and Vec.dist(o.pos, hq.pos) <= cfg.radius then
			o.morale = math.min(100, o.morale + cfg.moraleRestore)
			Morale.rally(sim, o, " to the colours")
			any = true
		end
	end
	hq.timers.rallyCd = cfg.cooldown
	if not any then
		sim.emit(sim, { kind = "message", tick = sim.tick, id = hq.id, faction = hq.faction, text = "No routing formation within reach of the general" })
	end
	return true, nil
end

return Morale
