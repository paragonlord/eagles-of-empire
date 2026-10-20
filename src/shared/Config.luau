--!strict
-- Single source of every live balance / timing / visual constant.
-- docs/rules.md explains the formulas that consume these numbers. Change values here only.

local Config = {}

Config.Sim = {
	DT = 0.05, -- logical seconds per tick (20 Hz)
	TickRate = 20,
	MaxTicksPerFrame = 6, -- beyond this the sim lags instead of taking a giant step
	SnapshotEveryTicks = 2, -- 10 Hz
	VisibilityEveryTicks = 4,
	Speeds = { 1, 2, 4 },
	CommandDelayTicks = 1, -- accepted commands take effect next tick
}

Config.Map = {
	Width = 1600,
	Depth = 1200,
	CellSize = 4,
	NavCellSize = 16,
	MaxHeight = 80,
}

-- Terrain classes. speed multiplies base unit speed; cover reduces incoming fire;
-- sightHeight is added to terrain height for LOS when the cell is between observer and target.
Config.TerrainIds = { open = 1, road = 2, woods = 3, village = 4, water = 5, bridge = 6, steep = 7, cliff = 8, ford = 9 }
Config.Terrain = {
	[1] = { name = "open", speed = 1.0, cavalrySpeed = 1.0, passable = true, cover = 0.0, blocksSight = false, sightHeight = 0, fatigue = 1.0, cohesion = 0.0 },
	[2] = { name = "road", speed = 1.3, cavalrySpeed = 1.3, passable = true, cover = 0.0, blocksSight = false, sightHeight = 0, fatigue = 0.8, cohesion = 0.0 },
	[3] = { name = "woods", speed = 0.6, cavalrySpeed = 0.4, passable = true, cover = 0.35, blocksSight = true, sightHeight = 12, fatigue = 1.4, cohesion = 0.08 },
	[4] = { name = "village", speed = 0.7, cavalrySpeed = 0.5, passable = true, cover = 0.5, blocksSight = true, sightHeight = 10, fatigue = 1.1, cohesion = 0.05 },
	[5] = { name = "water", speed = 0.0, cavalrySpeed = 0.0, passable = false, cover = 0.0, blocksSight = false, sightHeight = 0, fatigue = 1.0, cohesion = 0.0 },
	[6] = { name = "bridge", speed = 0.9, cavalrySpeed = 0.8, passable = true, cover = 0.0, blocksSight = false, sightHeight = 0, fatigue = 1.0, cohesion = 0.0 },
	[7] = { name = "steep", speed = 0.5, cavalrySpeed = 0.45, passable = true, cover = 0.1, blocksSight = false, sightHeight = 0, fatigue = 1.8, cohesion = 0.06 },
	[8] = { name = "cliff", speed = 0.0, cavalrySpeed = 0.0, passable = false, cover = 0.0, blocksSight = false, sightHeight = 0, fatigue = 1.0, cohesion = 0.0 },
	-- shallow crossing of a brook: wading, no firing, melee ×0.7 (Combat)
	[9] = { name = "ford", speed = 0.45, cavalrySpeed = 0.55, passable = true, cover = 0.0, blocksSight = false, sightHeight = 0, fatigue = 1.6, cohesion = 0.08, noFire = true, melee = 0.7 },
}

Config.Slope = {
	Steep = 0.42, -- rise/run above which open ground becomes "steep"
	Impassable = 0.95, -- rise/run above which ground is a cliff
	UphillPenalty = 0.6, -- speed *= 1 - penalty * max(0, slopeAlongMotion)
	DownhillBonus = 0.15,
	UphillFireBonus = 0.1, -- firing from higher ground
	DownhillChargeBonus = 0.25, -- charge impact from higher ground
	DownhillMeleeBonus = 0.1, -- melee from higher ground
}

-- Visibility
Config.Vision = {
	EyeHeight = 4.0, -- mounted officers / colour party; sees over small bulges of a slope
	SightTolerance = 0.5, -- studs the terrain may rise above the sight line before it blocks
	WoodsReveal = 90, -- a formation inside woods/village is only spotted within this distance
	ContactReveal = 15, -- footprints this close (beyond touching) always see each other
	LastKnownForgetSeconds = 180,
}

