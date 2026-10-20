--!strict
-- Orders of battle. Condensed and partly representative: regiment names are drawn from
-- formations present at each battle where known (docs/battles.md says which names are attested
-- and which are representative), strengths are balance choices (docs/rules.md), not returns.
-- Positions are initial deployment inside the zones; `arrival` units start off the map.

local Vec = require(script.Parent.Vec)
local Moments = require(script.Parent.Moments)
local Config = require(script.Parent.Config)

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
	colour: string?, -- palette key override (Saxony, Austria, Netherlands, Prussia under britain...)
	commander: boolean?, -- is the army HQ
	key: string?, -- campaign identity of this unit (nil for standalone battles)
	arrival: { seconds: number, pos: Vec }?, -- off-map reinforcement: enters at pos at that sim time
	general: string?, -- HQ only: id in src/shared/Generals.luau (else matched from the name)
	type: string?, -- Config.UnitTypes id (else inferred from the name: Scenarios.typeOf)
	fireByRank: boolean?, -- the drill (else: guard infantry and British foot have it)
	quickSquare: boolean?, -- forms square a third faster (campaign tech: Squares from column)
	canisterBonus: number?, -- canister casualties multiplier (campaign tech: Improved canister)
	moraleBonus: number?, -- added to base morale (campaign tech: Nationalism)
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
	date: string?, -- display date, e.g. "14 October 1806"
	year: number?,
	summary: string?, -- what happened historically and the result
	difficultyNote: string?, -- e.g. "Hard: you are outnumbered 2:1"
	weather: string?, -- key into Config.Weather; nil = clear
	weatherUntil: number?, -- sim seconds after which the weather clears
	moments: { Moments.Moment }?, -- historical moments (src/shared/Moments.luau)
	mode: ("full" | "episode")?, -- listed battles: the whole field, or a quick-battle slice of it
	parent: string?, -- episodes: id of the full battle they are cut from
	buildings: boolean?, -- false: no garrisonable buildings (the tutorial teaches the basics first)
	attacker: string?, -- the side that came to take the field (the AI defender holds); nil = a meeting battle
	historicalWinner: string?, -- listed battles: the faction that carried the day in history (results)
}

-- mode: "full" | "episode"; parent: the full battle's id for episodes (nil for full battles).
export type ListEntry = { id: string, name: string, date: string?, map: string, factionNames: { [string]: string }, summary: string?, difficultyNote: string?, mode: string, parent: string?, timeLimit: number? }

local NORTH = math.pi / 2
local SOUTH = -math.pi / 2
local EAST = 0
local WEST = math.pi

type Extra = { colour: string?, commander: boolean?, arrival: { seconds: number, pos: Vec }?, general: string? }

local function u(faction: string, corps: string, class: "infantry" | "cavalry" | "artillery" | "hq", name: string, strength: number, exp: number, x: number, z: number, heading: number, extra: Extra?): UnitDef
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
		def.arrival = extra.arrival
		def.general = extra.general
	end
	return def
end

local Scenarios = {}

local JENA_FRENCH = {
	u("france", "HQ", "hq", "Napoléon — Imperial HQ", 120, 3, 800, 200, NORTH, { commander = true, general = "napoleon" }),
	u("france", "V Corps · Lannes", "hq", "Lannes — V Corps HQ", 120, 3, 780, 280, NORTH, { general = "lannes" }),
	u("france", "IV Corps · Soult", "hq", "Soult — IV Corps HQ", 120, 3, 1040, 260, NORTH, { general = "soult" }),
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
	u("prussia", "HQ", "hq", "Hohenlohe — Army HQ", 120, 2, 760, 860, SOUTH, { commander = true, general = "hohenlohe" }),
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
	historicalWinner = "france",
	attacker = "france",
	name = "Jena, 14 October 1806",
	map = "jena",
	briefing = "Dawn, 14 October 1806. Your corps crossed the Saale in the night and stand on the Landgrafenberg above Jena in thick morning mist, which will lift within five minutes. Hohenlohe's Prussians and Saxons hold the villages to the north. Take Vierzehnheiligen, Closewitz and the Dornberg, or break the Prussian army. You have twenty-five minutes before Hohenlohe is reinforced.",
	factions = { player = "france", enemy = "prussia" },
	factionNames = { france = "France", prussia = "Prussia" },
	units = {},
	timeLimit = nil,
	date = "14 October 1806",
	year = 1806,
	summary = "Napoleon's corps debouched from the Landgrafenberg through the fog and, after Ney's premature rush on Vierzehnheiligen was rescued, rolled Hohenlohe's line back through the villages. Rüchel's late counter-attack was shattered and Murat's cavalry turned the retreat into a rout; the same morning Davout beat the Prussian main army at Auerstedt, and within weeks Prussia had lost its fortresses and its army.",
	difficultyNote = "Even: the opening battle. Equal numbers, the French hold the high ground.",
	weather = "fog",
	weatherUntil = 300,
	mode = "full",
	moments = {
		{
			id = "jena_fog",
			title = "The fog lifts",
			text = "The mist tears open over the Landgrafenberg. Hohenlohe sees at last how many French stand on the plateau above Jena.",
			when = { weatherCleared = true },
			camera = { x = 800, z = 330 },
			effect = { morale = { { faction = "france", amount = 6 } } },
		},
		{
			id = "jena_ney",
			title = "Ney goes in alone",
			text = "Marshal Ney has flung his advance guard at Vierzehnheiligen without orders and is out on his own. The Emperor sends Lannes to his aid.",
			when = { before = 600, formationNear = { faction = "france", corps = "VI Corps", objective = "vierzehnheiligen", radius = 150 } },
			camera = { x = 760, z = 700 },
			effect = { morale = { { faction = "france", corps = "VI Corps", amount = -6 } } },
			faction = "france",
		},
		{
			id = "jena_vierzehnheiligen",
			title = "Vierzehnheiligen is taken",
			text = "Vierzehnheiligen burns, and it is French. Grawert's battalions stand in the open before it, volleying by numbers as on parade, and are shot to pieces.",
			when = { objectiveTaken = { id = "vierzehnheiligen", by = "france" } },
			camera = { x = 760, z = 760 },
			effect = { morale = { { faction = "prussia", amount = -8 } } },
		},
	},
} :: Scenario

for _, d in JENA_FRENCH do
	table.insert(Scenarios.jena.units, d)
end
for _, d in JENA_PRUSSIAN do
	table.insert(Scenarios.jena.units, d)
end

-- ---------------------------------------------------------------------------------------------
-- Auerstedt, 14 October 1806. Davout's III Corps (player) faces the Prussian main army.
-- French face west; Prussians arrive from the west over the Lissbach. Morand's division is still
-- on the road from Kösen and enters as reinforcements.
-- ---------------------------------------------------------------------------------------------
local AUERSTEDT_FRENCH = {
	u("france", "HQ", "hq", "Davout — III Corps HQ", 120, 3, 1300, 640, WEST, { commander = true, general = "davout" }),
	-- Gudin's division — Hassenhausen
	u("france", "Division Gudin", "infantry", "25e de Ligne", 600, 2, 1080, 640, WEST),
	u("france", "Division Gudin", "infantry", "85e de Ligne", 600, 2, 1080, 760, WEST),
	u("france", "Division Gudin", "infantry", "21e de Ligne", 600, 2, 1180, 600, WEST),
	u("france", "Division Gudin", "infantry", "12e de Ligne", 600, 2, 1180, 800, WEST),
	u("france", "Division Gudin", "artillery", "Batterie Gudin", 120, 2, 1230, 700, WEST),
	-- Friant's division — right, toward Spielberg
	u("france", "Division Friant", "infantry", "33e de Ligne", 600, 2, 1250, 920, WEST),
	u("france", "Division Friant", "infantry", "48e de Ligne", 600, 2, 1350, 940, WEST),
	u("france", "Division Friant", "infantry", "108e de Ligne", 600, 2, 1300, 860, WEST),
	u("france", "Division Friant", "infantry", "111e de Ligne", 600, 2, 1450, 900, WEST),
	-- Corps artillery and Vialannes' light cavalry
	u("france", "III Corps", "artillery", "Batterie du 3e Corps", 120, 2, 1400, 700, WEST),
	u("france", "Cavalerie · Vialannes", "cavalry", "1er Chasseurs à cheval", 400, 2, 1500, 560, WEST),
	u("france", "Cavalerie · Vialannes", "cavalry", "12e Chasseurs à cheval", 400, 2, 1500, 800, WEST),
	-- Morand's division — marching up from the Kösen bridge
	u("france", "Division Morand", "infantry", "13e Légère", 600, 2, 1560, 400, WEST, { arrival = { seconds = 150, pos = { x = 1560, z = 400 } } }),
	u("france", "Division Morand", "infantry", "17e de Ligne", 600, 2, 1620, 440, WEST, { arrival = { seconds = 180, pos = { x = 1620, z = 440 } } }),
	u("france", "Division Morand", "infantry", "30e de Ligne", 600, 2, 1540, 470, WEST, { arrival = { seconds = 210, pos = { x = 1540, z = 470 } } }),
	u("france", "Division Morand", "infantry", "61e de Ligne", 600, 2, 1600, 500, WEST, { arrival = { seconds = 240, pos = { x = 1600, z = 500 } } }),
	u("france", "Division Morand", "artillery", "Batterie Morand", 120, 2, 1660, 480, WEST, { arrival = { seconds = 270, pos = { x = 1660, z = 480 } } }),
}

