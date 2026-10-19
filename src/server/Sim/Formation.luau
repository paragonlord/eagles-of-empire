--!strict
-- Formation records: creation from scenario definitions, footprint geometry, shape changes,
-- legality helpers. Pure Luau; no Roblox APIs.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local Scenarios = require(Shared.Scenarios)
local Types = require(Shared.Types)

type Vec = Vec.Vec
type UnitDef = Scenarios.UnitDef

-- Per-tick modifiers from generals' traits and abilities (set by Sim/Abilities, neutral otherwise).
export type Mods = {
	speed: number,
	chargeImpact: number,
	chargeRecovery: number,
	accuracy: number,
	melee: number,
	cover: number, -- added to the terrain cover of incoming fire
	recovery: number, -- extra morale per second
	shockFloor: number, -- casualty shock cannot push morale below this
	hideBeyond: number?, -- enemies cannot spot it from further away
	noRout: boolean, -- morale stops at the rout threshold (unless below 30 % strength)
	steadyRetreat: boolean, -- Retreat costs no cohesion
	tags: { string }, -- trait / ability ids applied this tick (shown to the owner)
}

export type Formation = {
	id: number,
	faction: string,
	name: string,
	corps: string,
	class: Types.UnitClass,
	type: string, -- Config.UnitTypes id
	fireByRank: boolean, -- drilled: reloads faster halted in line (Config.Combat.FireByRankReload)
	garrison: string?, -- the strongpoint it holds (Sim/Garrison)
	kills: number, -- enemy casualties it has inflicted this battle (experience, results)
	colour: string?,
	commander: boolean,
	startStrength: number,
	strength: number,
	experience: number,
	pos: Vec,
	heading: number,
	shape: Types.Shape,
	prevShape: Types.Shape?, -- shape to restore after a forced travel column
	state: Types.State,
	morale: number,
	baseMorale: number,
	aiMoraleBonus: number, -- difficulty bonus currently in baseMorale (AI.steady)
	fatigue: number,
	ammo: number,
	ammoMode: string, -- artillery: auto | roundShot | canister
	reload: number,
	order: Types.Order?,
	queue: { Types.Order },
	path: { Vec }?,
	pathIndex: number,
	targetId: number?,
	timers: {
		reform: number,
		limber: number,
		chargeRecover: number,
		rallyCd: number,
		routing: number,
		routStill: number, -- seconds a routing formation has made no progress
		rallying: number,
		bayonet: number,
		noDamage: number,
		friendRout: number,
		isolation: number,
		stuck: number,
		halt: number,
		meleeSeconds: number,
	},
	fireAtWill: boolean,
	cohesion: number,
	lastShotTick: number,
	meleeWith: { [number]: boolean },
	routCount: number,
	shattered: boolean,
	runUp: number, -- distance at charge speed this charge
	chargeReady: boolean, -- impact not yet applied for the current charge
	hitSide: string?, -- strongest one-shot attack side suffered this tick (volley/cannon/charge)
	meleeSide: string?, -- strongest melee attack side this tick (sustained)
	status: string?,
	lastProgressDist: number,
	moraleBand: Types.MoraleBand,
	width: number,
	depth: number,
	halfRadius: number,
	destroyedTick: number?,
	pendingShape: Types.Shape?,
	pendingLimber: boolean?,
	casualtiesThisTick: number,
	visibleTo: { [string]: boolean },
	inWoods: boolean,
	arrivalTick: number?, -- reinforcements: tick at which the formation enters the field
	routCheckPos: Vec?, -- where a routing formation was last seen making progress
	mods: Mods,
}

local Formation = {}

-- The unit's stats: its type's table (Config.TypeStats), its class merged with the type's overrides.
function Formation.unitConfig(f: Formation)
	return Config.TypeStats[f.type]
end

-- On horseback: cavalry and the generals' escorts ride, charge and suffer as horsemen do.
function Formation.mounted(f: Formation): boolean
	return Formation.unitConfig(f).mounted == true
end

function Formation.figures(f: Formation): number
	if f.class == "artillery" then
		return math.max(1, math.ceil(f.strength / Config.Visual.CrewPerGun))
	end
	return math.max(1, math.ceil(f.strength / Config.Visual.SoldiersPerFigure))
end

-- Width (frontage) and depth of the footprint for the current shape.
function Formation.footprint(f: Formation): (number, number)
	local shapeCfg = (Config.Shapes :: any)[f.shape]
	local figures = Formation.figures(f)
	local spacing = shapeCfg.figureSpacing
	local rankSpacing = shapeCfg.rankSpacing
	if f.shape == "square" then
		local side = math.max(2, math.ceil(math.sqrt(figures)))
		return side * spacing, side * rankSpacing
	elseif f.shape == "garrison" then
		return 16, 16 -- the building
	end
	local ranks = math.max(1, shapeCfg.ranks)
	local files = math.max(1, math.ceil(figures / ranks))
	return files * spacing, ranks * rankSpacing
end

function Formation.refreshFootprint(f: Formation)
	local w, d = Formation.footprint(f)
	f.width = w
	f.depth = d
	f.halfRadius = math.max(w, d) / 2
end

function Formation.neutralMods(): Mods
	return { speed = 1, chargeImpact = 1, chargeRecovery = 1, accuracy = 1, melee = 1, cover = 0, recovery = 0, shockFloor = 0, hideBeyond = nil, noRout = false, steadyRetreat = false, tags = {} }
end

