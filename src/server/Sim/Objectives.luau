--!strict
-- Objective capture (step 9) and the single victory evaluator (step 10).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local Types = require(Shared.Types)
local MapGen = require(Shared.MapGen)

local Formation = require(script.Parent.Formation)

type Formation = Formation.Formation

export type ObjectiveState = {
	def: MapGen.Objective,
	owner: string?,
	capturing: string?,
	progress: number, -- 0..1
	contested: boolean,
	heldSince: number?, -- tick when current owner took it
}

export type SimLike = {
	tick: number,
	formations: { [number]: Formation },
	order: { number },
	factions: { string },
	objectives: { ObjectiveState },
	emit: (sim: any, ev: Types.Event) -> (),
	log: (sim: any, text: string) -> (),
	playerFaction: string,
	enemyFaction: string,
	deployed: { [string]: number },
	timeLimit: number,
	clock: number,
}

local Objectives = {}

local DT = Config.Sim.DT
local O = Config.Objectives

function Objectives.init(defs: { MapGen.Objective }): { ObjectiveState }
	local out = {}
	for _, d in defs do
		out[#out + 1] = { def = d, owner = nil, capturing = nil, progress = 0, contested = false, heldSince = nil }
	end
	return out
end

local function eligible(f: Formation): boolean
	if not O.EligibleClasses[f.class] then
		return false
	end
	if not Formation.isActive(f) or f.state == "routing" or f.state == "rallying" or f.shattered then
		return false
	end
	if f.state == "reforming" and f.pendingShape == "square" then
		return false
	end
	return true
end

function Objectives.update(sim: SimLike)
	for _, obj in sim.objectives do
		local present: { [string]: number } = {}
		local r2 = obj.def.radius * obj.def.radius
		for _, id in sim.order do
			local f = sim.formations[id]
			if f and eligible(f) and Vec.dist2(f.pos, obj.def.pos) <= r2 then
				present[f.faction] = (present[f.faction] or 0) + 1
			end
		end
		local factionsPresent = 0
		local only: string? = nil
		for faction in present do
			factionsPresent += 1
			only = faction
		end
		obj.contested = factionsPresent > 1
		if factionsPresent == 1 and only and only ~= obj.owner then
			if obj.capturing ~= only then
				obj.capturing = only
				obj.progress = 0
			end
			obj.progress = math.min(1, obj.progress + DT / O.CaptureSeconds)
			if obj.progress >= 1 then
				local prev = obj.owner
				obj.owner = only
				obj.heldSince = sim.tick
				obj.capturing = nil
				obj.progress = 0
				sim.emit(sim, { kind = "capture", tick = sim.tick, faction = only, x = obj.def.pos.x, z = obj.def.pos.z, text = obj.def.name .. " taken" })
				sim.log(sim, string.format("%s captured %s%s", only, obj.def.name, if prev then " from " .. prev else ""))
			end
		elseif factionsPresent == 0 then
			-- Progress decays when nobody is present.
			if obj.capturing then
				obj.progress = math.max(0, obj.progress - DT / O.CaptureSeconds)
				if obj.progress == 0 then
					obj.capturing = nil
				end
			end
		end
		-- contested: progress frozen (no change)
	end
end

function Objectives.view(sim: SimLike): { Types.ObjectiveView }
	local out = {}
	for _, obj in sim.objectives do
		out[#out + 1] = {
			id = obj.def.id,
			name = obj.def.name,
			x = obj.def.pos.x,
			z = obj.def.pos.z,
			radius = obj.def.radius,
			owner = obj.owner,
			contested = obj.contested,
			progress = obj.progress,
			capturing = obj.capturing,
		}
	end
	return out
end

local function sideStats(sim: SimLike, faction: string)
	local total, broken, strength = 0, 0, 0
	for _, id in sim.order do
		local f = sim.formations[id]
		if f and f.faction == faction then
			total += 1
			if f.state == "routing" or f.state == "rallying" or f.shattered or not Formation.isActive(f) then
				broken += 1
			end
			if Formation.isActive(f) then
				strength += f.strength
			end
		end
	end
	return total, broken, strength
end

function Objectives.collapsed(sim: SimLike, faction: string): boolean
	local total, broken, strength = sideStats(sim, faction)
	if total == 0 then
		return true
	end
	if broken / total >= Config.Victory.CollapseFraction then
		return true
	end
	local deployed = sim.deployed[faction] or 1
	return strength < deployed * Config.Victory.CollapseStrengthFraction
end

function Objectives.heldAll(sim: SimLike, faction: string): boolean
	if #sim.objectives == 0 then
		return false
	end
	for _, obj in sim.objectives do
		if obj.owner ~= faction or not obj.heldSince or (sim.tick - obj.heldSince) * DT < O.HoldAllSeconds then
			return false
		end
	end
	return true
end

function Objectives.countOwned(sim: SimLike, faction: string): number
	local n = 0
	for _, obj in sim.objectives do
		if obj.owner == faction then
			n += 1
		end
	end
	return n
end

-- Returns winner faction (or "draw") and reason, or nil while the battle continues.
-- Precedence: player collapse, enemy collapse, objectives held, timeout.
function Objectives.evaluate(sim: SimLike): (string?, string?)
	local player, enemy = sim.playerFaction, sim.enemyFaction
	if Objectives.collapsed(sim, player) then
		return enemy, "Your army has collapsed"
	end
	if Objectives.collapsed(sim, enemy) then
		return player, "The enemy army has collapsed"
	end
	if Objectives.heldAll(sim, player) then
		return player, "All objectives held"
	end
	if Objectives.heldAll(sim, enemy) then
		return enemy, "The enemy holds every objective"
	end
	if sim.clock >= sim.timeLimit then
		local p, e = Objectives.countOwned(sim, player), Objectives.countOwned(sim, enemy)
		if p > e then
			return player, "Time expired holding more objectives"
		elseif e > p then
			return enemy, "Time expired; the enemy holds more objectives"
		end
		return "draw", "Time expired with the field divided"
	end
	return nil, nil
end

return Objectives