local AUERSTEDT_PRUSSIAN = {
	u("prussia", "HQ", "hq", "Brunswick — Army HQ", 120, 2, 300, 800, EAST, { commander = true, general = "brunswick" }),
	u("prussia", "Kavallerie · Blücher", "hq", "Blücher — Cavalry HQ", 120, 2, 420, 1180, EAST, { general = "blucher" }),
	-- Schmettau's division — first onto the field, centre
	u("prussia", "Division Schmettau", "infantry", "IR Nr. 21 Herzog von Braunschweig", 600, 1, 560, 760, EAST),
	u("prussia", "Division Schmettau", "infantry", "IR Nr. 30 Borcke", 600, 1, 560, 660, EAST),
	u("prussia", "Division Schmettau", "infantry", "IR Nr. 22 Pirch", 600, 1, 520, 860, EAST),
	u("prussia", "Division Schmettau", "infantry", "Grenadier-Bataillon Hanstein", 600, 2, 480, 700, EAST),
	u("prussia", "Division Schmettau", "artillery", "Batterie Schmettau", 120, 1, 430, 760, EAST),
	-- Wartensleben's division — left, over the Sonnenkuppe, a few minutes behind Schmettau
	u("prussia", "Division Wartensleben", "infantry", "IR Nr. 23 Winning", 600, 1, 540, 500, EAST, { arrival = { seconds = 180, pos = { x = 200, z = 500 } } }),
	u("prussia", "Division Wartensleben", "infantry", "IR Nr. 55 Manstein", 600, 1, 540, 400, EAST, { arrival = { seconds = 200, pos = { x = 200, z = 400 } } }),
	u("prussia", "Division Wartensleben", "infantry", "Grenadier-Bataillon Rheinbaben", 600, 2, 460, 450, EAST, { arrival = { seconds = 220, pos = { x = 200, z = 450 } } }),
	u("prussia", "Division Wartensleben", "artillery", "Batterie Wartensleben", 120, 1, 400, 500, EAST, { arrival = { seconds = 240, pos = { x = 200, z = 500 } } }),
	u("prussia", "Division Wartensleben", "cavalry", "Dragoner-Regiment Königin Nr. 5", 400, 1, 560, 350, EAST, { arrival = { seconds = 200, pos = { x = 200, z = 350 } } }),
	-- Orange's division — right, toward Poppel, the last up the road
	u("prussia", "Division Oranien", "infantry", "IR Nr. 19 Prinz von Oranien", 600, 1, 380, 1000, EAST, { arrival = { seconds = 330, pos = { x = 150, z = 1000 } } }),
	u("prussia", "Division Oranien", "infantry", "IR Nr. 25 Möllendorff", 600, 1, 380, 1100, EAST, { arrival = { seconds = 360, pos = { x = 150, z = 1100 } } }),
	u("prussia", "Division Oranien", "infantry", "Füsilier-Bataillon Oswald", 600, 1, 600, 1050, EAST, { arrival = { seconds = 390, pos = { x = 150, z = 1050 } } }),
	u("prussia", "Division Oranien", "artillery", "Batterie Oranien", 120, 1, 300, 1050, EAST, { arrival = { seconds = 420, pos = { x = 150, z = 1050 } } }),
	-- Kalckreuth's reserve — held back behind the Eckartsberg; historically never committed
	u("prussia", "Reserve · Kalckreuth", "infantry", "IR Nr. 15 Garde", 600, 2, 200, 850, EAST, { arrival = { seconds = 1200, pos = { x = 150, z = 850 } } }),
	u("prussia", "Reserve · Kalckreuth", "infantry", "Grenadier-Garde Nr. 6", 600, 2, 200, 750, EAST, { arrival = { seconds = 1230, pos = { x = 150, z = 750 } } }),
	-- Blücher's cavalry — the northern flank
	u("prussia", "Kavallerie · Blücher", "cavalry", "Garde du Corps Nr. 13", 400, 2, 480, 1200, EAST),
	u("prussia", "Kavallerie · Blücher", "cavalry", "Gensd'armes Kürassier Nr. 10", 400, 1, 420, 1250, EAST),
	u("prussia", "Kavallerie · Blücher", "cavalry", "Husaren-Regiment Blücher Nr. 8", 400, 1, 560, 1150, EAST),
	u("prussia", "Kavallerie · Blücher", "cavalry", "Leib-Kürassier-Regiment Nr. 3", 400, 1, 350, 1200, EAST),
	u("prussia", "Kavallerie · Blücher", "artillery", "Reitende Batterie Blücher", 120, 1, 300, 1150, EAST),
}

Scenarios.auerstedt = {
	id = "auerstedt",
	historicalWinner = "france",
	attacker = "prussia",
	name = "Auerstedt, 14 October 1806",
	map = "auerstedt",
	briefing = "Morning, 14 October 1806. Marshal Davout's III Corps has crossed the Saale at Kösen and holds Hassenhausen in the fog, which will clear within four minutes; the Prussian main army under the Duke of Brunswick is coming up the road from Auerstedt, twice your strength but strung out over the Lissbach. Gudin and Friant are on the field; Morand's division is still marching up from the Kösen bridge and will arrive in the first five minutes. Hold Hassenhausen, keep the Kösen bridge, and take Poppel when the Prussian columns falter. Break them before Brunswick can commit his reserve.",
	factions = { player = "france", enemy = "prussia" },
	factionNames = { france = "France", prussia = "Prussia" },
	units = {},
	timeLimit = 25 * 60,
	date = "14 October 1806",
	year = 1806,
	summary = "While Napoleon fought Hohenlohe at Jena, Davout's single corps of about 26,000 met the Prussian main army of around 50,000 at Auerstedt. The Prussians attacked piecemeal across the Lissbach; Gudin held Hassenhausen in squares against Blücher's cavalry, Friant and Morand extended the flanks, Brunswick and Schmettau were mortally wounded, and by early afternoon the Prussian army, its reserve never committed, was retreating west. It was the most celebrated corps action of the Napoleonic wars.",
	difficultyNote = "Hard: you are outnumbered 2:1, but your men are veterans and the enemy arrives in pieces.",
	weather = "fog",
	weatherUntil = 240,
	mode = "full",
	moments = {
		{
			id = "auerstedt_hassenhausen",
			title = "Davout holds Hassenhausen",
			text = "Hassenhausen is still French. Gudin's division has held the village against half the Prussian army, and the whole corps stands in line at last.",
			when = { time = 600, objectiveTaken = { id = "hassenhausen", by = "france", seconds = 300 } },
			camera = { x = 1150, z = 700 },
			effect = { morale = { { faction = "france", amount = 8 } } },
		},
		{
			id = "auerstedt_brunswick",
			title = "Brunswick is struck down",
			text = "The Duke of Brunswick is shot through the eyes while leading his grenadiers forward. He will not live, and the Prussian command falls into confusion.",
			when = {
				any = {
					{ strengthBelow = { faction = "prussia", name = "Brunswick", fraction = 0.95 } },
					{ strengthBelow = { faction = "prussia", fraction = 0.85 } },
					{ time = 480, formationNear = { faction = "prussia", class = "infantry", objective = "hassenhausen", radius = 250 } },
				},
			},
			effect = { morale = { { faction = "prussia", amount = -10 } } },
		},
	},
} :: Scenario
for _, d in AUERSTEDT_FRENCH do
	table.insert(Scenarios.auerstedt.units, d)
end
for _, d in AUERSTEDT_PRUSSIAN do
	table.insert(Scenarios.auerstedt.units, d)
end

-- ---------------------------------------------------------------------------------------------
-- Austerlitz, 2 December 1805. French (player) west of the Goldbach face the Russo-Austrian
-- army on the Pratzen. Friant's division enters from the south-west as reinforcements.
-- ---------------------------------------------------------------------------------------------
local AUSTERLITZ_FRENCH = {
	u("france", "HQ", "hq", "Napoléon — Imperial HQ (Zuran)", 120, 3, 450, 1250, EAST, { commander = true, general = "napoleon" }),
	u("france", "IV Corps · Soult", "hq", "Soult — IV Corps HQ", 120, 3, 470, 820, EAST, { general = "soult" }),
	u("france", "V Corps · Lannes", "hq", "Lannes — V Corps HQ", 120, 3, 400, 1400, EAST, { general = "lannes" }),
	-- IV Corps (Soult) — centre, the hammer against the Pratzen
	u("france", "IV Corps · Soult / Saint-Hilaire", "infantry", "10e Légère", 600, 2, 600, 1150, EAST),
	u("france", "IV Corps · Soult / Saint-Hilaire", "infantry", "14e de Ligne", 600, 2, 600, 1070, EAST),
	u("france", "IV Corps · Soult / Saint-Hilaire", "infantry", "36e de Ligne", 600, 1, 520, 1110, EAST),
	u("france", "IV Corps · Soult / Vandamme", "infantry", "24e Légère", 600, 2, 600, 950, EAST),
	u("france", "IV Corps · Soult / Vandamme", "infantry", "4e de Ligne", 600, 1, 600, 870, EAST),
	u("france", "IV Corps · Soult / Vandamme", "infantry", "28e de Ligne", 600, 1, 520, 910, EAST),
	u("france", "IV Corps · Soult / Vandamme", "infantry", "57e de Ligne", 600, 2, 600, 790, EAST),
	u("france", "IV Corps · Soult / Legrand", "infantry", "26e Légère", 600, 2, 620, 560, EAST),
	u("france", "IV Corps · Soult / Legrand", "infantry", "3e de Ligne", 600, 1, 600, 460, EAST),
	u("france", "IV Corps · Soult / Legrand", "infantry", "Tirailleurs du Pô", 600, 1, 560, 380, EAST),
	u("france", "IV Corps · Soult", "artillery", "Batterie 4e Corps", 120, 2, 480, 1000, EAST),
	-- V Corps (Lannes) — north, by the Santon
	u("france", "V Corps · Lannes", "infantry", "17e Légère", 600, 2, 560, 1480, EAST),
	u("france", "V Corps · Lannes", "infantry", "34e de Ligne", 600, 1, 480, 1420, EAST),
	u("france", "V Corps · Lannes", "infantry", "13e Légère", 600, 2, 560, 1380, EAST),
	u("france", "V Corps · Lannes", "artillery", "Batterie 5e Corps", 120, 1, 420, 1480, EAST),
	-- I Corps (Bernadotte) — behind the Zuran
	u("france", "I Corps · Bernadotte", "infantry", "8e de Ligne", 600, 1, 350, 1200, EAST),
	u("france", "I Corps · Bernadotte", "infantry", "27e Légère", 600, 1, 350, 1120, EAST),
	-- Imperial Guard — reserve
	u("france", "Garde Impériale", "infantry", "Grenadiers à pied de la Garde", 700, 3, 250, 1000, EAST),
	u("france", "Garde Impériale", "infantry", "Chasseurs à pied de la Garde", 700, 3, 250, 920, EAST),
	u("france", "Garde Impériale", "cavalry", "Grenadiers à cheval de la Garde", 400, 3, 180, 960, EAST),
	u("france", "Garde Impériale", "artillery", "Artillerie de la Garde", 120, 2, 300, 960, EAST),
	-- Cavalry reserve (Murat) — north-centre
	u("france", "Réserve de cavalerie · Murat", "cavalry", "1er Cuirassiers", 400, 2, 420, 1350, EAST),
	u("france", "Réserve de cavalerie · Murat", "cavalry", "2e Carabiniers", 400, 2, 350, 1320, EAST),
	u("france", "Réserve de cavalerie · Murat", "cavalry", "5e Hussards", 400, 1, 500, 1560, EAST),
	-- III Corps (Davout): Friant's division, force-marching from Raigern
	u("france", "III Corps · Davout / Friant", "infantry", "48e de Ligne", 600, 2, 120, 200, EAST, { arrival = { seconds = 120, pos = { x = 120, z = 200 } } }),
	u("france", "III Corps · Davout / Friant", "infantry", "108e de Ligne", 600, 2, 120, 260, EAST, { arrival = { seconds = 150, pos = { x = 120, z = 260 } } }),
	u("france", "III Corps · Davout / Friant", "infantry", "15e Légère", 600, 2, 180, 230, EAST, { arrival = { seconds = 180, pos = { x = 180, z = 230 } } }),
}