function Formation.fromDef(id: number, def: UnitDef): Formation
	local unitType = Scenarios.typeOf(def)
	local unit = Config.TypeStats[unitType]
	local baseMorale = unit.baseMorale + Config.Combat.ExperienceMorale * def.experience
	local f: Formation = {
		id = id,
		faction = def.faction,
		name = def.name,
		corps = def.corps,
		class = def.class,
		type = unitType,
		fireByRank = Scenarios.firesByRank(def),
		kills = 0,
		colour = def.colour,
		commander = def.commander == true,
		startStrength = def.strength,
		strength = def.strength,
		experience = def.experience,
		pos = { x = def.pos.x, z = def.pos.z },
		heading = def.heading,
		shape = unit.defaultShape,
		prevShape = nil,
		state = "idle",
		morale = baseMorale,
		baseMorale = baseMorale,
		aiMoraleBonus = 0,
		fatigue = 0,
		ammo = if def.class == "artillery" then unit.gun.ammo elseif unit.musket then unit.musket.ammo else 0,
		ammoMode = "auto",
		reload = 0,
		order = nil,
		queue = {},
		path = nil,
		pathIndex = 1,
		targetId = nil,
		timers = {
			reform = 0,
			limber = 0,
			chargeRecover = 0,
			rallyCd = 0,
			routing = 0,
			routStill = 0,
			rallying = 0,
			bayonet = 0,
			noDamage = 999,
			friendRout = 0,
			isolation = 0,
			stuck = 0,
			halt = 0,
			meleeSeconds = 0,
		},
		fireAtWill = true,
		cohesion = 1,
		lastShotTick = -1000,
		meleeWith = {},
		routCount = 0,
		shattered = false,
		runUp = 0,
		chargeReady = false,
		hitSide = nil,
		meleeSide = nil,
		status = nil,
		lastProgressDist = math.huge,
		moraleBand = "steady",
		width = 0,
		depth = 0,
		halfRadius = 0,
		destroyedTick = nil,
		pendingShape = nil,
		pendingLimber = nil,
		casualtiesThisTick = 0,
		visibleTo = {},
		inWoods = false,
		arrivalTick = nil,
		routCheckPos = nil,
		mods = Formation.neutralMods(),
	}
	-- Off-map reinforcements: `arrival = { seconds, pos }` on the unit definition.
	local arrival = (def :: any).arrival
	if type(arrival) == "table" and type(arrival.seconds) == "number" and arrival.seconds > 0 then
		f.state = "offmap"
		f.arrivalTick = math.floor(arrival.seconds / Config.Sim.DT)
		if type(arrival.pos) == "table" then
			f.pos = { x = arrival.pos.x, z = arrival.pos.z }
		end
	end
	Formation.refreshFootprint(f)
	return f
end

function Formation.isActive(f: Formation): boolean
	return f.state ~= "destroyed" and f.state ~= "exited" and f.state ~= "offmap"
end

function Formation.isBroken(f: Formation): boolean
	return f.state == "routing" or f.state == "rallying" or f.shattered or not Formation.isActive(f)
end

function Formation.canTakeOrders(f: Formation): (boolean, string?)
	if f.state == "offmap" then
		return false, "badState"
	end
	if not Formation.isActive(f) then
		return false, "destroyed"
	end
	if f.state == "routing" or f.state == "rallying" then
		return false, "routing"
	end
	return true, nil
end

function Formation.legalShapes(f: Formation): { [string]: boolean }
	return Formation.unitConfig(f).legalShapes
end

-- Begin a shape change; completes when timers.reform reaches 0 (Movement handles the timer).
function Formation.beginShape(f: Formation, shape: Types.Shape, forced: boolean?)
	if f.shape == shape and f.pendingShape == nil then
		return
	end
	local t = (Config.ReformTime :: any)[shape] or 8
	if shape == "square" and f.shape == "column" then
		t = Config.SquareFromColumnTime
	end
	t *= Formation.unitConfig(f).reformScale or 1
	if forced and f.shape ~= "travel" then
		f.prevShape = f.shape
	end
	f.pendingShape = shape
	f.timers.reform = t
	f.state = "reforming"
	f.cohesion = math.min(f.cohesion, 0.6)
end

function Formation.completeShape(f: Formation)
	if f.pendingShape then
		f.shape = f.pendingShape
		f.pendingShape = nil
		Formation.refreshFootprint(f)
	end
	if f.state == "reforming" then
		-- An order received during the reform still needs executing: Movement replans.
		f.state = if f.path or (f.order and (f.order.pos or f.order.targetId)) then "moving" else "idle"
	end
end

function Formation.isLimbered(f: Formation): boolean
	return f.class == "artillery" and f.shape == "limbered"
end

function Formation.speedBase(f: Formation, charging: boolean): number
	local unit = Formation.unitConfig(f)
	return if charging then unit.chargeSpeed else unit.speed
end

function Formation.fatigueFactor(f: Formation, penalty: number): number
	return 1 - penalty * f.fatigue / 100
end

function Formation.clearOrder(f: Formation)
	f.order = nil
	f.queue = {}
	f.path = nil
	f.pathIndex = 1
	f.targetId = nil
	f.chargeReady = false
	f.runUp = 0
	if f.state == "moving" or f.state == "charging" or f.state == "retreating" then
		f.state = "idle"
	end
end

function Formation.moraleBandOf(f: Formation): Types.MoraleBand
	if f.shattered then
		return "shattered"
	end
	if f.state == "routing" or f.state == "rallying" then
		return "routing"
	end
	return f.moraleBand
end

-- Corners of the footprint rectangle (for client ghosts and contact tests).
function Formation.frontCentre(f: Formation): Vec
	local fwd = Vec.fromHeading(f.heading)
	return Vec.add(f.pos, Vec.scale(fwd, f.depth / 2))
end

return Formation