Config.Visual = {
	SoldiersPerFigure = 25,
	CrewPerGun = 20,
	-- camera distance beyond which ranks become blocks, by quality (Low, Medium, High): the default
	-- view (~565 away) shows men at every setting; the figure budget thins ranks past it
	FarLodDistance = { 600, 700, 850 },
	MaxFiguresHigh = 1200,
	MaxFiguresLow = 400,
	-- RGB 0-255 triples (plain tables so the sim/tests never need Roblox datatypes);
	-- the client converts with Color3.fromRGB.
	Palette = {
		TerrainGrass = { 154, 138, 78 },
		TerrainSlope = { 122, 92, 58 },
		TerrainWoodsFloor = { 62, 78, 42 },
		Water = { 90, 95, 168 },
		Bank = { 196, 180, 140 },
		Road = { 140, 122, 92 },
		Roof = { 138, 74, 50 },
		Wall = { 190, 170, 140 },
		TreeCrown = { 70, 96, 48 },
		TreeTrunk = { 78, 58, 40 },
		Cream = { 237, 228, 204 },
		Ink = { 42, 36, 32 },
		France = { 44, 79, 166 },
		Prussia = { 58, 61, 66 },
		Saxony = { 108, 113, 128 },
		Russia = { 40, 72, 52 }, -- dark green coat
		Austria = { 214, 208, 190 }, -- off-white
		Britain = { 160, 52, 44 }, -- brick red
		Bavaria = { 96, 128, 200 }, -- cornflower
		Netherlands = { 150, 112, 80 }, -- orange-tinged slate
		Select = { 240, 226, 180 },
		Hostile = { 170, 60, 48 },
		Spain = { 196, 150, 40 },
		Portugal = { 40, 110, 70 },
		Italy = { 60, 120, 70 },
		Naples = { 150, 160, 180 },
		Wurttemberg = { 170, 50, 50 },
		Sweden = { 50, 90, 160 },
		Denmark = { 180, 40, 50 },
		Ottoman = { 120, 30, 40 },
	},
}

-- Formation shapes. ranks: files are derived from figure count / ranks. figureSpacing = studs between
-- files (frontage per figure), rankSpacing = studs between ranks.
-- fire: fraction of strength that can fire. shock: multiplier on cavalry charge impact received.
-- artillery: multiplier on artillery casualties received. speed: multiplier on base speed.
Config.Shapes = {
	line = { ranks = 3, fire = 1.0, melee = 1.0, speed = 0.75, shock = 1.0, artillery = 1.0, turnRate = 0.45, figureSpacing = 5, rankSpacing = 3 },
	column = { ranks = 8, fire = 0.3, melee = 1.15, speed = 1.0, shock = 1.3, artillery = 1.9, turnRate = 0.9, figureSpacing = 4, rankSpacing = 3 },
	square = { ranks = 0, fire = 0.5, melee = 0.9, speed = 0.3, shock = 0.15, artillery = 2.2, turnRate = 1.2, figureSpacing = 4, rankSpacing = 4 },
	travel = { ranks = 12, fire = 0.0, melee = 0.6, speed = 1.0, shock = 1.8, artillery = 2.0, turnRate = 1.0, figureSpacing = 4, rankSpacing = 3 }, -- forced column at choke points
	limbered = { ranks = 1, fire = 0.0, melee = 0.3, speed = 1.0, shock = 3.0, artillery = 1.5, turnRate = 0.8, figureSpacing = 8, rankSpacing = 10 },
	deployed = { ranks = 1, fire = 1.0, melee = 0.3, speed = 0.0, shock = 3.0, artillery = 1.0, turnRate = 0.0, figureSpacing = 8, rankSpacing = 8 },
	wedge = { ranks = 4, fire = 0.0, melee = 1.0, speed = 1.0, shock = 1.0, artillery = 1.6, turnRate = 1.1, figureSpacing = 5, rankSpacing = 6 },
	staff = { ranks = 2, fire = 0.0, melee = 1.0, speed = 1.0, shock = 1.5, artillery = 1.5, turnRate = 1.5, figureSpacing = 4, rankSpacing = 4 },
	-- open order (light infantry and rifles): fires on the move and all round, hard to hit, prey to cavalry
	skirmish = { ranks = 2, fire = 0.5, melee = 0.5, speed = 1.0, shock = 2.0, artillery = 0.35, turnRate = 1.2, figureSpacing = 7, rankSpacing = 6 },
	-- inside a building (Sim/Garrison): fires from the windows all round, cannot be charged by horse
	garrison = { ranks = 1, fire = 0.45, melee = 1.4, speed = 0.0, shock = 0.0, artillery = 0.5, turnRate = 0.0, figureSpacing = 4, rankSpacing = 4 },
}