local AUSTERLITZ_ALLIED = {
	u("russia", "HQ", "hq", "Kutuzov — Allied HQ", 120, 2, 1500, 950, WEST, { commander = true, general = "kutuzov" }),
	u("russia", "Avantgarde · Bagration", "hq", "Bagration — Advance Guard HQ", 120, 2, 1260, 1530, WEST, { general = "bagration" }),
	u("russia", "1. Kolonne · Dokhturov", "hq", "Buxhöwden — Allied left HQ", 120, 2, 1340, 380, WEST, { general = "buxhowden" }),
	-- Kienmayer's Austrian advance guard — south, Telnitz
	u("russia", "Avantgarde · Kienmayer", "cavalry", "Husaren-Regiment Hessen-Homburg", 400, 1, 1100, 260, WEST, { colour = "Austria" }),
	u("russia", "Avantgarde · Kienmayer", "infantry", "Székler Grenz-Infanterie", 600, 1, 1150, 200, WEST, { colour = "Austria" }),
	u("russia", "Avantgarde · Kienmayer", "cavalry", "Chevaulegers-Regiment O'Reilly", 400, 1, 1100, 340, WEST, { colour = "Austria" }),
	-- 1st column (Dokhturov) — south-west, toward Telnitz
	u("russia", "1. Kolonne · Dokhturov", "infantry", "Novo-Ingermanland Musketeers", 600, 1, 1250, 420, WEST),
	u("russia", "1. Kolonne · Dokhturov", "infantry", "Yaroslavl Musketeers", 600, 1, 1250, 500, WEST),
	u("russia", "1. Kolonne · Dokhturov", "infantry", "Kiev Grenadiers", 600, 2, 1350, 460, WEST),
	u("russia", "1. Kolonne · Dokhturov", "artillery", "Battery, 1st Column", 120, 1, 1300, 380, WEST),
	-- 2nd column (Langeron) — toward Sokolnitz
	u("russia", "2. Kolonne · Langeron", "infantry", "Vyborg Musketeers", 600, 1, 1250, 620, WEST),
	u("russia", "2. Kolonne · Langeron", "infantry", "Perm Musketeers", 600, 1, 1250, 700, WEST),
	u("russia", "2. Kolonne · Langeron", "infantry", "Fanagoria Grenadiers", 600, 2, 1350, 660, WEST),
	u("russia", "2. Kolonne · Langeron", "artillery", "Battery, 2nd Column", 120, 1, 1400, 620, WEST),
	-- 3rd column (Przhebishevsky) — Sokolnitz castle
	u("russia", "3. Kolonne · Przhebishevsky", "infantry", "Galicia Musketeers", 600, 1, 1200, 800, WEST),
	u("russia", "3. Kolonne · Przhebishevsky", "infantry", "Narva Musketeers", 600, 1, 1230, 980, WEST),
	-- 4th column (Kolowrat / Miloradovich) — on the Pratzen
	u("russia", "4. Kolonne · Kolowrat", "infantry", "Novgorod Musketeers", 600, 1, 1400, 1000, WEST),
	u("russia", "4. Kolonne · Kolowrat", "infantry", "Apsheron Musketeers", 600, 1, 1400, 1080, WEST),
	u("russia", "4. Kolonne · Kolowrat", "infantry", "IR Nr. 23 Salzburg", 600, 1, 1500, 1040, WEST, { colour = "Austria" }),
	u("russia", "4. Kolonne · Kolowrat", "infantry", "IR Nr. 20 Kaunitz", 600, 1, 1500, 1120, WEST, { colour = "Austria" }),
	u("russia", "4. Kolonne · Kolowrat", "artillery", "Österreichische Batterie", 120, 1, 1600, 1080, WEST, { colour = "Austria" }),
	-- 5th column (Liechtenstein) — cavalry, north-centre
	u("russia", "5. Kolonne · Liechtenstein", "cavalry", "Uhlans Grand Duke Constantine", 400, 1, 1500, 1350, WEST),
	u("russia", "5. Kolonne · Liechtenstein", "cavalry", "Elisabethgrad Hussars", 400, 1, 1400, 1300, WEST),
	u("russia", "5. Kolonne · Liechtenstein", "cavalry", "Kürassier-Regiment Nassau", 400, 1, 1600, 1300, WEST, { colour = "Austria" }),
	-- Bagration's advance guard — north, the Olmütz road
	u("russia", "Avantgarde · Bagration", "cavalry", "Pavlograd Hussars", 400, 2, 1150, 1550, WEST),
	u("russia", "Avantgarde · Bagration", "infantry", "5th Jägers", 600, 1, 1100, 1450, WEST),
	u("russia", "Avantgarde · Bagration", "infantry", "Arkhangelgorod Musketeers", 600, 1, 1200, 1400, WEST),
	u("russia", "Avantgarde · Bagration", "artillery", "Battery Bagration", 120, 1, 1300, 1480, WEST),
	-- Russian Imperial Guard (Grand Duke Constantine) — reserve, north-east
	u("russia", "Garde · Grossfürst Konstantin", "infantry", "Preobrazhensky Guards", 700, 3, 1750, 1150, WEST),
	u("russia", "Garde · Grossfürst Konstantin", "infantry", "Semenovsky Guards", 700, 3, 1750, 1050, WEST),
	u("russia", "Garde · Grossfürst Konstantin", "cavalry", "Chevalier Guards", 400, 3, 1850, 1100, WEST),
	u("russia", "Garde · Grossfürst Konstantin", "artillery", "Guard Battery", 120, 2, 1700, 1200, WEST),
	-- Held back: enters only through the "The Russian Guard" moment (arrival is past the time limit).
	u("russia", "Garde · Grossfürst Konstantin", "cavalry", "Life Guard Horse Regiment", 400, 3, 1950, 1150, WEST, { arrival = { seconds = 3600, pos = { x = 1950, z = 1150 } } }),
}

Scenarios.austerlitz = {
	id = "austerlitz",
	historicalWinner = "france",
	name = "Austerlitz, 2 December 1805",
	map = "austerlitz",
	briefing = "Dawn, 2 December 1805. The Russo-Austrian army under Kutuzov has occupied the Pratzen Heights and is wheeling south to turn your right along the Goldbach; a thick fog hides the valley and will lift in about eight minutes with the sun. Soult's corps is massed below the Pratzen, Lannes holds the Santon, the Guard and Murat stand in reserve, and Friant's division is force-marching up from the south-west to reach the field in the first few minutes. Hold Sokolnitz and the Santon, then storm the Pratzen when the allied columns have drained off the plateau. Break the allied army on its own ground.",
	factions = { player = "france", enemy = "russia" },
	factionNames = { france = "France", russia = "Russia & Austria" },
	units = {},
	timeLimit = 30 * 60,
	date = "2 December 1805",
	year = 1805,
	summary = "Napoleon feigned weakness, abandoned the Pratzen and let the allies march their columns off the plateau into the Goldbach villages. As the fog lifted Soult's divisions climbed the heights, took them and held them against the Russian Guard, then turned south on the rear of the allied columns, which broke across the frozen ponds. The allies lost around 27,000 men to French losses of about 9,000; Austria made peace at Pressburg within the month.",
	difficultyNote = "Hard: outnumbered and fog-bound; the plateau is the battle.",
	weather = "fog",
	weatherUntil = 480,
	mode = "full",
	moments = {
		{
			id = "austerlitz_sun",
			title = "The Sun of Austerlitz",
			text = "The fog burns off and the sun rises over the Pratzen. The allied columns are marching down off the heights, just as the Emperor foretold.",
			when = { weatherCleared = true },
			camera = { x = 1450, z = 900 },
			effect = { morale = { { faction = "france", amount = 8 } } },
		},
		{
			id = "austerlitz_pratzen",
			title = "Soult on the Pratzen",
			text = "Saint-Hilaire and Vandamme have the plateau. 'Twenty minutes, Sire,' Soult had promised, and the allied centre is cut in two.",
			when = { objectiveTaken = { id = "pratzen", by = "france" } },
			camera = { x = 1450, z = 900 },
			effect = { morale = { { faction = "russia", corps = "4. Kolonne", amount = -10 }, { faction = "russia", corps = "3. Kolonne", amount = -6 } } },
		},
		{
			id = "austerlitz_guard",
			title = "The Russian Guard",
			text = "Grand Duke Constantine throws the Guard at the heights. The Life Guard Horse comes on at the gallop from Krzenowitz.",
			when = { time = 900, objectiveTaken = { id = "pratzen", by = "france", seconds = 120 } },
			camera = { x = 1750, z = 1150 },
			effect = { release = "Life Guard Horse Regiment" },
		},
	},
} :: Scenario
for _, d in AUSTERLITZ_FRENCH do
	table.insert(Scenarios.austerlitz.units, d)
end
for _, d in AUSTERLITZ_ALLIED do
	table.insert(Scenarios.austerlitz.units, d)
end

