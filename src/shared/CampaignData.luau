--!strict
-- Authored campaign map: Thuringia / Saxony, October 1806 (inspired by the Jena campaign; names
-- are real towns, borders and numbers are balance choices). Region `pos` is on a 0..1000 client
-- map (x east, z south). `terrain` names the tactical map variant used when a battle happens there.

export type Region = {
	id: string,
	name: string,
	pos: { x: number, z: number },
	adjacent: { string },
	terrain: string, -- "jena" | "bridge" | "village" (MapGen.list())
	owner: string,
	income: number, -- treasury per turn
	manpower: number, -- manpower per turn
	isCity: boolean,
}

export type UnitType = {
	name: string,
	class: "infantry" | "cavalry" | "artillery" | "hq",
	strength: number,
	cost: number,
	turns: number,
	upkeep: number,
	recruitable: boolean,
}

export type StartUnit = { type: string, name: string, experience: number }
export type StartArmy = { faction: string, name: string, regionId: string, units: { StartUnit } }

local CampaignData = {}

CampaignData.Factions = { player = "france", enemy = "prussia" }
CampaignData.FactionNames = { france = "France", prussia = "Prussia" } :: { [string]: string }
CampaignData.Capitals = { france = "rudolstadt", prussia = "weimar" } :: { [string]: string }

local function r(id: string, name: string, x: number, z: number, adjacent: { string }, terrain: string, owner: string, isCity: boolean): Region
	return {
		id = id,
		name = name,
		pos = { x = x, z = z },
		adjacent = adjacent,
		terrain = terrain,
		owner = owner,
		income = if isCity then 120 else 80,
		manpower = if isCity then 80 else 40,
		isCity = isCity,
	}
end

-- North (Prussia) at low z, south (France) at high z. Adjacency is a road graph and must be symmetric.
CampaignData.Regions = {
	r("erfurt", "Erfurt", 150, 250, { "weimar" }, "village", "prussia", true),
	r("weimar", "Weimar", 350, 230, { "erfurt", "apolda", "jena" }, "village", "prussia", true),
	r("apolda", "Apolda", 480, 150, { "weimar", "naumburg", "jena" }, "village", "prussia", false),
	r("naumburg", "Naumburg", 700, 80, { "apolda", "gera" }, "bridge", "prussia", true),
	r("jena", "Jena", 500, 420, { "weimar", "apolda", "kahla", "gera" }, "jena", "prussia", true),
	r("gera", "Gera", 850, 450, { "naumburg", "jena", "kahla" }, "bridge", "france", true),
	r("kahla", "Kahla", 470, 620, { "jena", "gera", "rudolstadt" }, "bridge", "france", false),
	r("rudolstadt", "Rudolstadt", 300, 800, { "kahla" }, "village", "france", false),
} :: { Region }

CampaignData.UnitTypes = {
	line = { name = "Line infantry", class = "infantry", strength = 600, cost = 400, turns = 2, upkeep = 30, recruitable = true },
	light = { name = "Light infantry", class = "infantry", strength = 600, cost = 450, turns = 2, upkeep = 30, recruitable = true },
	cavalry = { name = "Cavalry", class = "cavalry", strength = 400, cost = 500, turns = 3, upkeep = 40, recruitable = true },
	artillery = { name = "Foot artillery", class = "artillery", strength = 120, cost = 450, turns = 3, upkeep = 35, recruitable = true },
	hq = { name = "Headquarters", class = "hq", strength = 40, cost = 0, turns = 0, upkeep = 20, recruitable = false },
} :: { [string]: UnitType }

CampaignData.Economy = {
	StartTreasury = { france = 800, prussia = 700 } :: { [string]: number },
	StartManpower = { france = 600, prussia = 600 } :: { [string]: number },
	MaxManpower = 2000,
	MaxTreasury = 20000,
	ReplenishCostPerMan = 0.5, -- treasury per man restored (plus one manpower per man)
	SupplyRecovery = 20, -- supply gained per fully paid turn (0..100)
	SupplyShortage = 25, -- supply lost per turn upkeep cannot be paid
	AttritionFraction = 0.05, -- strength lost per turn while supply is 0
	MaxQueue = 6, -- recruitment orders per faction
	MaxArmies = 10,
	MaxUnitsPerArmy = 12,
	AIReserve = 200, -- treasury the AI keeps before recruiting
}

CampaignData.Victory = {
	TurnLimit = 20,
	Objectives = { "jena", "weimar", "naumburg" },
	MinArmyStrength = 1500, -- total French strength required at the moment the objectives are held
}

local function su(t: string, name: string, exp: number): StartUnit
	return { type = t, name = name, experience = exp }
end

CampaignData.StartArmies = {
	{
		faction = "france", name = "Armée · Lannes", regionId = "kahla",
		units = {
			su("hq", "Napoléon — Imperial HQ", 3),
			su("light", "17e Légère", 2),
			su("line", "34e de Ligne", 1),
			su("line", "40e de Ligne", 1),
			su("cavalry", "5e Hussards", 1),
			su("artillery", "Batterie 5e Corps", 1),
		},
	},
	{
		faction = "france", name = "Corps · Soult", regionId = "gera",
		units = { su("line", "26e Légère", 1), su("line", "36e de Ligne", 0), su("cavalry", "1er Cuirassiers", 2) },
	},
	{
		faction = "prussia", name = "Armee · Hohenlohe", regionId = "jena",
		units = {
			su("hq", "Hohenlohe — Army HQ", 2),
			su("line", "IR Nr. 29 Treuenfels", 2),
			su("line", "IR Nr. 49 Müffling", 1),
			su("light", "Füsilier-Bataillon Pelet", 1),
			su("cavalry", "Kürassier-Regiment Henckel", 2),
			su("artillery", "Batterie Grawert", 1),
		},
	},
	{
		faction = "prussia", name = "Korps · Rüchel", regionId = "weimar",
		units = { su("line", "IR Nr. 20 Prinz Louis Ferdinand", 1), su("line", "IR Nr. 51 Kauffberg", 1), su("cavalry", "Husaren-Regiment Gettkandt", 1) },
	},
} :: { StartArmy }

function CampaignData.region(id: string): Region?
	for _, reg in CampaignData.Regions do
		if reg.id == id then
			return reg
		end
	end
	return nil
end

return CampaignData