-- Seconds to change shape (from any shape to the key). Square from column is faster.
Config.ReformTime = { line = 12, column = 8, square = 15, travel = 6, limbered = 25, deployed = 20, wedge = 4, staff = 2, skirmish = 6, garrison = 8 }
Config.SquareFromColumnTime = 10

Config.Units = {
	infantry = {
		speed = 5.5, chargeSpeed = 7.5,
		defaultShape = "line", legalShapes = { line = true, column = true, square = true, travel = true },
		musket = { range = 90, reload = 15, accuracy = 0.07, minReadiness = 0.4, ammo = 60 },
		melee = { attack = 1.0, defense = 1.0 },
		baseMorale = 70, fatigueMove = 0.35, fatigueCharge = 6.0, fatigueMelee = 2.0, rest = 1.5,
		spot = 260,
	},
	cavalry = {
		mounted = true,
		speed = 14.0, chargeSpeed = 20.0,
		defaultShape = "wedge", legalShapes = { wedge = true, line = true },
		musket = nil,
		melee = { attack = 1.4, defense = 0.8 },
		charge = { runUp = 80, base = 0.06, recovery = 40, maxMeleeSeconds = 25, frontFactor = 1.0, flankFactor = 1.8, rearFactor = 2.5 },
		baseMorale = 72, fatigueMove = 0.5, fatigueCharge = 7.0, fatigueMelee = 2.5, rest = 1.5,
		spot = 320,
	},
	artillery = {
		speed = 4.5, chargeSpeed = 4.5,
		defaultShape = "limbered", legalShapes = { limbered = true, deployed = true },
		musket = nil,
		melee = { attack = 0.2, defense = 0.4 },
		gun = {
			arcHalfAngle = 0.52, -- radians (30°)
			roundShot = { range = 450, minRange = 60, reload = 20, hit = 0.5, casualtiesPerHit = 3, morale = 3 },
			canister = { range = 120, minRange = 0, reload = 18, hit = 0.9, casualtiesPerHit = 7, morale = 5 },
			ammo = 40,
		},
		baseMorale = 60, fatigueMove = 0.3, fatigueCharge = 0.3, fatigueMelee = 2.0, rest = 1.5,
		spot = 240,
	},
	hq = {
		-- the general and his escort: a squadron of heavy horse (120 sabres) that can charge
		mounted = true,
		speed = 12.0, chargeSpeed = 18.0,
		defaultShape = "staff", legalShapes = { staff = true },
		musket = nil,
		melee = { attack = 1.2, defense = 0.9 },
		charge = { runUp = 60, base = 0.04, recovery = 40, maxMeleeSeconds = 20, frontFactor = 1.0, flankFactor = 1.8, rearFactor = 2.5 },
		influence = { radius = 120, moraleBonus = 10, recoveryBonus = 0.3 },
		rally = { cooldown = 90, radius = 100, moraleRestore = 30, minRoutingSeconds = 5 },
		lossMoralePenalty = 15, -- when an HQ is destroyed/exited: the army's to everyone, a corps general's
		lossRadius = 300, -- to the formations within this of a fallen corps general
		baseMorale = 80, fatigueMove = 0.3, fatigueCharge = 0.3, fatigueMelee = 2.0, rest = 2.0,
		spot = 300,
	},
}

