--!strict
-- Fire, artillery, melee and charge resolution. Step 6 gathers attacks from a frozen view of
-- the tick (positions/states as they are after movement); step 7 applies them. Both sides
-- resolve simultaneously; ordering is ascending formation id for determinism.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local WorldGen = require(Shared.WorldGen)
local Vec = require(Shared.Vec)
local Types = require(Shared.Types)

local Formation = require(script.Parent.Formation)

type Vec = Vec.Vec
type Formation = Formation.Formation

export type Attack = {
	attackerId: number,
	targetId: number,
	casualties: number,
	side: string, -- front | flank | rear
	moraleExtra: number,
	kind: "volley" | "cannon" | "melee" | "charge",
}

export type SimLike = {
	grid: Grid.Grid,
	map: any, -- MapGen.MapData (field borders for cover)
	tick: number,
	rng: any,
	weather: string?,
	formations: { [number]: Formation },
	order: { number },
	emit: (sim: any, ev: Types.Event) -> (),
	isVisibleTo: (sim: any, viewerFaction: string, id: number) -> boolean,
	findFormation: (sim: any, id: number) -> Formation?,
}

local Combat = {}

local DT = Config.Sim.DT
local C = Config.Combat

local function rollCasualties(sim: SimLike, expected: number): number
	local whole = math.floor(expected)
	local frac = expected - whole
	if sim.rng:chance(frac) then
		whole += 1
	end
	return whole
end

-- A friendly formation inside the lane between shooter and target blocks the volley.
local function laneBlocked(sim: SimLike, shooter: Formation, target: Formation): boolean
	if not C.FriendlyBlocksFire then
		return false
	end
	local a, b = shooter.pos, target.pos
	for _, id in sim.order do
		if id ~= shooter.id and id ~= target.id then
			local o = sim.formations[id]
			if o and o.faction == shooter.faction and Formation.isActive(o) then
				local d = Vec.distToSegment(o.pos, a, b)
				if d < C.FireLaneHalfWidth + o.halfRadius * 0.5 then
					-- only counts when strictly between (not behind the shooter)
					local t = Vec.dot(Vec.sub(o.pos, a), Vec.sub(b, a)) / math.max(1e-6, Vec.dist2(a, b))
					if t > 0.1 and t < 0.9 then
						return true
					end
				end
			end
		end
	end
	return false
end

local function inArc(shooter: Formation, target: Formation, halfAngle: number): boolean
	return math.abs(Vec.bearing(shooter.pos, shooter.heading, target.pos)) <= halfAngle
end