-- ---------------------------------------------------------------------------------------------
-- Waterloo, 18 June 1815. French (player) south of the Mont-Saint-Jean ridge; Wellington's
-- Anglo-allied army on it. Bülow's Prussians enter from the east from minute 12.
-- ---------------------------------------------------------------------------------------------
local WATERLOO_FRENCH = {
	u("france", "HQ", "hq", "Napoléon — Imperial HQ (Rossomme)", 120, 3, 1260, 240, NORTH, { commander = true, general = "napoleon" }),
	u("france", "I Corps · d'Erlon", "hq", "Ney — Wing HQ", 120, 3, 1150, 420, NORTH, { general = "ney" }),
	-- Grand Battery — the ridge of La Belle Alliance
	u("france", "Grande Batterie", "artillery", "Grande Batterie (12-livres)", 120, 2, 1050, 560, NORTH),
	u("france", "Grande Batterie", "artillery", "Grande Batterie (6-livres)", 120, 2, 1350, 560, NORTH),
	-- II Corps (Reille) — left, facing Hougoumont
	u("france", "II Corps · Reille / Jérôme", "infantry", "1er Légère", 600, 2, 700, 560, NORTH),
	u("france", "II Corps · Reille / Jérôme", "infantry", "1er de Ligne", 600, 1, 780, 520, NORTH),
	u("france", "II Corps · Reille / Foy", "infantry", "92e de Ligne", 600, 1, 880, 540, NORTH),
	u("france", "II Corps · Reille / Foy", "infantry", "100e de Ligne", 600, 1, 960, 500, NORTH),
	u("france", "II Corps · Reille / Bachelu", "infantry", "2e Légère", 600, 2, 1000, 440, NORTH),
	u("france", "II Corps · Reille / Bachelu", "infantry", "61e de Ligne", 600, 1, 900, 440, NORTH),
	u("france", "II Corps · Reille / Piré", "cavalry", "6e Lanciers", 400, 1, 500, 480, NORTH),
	-- I Corps (d'Erlon) — right, facing La Haye Sainte and Papelotte
	u("france", "I Corps · d'Erlon / Quiot", "infantry", "54e de Ligne", 600, 1, 1350, 480, NORTH),
	u("france", "I Corps · d'Erlon / Quiot", "infantry", "105e de Ligne", 600, 1, 1450, 500, NORTH),
	u("france", "I Corps · d'Erlon / Donzelot", "infantry", "13e Légère", 600, 2, 1550, 520, NORTH),
	u("france", "I Corps · d'Erlon / Donzelot", "infantry", "51e de Ligne", 600, 1, 1650, 500, NORTH),
	u("france", "I Corps · d'Erlon / Marcognet", "infantry", "45e de Ligne", 600, 1, 1750, 480, NORTH),
	u("france", "I Corps · d'Erlon / Durutte", "infantry", "85e de Ligne", 600, 1, 1900, 520, NORTH),
	u("france", "I Corps · d'Erlon / Jacquinot", "cavalry", "3e Chasseurs à cheval", 400, 1, 1850, 400, NORTH),
	-- VI Corps (Lobau) — reserve
	u("france", "VI Corps · Lobau", "infantry", "5e de Ligne", 600, 1, 1400, 330, NORTH),
	u("france", "VI Corps · Lobau", "infantry", "84e de Ligne", 600, 1, 1500, 330, NORTH),
	-- Imperial Guard
	u("france", "Garde Impériale", "infantry", "Grenadiers à pied de la Garde", 700, 3, 1100, 300, NORTH),
	u("france", "Garde Impériale", "infantry", "Chasseurs à pied de la Garde", 700, 3, 1000, 300, NORTH),
	u("france", "Garde Impériale · Jeune Garde", "infantry", "1er Tirailleurs", 600, 2, 1550, 240, NORTH),
	u("france", "Garde Impériale", "cavalry", "Grenadiers à cheval de la Garde", 400, 3, 900, 300, NORTH),
	u("france", "Garde Impériale", "artillery", "Artillerie de la Garde", 120, 3, 1300, 330, NORTH),
	-- Cavalry corps
	u("france", "IV Corps de cavalerie · Milhaud", "cavalry", "1er Cuirassiers", 400, 2, 1250, 380, NORTH),
	u("france", "IV Corps de cavalerie · Milhaud", "cavalry", "10e Cuirassiers", 400, 2, 1150, 380, NORTH),
	u("france", "III Corps de cavalerie · Kellermann", "cavalry", "1er Carabiniers", 400, 2, 800, 380, NORTH),
	u("france", "III Corps de cavalerie · Kellermann", "cavalry", "8e Cuirassiers", 400, 2, 700, 400, NORTH),
}

local WATERLOO_ALLIED = {
	u("britain", "HQ", "hq", "Wellington — Army HQ", 120, 3, 1230, 1130, SOUTH, { commander = true, general = "wellington" }),
	u("britain", "Cavalry · Uxbridge", "hq", "Uxbridge — Cavalry HQ", 120, 2, 1300, 1300, SOUTH, { general = "uxbridge" }),
	u("britain", "5th Division · Picton", "hq", "Picton — 5th Division HQ", 120, 2, 1420, 1230, SOUTH, { general = "picton" }),
	-- 3rd Division (Alten) — centre right, La Haye Sainte
	u("britain", "3rd Division · Alten / Ompteda", "infantry", "2nd Light Battalion KGL", 600, 2, 1200, 920, SOUTH),
	u("britain", "3rd Division · Alten / Ompteda", "infantry", "5th Line Battalion KGL", 600, 2, 1100, 1100, SOUTH),
	u("britain", "3rd Division · Alten / Halkett", "infantry", "30th Foot", 600, 1, 1000, 1100, SOUTH),
	u("britain", "3rd Division · Alten / Halkett", "infantry", "73rd Foot", 600, 1, 900, 1100, SOUTH),
	-- 5th Division (Picton) — centre left
	u("britain", "5th Division · Picton / Kempt", "infantry", "28th Foot", 600, 2, 1300, 1100, SOUTH),
	u("britain", "5th Division · Picton / Kempt", "infantry", "79th Cameron Highlanders", 600, 2, 1400, 1100, SOUTH),
	u("britain", "5th Division · Picton / Pack", "infantry", "92nd Gordon Highlanders", 600, 2, 1500, 1100, SOUTH),
	u("britain", "5th Division · Picton / Pack", "infantry", "42nd Black Watch", 600, 2, 1400, 1180, SOUTH),
	u("britain", "5th Division · Picton / Kempt", "infantry", "1/95th Rifles", 600, 2, 1260, 1010, SOUTH),
	-- 1st Division (Cooke) — the Guards, right, Hougoumont
	u("britain", "1st Division · Cooke / Byng", "infantry", "2/3rd Foot Guards", 700, 2, 760, 790, SOUTH),
	u("britain", "1st Division · Cooke / Byng", "infantry", "2/2nd Coldstream Guards", 700, 2, 760, 900, SOUTH),
	u("britain", "1st Division · Cooke / Maitland", "infantry", "2/1st Foot Guards", 700, 2, 800, 1080, SOUTH),
	-- Netherlands contingent
	u("britain", "2e Division · Perponcher / Bylandt", "infantry", "7e Bataillon de Ligne (Belge)", 600, 1, 1600, 1020, SOUTH, { colour = "Netherlands" }),
	u("britain", "2e Division · Perponcher / Bylandt", "infantry", "27e Bataillon de Jagers", 600, 1, 1650, 1100, SOUTH, { colour = "Netherlands" }),
	u("britain", "2e Division · Perponcher / Saxe-Weimar", "infantry", "2nd Nassau Regiment", 600, 1, 1760, 950, SOUTH, { colour = "Netherlands" }),
	u("britain", "2e Division · Perponcher", "artillery", "Batterie à cheval Bijleveld", 120, 1, 1700, 1150, SOUTH, { colour = "Netherlands" }),
	-- Cavalry (Uxbridge)
	u("britain", "Cavalry · Uxbridge / Somerset", "cavalry", "1st Life Guards", 400, 2, 1100, 1230, SOUTH),
	u("britain", "Cavalry · Uxbridge / Ponsonby", "cavalry", "Royal Dragoons", 400, 2, 1350, 1250, SOUTH),
	u("britain", "Cavalry · Uxbridge / Ponsonby", "cavalry", "Scots Greys", 400, 2, 1450, 1260, SOUTH),
	u("britain", "Cavalry · Uxbridge / Vandeleur", "cavalry", "12th Light Dragoons", 400, 1, 1800, 1200, SOUTH),
	u("britain", "Cavalry · Uxbridge / Vivian", "cavalry", "1st Hussars KGL", 400, 2, 1950, 1250, SOUTH),
	-- Royal Horse Artillery
	u("britain", "Royal Horse Artillery", "artillery", "Mercer's Troop RHA", 120, 2, 700, 1040, SOUTH),
	u("britain", "Royal Horse Artillery", "artillery", "Ross's Troop RHA", 120, 2, 1340, 1020, SOUTH),
	-- Prussian IV Corps (Bülow) — enters from the east toward Plancenoit
	u("britain", "IV. Armeekorps · Bülow / Hiller", "infantry", "15. Infanterie-Regiment", 600, 1, 2330, 300, WEST, { colour = "Prussia", arrival = { seconds = 720, pos = { x = 2330, z = 300 } } }),
	u("britain", "IV. Armeekorps · Bülow / Losthin", "infantry", "18. Infanterie-Regiment", 600, 1, 2330, 380, WEST, { colour = "Prussia", arrival = { seconds = 840, pos = { x = 2330, z = 380 } } }),
	u("britain", "IV. Armeekorps · Bülow / Hiller", "infantry", "Schlesisches Landwehr-Regiment", 600, 0, 2330, 220, WEST, { colour = "Prussia", arrival = { seconds = 960, pos = { x = 2330, z = 220 } } }),
	u("britain", "IV. Armeekorps · Bülow / Prinz Wilhelm", "cavalry", "Schlesisches Husaren-Regiment", 400, 1, 2330, 460, WEST, { colour = "Prussia", arrival = { seconds = 1080, pos = { x = 2330, z = 460 } } }),
}

Scenarios.waterloo = {
	id = "waterloo",
	historicalWinner = "britain",
	attacker = "france",
	name = "Waterloo, 18 June 1815",
	map = "waterloo",
	briefing = "Late morning, 18 June 1815. Wellington's Anglo-allied army stands along the Mont-Saint-Jean ridge behind the sunken Ohain road, with Hougoumont and La Haye Sainte held in front of it; the night's rain has left the low ground sodden, slowing every march and deadening your round shot. Reille faces Hougoumont, d'Erlon the allied left, the Guard and the cuirassiers are in reserve behind La Belle Alliance. Bülow's Prussians will begin to arrive from the east at Plancenoit from the twelfth minute. Take Hougoumont, La Haye Sainte and the crossroads on the ridge, or break Wellington's army before the Prussians weigh in.",
	factions = { player = "france", enemy = "britain" },
	factionNames = { france = "France", britain = "Anglo-allied" },
	units = {},
	timeLimit = 30 * 60,
	date = "18 June 1815",
	year = 1815,
	summary = "Napoleon delayed his attack for the ground to dry, then spent the day on frontal assaults: Reille was drawn into Hougoumont, d'Erlon's columns were broken by Picton and the Union Brigade, Ney's cavalry charged the allied squares unsupported, and La Haye Sainte fell only in the evening. Bülow's Prussians took Plancenoit, Zieten joined Wellington's left, and the repulse of the Imperial Guard at dusk turned the French retreat into a rout. The French lost around 25,000 killed and wounded and the war; Napoleon abdicated four days later.",
	difficultyNote = "Very hard: a strong defensive position, mud, and Prussian reinforcements against you from minute 12.",
	weather = "mud",
	mode = "full",
	moments = {
		{
			id = "waterloo_hougoumont",
			title = "Hougoumont ablaze",
			text = "French howitzers have set Hougoumont alight. The château and the great barn burn over the wounded, and still the Guards hold the walls.",
			when = { time = 600, formationNear = { faction = "france", objective = "hougoumont", radius = 180 } },
			camera = { x = 760, z = 790 },
			effect = { morale = { { faction = "britain", corps = "Byng", amount = -5 } } },
		},
		{
			id = "waterloo_prussians",
			title = "The Prussians at Plancenoit",
			text = "Dark columns are coming out of the Bois de Paris: Bülow's Prussians are on the field, marching on Plancenoit and the French rear.",
			when = { formationNear = { faction = "britain", corps = "Bülow", pos = { x = 2200, z = 340 }, radius = 400 } },
			camera = { x = 2100, z = 350 },
			effect = { morale = { { faction = "france", amount = -4 } } },
		},
		{
			id = "waterloo_garde",
			title = "La Garde recule !",
			text = "The Guard is falling back! The cry runs down the French line, and an army that has fought all day begins to come apart.",
			when = { formationRouted = { faction = "france", corps = "Garde Impériale", class = "infantry" } },
			effect = { morale = { { faction = "france", amount = -12 } } },
		},
	},
} :: Scenario
for _, d in WATERLOO_FRENCH do
	table.insert(Scenarios.waterloo.units, d)
end
for _, d in WATERLOO_ALLIED do
	table.insert(Scenarios.waterloo.units, d)
end

-- ---------------------------------------------------------------------------------------------
-- Episodes: quick battles (10 min) cut from the four battles. Same ground as the parent battle
-- (map ids `<battle>_<episode>` in MapGen share its features and seed) with their own zones and
-- objectives. docs/battles.md has the history and the name legend for each.
-- ---------------------------------------------------------------------------------------------
local EPISODE_MINUTES = 10

local function episode(s: Scenario): Scenario
	s.timeLimit = EPISODE_MINUTES * 60
	s.mode = "episode"
	(Scenarios :: any)[s.id] = s
	return s
end

episode({
	id = "jena_landgrafenberg",
	historicalWinner = "france",
	attacker = "france",
	parent = "jena",
	name = "Lannes on the Landgrafenberg",
	map = "jena_landgrafenberg",
	date = "14 October 1806, dawn",
	year = 1806,
	briefing = "Six in the morning, 14 October 1806. Lannes' V Corps has spent the night packed on the Landgrafenberg and now goes down into a fog so thick that battalions lose each other. Tauentzien's advance guard holds Closewitz and Cospeda below. Clear both villages to give the army room to deploy. The fog will lift in about four minutes; you have ten.",
	factions = { player = "france", enemy = "prussia" },
	factionNames = { france = "France", prussia = "Prussia" },
	summary = "Suchet's and Gazan's divisions came down off the plateau in the fog, took Closewitz and Cospeda and threw Tauentzien's advance guard back towards the Dornberg and Vierzehnheiligen, opening the ground on which Napoleon deployed the rest of the army that morning.",
	difficultyNote = "Even: equal numbers in the fog; the villages are the cover.",
	weather = "fog",
	weatherUntil = 240,
	units = {
		u("france", "HQ", "hq", "Lannes — V Corps HQ", 120, 3, 820, 170, NORTH, { commander = true }),
		u("france", "V Corps · Lannes / Suchet", "infantry", "17e Légère", 600, 2, 700, 330, NORTH),
		u("france", "V Corps · Lannes / Suchet", "infantry", "34e de Ligne", 600, 1, 800, 330, NORTH),
		u("france", "V Corps · Lannes / Suchet", "infantry", "40e de Ligne", 600, 1, 900, 330, NORTH),
		u("france", "V Corps · Lannes / Suchet", "infantry", "64e de Ligne", 600, 1, 1000, 320, NORTH),
		u("france", "V Corps · Lannes / Suchet", "infantry", "88e de Ligne", 600, 1, 1100, 300, NORTH),
		u("france", "V Corps · Lannes / Gazan", "infantry", "21e Légère", 600, 2, 620, 300, NORTH),
		u("france", "V Corps · Lannes", "artillery", "Batterie 5e Corps", 120, 1, 860, 250, NORTH),
		u("prussia", "HQ", "hq", "Tauentzien — Avantgarde HQ", 120, 2, 800, 680, SOUTH, { commander = true }),
		u("prussia", "Avantgarde · Tauentzien", "infantry", "Füsilier-Bataillon Pelet", 600, 1, 1000, 560, SOUTH),
		u("prussia", "Avantgarde · Tauentzien", "infantry", "IR Nr. 20 Prinz Louis Ferdinand", 600, 1, 890, 530, SOUTH),
		u("prussia", "Avantgarde · Tauentzien", "infantry", "IR Nr. 38 Pelchrzim", 600, 1, 560, 500, SOUTH),
		u("prussia", "Avantgarde · Tauentzien", "artillery", "Batterie Tauentzien", 120, 1, 760, 580, SOUTH),
		u("prussia", "Avantgarde · Tauentzien", "infantry", "IR Rechten (Sachsen)", 600, 0, 660, 620, SOUTH, { colour = "Saxony" }),
		u("prussia", "Avantgarde · Tauentzien", "cavalry", "Dragoner-Regiment Prinz Johann (Sachsen)", 400, 1, 1100, 640, SOUTH, { colour = "Saxony" }),
		u("prussia", "Detachement Holtzendorff", "infantry", "IR Nr. 51 Kauffberg", 600, 1, 1220, 600, SOUTH),
	},
	moments = {
		{
			id = "landgrafenberg_fog",
			title = "The fog lifts",
			text = "The mist tears open over the Landgrafenberg. Tauentzien sees for the first time how many French are on the slope above him.",
			when = { weatherCleared = true },
			camera = { x = 800, z = 380 },
			effect = { morale = { { faction = "france", amount = 6 } } },
		},
		{
			id = "landgrafenberg_closewitz",
			title = "Closewitz is carried",
			text = "Suchet's skirmishers clear Closewitz and the wood beyond it. Tauentzien's battalions fall back towards the Dornberg.",
			when = { objectiveTaken = { id = "closewitz", by = "france" } },
			camera = { x = 1000, z = 520 },
			effect = { morale = { { faction = "prussia", corps = "Tauentzien", amount = -8 } } },
		},
	},
} :: Scenario)

episode({
	id = "jena_vierzehnheiligen",
	historicalWinner = "france",
	attacker = "france",
	parent = "jena",
	name = "The fight for Vierzehnheiligen",
	map = "jena_vierzehnheiligen",
	date = "14 October 1806, late morning",
	year = 1806,
	briefing = "Late morning, 14 October 1806. The fog is gone. Marshal Ney has pushed his advance guard far ahead of the army towards Vierzehnheiligen, with Lannes' men on his flanks. Grawert's division is forming its line beyond the village, with cavalry on both wings. Take Vierzehnheiligen and hold it until the Prussian line breaks. Ten minutes.",
	factions = { player = "france", enemy = "prussia" },
	factionNames = { france = "France", prussia = "Prussia" },
	summary = "Ney's premature attack took Vierzehnheiligen and was nearly cut off until Lannes and Napoleon came to his aid. Grawert's Prussians then stood for two hours in the open before the burning village, firing volleys at skirmishers they could not see, and broke when the French reserves came up.",
	difficultyNote = "Even: the village is the battle; whoever holds it has the cover.",
	units = {
		u("france", "HQ", "hq", "Ney — VI Corps HQ", 120, 3, 760, 440, NORTH, { commander = true }),
		u("france", "VI Corps · Ney / Marchand", "infantry", "6e Légère", 600, 1, 700, 600, NORTH),
		u("france", "VI Corps · Ney / Marchand", "infantry", "39e de Ligne", 600, 1, 820, 600, NORTH),
		u("france", "VI Corps · Ney / Marchand", "infantry", "69e de Ligne", 600, 1, 760, 530, NORTH),
		u("france", "VI Corps · Ney", "artillery", "Batterie 6e Corps", 120, 1, 860, 500, NORTH),
		u("france", "VI Corps · Ney / Colbert", "cavalry", "10e Chasseurs à cheval", 400, 1, 1050, 600, NORTH),
		u("france", "V Corps · Lannes", "infantry", "17e Légère", 600, 2, 580, 560, NORTH),
		u("france", "V Corps · Lannes", "infantry", "40e de Ligne", 600, 1, 960, 600, NORTH),
		u("france", "V Corps · Lannes", "artillery", "Batterie 5e Corps", 120, 1, 640, 480, NORTH),
		u("prussia", "HQ", "hq", "Grawert — Division HQ", 120, 2, 900, 890, SOUTH, { commander = true }),
		u("prussia", "Division Grawert", "infantry", "IR Nr. 29 Treuenfels", 600, 2, 600, 850, SOUTH),
		u("prussia", "Division Grawert", "infantry", "IR Nr. 49 Müffling", 600, 1, 700, 850, SOUTH),
		u("prussia", "Division Grawert", "infantry", "Grenadier-Bataillon Hahn", 600, 2, 820, 850, SOUTH),
		u("prussia", "Division Grawert", "artillery", "Batterie Grawert", 120, 1, 760, 900, SOUTH),
		u("prussia", "Kavallerie · Prinz Wilhelm", "cavalry", "Kürassier-Regiment Henckel", 400, 2, 1000, 860, SOUTH),
		u("prussia", "Kavallerie · Prinz Wilhelm", "cavalry", "Husaren-Regiment Gettkandt", 400, 1, 1090, 880, SOUTH),
		u("prussia", "Sächsisches Korps · Zezschwitz", "infantry", "IR Prinz Clemens (Sachsen)", 600, 1, 470, 870, SOUTH, { colour = "Saxony" }),
	},
	moments = {
		{
			id = "vierzehnheiligen_rescue",
			title = "Lannes to the rescue",
			text = "Ney's battalions are being shot down before the village, too far ahead of the army. The Emperor sends Lannes in on either side of them.",
			when = { strengthBelow = { faction = "france", corps = "VI Corps", fraction = 0.8 } },
			camera = { x = 760, z = 680 },
			effect = { morale = { { faction = "france", corps = "VI Corps", amount = 6 } } },
			faction = "france",
		},
		{
			id = "vierzehnheiligen_taken",
			title = "Vierzehnheiligen is taken",
			text = "Vierzehnheiligen burns, and it is French. Grawert's battalions stand in the open before it, volleying by numbers as on parade, and are shot to pieces.",
			when = { objectiveTaken = { id = "vierzehnheiligen", by = "france" } },
			camera = { x = 760, z = 760 },
			effect = { morale = { { faction = "prussia", amount = -8 } } },
		},
	},
} :: Scenario)

episode({
	id = "auerstedt_hassenhausen",
	historicalWinner = "france",
	attacker = "prussia",
	parent = "auerstedt",
	name = "Gudin at Hassenhausen",
	map = "auerstedt_hassenhausen",
	date = "14 October 1806, morning",
	year = 1806,
	briefing = "Morning, 14 October 1806, in fog. Gudin's division has just reached Hassenhausen and run into the head of the whole Prussian army: Schmettau's infantry is already over the Lissbach, with Blücher's cavalry on its flank. Friant is coming up on your right. Hold Hassenhausen, then throw the Prussians back over the Lissbach bridge. Form squares when the horsemen come. Ten minutes.",
	factions = { player = "france", enemy = "prussia" },
	factionNames = { france = "France", prussia = "Prussia" },
	summary = "Gudin's division held Hassenhausen alone for the first hours of Auerstedt. Blücher's cavalry broke on its squares in the fog and Schmettau's division was fought to a standstill in front of the village. Brunswick, leading the grenadiers forward, was mortally wounded, and Friant's arrival on the right saved the position.",
	difficultyNote = "Hard: one division against the head of an army; the squares must hold.",
	weather = "fog",
	weatherUntil = 180,
	units = {
		u("france", "HQ", "hq", "Davout — III Corps HQ", 120, 3, 1300, 700, WEST, { commander = true }),
		u("france", "Division Gudin", "infantry", "25e de Ligne", 600, 2, 1080, 640, WEST),
		u("france", "Division Gudin", "infantry", "85e de Ligne", 600, 2, 1080, 760, WEST),
		u("france", "Division Gudin", "infantry", "21e de Ligne", 600, 2, 1180, 600, WEST),
		u("france", "Division Gudin", "infantry", "12e de Ligne", 600, 2, 1180, 800, WEST),
		u("france", "Division Gudin", "artillery", "Batterie Gudin", 120, 2, 1230, 700, WEST),
		u("france", "Division Friant", "infantry", "108e de Ligne", 600, 2, 1400, 900, WEST, { arrival = { seconds = 240, pos = { x = 1400, z = 900 } } }),
		u("france", "Division Friant", "infantry", "111e de Ligne", 600, 2, 1480, 940, WEST, { arrival = { seconds = 300, pos = { x = 1480, z = 940 } } }),
		u("prussia", "HQ", "hq", "Brunswick — Army HQ", 120, 2, 560, 760, EAST, { commander = true }),
		u("prussia", "Division Schmettau", "infantry", "IR Nr. 21 Herzog von Braunschweig", 600, 1, 860, 760, EAST),
		u("prussia", "Division Schmettau", "infantry", "IR Nr. 30 Borcke", 600, 1, 860, 660, EAST),
		u("prussia", "Division Schmettau", "infantry", "IR Nr. 22 Pirch", 600, 1, 840, 860, EAST),
		u("prussia", "Division Schmettau", "infantry", "Grenadier-Bataillon Hanstein", 600, 2, 820, 570, EAST),
		u("prussia", "Division Schmettau", "artillery", "Batterie Schmettau", 120, 1, 640, 760, EAST),
		u("prussia", "Division Wartensleben", "infantry", "IR Nr. 23 Winning", 600, 1, 810, 950, EAST),
		u("prussia", "Kavallerie · Blücher", "cavalry", "Garde du Corps Nr. 13", 400, 2, 620, 1050, EAST),
		u("prussia", "Kavallerie · Blücher", "cavalry", "Husaren-Regiment Blücher Nr. 8", 400, 1, 540, 1000, EAST),
	},
	moments = {
		{
			id = "hassenhausen_squares",
			title = "Gudin's squares",
			text = "Blücher's squadrons have broken on Gudin's squares in the fog. His own horse is shot under him.",
			when = { any = { { formationRouted = { faction = "prussia", corps = "Blücher" } }, { strengthBelow = { faction = "prussia", corps = "Blücher", fraction = 0.75 } } } },
			camera = { x = 1050, z = 800 },
			effect = { morale = { { faction = "france", amount = 6 } } },
		},
		{
			id = "hassenhausen_brunswick",
			title = "Brunswick is struck down",
			text = "The Duke of Brunswick is shot through the eyes while leading his grenadiers forward. He will not live, and the Prussian command falls into confusion.",
			when = {
				any = {
					{ strengthBelow = { faction = "prussia", name = "Brunswick", fraction = 0.95 } },
					{ strengthBelow = { faction = "prussia", fraction = 0.8 } },
					{ time = 180, formationNear = { faction = "prussia", class = "infantry", objective = "hassenhausen", radius = 250 } },
				},
			},
			effect = { morale = { { faction = "prussia", amount = -10 } } },
		},
	},
} :: Scenario)

episode({
	id = "auerstedt_spielberg",
	historicalWinner = "france",
	attacker = "france",
	parent = "auerstedt",
	name = "Friant at Spielberg",
	map = "auerstedt_spielberg",
	date = "14 October 1806, midday",
	year = 1806,
	briefing = "Midday, 14 October 1806. Friant's division has come up on Gudin's right and is ordered to swing round the Prussian left: take Spielberg, then push on over the Lissbach to Poppel. The Prince of Orange's division stands between you and the stream. Brunswick is down and nobody is commanding the Prussian reserve. Ten minutes.",
	factions = { player = "france", enemy = "prussia" },
	factionNames = { france = "France", prussia = "Prussia" },
	summary = "Friant extended Davout's right through Spielberg and turned the Prussian flank while Morand did the same on the left. With Brunswick mortally wounded and the reserve under Kalckreuth never committed, the Prussian army fell back west in growing disorder.",
	difficultyNote = "Even: a fair fight on open ground; the Prussians hold the stream.",
	units = {
		u("france", "HQ", "hq", "Friant — Division HQ", 120, 3, 1550, 760, WEST, { commander = true }),
		u("france", "Division Friant", "infantry", "33e de Ligne", 600, 2, 1300, 900, WEST),
		u("france", "Division Friant", "infantry", "48e de Ligne", 600, 2, 1400, 900, WEST),
		u("france", "Division Friant", "infantry", "108e de Ligne", 600, 2, 1500, 900, WEST),
		u("france", "Division Friant", "infantry", "111e de Ligne", 600, 2, 1350, 820, WEST),
		u("france", "III Corps", "artillery", "Batterie du 3e Corps", 120, 2, 1450, 820, WEST),
		u("france", "Cavalerie · Vialannes", "cavalry", "12e Chasseurs à cheval", 400, 2, 1600, 880, WEST),
		u("prussia", "HQ", "hq", "Prinz von Oranien — Division HQ", 120, 2, 820, 1150, EAST, { commander = true }),
		u("prussia", "Division Oranien", "infantry", "IR Nr. 19 Prinz von Oranien", 600, 1, 960, 1000, EAST),
		u("prussia", "Division Oranien", "infantry", "IR Nr. 25 Möllendorff", 600, 1, 960, 1100, EAST),
		u("prussia", "Division Oranien", "infantry", "Füsilier-Bataillon Oswald", 600, 1, 980, 1200, EAST),
		u("prussia", "Division Oranien", "artillery", "Batterie Oranien", 120, 1, 880, 1050, EAST),
		u("prussia", "Kavallerie · Blücher", "cavalry", "Leib-Kürassier-Regiment Nr. 3", 400, 1, 880, 1300, EAST),
		u("prussia", "Division Wartensleben", "cavalry", "Dragoner-Regiment Königin Nr. 5", 400, 1, 820, 1300, EAST),
	},
	moments = {
		{
			id = "spielberg_taken",
			title = "Spielberg falls",
			text = "Friant's men have stormed Spielberg and are swinging in on the Prussian flank. Orange's battalions find French fire coming at them from two sides.",
			when = { objectiveTaken = { id = "spielberg", by = "france" } },
			camera = { x = 1280, z = 1130 },
			effect = { morale = { { faction = "prussia", corps = "Oranien", amount = -6 } } },
		},
		{
			id = "spielberg_reserve",
			title = "The reserve does not come",
			text = "Couriers gallop back for Kalckreuth's reserve, but with Brunswick fallen nobody commands the army to send it. It will stand idle all day.",
			when = { time = 420, strengthBelow = { faction = "prussia", fraction = 0.8 } },
			effect = { morale = { { faction = "prussia", amount = -6 } } },
		},
	},
} :: Scenario)

episode({
	id = "austerlitz_pratzen",
	historicalWinner = "france",
	attacker = "france",
	parent = "austerlitz",
	name = "Soult on the Pratzen",
	map = "austerlitz_pratzen",
	date = "2 December 1805, morning",
	year = 1805,
	briefing = "Eight in the morning, 2 December 1805. Saint-Hilaire's and Vandamme's divisions wait in the fog below the Pratzen while the allied columns march off it to the south. When the sun breaks through, go up: take the plateau and Staré Vinohrady from what is left of Kolowrat's column. The Russian Guard is close behind them. Ten minutes.",
	factions = { player = "france", enemy = "russia" },
	factionNames = { france = "France", russia = "Russia & Austria" },
	summary = "Soult's two divisions climbed out of the mist onto the half-empty plateau, routed Kolowrat's and Miloradovich's troops and held the heights against Constantine's Guard, whose cavalry was finally thrown back by the French Guard cavalry under Bessières and Rapp. The allied army was cut in two.",
	difficultyNote = "Hard: an uphill attack, and the Russian Guard is coming.",
	weather = "fog",
	weatherUntil = 150,
	units = {
		u("france", "HQ", "hq", "Soult — IV Corps HQ", 120, 3, 860, 840, EAST, { commander = true }),
		u("france", "IV Corps · Soult / Saint-Hilaire", "infantry", "10e Légère", 600, 2, 1060, 700, EAST),
		u("france", "IV Corps · Soult / Saint-Hilaire", "infantry", "14e de Ligne", 600, 2, 1060, 620, EAST),
		u("france", "IV Corps · Soult / Saint-Hilaire", "infantry", "36e de Ligne", 600, 1, 980, 660, EAST),
		u("france", "IV Corps · Soult / Vandamme", "infantry", "24e Légère", 600, 2, 1060, 960, EAST),
		u("france", "IV Corps · Soult / Vandamme", "infantry", "4e de Ligne", 600, 1, 1060, 880, EAST),
		u("france", "IV Corps · Soult / Vandamme", "infantry", "28e de Ligne", 600, 1, 980, 920, EAST),
		u("france", "IV Corps · Soult / Vandamme", "infantry", "57e de Ligne", 600, 2, 980, 990, EAST),
		u("france", "IV Corps · Soult", "artillery", "Batterie 4e Corps", 120, 2, 940, 780, EAST),
		u("russia", "HQ", "hq", "Kutuzov — Allied HQ", 120, 2, 1700, 1000, WEST, { commander = true }),
		u("russia", "4. Kolonne · Kolowrat", "infantry", "Novgorod Musketeers", 600, 1, 1400, 950, WEST),
		u("russia", "4. Kolonne · Kolowrat", "infantry", "Apsheron Musketeers", 600, 1, 1400, 1050, WEST),
		u("russia", "4. Kolonne · Kolowrat", "infantry", "IR Nr. 23 Salzburg", 600, 1, 1480, 1180, WEST, { colour = "Austria" }),
		u("russia", "4. Kolonne · Kolowrat", "infantry", "IR Nr. 20 Kaunitz", 600, 1, 1480, 920, WEST, { colour = "Austria" }),
		u("russia", "4. Kolonne · Kolowrat", "artillery", "Österreichische Batterie", 120, 1, 1540, 1040, WEST, { colour = "Austria" }),
		u("russia", "Garde · Grossfürst Konstantin", "infantry", "Preobrazhensky Guards", 700, 3, 1900, 1150, WEST, { arrival = { seconds = 240, pos = { x = 1900, z = 1150 } } }),
		u("russia", "Garde · Grossfürst Konstantin", "infantry", "Semenovsky Guards", 700, 3, 1900, 1050, WEST, { arrival = { seconds = 300, pos = { x = 1900, z = 1050 } } }),
		u("russia", "Garde · Grossfürst Konstantin", "cavalry", "Chevalier Guards", 400, 3, 1950, 1250, WEST, { arrival = { seconds = 3600, pos = { x = 1950, z = 1250 } } }),
	},
	moments = {
		{
			id = "pratzen_sun",
			title = "The Sun of Austerlitz",
			text = "The fog burns off and the sun rises over the Pratzen. The allied columns are marching down off the heights, just as the Emperor foretold.",
			when = { weatherCleared = true },
			camera = { x = 1450, z = 900 },
			effect = { morale = { { faction = "france", amount = 8 } } },
		},
		{
			id = "pratzen_guard",
			title = "The Chevalier Guards",
			text = "Grand Duke Constantine throws his Guard at the heights. The Chevalier Guards, the Tsar's own horsemen, are coming at the gallop.",
			when = { time = 300, objectiveTaken = { id = "pratzen", by = "france", seconds = 60 } },
			camera = { x = 1750, z = 1150 },
			effect = { release = "Chevalier Guards" },
		},
	},
} :: Scenario)

episode({
	id = "austerlitz_sokolnitz",
	historicalWinner = "france",
	attacker = "russia",
	parent = "austerlitz",
	name = "Davout at Sokolnitz",
	map = "austerlitz_sokolnitz",
	date = "2 December 1805, morning",
	year = 1805,
	briefing = "Morning, 2 December 1805. Three allied columns are coming down off the Pratzen against the French right, and only Legrand's thin division holds Telnitz and Sokolnitz on the Goldbach. Davout's III Corps is still arriving: Friant's men have marched from Vienna in two days and will come up the Raigern road in the first three minutes. Hold both villages for ten minutes.",
	factions = { player = "france", enemy = "russia" },
	factionNames = { france = "France", russia = "Russia & Austria" },
	summary = "Legrand's division and Friant's exhausted regiments held the Goldbach villages all morning against three allied columns, losing and retaking Sokolnitz several times. The columns were still jammed in the villages when Soult's corps, having taken the Pratzen, fell on their rear and drove them onto the frozen ponds.",
	difficultyNote = "Hard: outnumbered, with the reinforcements still on the road.",
	weather = "fog",
	weatherUntil = 180,
	units = {
		u("france", "HQ", "hq", "Davout — III Corps HQ", 120, 3, 560, 300, EAST, { commander = true }),
		u("france", "IV Corps · Soult / Legrand", "infantry", "3e de Ligne", 600, 1, 930, 200, EAST),
		u("france", "IV Corps · Soult / Legrand", "infantry", "26e Légère", 600, 2, 890, 450, EAST),
		u("france", "IV Corps · Soult / Legrand", "infantry", "Tirailleurs du Pô", 600, 1, 900, 560, EAST),
		u("france", "IV Corps · Soult / Legrand", "artillery", "Batterie Legrand", 120, 1, 700, 450, EAST),
		u("france", "Division de dragons · Bourcier", "cavalry", "15e Dragons", 400, 1, 620, 200, EAST),
		u("france", "III Corps · Davout / Friant", "infantry", "48e de Ligne", 600, 2, 300, 200, EAST, { arrival = { seconds = 90, pos = { x = 300, z = 200 } } }),
		u("france", "III Corps · Davout / Friant", "infantry", "108e de Ligne", 600, 2, 300, 280, EAST, { arrival = { seconds = 120, pos = { x = 300, z = 280 } } }),
		u("france", "III Corps · Davout / Friant", "infantry", "15e Légère", 600, 2, 360, 240, EAST, { arrival = { seconds = 150, pos = { x = 360, z = 240 } } }),
		u("russia", "HQ", "hq", "Buxhöwden — Allied left HQ", 120, 2, 1400, 980, WEST, { commander = true }),
		u("russia", "Avantgarde · Kienmayer", "infantry", "Székler Grenz-Infanterie", 600, 1, 1100, 720, WEST, { colour = "Austria" }),
		u("russia", "1. Kolonne · Dokhturov", "infantry", "Novo-Ingermanland Musketeers", 600, 1, 1180, 720, WEST),
		u("russia", "1. Kolonne · Dokhturov", "infantry", "Yaroslavl Musketeers", 600, 1, 1260, 720, WEST),
		u("russia", "1. Kolonne · Dokhturov", "artillery", "Battery, 1st Column", 120, 1, 1180, 880, WEST),
		u("russia", "2. Kolonne · Langeron", "infantry", "Vyborg Musketeers", 600, 1, 1100, 800, WEST),
		u("russia", "2. Kolonne · Langeron", "infantry", "Perm Musketeers", 600, 1, 1180, 800, WEST),
		u("russia", "3. Kolonne · Przhebishevsky", "infantry", "Galicia Musketeers", 600, 1, 1260, 800, WEST),
		u("russia", "3. Kolonne · Przhebishevsky", "infantry", "Narva Musketeers", 600, 1, 1100, 880, WEST),
	},
	moments = {
		{
			id = "sokolnitz_friant",
			title = "Friant comes up",
			text = "Friant's division, seventy miles in two days from Vienna, comes up the Raigern road and goes straight in at Sokolnitz.",
			when = { formationNear = { faction = "france", name = "108e", objective = "sokolnitz", radius = 200 } },
			camera = { x = 820, z = 420 },
			effect = { morale = { { faction = "france", amount = 6 } } },
		},
		{
			id = "sokolnitz_jammed",
			title = "The columns are stuck",
			text = "Three allied columns are jammed in the lanes of Telnitz and Sokolnitz while the battle is decided on the heights above them.",
			when = { time = 360, all = { { objectiveTaken = { id = "sokolnitz", by = "france", seconds = 90 } }, { objectiveTaken = { id = "telnitz", by = "france" } } } },
			camera = { x = 900, z = 320 },
			effect = { morale = { { faction = "russia", amount = -6 } } },
		},
	},
} :: Scenario)

episode({
	id = "waterloo_hougoumont",
	historicalWinner = "britain",
	attacker = "france",
	parent = "waterloo",
	name = "The struggle for Hougoumont",
	map = "waterloo_hougoumont",
	date = "18 June 1815, from 11:30",
	year = 1815,
	briefing = "Half past eleven, 18 June 1815. The Emperor wants a diversion against Wellington's right: Reille is to take Hougoumont, the walled farm in front of the ridge. Jérôme's division leads through the wood; Foy and Bachelu are behind. The Guards hold the château, with Nassauers in the orchard. Take Hougoumont in ten minutes. The ground is sodden.",
	factions = { player = "france", enemy = "britain" },
	factionNames = { france = "France", britain = "Anglo-allied" },
	summary = "The attack on Hougoumont, meant as a diversion, drew in most of Reille's corps for the whole day. The French cleared the wood and briefly broke in through the north gate before Macdonell's Coldstreamers forced it shut. Howitzers set the château on fire in the afternoon, but the Guards held it until the end of the battle.",
	difficultyNote = "Hard: walls, a wood and mud between you and the farm.",
	weather = "mud",
	units = {
		u("france", "HQ", "hq", "Reille — II Corps HQ", 120, 3, 800, 400, NORTH, { commander = true }),
		u("france", "II Corps · Reille / Jérôme", "infantry", "1er Légère", 600, 2, 700, 560, NORTH),
		u("france", "II Corps · Reille / Jérôme", "infantry", "3e de Ligne", 600, 1, 780, 560, NORTH),
		u("france", "II Corps · Reille / Jérôme", "infantry", "1er de Ligne", 600, 1, 860, 560, NORTH),
		u("france", "II Corps · Reille / Foy", "infantry", "92e de Ligne", 600, 1, 960, 540, NORTH),
		u("france", "II Corps · Reille / Foy", "infantry", "100e de Ligne", 600, 1, 1040, 540, NORTH),
		u("france", "II Corps · Reille / Bachelu", "infantry", "2e Légère", 600, 2, 1000, 460, NORTH),
		u("france", "II Corps · Reille", "artillery", "Obusiers du 2e Corps", 120, 1, 880, 460, NORTH),
		u("france", "II Corps · Reille / Piré", "cavalry", "6e Lanciers", 400, 1, 520, 480, NORTH),
		u("britain", "HQ", "hq", "Cooke — 1st Division HQ", 120, 2, 800, 1130, SOUTH, { commander = true }),
		u("britain", "1st Division · Cooke / Byng", "infantry", "2/3rd Foot Guards", 700, 2, 760, 790, SOUTH),
		u("britain", "1st Division · Cooke / Byng", "infantry", "2/2nd Coldstream Guards", 700, 2, 820, 900, SOUTH),
		u("britain", "1st Division · Cooke / Maitland", "infantry", "2/1st Foot Guards", 700, 2, 760, 1060, SOUTH),
		u("britain", "1st Division · Cooke / Maitland", "infantry", "3/1st Foot Guards", 700, 2, 880, 1060, SOUTH),
		u("britain", "2e Division · Perponcher / Saxe-Weimar", "infantry", "1st Bn, 2nd Nassau Regiment", 600, 1, 680, 870, SOUTH, { colour = "Netherlands" }),
		u("britain", "Royal Horse Artillery", "artillery", "Bull's Troop RHA", 120, 2, 960, 1040, SOUTH),
	},
	moments = {
		{
			id = "hougoumont_gate",
			title = "The north gate",
			text = "Sous-lieutenant Legros of the 1er Légère has axed open the north gate and the French are in the courtyard. Macdonell and a handful of Coldstreamers put their shoulders to it and force it shut.",
			when = { formationNear = { faction = "france", objective = "hougoumont", radius = 45 } },
			camera = { x = 760, z = 800 },
			effect = { morale = { { faction = "britain", corps = "Byng", amount = 8 } } },
		},
		{
			id = "hougoumont_ablaze",
			title = "Hougoumont ablaze",
			text = "French howitzers have set Hougoumont alight. The château and the great barn burn over the wounded, and still the Guards hold the walls.",
			when = { time = 240, formationNear = { faction = "france", objective = "hougoumont", radius = 180 } },
			camera = { x = 760, z = 790 },
			effect = { morale = { { faction = "britain", corps = "Byng", amount = -5 }, { faction = "britain", corps = "Saxe-Weimar", amount = -5 } } },
		},
	},
} :: Scenario)

episode({
	id = "waterloo_lahayesainte",
	historicalWinner = "france",
	attacker = "france",
	parent = "waterloo",
	name = "The fall of La Haye Sainte",
	map = "waterloo_lahayesainte",
	date = "18 June 1815, evening",
	year = 1815,
	briefing = "About six in the evening, 18 June 1815. Major Baring's King's German Legion riflemen have held La Haye Sainte on the Brussels road all afternoon, and their ammunition is running out. The Emperor orders Ney to take the farm at any cost. Take La Haye Sainte, then push for the crossroads on the ridge behind it. Ten minutes, in the mud.",
	factions = { player = "france", enemy = "britain" },
	factionNames = { france = "France", britain = "Anglo-allied" },
	summary = "After repulsing every attack since early afternoon, Baring's 2nd Light Battalion KGL ran out of rifle ammunition and La Haye Sainte fell at about 18:30. French guns and skirmishers then pushed up close to the centre of Wellington's line, which was never closer to breaking. Then the Prussians arrived and the Guard was repulsed.",
	difficultyNote = "Very hard: a fortified farm, a ridge behind it, and riflemen in the sandpit.",
	weather = "mud",
	units = {
		u("france", "HQ", "hq", "Ney — Advanced HQ", 120, 3, 1200, 420, NORTH, { commander = true }),
		u("france", "I Corps · d'Erlon / Donzelot", "infantry", "13e Légère", 600, 2, 1120, 600, NORTH),
		u("france", "I Corps · d'Erlon / Donzelot", "infantry", "51e de Ligne", 600, 1, 1280, 600, NORTH),
		u("france", "I Corps · d'Erlon / Quiot", "infantry", "54e de Ligne", 600, 1, 1040, 560, NORTH),
		u("france", "I Corps · d'Erlon / Quiot", "infantry", "55e de Ligne", 600, 1, 1360, 560, NORTH),
		u("france", "I Corps · d'Erlon / Quiot", "infantry", "105e de Ligne", 600, 1, 1200, 540, NORTH),
		u("france", "Grande Batterie", "artillery", "Grande Batterie (12-livres)", 120, 2, 1080, 480, NORTH),
		u("france", "IV Corps de cavalerie · Milhaud", "cavalry", "1er Cuirassiers", 400, 2, 960, 500, NORTH),
		u("france", "IV Corps de cavalerie · Milhaud", "cavalry", "4e Cuirassiers", 400, 2, 1440, 480, NORTH),
		u("britain", "HQ", "hq", "Alten — 3rd Division HQ", 120, 2, 1100, 1220, SOUTH, { commander = true }),
		u("britain", "3rd Division · Alten / Ompteda", "infantry", "2nd Light Battalion KGL", 600, 2, 1200, 920, SOUTH),
		u("britain", "5th Division · Picton / Kempt", "infantry", "1/95th Rifles", 600, 2, 1270, 1000, SOUTH),
		u("britain", "3rd Division · Alten / Ompteda", "infantry", "5th Line Battalion KGL", 600, 2, 1100, 1100, SOUTH),
		u("britain", "3rd Division · Alten / Ompteda", "infantry", "8th Line Battalion KGL", 600, 2, 1300, 1120, SOUTH),
		u("britain", "3rd Division · Alten / Halkett", "infantry", "30th Foot", 600, 1, 1000, 1110, SOUTH),
		u("britain", "3rd Division · Alten / Halkett", "infantry", "73rd Foot", 600, 1, 1000, 1190, SOUTH),
		u("britain", "Royal Horse Artillery", "artillery", "Ross's Troop RHA", 120, 2, 1350, 1040, SOUTH),
	},
	moments = {
		{
			id = "lahayesainte_ammunition",
			title = "The rifles fall silent",
			text = "Baring's riflemen have fired their last rounds. The rifle cartridges they need never came, and they are holding the walls with the bayonet.",
			when = { time = 240, formationNear = { faction = "france", objective = "lahayesainte", radius = 200 } },
			camera = { x = 1200, z = 920 },
			effect = { morale = { { faction = "britain", name = "2nd Light Battalion KGL", amount = -10 } } },
		},
		{
			id = "lahayesainte_falls",
			title = "La Haye Sainte has fallen",
			text = "La Haye Sainte is French. Guns are galloping up to the farm and shooting into the centre of Wellington's line at point-blank range.",
			when = { objectiveTaken = { id = "lahayesainte", by = "france" } },
			camera = { x = 1200, z = 960 },
			effect = { morale = { { faction = "britain", corps = "Alten", amount = -8 } } },
		},
	},
} :: Scenario)

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
				units[#units + 1] = u(faction, "HQ", "hq", base.name, 120, 2, 800, zBase + (faction == "france" and -80 or 80), heading, { commander = true })
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
		u("france", "HQ", "hq", "French HQ", 120, 2, 800, 200, NORTH, { commander = true }),
		u("france", "V Corps", "infantry", "34e de Ligne", 600, 1, 760, 320, NORTH),
		u("france", "V Corps", "cavalry", "5e Hussards", 400, 1, 900, 300, NORTH),
		u("prussia", "HQ", "hq", "Prussian HQ", 120, 2, 760, 860, SOUTH, { commander = true }),
		u("prussia", "Grawert", "infantry", "IR Nr. 49 Müffling", 600, 1, 740, 700, SOUTH),
		u("prussia", "Grawert", "artillery", "Batterie Grawert", 120, 1, 820, 740, SOUTH),
	},
	timeLimit = nil,
} :: Scenario