-- Unit types (docs/rules.md "Unit types"). Each names its class and overrides that class's stats
-- above; Config.TypeStats[type] is the merged table every rule reads (Formation.unitConfig).
-- reformScale multiplies reform/limber times; pursuit multiplies a charge's impact on routing units.
Config.UnitTypes = {
	line = { class = "infantry", name = "Line infantry" },
	light = { class = "infantry", name = "Light infantry", stats = { legalShapes = { skirmish = true }, speed = 6.2, chargeSpeed = 8.2, musket = { accuracy = 0.075 }, melee = { attack = 0.95, defense = 0.95 }, spot = 300 } },
	rifle = { class = "infantry", name = "Rifles", stats = { legalShapes = { skirmish = true }, speed = 6.0, chargeSpeed = 8.0, baseMorale = 70, musket = { range = 130, reload = 21, accuracy = 0.11, ammo = 50 }, melee = { attack = 0.8, defense = 0.85 }, spot = 320 } },
	grenadier = { class = "infantry", name = "Grenadiers", stats = { baseMorale = 72, melee = { attack = 1.1, defense = 1.05 } } },
	guard = { class = "infantry", name = "Guard infantry", stats = { baseMorale = 76, melee = { attack = 1.15, defense = 1.1 } } },
	militia = { class = "infantry", name = "Militia", stats = { baseMorale = 58, musket = { accuracy = 0.055 }, melee = { attack = 0.85, defense = 0.9 } } },
	lightCav = { class = "cavalry", name = "Light cavalry", stats = { speed = 16.0, chargeSpeed = 22.0, baseMorale = 70, melee = { attack = 1.2, defense = 0.75 }, pursuit = 1.4, charge = { base = 0.05 }, fatigueMove = 0.4, spot = 380 } },
	lancer = { class = "cavalry", name = "Lancers", stats = { speed = 15.0, chargeSpeed = 21.0, baseMorale = 70, melee = { attack = 1.2, defense = 0.75 }, pursuit = 1.4, charge = { base = 0.065 }, fatigueMove = 0.45, spot = 340 } },
	dragoon = { class = "cavalry", name = "Dragoons" },
	heavyCav = { class = "cavalry", name = "Heavy cavalry", stats = { speed = 13.0, chargeSpeed = 19.0, baseMorale = 74, melee = { attack = 1.35, defense = 1.0 }, charge = { base = 0.065 }, fatigueMove = 0.6 } },
	footArt = { class = "artillery", name = "Foot artillery" },
	horseArt = { class = "artillery", name = "Horse artillery", stats = { speed = 7.5, reformScale = 0.5, gun = { roundShot = { range = 380, casualtiesPerHit = 2.5 } } } },
	-- indirect fire: a target the side can see, no line of sight needed, lobbed over friends; shells
	-- burst over `splash` studs (Combat cannonade)
	howitzer = { class = "artillery", name = "Howitzers", stats = { gun = { indirect = true, roundShot = { range = 400, minRange = 80, reload = 26, hit = 0.4, casualtiesPerHit = 3.5, morale = 6, splash = 30 } } } },
	hq = { class = "hq", name = "Headquarters" },
}

local function merged(base: any, over: any): any
	local out = {}
	for k, v in base do
		out[k] = if type(v) == "table" then merged(v, {}) else v
	end
	for k, v in over do
		out[k] = if type(v) == "table" and type(out[k]) == "table" then merged(out[k], v) else v
	end
	return out
end

Config.TypeStats = {} :: { [string]: any }
for id, t in Config.UnitTypes :: { [string]: any } do
	Config.TypeStats[id] = merged((Config.Units :: any)[t.class], t.stats or {})
end

-- Running (Move/AttackMove with run, or the Run order): infantry, cavalry and staff only.
Config.Run = { speed = 1.4, fatigue = 3.0 }

Config.Combat = {
	RangeFalloff = 0.65, -- hit factor at max range = 1 - falloff
	MaxHitChance = 0.30,
	TargetShapeFactor = { line = 1.0, column = 1.5, square = 1.3, travel = 1.6, limbered = 1.2, deployed = 1.0, wedge = 1.2, staff = 1.0, skirmish = 0.45, garrison = 0.4 },
	FlankFireFactor = 1.35,
	RearFireFactor = 1.6,
	FriendlyBlocksFire = true, -- a friendly formation inside the fire lane blocks the volley
	FireLaneHalfWidth = 10,
	FireByRankReload = 0.75, -- reload multiplier for drilled infantry halted in line
	-- round shot carries on past its target: formations of either side whose footprint touches the
	-- next `length` studs of the line of fire take `factor` of the first strike, fading to half at the end
	Ricochet = { length = 140, factor = 0.45, maxHits = 2 },
	-- a field hedge / stone wall the musket shot has to cross, within 6 studs of the target's centre
	BorderCover = { [1] = 0.25, [2] = 0.4 },
	MeleeRatePerSecond = 0.0025, -- casualties = attackerStrength * rate * factors * dt
	MeleeDirFactor = { front = 1.0, flank = 1.6, rear = 2.2 },
	MeleeContactDistance = 6, -- studs between footprints
	BayonetBonus = 1.3,
	BayonetBonusSeconds = 10,
	BayonetMoraleShock = { front = 10, flank = 20 },
	ChargeShapeFactor = { line = 1.0, column = 1.3, square = 0.15, travel = 1.8, limbered = 3.0, deployed = 3.0, wedge = 1.0, staff = 2.0, skirmish = 2.0, garrison = 0.0 },
	ChargeRoutingFactor = 1.5,
	SquareReturnsDamage = 2.0, -- cavalry in melee with a square takes x2
	MinRunUpFactor = 0.3,
	ExperienceAccuracy = 0.08, -- per experience level
	ExperienceMelee = 0.08,
	ExperienceMorale = 4,
	ExperienceKills = 150, -- enemy casualties a formation inflicts per experience level gained in battle (max 3)
	FatigueSpeedPenalty = 0.4,
	FatigueAccuracyPenalty = 0.3,
	FatigueMeleePenalty = 0.4,
	VolleyMinStrength = 10,
	ShakenFireFactor = 0.7,
	ShakenMeleeFactor = 0.8,
}

