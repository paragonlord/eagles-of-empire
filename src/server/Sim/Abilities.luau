--!strict
-- Generals in battle: trait modifiers recomputed every tick (bounded) and the HQ's active ability.
-- Data and plain-text descriptions live in src/shared/Generals.luau; docs/rules.md ("Generals")
-- is the contract. Pure Luau, deterministic, no randomness.
--
-- Each tick (after commands and the AI, before movement) every formation's `mods` are reset to
-- neutral, then the traits that reach it and the ability effects it is under are folded in once
-- each, and the result is clamped to Abilities.Bounds. The ids applied are kept in `mods.tags` so
-- the owner's client can show every modifier.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local Grid = require(Shared.Grid)
local Types = require(Shared.Types)
local Generals = require(Shared.Generals)

local Formation = require(script.Parent.Formation)
local Morale = require(script.Parent.Morale)

type Formation = Formation.Formation
type General = Generals.General
type Ability = Generals.Ability

type Effect = { id: string, faction: string, untilTick: number, ids: { [number]: boolean }, mods: Generals.Mods }
export type State = {
	generals: { [number]: General }, -- HQ formation id -> general
	corps: { [number]: General | false }, -- formation id -> corps commander named in its corps
	readyTick: { [number]: number }, -- HQ id -> tick its ability is ready again
	effects: { Effect },
}

export type SimLike = {
	tick: number,
	grid: Grid.Grid,
	scenario: any,
	formations: { [number]: Formation },
	order: { number },
	playerFaction: string,
	enemyFaction: string,
	abilities: State?,
	emit: (sim: any, ev: Types.Event) -> (),
	log: (sim: any, text: string) -> (),
	homeEdge: (sim: any, faction: string) -> { x: number, z: number },
	map: any,
}

local Abilities = {}

local DT = Config.Sim.DT
local HIDE_AFTER_FIRE_TICKS = math.floor(10 / DT) -- reverse-slope infantry shows itself for 10 s after a volley

-- Final modifiers never leave these ranges, whatever stacks.
local BOUNDS: { [string]: { number } } = {
	speed = { 0.8, 1.25 },
	chargeImpact = { 0.8, 1.5 },
	chargeRecovery = { 0.6, 1.3 },
	accuracy = { 0.8, 1.6 },
	melee = { 0.85, 1.25 },
	cover = { 0, 0.2 },
	recovery = { 0, 0.6 },
	shockFloor = { 0, 30 },
}
Abilities.Bounds = BOUNDS

local MULT: { [string]: boolean } = { speed = true, chargeImpact = true, chargeRecovery = true, accuracy = true, melee = true }

function Abilities.state(sim: SimLike): State
	local st = sim.abilities
	if st then
		return st
	end
	local fresh: State = { generals = {}, corps = {}, readyTick = {}, effects = {} }
	for i, def in sim.scenario.units do
		local f = sim.formations[i]
		if f then
			if f.class == "hq" then
				fresh.generals[i] = Generals.forHQ(f.name, def.general)
			end
			fresh.corps[i] = Generals.corpsGeneral(f.corps) or false
		end
	end
	sim.abilities = fresh
	return fresh
end

function Abilities.generalOf(sim: SimLike, hqId: number): General?
	return Abilities.state(sim).generals[hqId]
end

-- Infantry halted with rising ground ahead of it: the crest hides it from the far side.
function Abilities.behindCrest(grid: Grid.Grid, f: Formation): boolean
	local h = Grid.heightAt(grid, f.pos.x, f.pos.z)
	local fwd = Vec.fromHeading(f.heading)
	for _, d in Generals.CrestLook do
		local p = Vec.add(f.pos, Vec.scale(fwd, d))
		if Grid.heightAt(grid, p.x, p.z) >= h + Generals.CrestRise then
			return true
		end
	end
	return false
end

local function halted(f: Formation): boolean
	return f.state == "idle" or f.state == "firing"
end

local function advancing(sim: SimLike, f: Formation): boolean
	local o = f.order
	if not o or (f.state ~= "moving" and f.state ~= "charging") or o.kind == "Retreat" then
		return false
	end
	local dest = o.pos
	if o.targetId then
		local t = sim.formations[o.targetId]
		dest = if t then t.pos else nil
	end
	if not dest then
		return false
	end
	local enemy = if f.faction == sim.playerFaction then sim.enemyFaction else sim.playerFaction
	local toward = Vec.sub(sim.homeEdge(sim, enemy), f.pos)
	return Vec.dot(Vec.sub(dest, f.pos), toward) > 0
end

local function fold(m: Formation.Mods, mods: Generals.Mods)
	local mm: any = m
	for k, v in mods do
		if MULT[k] then
			mm[k] *= v :: number
		elseif k == "cover" or k == "recovery" then
			mm[k] += v :: number
		elseif k == "shockFloor" then
			mm[k] = math.max(mm[k], v :: number)
		elseif k == "hideBeyond" then
			mm[k] = math.min(mm[k] or math.huge, v :: number)
		elseif k == "noRout" or k == "steadyRetreat" then
			mm[k] = mm[k] or v == true
		end
	end
