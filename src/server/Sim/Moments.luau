--!strict
-- Evaluates the scenario's historical moments (src/shared/Moments.luau) every
-- Moments.EveryTicks ticks, after objectives. Pure and deterministic: reads sim state only,
-- fires each moment at most once, in list order.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local Defs = require(Shared.Moments)

local Formation = require(script.Parent.Formation)

type Formation = Formation.Formation
type Condition = Defs.Condition
type Selector = Defs.Selector
type Moment = Defs.Moment

local Moments = {}

local DT = Config.Sim.DT
local LIMIT = Defs.MoraleLimit

local function each(sim: any, sel: Selector, fn: (Formation) -> boolean?): boolean
	for _, id in sim.order do
		local f = sim.formations[id]
		if f and Defs.matches(sel, f) and fn(f) then
			return true
		end
	end
	return false
end

local function objective(sim: any, id: string): any
	for _, o in sim.objectives do
		if o.def.id == id then
			return o
		end
	end
	return nil
end

local function holds(sim: any, c: Condition): boolean
	if c.time and sim.clock < c.time then
		return false
	end
	if c.before and sim.clock >= c.before then
		return false
	end
	if c.weatherCleared ~= nil and (sim.weather == "clear") ~= c.weatherCleared then
		return false
	end
	local ot = c.objectiveTaken
	if ot then
		local o = objective(sim, ot.id)
		if not o or o.owner ~= ot.by then
			return false
		end
		if ot.seconds and (not o.heldSince or (sim.tick - o.heldSince) * DT < ot.seconds) then
			return false
		end
	end
	local fr = c.formationRouted
	if fr and not each(sim, fr, function(f)
		return f.state == "routing" or f.state == "destroyed" or f.shattered
	end) then
		return false
	end
	local sb = c.strengthBelow
	if sb then
		local now, start = 0, 0
		each(sim, sb, function(f)
			start += f.startStrength
			if f.state ~= "destroyed" and f.state ~= "exited" then
				now += f.strength
			end
			return false
		end)
		if start == 0 or now >= start * (sb.fraction or 0) then
			return false
		end
	end
	local fn = c.formationNear
	if fn then
		local at = fn.pos
		if fn.objective then
			local o = objective(sim, fn.objective)
			at = if o then o.def.pos else nil
		end
		local p = at
		if not p then
			return false
		end
		local r2 = (fn.radius or 0) ^ 2
		if not each(sim, fn, function(f)
			return Formation.isActive(f) and f.state ~= "routing" and Vec.dist2(f.pos, p) <= r2
		end) then
			return false
		end
	end
	if c.all then
		for _, sub in c.all do
			if not holds(sim, sub) then
				return false
			end
		end
	end
	if c.any then
		local ok = false
		for _, sub in c.any do
			if holds(sim, sub) then
				ok = true
				break
			end
		end
		if not ok then
			return false
		end
	end
	return true
end
Moments.holds = holds

local function apply(sim: any, m: Moment)
	local e = m.effect
	if not e then
		return
	end
	for _, sel in e.morale or {} do
		local amount = math.clamp(sel.amount or 0, -LIMIT, LIMIT)
		each(sim, sel, function(f)
			if Formation.isActive(f) then
				f.morale = math.clamp(f.morale + amount, 0, 100)
			end
			return false
		end)
	end
	if e.release then
		each(sim, { name = e.release }, function(f)
			if f.state == "offmap" and f.arrivalTick and f.arrivalTick > sim.tick then
				f.arrivalTick = sim.tick -- enters at step 0 of the next tick
			end
			return false
		end)
	end
	if e.weather and (Config.Weather :: any)[e.weather] then
		sim.weather = e.weather
	end
end

-- Called every tick from Sim.step; does work every Moments.EveryTicks.
function Moments.update(sim: any)
	local list: { Moment }? = sim.scenario.moments
	if not list or sim.tick % Defs.EveryTicks ~= 0 then
		return
	end
	for _, m in list do
		if not sim.momentsFired[m.id] and holds(sim, m.when) then
			sim.momentsFired[m.id] = true
			apply(sim, m)
			local cam = m.camera
			sim:emit({ kind = "moment", tick = sim.tick, momentId = m.id, title = m.title, text = m.text, faction = m.faction, x = cam and cam.x, z = cam and cam.z, height = cam and cam.height })
			sim:log(m.title)
		end
	end
end

return Moments