Config.Morale = {
	CasualtyFactor = 1.0, -- morale -= (casualties/strength) * 100 * factor
	FlankHitPenalty = 6, -- once per flank volley / cannonade / charge received
	RearHitPenalty = 12,
	FlankMeleePerSecond = 1.5,
	RearMeleePerSecond = 3,
	FriendRoutPenalty = 2, FriendRoutRadius = 80, FriendRoutMax = 6, FriendRoutInterval = 5,
	IsolationRadius = 150, IsolationPenalty = 1, IsolationInterval = 5,
	FatigueThreshold = 70, FatiguePenaltyPerSecond = 0.2,
	RecoveryPerSecond = 0.5, RecoveryDelay = 10, -- seconds without taking damage
	ShakenEnter = 40, ShakenExit = 50,
	RoutEnter = 20, RallyMorale = 35, MinRoutSeconds = 20,
	RallyNoEnemyRadius = 120,
	ShatterStrengthFraction = 0.3, MaxRouts = 2,
	RoutSpeedFactor = 1.3,
	RoutExitMargin = 20, -- studs outside map edge => exited
	CapturedGunsMorale = 5, -- penalty to the army when an artillery formation is destroyed
}

Config.Objectives = {
	CaptureRadius = 60,
	CaptureSeconds = 30,
	HoldAllSeconds = 120,
	HoldAllEarliest = 600, -- holding every objective only wins after this many seconds (gives the attacker a chance)
	EligibleClasses = { infantry = true, cavalry = true },
}

-- Weather / ground state per scenario (`scenario.weather`, optional `scenario.weatherUntil` seconds
-- after which it clears). Multipliers on musket accuracy, artillery hit chance, movement speed and
-- spotting distance.
Config.Weather = {
	clear = { accuracy = 1.0, cannon = 1.0, speed = 1.0, spot = 1.0, label = "Clear" },
	rain = { accuracy = 0.6, cannon = 0.85, speed = 0.9, spot = 0.8, label = "Rain" },
	mud = { accuracy = 0.9, cannon = 0.7, speed = 0.8, spot = 1.0, label = "Sodden ground" },
	fog = { accuracy = 0.9, cannon = 0.8, speed = 1.0, spot = 0.45, label = "Fog" },
	snow = { accuracy = 0.85, cannon = 0.9, speed = 0.8, spot = 0.7, label = "Snow" },
}

Config.Victory = {
	CollapseFraction = 0.7, -- fraction of formations routing/shattered/destroyed/exited
	CollapseStrengthFraction = 0.35,
	TimeLimitSeconds = 25 * 60,
}

Config.Match = {
	ReconnectGrace = 120,
	DeploymentMinSpacing = 8,
	MaxQueue = 4,
	LeashDistance = 160, -- engage/attack-move chase limit
	StuckSeconds = 4,
}

Config.AI = {
	DecisionTicks = 10,
	CommitSeconds = 20,
	Difficulties = {
		easy = { reaction = 2.0, planQuality = 0.6, moraleBonus = 0 },
		normal = { reaction = 1.0, planQuality = 1.0, moraleBonus = 0 },
		hard = { reaction = 0.6, planQuality = 1.0, moraleBonus = 5 }, -- disclosed in settings
	},
}

Config.Net = {
	RequestsPerSecond = 30,
	MaxBatch = 24,
	MaxQueueDepth = 4,
	DedupeWindow = 4096,
}

return Config
