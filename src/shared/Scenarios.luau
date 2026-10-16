--!strict
-- Orders of battle. Condensed and partly representative: regiment names are drawn from
-- formations present at Jena-Auerstedt (14 Oct 1806) where known, strengths are balance
-- choices (docs/rules.md), not returns. Positions are initial deployment inside the zones.

local Vec = require(script.Parent.Vec)

type Vec = Vec.Vec

export type UnitDef = {
	name: string,
	class: "infantry" | "cavalry" | "artillery" | "hq",
	corps: string,
	strength: number,
	experience: number,
	pos: Vec,
	heading: number,
	faction: string,
	colour: string?, -- palette key override (Saxony)
	commander: boolean?, -- is the army HQ
	key: string?, -- campaign identity of this unit (nil for standalone battles)
}

export type Scenario = {
	id: string,
	name: string,
	map: string,
	briefing: string,
	factions: { player: string, enemy: string },
	factionNames: { [string]: string },
	units: { UnitDef },
	timeLimit: number?,
}

local NORTH = math.pi / 2
local SOUTH = -math.pi / 2

local function u(faction: string, corps: string, class: "infantry" | "cavalry" | "artillery" | "hq", name: string, strength: number, exp: number, x: number, z: number, heading: number, extra: { colour: string?, commander: boolean? }?): UnitDef
	local def: UnitDef = {
		name = name,
		class = class,
		corps = corps,
		strength = strength,
		experience = exp,
		pos = { x = x, z = z },
		heading = heading,
		faction = faction,
	}
	if extra then
		def.colour = extra.colour
		def.commander = extra.commander
	end
	return def
end

local Scenarios = {}

local JENA_FRENCH = {
	u("france", "HQ", "hq", "Napoléon — Imperial HQ", 40, 3, 800, 200, NORTH, { commander = true }),
	-- V Corps (Lannes) — centre
	u("france", "V Corps · Lannes", "infantry", "17e Légère", 600, 2, 700, 320, NORTH),
	u("france", "V Corps · Lannes", "infantry", "34e de Ligne", 600, 1, 780, 320, NORTH),
	u("france", "V Corps · Lannes", "infantry", "40e de Ligne", 600, 1, 860, 320, NORTH),
	u("france", "V Corps · Lannes", "artillery", "Batterie 5e Corps", 120, 1, 780, 270, NORTH),
	-- VII Corps (Augereau) — left
	u("france", "VII Corps · Augereau", "infantry", "7e Légère", 600, 1, 500, 300, NORTH),
	u("france", "VII Corps · Augereau", "infantry", "44e de Ligne", 600, 0, 580, 300, NORTH),
	-- VI Corps (Ney) — reserve centre
	u("france", "VI Corps · Ney", "infantry", "6e Légère", 600, 1, 740, 240, NORTH),
	u("france", "VI Corps · Ney", "infantry", "39e de Ligne", 600, 1, 820, 240, NORTH),
	u("france", "VI Corps · Ney", "artillery", "Batterie 6e Corps", 120, 1, 900, 270, NORTH),
	-- IV Corps (Soult) — right
	u("france", "IV Corps · Soult", "infantry", "26e Légère", 600, 1, 1000, 300, NORTH),
	u("france", "IV Corps · Soult", "infantry", "36e de Ligne", 600, 0, 1080, 300, NORTH),
	-- Imperial Guard
	u("france", "Garde Impériale", "infantry", "Grenadiers à pied de la Garde", 700, 3, 800, 150, NORTH),
	u("france", "Garde Impériale", "artillery", "Artillerie de la Garde", 120, 2, 720, 170, NORTH),
	-- Cavalry reserve (Murat)
	u("france", "Réserve de cavalerie · Murat", "cavalry", "1er Cuirassiers", 400, 2, 1150, 230, NORTH),
	u("france", "Réserve de cavalerie · Murat", "cavalry", "5e Hussards", 400, 1, 450, 220, NORTH),
	u("france", "Réserve de cavalerie · Murat", "cavalry", "9e Chasseurs à cheval", 400, 1, 950, 200, NORTH),
}