-- Why a formation cannot fire right now (nil = it can). Also used for the HUD status word.
function Combat.fireBlockReason(sim: SimLike, f: Formation, target: Formation?): string?
	local unit = Formation.unitConfig(f)
	if f.class == "artillery" then
		if f.shape ~= "deployed" then
			return "Limbered"
		end
	elseif not unit.musket then
		return "No firearms"
	end
	if f.ammo <= 0 then
		return "Out of ammunition"
	end
	if f.state == "reforming" then
		return "Reforming"
	end
	if f.state == "melee" or f.state == "charging" or f.state == "routing" or f.state == "rallying" then
		return "Engaged"
	end
	if (Grid.terrainAt(sim.grid, f.pos.x, f.pos.z) :: any).noFire then
		return "Wading the ford"
	end
	if f.class == "infantry" and f.shape == "travel" then
		return "In travel column"
	end
	if f.reload > 0 then
		return "Reloading"
	end
	if not target then
		return "No target"
	end
	local dist = Vec.dist(f.pos, target.pos)
	if f.class == "artillery" then
		local gun = unit.gun
		local mode = Combat.artilleryMode(f, dist)
		local ammo = (gun :: any)[mode]
		if dist > ammo.range or dist < ammo.minRange then
			return "Out of range"
		end
		if not inArc(f, target, gun.arcHalfAngle) then
			return "Outside firing arc"
		end
	else
		if dist > unit.musket.range then
			return "Out of range"
		end
		-- a square faces every way (its fire factor already counts one face's muskets); skirmishers
		-- each pick their own mark
		if f.shape ~= "square" and f.shape ~= "skirmish" and f.shape ~= "garrison" and not inArc(f, target, math.rad(60)) then
			return "Target not to the front"
		end
	end
	if not sim.isVisibleTo(sim, f.faction, target.id) then
		return "Target not visible"
	end
	-- howitzer shells are lobbed: over the crest and over friends, at anything the side can see
	local lobbed = unit.gun and unit.gun.indirect and Combat.artilleryMode(f, dist) == "roundShot"
	if not lobbed and not Grid.lineOfSight(sim.grid, f.pos, target.pos) then
		return "Line of fire blocked"
	end
	if not lobbed and laneBlocked(sim, f, target) then
		return "Friends in the line of fire"
	end
	return nil
end

function Combat.artilleryMode(f: Formation, dist: number): "roundShot" | "canister"
	if f.ammoMode == "canister" then
		return "canister"
	elseif f.ammoMode == "roundShot" then
		return "roundShot"
	end
	return if dist <= Formation.unitConfig(f).gun.canister.range then "canister" else "roundShot"
end

-- Best visible enemy for fire-at-will: nearest in arc and range with a clear lane.
function Combat.pickFireTarget(sim: SimLike, f: Formation): Formation?
	local best: Formation? = nil
	local bestD = math.huge
	local preferred = f.targetId and sim.findFormation(sim, f.targetId)
	if preferred and Formation.isActive(preferred) and Combat.fireBlockReason(sim, f, preferred) == nil then
		return preferred
	end
	if not f.fireAtWill and f.class ~= "artillery" then
		return nil
	end
	for _, id in sim.order do
		local o = sim.formations[id]
		if o and o.faction ~= f.faction and Formation.isActive(o) then
			local d = Vec.dist2(f.pos, o.pos)
			if d < bestD and Combat.fireBlockReason(sim, f, o) == nil then
				best = o
				bestD = d
			end
		end
	end
	return best
end

local function uphill(sim: SimLike, a: Vec, b: Vec): boolean
	return Grid.heightAt(sim.grid, a.x, a.z) > Grid.heightAt(sim.grid, b.x, b.z) + 3
end

local function volley(sim: SimLike, f: Formation, target: Formation, attacks: { Attack })
	local unit = Formation.unitConfig(f)
	local musket = unit.musket
	local shapeCfg = (Config.Shapes :: any)[f.shape]
	local readiness = math.max(musket.minReadiness, f.cohesion)
	if f.moraleBand == "shaken" then
		readiness *= C.ShakenFireFactor
	end
	local shooters = f.strength * shapeCfg.fire * readiness
	if shooters < C.VolleyMinStrength then
		return
	end
	local dist = Vec.dist(f.pos, target.pos)
	local rangeF = 1 - C.RangeFalloff * (dist / musket.range)
	local terrain = Grid.terrainAt(sim.grid, target.pos.x, target.pos.z)
	local cover = terrain.cover + target.mods.cover
	if terrain.name == "open" or terrain.name == "steep" then
		local border = WorldGen.borderCover(sim.map, target.pos.x, target.pos.z, f.pos.x, f.pos.z, 6)
		if border then
			cover += C.BorderCover[border]
		end
	end
	cover = math.min(0.9, cover)
	local side = Vec.attackSide(target.pos, target.heading, f.pos)
	local sideF = if side == "front" then 1 elseif side == "flank" then C.FlankFireFactor else C.RearFireFactor
	local hit = musket.accuracy * rangeF * (1 - cover) * Formation.fatigueFactor(f, C.FatigueAccuracyPenalty) * (1 + C.ExperienceAccuracy * f.experience)
	hit *= (C.TargetShapeFactor :: any)[target.shape] or 1
	hit *= sideF
	if uphill(sim, f.pos, target.pos) then
		hit *= 1 + Config.Slope.UphillFireBonus
	end
	hit *= ((Config.Weather :: any)[sim.weather or "clear"] or Config.Weather.clear).accuracy * f.mods.accuracy
	hit = math.min(C.MaxHitChance, hit)
	local casualties = rollCasualties(sim, shooters * hit)
	f.reload = musket.reload
	if f.fireByRank and f.shape == "line" and f.state ~= "moving" then
		f.reload *= C.FireByRankReload
	end
	f.ammo -= 1
	f.lastShotTick = sim.tick
	f.state = if f.state == "idle" then "firing" else f.state
	f.timers.halt = if f.shape == "skirmish" then 0 else 1.5 -- a formed body halts to deliver the volley
	attacks[#attacks + 1] = { attackerId = f.id, targetId = target.id, casualties = casualties, side = side, moraleExtra = 0, kind = "volley" }
	sim.emit(sim, { kind = "volley", tick = sim.tick, id = f.id, targetId = target.id, faction = f.faction, x = f.pos.x, z = f.pos.z, tx = target.pos.x, tz = target.pos.z, n = casualties })
end

local function cannonade(sim: SimLike, f: Formation, target: Formation, attacks: { Attack })
	local gun = Formation.unitConfig(f).gun
	local dist = Vec.dist(f.pos, target.pos)
	local mode = Combat.artilleryMode(f, dist)
	local ammo = (gun :: any)[mode]
	local guns = Formation.figures(f)
	local rangeF = 1 - C.RangeFalloff * (dist / ammo.range)
	local shapeF = (Config.Shapes :: any)[target.shape].artillery
	local cover = math.min(0.9, Grid.terrainAt(sim.grid, target.pos.x, target.pos.z).cover + target.mods.cover)
	local weatherF = ((Config.Weather :: any)[sim.weather or "clear"] or Config.Weather.clear).cannon
	local expected = guns * ammo.hit * weatherF * rangeF * (1 - cover * 0.5) * ammo.casualtiesPerHit * shapeF * Formation.fatigueFactor(f, C.FatigueAccuracyPenalty) * (1 + C.ExperienceAccuracy * f.experience) * f.mods.accuracy
	local casualties = rollCasualties(sim, expected)
	f.reload = ammo.reload
	f.ammo -= 1
	f.lastShotTick = sim.tick
	f.state = if f.state == "idle" then "firing" else f.state
	local side = Vec.attackSide(target.pos, target.heading, f.pos)
	attacks[#attacks + 1] = { attackerId = f.id, targetId = target.id, casualties = casualties, side = side, moraleExtra = ammo.morale, kind = "cannon" }
	sim.emit(sim, { kind = "cannon", tick = sim.tick, id = f.id, targetId = target.id, faction = f.faction, x = f.pos.x, z = f.pos.z, tx = target.pos.x, tz = target.pos.z, n = casualties, text = if gun.indirect and mode == "roundShot" then "shell" else mode })
	if ammo.splash then
		-- a shell bursts: everyone within the splash, friend or foe, takes part of it
		for _, id in sim.order do
			local o = sim.formations[id]
			if o and o ~= f and o ~= target and Formation.isActive(o) then
				local d = Vec.dist(o.pos, target.pos) - o.halfRadius * 0.5
				if d < ammo.splash then
					local n = rollCasualties(sim, expected / shapeF * 0.5 * (1 - math.max(0, d) / ammo.splash) * (Config.Shapes :: any)[o.shape].artillery)
					attacks[#attacks + 1] = { attackerId = f.id, targetId = o.id, casualties = n, side = Vec.attackSide(o.pos, o.heading, f.pos), moraleExtra = ammo.morale * 0.5, kind = "cannon" }
				end
			end
		end
	elseif mode == "roundShot" then
		-- the ball bounces on through whatever stands behind, friend or foe
		local R = C.Ricochet
		local dir = Vec.normalize(Vec.sub(target.pos, f.pos))
		local far = Vec.add(target.pos, Vec.scale(dir, R.length))
		local strike = expected / shapeF -- the first strike before the target's shape
		local inLane: { { o: Formation, t: number } } = {}
		for _, id in sim.order do
			local o = sim.formations[id]
			if o and o ~= f and o ~= target and Formation.isActive(o) and Vec.distToSegment(o.pos, target.pos, far) < o.halfRadius * 0.6 then
				local t = Vec.dot(Vec.sub(o.pos, target.pos), dir) / R.length
				if t > 0 then
					table.insert(inLane, { o = o, t = t })
				end
			end
		end
		table.sort(inLane, function(p: { o: Formation, t: number }, q: { o: Formation, t: number }): boolean
			return if p.t ~= q.t then p.t < q.t else p.o.id < q.o.id
		end)
		for i = 1, math.min(R.maxHits, #inLane) do
			local o, t = inLane[i].o, inLane[i].t
			local n = rollCasualties(sim, strike * R.factor * (1 - 0.5 * t) * (Config.Shapes :: any)[o.shape].artillery)
			attacks[#attacks + 1] = { attackerId = f.id, targetId = o.id, casualties = n, side = Vec.attackSide(o.pos, o.heading, f.pos), moraleExtra = ammo.morale * 0.5, kind = "cannon" }
		end
	end
end

-- Footprints touching: centres within the sum of half-radii plus contact distance.
function Combat.inContact(a: Formation, b: Formation): boolean
	local r = a.halfRadius + b.halfRadius + C.MeleeContactDistance
	return Vec.dist2(a.pos, b.pos) <= r * r
end

local function meleeDamage(sim: SimLike, att: Formation, def: Formation, attacks: { Attack })
	local unitA = Formation.unitConfig(att)
	local unitD = Formation.unitConfig(def)
	local shapeA = (Config.Shapes :: any)[att.shape]
	local side = Vec.attackSide(def.pos, def.heading, att.pos)
	local dirF = (C.MeleeDirFactor :: any)[side]
	if def.shape == "square" then
		dirF = 1 -- a square has no flank
	end
	local rate = att.strength * C.MeleeRatePerSecond * unitA.melee.attack * shapeA.melee * dirF
	rate *= Formation.fatigueFactor(att, C.FatigueMeleePenalty) * (1 + C.ExperienceMelee * att.experience) * att.mods.melee
	if att.timers.bayonet > 0 then
		rate *= C.BayonetBonus
	end
	if att.class == "cavalry" and def.shape == "square" then
		rate *= 0.3
	elseif att.class == "cavalry" and def.shape == "garrison" then
		rate *= 0.15 -- horsemen cannot get at men behind walls
	end
	if def.class == "cavalry" and att.shape == "square" then
		rate *= C.SquareReturnsDamage
	end
	if att.class == "cavalry" and att.inWoods then
		rate *= 0.5
	end
	if att.class == "cavalry" and att.timers.meleeSeconds > unitA.charge.maxMeleeSeconds then
		rate *= 0.5 -- blown horses: sustained melee is not cavalry's business
	end
	if att.moraleBand == "shaken" then
		rate *= C.ShakenMeleeFactor
	end
	if uphill(sim, att.pos, def.pos) then
		rate *= 1 + Config.Slope.DownhillMeleeBonus
	end
	rate *= (Grid.terrainAt(sim.grid, att.pos.x, att.pos.z) :: any).melee or 1 -- wading men fight badly
	rate /= unitD.melee.defense
	local casualties = rollCasualties(sim, rate * DT)
	local extra = 0
	if att.class == "cavalry" and def.class == "artillery" then
		extra = 2 * DT
	end
	attacks[#attacks + 1] = { attackerId = att.id, targetId = def.id, casualties = casualties, side = side, moraleExtra = extra, kind = "melee" }
end

local function chargeImpact(sim: SimLike, att: Formation, def: Formation, attacks: { Attack })
	local unit = Formation.unitConfig(att)
	if att.class == "cavalry" then
		local ch = unit.charge
		local runUpF = math.clamp(att.runUp / ch.runUp, C.MinRunUpFactor, 1)
		local side = Vec.attackSide(def.pos, def.heading, att.pos)
		local dirF = if side == "front" then ch.frontFactor elseif side == "flank" then ch.flankFactor else ch.rearFactor
		local shapeF = (C.ChargeShapeFactor :: any)[def.shape] or 1
		if def.state == "reforming" then
			shapeF *= 1.5
		end
		if def.shape == "square" then
			dirF = 1
		end
		if def.state == "routing" then
			shapeF *= C.ChargeRoutingFactor * (unit.pursuit or 1) -- light cavalry rides down fugitives
		end
		local impact = att.strength * ch.base * runUpF * dirF * shapeF * Formation.fatigueFactor(att, C.FatigueMeleePenalty) * att.mods.chargeImpact
		if uphill(sim, att.pos, def.pos) then
			impact *= 1 + Config.Slope.DownhillChargeBonus
		end
		if att.inWoods then
			impact *= 0.5
		end
		local casualties = rollCasualties(sim, impact)
		attacks[#attacks + 1] = { attackerId = att.id, targetId = def.id, casualties = casualties, side = side, moraleExtra = if def.shape == "square" then 0 else 8, kind = "charge" }
		att.timers.chargeRecover = ch.recovery * att.mods.chargeRecovery
		att.fatigue = math.min(100, att.fatigue + 10)
		sim.emit(sim, { kind = "charge", tick = sim.tick, id = att.id, targetId = def.id, faction = att.faction, x = att.pos.x, z = att.pos.z, tx = def.pos.x, tz = def.pos.z, n = casualties, text = if def.shape == "square" then "square" else side })
	else
		-- bayonet assault
		local side = Vec.attackSide(def.pos, def.heading, att.pos)
		local shock = if side == "front" then C.BayonetMoraleShock.front else C.BayonetMoraleShock.flank
		att.timers.bayonet = C.BayonetBonusSeconds
		attacks[#attacks + 1] = { attackerId = att.id, targetId = def.id, casualties = 0, side = side, moraleExtra = shock, kind = "charge" }
		sim.emit(sim, { kind = "charge", tick = sim.tick, id = att.id, targetId = def.id, faction = att.faction, x = att.pos.x, z = att.pos.z, tx = def.pos.x, tz = def.pos.z, n = 0, text = "bayonet" })
	end
	att.chargeReady = false
	att.runUp = 0
end

-- Step 6: gather all attacks for this tick.
function Combat.gather(sim: SimLike): { Attack }
	local attacks: { Attack } = {}
	-- Contacts first (charges land before volleys in the same tick; both still resolve).
	for _, id in sim.order do
		local f = sim.formations[id]
		-- `state` is a copy so that `state == a or state == b` narrows the copy, not f: the analyzer
		-- would otherwise stop accepting f as a Formation in the calls below.
		local state = f and f.state
		if f and Formation.isActive(f) and f.state ~= "routing" and f.state ~= "rallying" then
			-- Charging into a target
			if state == "charging" and f.order and f.order.targetId then
				local target = sim.findFormation(sim, f.order.targetId)
				if target and Formation.isActive(target) and Combat.inContact(f, target) then
					if f.chargeReady and f.timers.chargeRecover <= 0 then
						chargeImpact(sim, f, target, attacks)
					end
					f.state = "melee"
					f.meleeWith[target.id] = true
					target.meleeWith[f.id] = true
					if target.state ~= "melee" and target.state ~= "routing" then
						target.state = "melee"
						target.path = nil
					end
					f.path = nil
				elseif target and Formation.isActive(target) and f.class == "cavalry" and not f.chargeReady and f.timers.chargeRecover <= 0 then
					f.chargeReady = true
				end
			elseif state == "charging" and f.order and f.order.pos and not f.order.targetId then
				-- charge toward a position: hit whatever enemy we touch
				for _, oid in sim.order do
					local o = sim.formations[oid]
					if o and o.faction ~= f.faction and Formation.isActive(o) and Combat.inContact(f, o) then
						if f.chargeReady and f.timers.chargeRecover <= 0 then
							chargeImpact(sim, f, o, attacks)
						end
						f.state = "melee"
						f.meleeWith[o.id] = true
						o.meleeWith[f.id] = true
						if o.state ~= "melee" and o.state ~= "routing" then
							o.state = "melee"
							o.path = nil
						end
						f.path = nil
						break
					end
				end
			elseif f.order and f.order.kind == "Engage" and f.order.targetId and (state == "moving" or state == "idle") then
				local target = sim.findFormation(sim, f.order.targetId)
				if target and Formation.isActive(target) and Combat.inContact(f, target) and f.class ~= "artillery" then
					f.state = "melee"
					f.meleeWith[target.id] = true
					target.meleeWith[f.id] = true
					if target.state ~= "melee" and target.state ~= "routing" then
						target.state = "melee"
						target.path = nil
					end
					f.path = nil
				end
			end
		end
	end
	-- Contact without an attack order (attack-move, a move that ran into the enemy, an enemy that
	-- walked into us): touching footprints fight. Guns and staff never start a melee themselves.
	for _, id in sim.order do
		local f = sim.formations[id]
		local state = f and f.state
		if f and Formation.isActive(f) and f.class ~= "artillery" and f.class ~= "hq" and (state == "idle" or state == "moving" or state == "firing") then
			for _, oid in sim.order do
				local o = sim.formations[oid]
				if o and o.faction ~= f.faction and Formation.isActive(o) and o.state ~= "routing" and o.state ~= "rallying" and Combat.inContact(f, o) then
					f.state = "melee"
					f.path = nil
					f.meleeWith[o.id] = true
					o.meleeWith[f.id] = true
					if o.state ~= "melee" then
						o.state = "melee"
						o.path = nil
					end
					break
				end
			end
		end
	end
	-- Melee damage for every engaged pair (each side attacks the other).
	for _, id in sim.order do
		local f = sim.formations[id]
		if f and f.state == "melee" then
			local anyContact = false
			for oid in f.meleeWith do
				local o = sim.formations[oid]
				if o and Formation.isActive(o) and o.state ~= "routing" and Combat.inContact(f, o) then
					anyContact = true
					meleeDamage(sim, f, o, attacks)
				else
					f.meleeWith[oid] = nil
				end
			end
			f.timers.meleeSeconds += DT
			f.fatigue = math.min(100, f.fatigue + Formation.unitConfig(f).fatigueMelee * DT)
			if not anyContact then
				f.state = "idle"
				f.timers.meleeSeconds = 0
				if f.order and (f.order.kind == "Charge" or f.order.kind == "Engage") then
					local target = f.order.targetId and sim.findFormation(sim, f.order.targetId)
					if not target or not Formation.isActive(target) or target.state == "routing" then
						Formation.clearOrder(f)
					else
						f.state = "moving"
						f.path = nil
					end
				end
			end
		end
	end
	-- Fire.
	for _, id in sim.order do
		local f = sim.formations[id]
		local state = f and f.state
		if f and Formation.isActive(f) and (state == "idle" or state == "firing" or state == "moving") then
			local target = Combat.pickFireTarget(sim, f)
			if target then
				if f.class == "artillery" then
					cannonade(sim, f, target, attacks)
				elseif f.class == "infantry" then
					if f.state == "moving" and f.order and f.order.kind == "Move" and f.shape ~= "skirmish" then
						-- Moving infantry does not stop for fire-at-will unless attack-moving (skirmishers fire on the move).
					else
						volley(sim, f, target, attacks)
					end
				end
			elseif f.state == "firing" then
				f.state = "idle"
			end
			f.status = if f.class ~= "cavalry" and f.class ~= "hq" then Combat.fireBlockReason(sim, f, target) else nil
		end
	end
	return attacks
end

-- Step 7: apply casualties and ammunition; morale consequences handled by Morale.
function Combat.apply(sim: SimLike, attacks: { Attack })
	for _, a in attacks do
		local t = sim.formations[a.targetId]
		if t and Formation.isActive(t) then
			local lost = math.min(t.strength, a.casualties)
			t.strength -= lost
			t.casualtiesThisTick += lost
			if lost > 0 then
				t.timers.noDamage = 0
			end
			if a.side ~= "front" and (lost > 0 or a.kind ~= "volley") then
				if a.kind == "melee" then
					-- sustained pressure: per-second penalty applied by Morale
					if t.meleeSide == nil or a.side == "rear" then
						t.meleeSide = a.side
					end
				elseif t.hitSide == nil or a.side == "rear" then
					-- one-shot shock from a flank/rear volley, cannonade or charge
					t.hitSide = a.side
				end
			end
			if a.moraleExtra > 0 then
				t.morale = math.max(0, t.morale - a.moraleExtra)
			end
			if t.state == "reforming" and a.kind == "charge" then
				-- a charge interrupts a half-formed square: resolve against the previous shape
				t.cohesion = math.max(0.3, t.cohesion - 0.2)
			end
			Formation.refreshFootprint(t)
		end
	end
end

return Combat