end

local function traitApplies(sim: SimLike, f: Formation, tr: Generals.Trait): boolean
	if tr.classes and not tr.classes[f.class] then
		return false
	end
	if tr.when == "advancing" then
		return advancing(sim, f)
	elseif tr.when == "crest" then
		return halted(f) and Abilities.behindCrest(sim.grid, f)
	end
	return true
end

local function reset(m: Formation.Mods)
	m.speed, m.chargeImpact, m.chargeRecovery, m.accuracy, m.melee = 1, 1, 1, 1, 1
	m.cover, m.recovery, m.shockFloor = 0, 0, 0
	m.hideBeyond = nil
	m.noRout, m.steadyRetreat = false, false
	table.clear(m.tags)
end

-- Tick hook: expire effects, recompute every formation's modifiers.
function Abilities.update(sim: SimLike)
	local st = Abilities.state(sim)
	for i = #st.effects, 1, -1 do
		if st.effects[i].untilTick <= sim.tick then
			table.remove(st.effects, i)
		end
	end
	-- Commanders in the field this tick.
	local hqs: { Formation } = {}
	for id in st.generals do
		local hq = sim.formations[id]
		if hq and Formation.isActive(hq) then
			hqs[#hqs + 1] = hq
		end
	end
	table.sort(hqs, function(a: Formation, b: Formation)
		return a.id < b.id
	end)
	for _, id in sim.order do
		local f = sim.formations[id]
		if not f then
			continue
		end
		local m = f.mods
		reset(m)
		if not Formation.isActive(f) then
			continue
		end
		local seen: { [string]: boolean } = {}
		local function consider(tr: Generals.Trait)
			if not seen[tr.id] and traitApplies(sim, f, tr) then
				seen[tr.id] = true
				fold(m, tr.mods)
				m.tags[#m.tags + 1] = tr.id
			end
		end
		for _, hq in hqs do
			if hq.faction == f.faction then
				local near = Vec.dist(hq.pos, f.pos) <= Generals.TraitRadius
				for _, tr in st.generals[hq.id].traits do
					if tr.scope == "army" or near then
						consider(tr)
					end
				end
			end
		end
		local cg = st.corps[id]
		if cg then
			for _, tr in cg.traits do
				consider(tr)
			end
		end
		for _, e in st.effects do
			if e.ids[id] then
				fold(m, e.mods)
				m.tags[#m.tags + 1] = e.id
			end
		end
		-- Reverse-slope cover stays, but a battalion that has just fired gives itself away.
		if m.hideBeyond and sim.tick - f.lastShotTick < HIDE_AFTER_FIRE_TICKS then
			m.hideBeyond = nil
		end
		local mm: any = m
		for k, b in BOUNDS do
			mm[k] = math.clamp(mm[k], b[1], b[2])
		end
	end
end

-- Abilities ------------------------------------------------------------------------------------

local function friendsWithin(sim: SimLike, hq: Formation, radius: number, pred: (Formation) -> boolean): { Formation }
	local out = {}
	for _, id in sim.order do
		local o = sim.formations[id]
		if o and o.id ~= hq.id and o.faction == hq.faction and Formation.isActive(o) and Vec.dist(o.pos, hq.pos) <= radius and pred(o) then
			out[#out + 1] = o
		end
	end
	return out
end

local function rallyable(o: Formation): boolean
	return o.state == "routing" and not o.shattered
end

local function standing(o: Formation): boolean
	return o.state ~= "routing" and o.state ~= "rallying"
end

local function nearest(list: { Formation }, hq: Formation): { Formation }
	local best: Formation? = nil
	for _, o in list do
		if not best or Vec.dist2(o.pos, hq.pos) < Vec.dist2(best.pos, hq.pos) then
			best = o
		end
	end
	return if best then { best } else {}
end

-- Who the ability would affect right now (empty = it would do nothing, so it is refused).
function Abilities.targets(sim: SimLike, hq: Formation, ab: Ability): { Formation }
	local r = ab.radius
	local k = ab.kind
	if k == "vive" then
		return friendsWithin(sim, hq, r, function(o)
			return rallyable(o) or standing(o)
		end)
	elseif k == "inspire" or k == "holdline" or k == "vorwaerts" then
		return friendsWithin(sim, hq, r, standing)
	elseif k == "charge" then
		return friendsWithin(sim, hq, r, function(o)
			return o.class == "cavalry" and standing(o)
		end)
	elseif k == "withdraw" then
		return friendsWithin(sim, hq, r, rallyable)
	elseif k == "example" then
		local routing = nearest(friendsWithin(sim, hq, r, rallyable), hq)
		if #routing > 0 then
			return routing
		end
		return nearest(friendsWithin(sim, hq, r, function(o)
			return standing(o) and o.moraleBand == "shaken"
		end), hq)
	elseif k == "upguards" then
		return friendsWithin(sim, hq, r, function(o)
			return o.class == "infantry" and halted(o) and Abilities.behindCrest(sim.grid, o)
		end)
	end
	return {}
end

-- Validation shared by Sim.precheck and the moment the command applies.
function Abilities.check(sim: SimLike, hq: Formation, data: any): (boolean, string?)
	if hq.class ~= "hq" then
		return false, "wrongClass"
	end
	local g = Abilities.generalOf(sim, hq.id)
	if not g or type(data) ~= "table" or data.abilityId ~= g.ability.id then
		return false, "badRequest"
	end
	local ok, reason = Formation.canTakeOrders(hq)
	if not ok then
		return false, reason
	end
	if (Abilities.state(sim).readyTick[hq.id] or 0) > sim.tick then
		return false, "cooldown"
	end
	if #Abilities.targets(sim, hq, g.ability) == 0 then
		return false, "noTarget"
	end
	return true, nil
end

-- Seconds until the HQ's ability is ready (0 = ready).
function Abilities.cooldownLeft(sim: SimLike, hqId: number): number
	return math.max(0, ((Abilities.state(sim).readyTick[hqId] or 0) - sim.tick) * DT)
end

local function addEffect(sim: SimLike, hq: Formation, ab: Ability, list: { Formation }, mods: Generals.Mods)
	local ids = {}
	for _, o in list do
		ids[o.id] = true
	end
	local st = Abilities.state(sim)
	st.effects[#st.effects + 1] = { id = ab.id, faction = hq.faction, untilTick = sim.tick + math.floor((ab.duration or 0) / DT), ids = ids, mods = mods }
end

local function boost(o: Formation, n: number)
	o.morale = math.min(100, o.morale + n)
end

-- Applies the HQ's ability (command kind "Ability"). Returns ok, reason.
function Abilities.use(sim: SimLike, hq: Formation, data: any): (boolean, string?)
	local ok, reason = Abilities.check(sim, hq, data)
	if not ok then
		if reason == "noTarget" or reason == "cooldown" then
			sim.emit(sim, { kind = "message", tick = sim.tick, id = hq.id, faction = hq.faction, text = if reason == "cooldown" then "The general's ability is recharging" else "No formation within reach of the general" })
		end
		return false, reason
	end
	local g = Abilities.generalOf(sim, hq.id) :: General
	local ab = g.ability
	local list = Abilities.targets(sim, hq, ab)
	local k = ab.kind
	if k == "vive" then
		for _, o in list do
			boost(o, 20)
			if rallyable(o) then
				Morale.rally(sim, o, " to the Emperor")
			end
		end
	elseif k == "inspire" then
		for _, o in list do
			boost(o, 10)
		end
	elseif k == "holdline" then
		addEffect(sim, hq, ab, list, { noRout = true })
	elseif k == "charge" then
		addEffect(sim, hq, ab, list, { chargeImpact = 1.3 })
	elseif k == "vorwaerts" then
		for _, o in list do
			boost(o, 10)
		end
		addEffect(sim, hq, ab, list, { speed = 1.2, recovery = 0.3 })
	elseif k == "withdraw" then
		for _, o in list do
			Morale.rally(sim, o, ", withdrawing in order")
			local home = sim.homeEdge(sim, o.faction)
			local dir = Vec.normalize(Vec.sub(home, o.pos))
			local w, d = sim.grid.width, sim.grid.depth
			o.order = { kind = "Retreat", pos = Vec.clamp(Vec.add(o.pos, Vec.scale(dir, 200)), 8, 8, w - 8, d - 8), issuedTick = sim.tick }
			o.queue = {}
		end
	elseif k == "example" then
		for _, o in list do
			if rallyable(o) then
				o.morale = math.max(o.morale, 45)
				Morale.rally(sim, o, ": the Archduke leads them back")
			else
				boost(o, 20)
			end
		end
	elseif k == "upguards" then
		for _, o in list do
			o.reload = 0
			o.fireAtWill = true
		end
		addEffect(sim, hq, ab, list, { accuracy = 1.5 })
	end
	Abilities.state(sim).readyTick[hq.id] = sim.tick + math.floor(ab.cooldown / DT)
	local text = string.format("%s: %s (%d formation%s)", Generals.displayName(g, hq.name), ab.name, #list, if #list == 1 then "" else "s")
	-- No id or position: both sides hear the cheer, nobody learns where the general stands.
	sim.emit(sim, { kind = "ability", tick = sim.tick, faction = hq.faction, text = text, n = #list })
	sim.log(sim, text)
	return true, nil
end

-- Snapshot fields for an own formation: the HQ's general and ability readiness, every formation's
-- active trait / ability ids.
function Abilities.view(sim: SimLike, f: Formation, v: any)
	if f.class == "hq" then
		local g = Abilities.generalOf(sim, f.id)
		if g then
			v.general = g.id
			v.abilityReadyAt = math.max(0, (Abilities.state(sim).readyTick[f.id] or 0) * DT)
		end
	end
	if #f.mods.tags > 0 then
		v.tags = table.concat(f.mods.tags, ",")
	end
end

return Abilities