-- Interactive tutorial (client UI/TutorialPanel + Tutorial, server MatchService tutorialStep).
-- Not listed in Scenarios.list(). The enemy starts passive (fire at will off, holding) and is
-- released step by step by the server; MatchService refers to these units by name.
Scenarios.tutorial = {
	id = "tutorial",
	name = "Training ground",
	map = "tutorial",
	briefing = "Spring 1809, on the Danube. Mon général, an Austrian brigade holds Ebersdorf beyond the Mühlbach, with outposts on our side of the stream. Your aide-de-camp will see you through the handling of the army before we take the village.",
	factions = { player = "france", enemy = "austria" },
	factionNames = { france = "France", austria = "Austria" },
	buildings = false,
	units = {
		u("france", "HQ", "hq", "Général de brigade", 40, 2, 200, 100, NORTH, { commander = true }),
		u("france", "Brigade", "infantry", "1er bataillon, 18e de Ligne", 600, 1, 240, 200, NORTH),
		u("france", "Brigade", "infantry", "2e bataillon, 18e de Ligne", 600, 1, 320, 200, NORTH),
		u("france", "Brigade", "infantry", "3e bataillon, 18e de Ligne", 600, 1, 400, 200, NORTH),
		u("france", "Brigade", "infantry", "Conscrits de 1809", 500, 0, 270, 110, NORTH),
		u("france", "Brigade", "artillery", "Batterie à pied, 5e d'artillerie", 120, 1, 480, 150, NORTH),
		u("france", "Brigade", "cavalry", "8e Hussards", 400, 1, 540, 220, NORTH),
		u("austria", "HQ", "hq", "Brigade-Hauptquartier", 40, 1, 860, 740, SOUTH, { commander = true }),
		u("austria", "Vorposten", "infantry", "Grenz-Infanterie Nr. 1", 300, 0, 420, 430, SOUTH),
		u("austria", "Brigade", "infantry", "IR 4 Hoch- und Deutschmeister", 600, 1, 800, 430, WEST),
		u("austria", "Brigade", "infantry", "IR 49 Kerpen", 600, 1, 620, 690, SOUTH),
		u("austria", "Brigade", "cavalry", "Chevaulegers Nr. 3", 400, 1, 880, 640, WEST),
	},
	timeLimit = 60 * 60,
} :: Scenario