local JENA_PRUSSIAN = {
	u("prussia", "HQ", "hq", "Hohenlohe — Army HQ", 40, 2, 760, 860, SOUTH, { commander = true }),
	-- Tauentzien's advance guard — forward, Closewitz/Cospeda
	u("prussia", "Avantgarde · Tauentzien", "infantry", "Füsilier-Bataillon Pelet", 600, 1, 980, 580, SOUTH),
	u("prussia", "Avantgarde · Tauentzien", "infantry", "IR Nr. 20 Prinz Louis Ferdinand", 600, 1, 1060, 600, SOUTH),
	u("prussia", "Avantgarde · Tauentzien", "infantry", "IR Nr. 38 Pelchrzim", 600, 1, 900, 620, SOUTH),
	u("prussia", "Avantgarde · Tauentzien", "artillery", "Batterie Tauentzien", 120, 1, 980, 640, SOUTH),
	-- Grawert's division — main line at Vierzehnheiligen
	u("prussia", "Division Grawert", "infantry", "IR Nr. 29 Treuenfels", 600, 2, 640, 720, SOUTH),
	u("prussia", "Division Grawert", "infantry", "IR Nr. 49 Müffling", 600, 1, 720, 700, SOUTH),
	u("prussia", "Division Grawert", "infantry", "Grenadier-Bataillon Hahn", 600, 2, 820, 700, SOUTH),
	u("prussia", "Division Grawert", "artillery", "Batterie Grawert", 120, 1, 740, 790, SOUTH),
	-- Saxon contingent (Zezschwitz) — left, Isserstedt
	u("prussia", "Sächsisches Korps · Zezschwitz", "infantry", "IR Prinz Clemens (Sachsen)", 600, 1, 420, 700, SOUTH, { colour = "Saxony" }),
	u("prussia", "Sächsisches Korps · Zezschwitz", "infantry", "IR Rechten (Sachsen)", 600, 0, 500, 720, SOUTH, { colour = "Saxony" }),
	-- Holtzendorff — right, Dornberg
	u("prussia", "Detachement Holtzendorff", "infantry", "IR Nr. 51 Kauffberg", 600, 1, 1180, 760, SOUTH),
	-- Cavalry
	u("prussia", "Kavallerie · Prinz Wilhelm", "cavalry", "Kürassier-Regiment Henckel", 400, 2, 600, 820, SOUTH),
	u("prussia", "Kavallerie · Prinz Wilhelm", "cavalry", "Dragoner-Regiment Prinz Johann (Sachsen)", 400, 1, 1000, 820, SOUTH, { colour = "Saxony" }),
	u("prussia", "Kavallerie · Prinz Wilhelm", "cavalry", "Husaren-Regiment Gettkandt", 400, 1, 380, 800, SOUTH),
}

Scenarios.jena = {
	id = "jena",
	name = "Jena, 14 October 1806",
	map = "jena",
	briefing = "Dawn, 14 October 1806. Your corps crossed the Saale in the night and stand on the Landgrafenberg above Jena. Hohenlohe's Prussians and Saxons hold the villages to the north. Take Vierzehnheiligen, Closewitz and the Dornberg, or break the Prussian army. You have twenty-five minutes before the fog lifts and Hohenlohe is reinforced.",
	factions = { player = "france", enemy = "prussia" },
	factionNames = { france = "France", prussia = "Prussia" },
	units = {},
	timeLimit = nil,
} :: Scenario

for _, d in JENA_FRENCH do
	table.insert(Scenarios.jena.units, d)
end
for _, d in JENA_PRUSSIAN do
	table.insert(Scenarios.jena.units, d)
end

-- Stress fixture: 24 formations per side, generated from the Jena roster. Profiling only.
local function stress(): Scenario
	local units: { UnitDef } = {}
	local function add(src: { UnitDef }, faction: string, zBase: number, heading: number)
		local i = 0
		local x = 300
		local z = zBase
		while i < 24 do
			local base = src[(i % #src) + 1]
			if base.class ~= "hq" then
				i += 1
				units[#units + 1] = u(faction, base.corps, base.class, base.name .. " (" .. i .. ")", base.strength, base.experience, x, z, heading)
				x += 90
				if x > 1300 then
					x = 300
					z += (faction == "france" and 70 or -70)
				end
			else
				i += 1
				units[#units + 1] = u(faction, "HQ", "hq", base.name, 40, 2, 800, zBase + (faction == "france" and -80 or 80), heading, { commander = true })
			end
		end
	end
	add(JENA_FRENCH, "france", 300, NORTH)
	add(JENA_PRUSSIAN, "prussia", 760, SOUTH)
	return {
		id = "stress",
		name = "Stress fixture (24 v 24)",
		map = "jena",
		briefing = "Profiling fixture. Not a historical scenario.",
		factions = { player = "france", enemy = "prussia" },
		factionNames = { france = "France", prussia = "Prussia" },
		units = units,
		timeLimit = nil,
	}
end
Scenarios.stress = stress()

-- Tiny fixture for tests and Gate 2: 3 v 3.
Scenarios.skirmish = {
	id = "skirmish",
	name = "Skirmish (test fixture)",
	map = "jena",
	briefing = "Three formations a side. Test fixture.",
	factions = { player = "france", enemy = "prussia" },
	factionNames = { france = "France", prussia = "Prussia" },
	units = {
		u("france", "HQ", "hq", "French HQ", 40, 2, 800, 200, NORTH, { commander = true }),
		u("france", "V Corps", "infantry", "34e de Ligne", 600, 1, 760, 320, NORTH),
		u("france", "V Corps", "cavalry", "5e Hussards", 400, 1, 900, 300, NORTH),
		u("prussia", "HQ", "hq", "Prussian HQ", 40, 2, 760, 860, SOUTH, { commander = true }),
		u("prussia", "Grawert", "infantry", "IR Nr. 49 Müffling", 600, 1, 740, 700, SOUTH),
		u("prussia", "Grawert", "artillery", "Batterie Grawert", 120, 1, 820, 740, SOUTH),
	},
	timeLimit = nil,
} :: Scenario

function Scenarios.get(id: string): Scenario?
	local s = (Scenarios :: any)[id]
	if type(s) == "table" and s.units then
		return s
	end
	return nil
end

return Scenarios