-- Battles in display order, each full battle followed by its episodes; fixtures (stress,
-- skirmish) and the tutorial are not listed.
local DISPLAY_ORDER = {
	"jena", "jena_landgrafenberg", "jena_vierzehnheiligen",
	"auerstedt", "auerstedt_hassenhausen", "auerstedt_spielberg",
	"austerlitz", "austerlitz_pratzen", "austerlitz_sokolnitz",
	"waterloo", "waterloo_hougoumont", "waterloo_lahayesainte",
}

function Scenarios.list(): { ListEntry }
	local out: { ListEntry } = {}
	for _, id in DISPLAY_ORDER do
		local s = (Scenarios :: any)[id] :: Scenario
		out[#out + 1] = { id = s.id, name = s.name, date = s.date, map = s.map, factionNames = s.factionNames, summary = s.summary, difficultyNote = s.difficultyNote, mode = s.mode or "full", parent = s.parent, timeLimit = s.timeLimit }
	end
	return out
end

-- Name fragments (lower case) that mark a type, checked in order within the unit's class.
local TYPE_MARKS: { [string]: { { string | { string } } } } = {
	infantry = {
		{ "guard", { "garde", "guards", "preobrazhensky", "semenovsky" } },
		{ "rifle", { "rifle", "95th", "jäger", "jager" } },
		{ "militia", { "landwehr", "conscrit", "militia" } },
		{ "light", { "légère", "legere", "light", "tirailleur", "voltigeur", "füsilier", "fusilier", "grenz", "schützen" } },
		{ "grenadier", { "grenadier" } },
	},
	cavalry = {
		{ "heavyCav", { "cuirassier", "kürassier", "carabinier", "garde du corps", "life guard", "chevalier guard", "grenadiers à cheval", "gensd'armes", "horse guards" } },
		{ "lancer", { "lancier", "lancer", "uhlan", "ulan" } },
		{ "lightCav", { "hussar", "husar", "chasseur", "cossack", "chevauleger", "chevau-léger", "light dragoon" } },
	},
	artillery = {
		{ "horseArt", { "à cheval", "reitende", " rha", "horse artillery" } },
		{ "howitzer", { "obusier", "howitzer", "haubitz", "unicorn" } },
	},
}
local DEFAULT_TYPE = { infantry = "line", cavalry = "dragoon", artillery = "footArt", hq = "hq" }

-- The unit's type: its own `type` when that belongs to its class, else read from its name.
function Scenarios.typeOf(def: UnitDef): string
	local given = def.type and (Config.UnitTypes :: any)[def.type]
	if given and given.class == def.class then
		return def.type :: string
	end
	-- ASCII-only lower case: string.lower would mangle UTF-8 letters such as ü under Latin-1 rules
	local name = string.gsub(def.name, "[A-Z]", function(c: string): string
		return string.char(string.byte(c) + 32)
	end)
	for _, rule in TYPE_MARKS[def.class] or {} do
		for _, mark in rule[2] :: { string } do
			if string.find(name, mark, 1, true) then
				return rule[1] :: string
			end
		end
	end
	return DEFAULT_TYPE[def.class] or "line"
end

-- Fire by rank: a scenario's explicit choice, else every guard battalion and British foot.
function Scenarios.firesByRank(def: UnitDef): boolean
	if def.fireByRank ~= nil then
		return def.fireByRank
	end
	return def.class == "infantry" and (Scenarios.typeOf(def) == "guard" or def.faction == "britain")
end

-- A listed battle fought from either army: "historical" as written, "other" with the sides
-- swapped (the battle AI takes the historical player's army). Roles (`attacker`), the field and
-- the order of battle stay; the briefing is rewritten from the chosen army's side.
function Scenarios.forSide(sc: Scenario, side: string): Scenario
	if side ~= "other" then
		return sc
	end
	local me, them = sc.factions.enemy, sc.factions.player
	local mine, theirs = sc.factionNames[me] or me, sc.factionNames[them] or them
	local task = if sc.attacker == me
		then string.format("Take the field from %s: carry the objectives or break their army.", theirs)
		elseif sc.attacker == them then string.format("%s comes to take the field: hold the objectives until time runs out, or break their army.", theirs)
		else string.format("Meet %s: take the objectives or break their army.", theirs)
	local out = table.clone(sc)
	out.factions = { player = me, enemy = them }
	out.briefing = string.format("%sYou command %s. %s", if sc.date then sc.date .. ". " else "", mine, task)
	out.difficultyNote = nil
	return out
end

-- A line for the results: how the battle just fought compares with history (nil: no history).
function Scenarios.historyVerdict(sc: Scenario, winner: string?): string?
	local listed = Scenarios.get(sc.id)
	local h = listed and listed.historicalWinner
	if not h then
		return nil
	end
	local name = sc.factionNames[h] or h
	if winner == h then
		return "As in history, " .. name .. " carried the day."
	elseif winner == nil then
		return "A draw; in history " .. name .. " carried the day."
	end
	return "History went otherwise: " .. name .. " carried the day."
end

function Scenarios.get(id: string): Scenario?
	local s = (Scenarios :: any)[id]
	if type(s) == "table" and s.units then
		return s
	end
	return nil
end

return Scenarios
