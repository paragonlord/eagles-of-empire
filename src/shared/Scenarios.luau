--!strict
-- Orders of battle. Condensed and partly representative: regiment names are drawn from
-- formations present at each battle where known (docs/battles.md says which names are attested
-- and which are representative), strengths are balance choices (docs/rules.md), not returns.
-- Positions are initial deployment inside the zones; `arrival` units start off the map.

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
	colour: string?, -- palette key override (Saxony, Austria, Netherlands, Prussia under britain...)
	commander: boolean?, -- is the army HQ
	key: string?, -- campaign identity of this unit (nil for standalone battles)
	arrival: { seconds: number, pos: Vec }?, -- off-map reinforcement: enters at pos at that sim time
	general: string?, -- HQ only: id in src/shared/Generals.luau (else matched from the name)
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
}

export type ListEntry = { id: string, name: string, date: string?, map: string, factionNames: { [string]: string }, summary: string?, difficultyNote: string? }

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
	u("france", "HQ", "hq", "Napoléon — Imperial HQ", 40, 3, 800, 200, NORTH, { commander = true, general = "napoleon" }),
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
	u("prussia", "HQ", "hq", "Hohenlohe — Army HQ", 40, 2, 760, 860, SOUTH, { commander = true, general = "hohenlohe" }),
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
	u("france", "HQ", "hq", "Davout — III Corps HQ", 40, 3, 1300, 640, WEST, { commander = true, general = "davout" }),
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
	u("prussia", "HQ", "hq", "Brunswick — Army HQ", 40, 2, 300, 800, EAST, { commander = true, general = "brunswick" }),
	-- Schmettau's division — first onto the field, centre
	u("prussia", "Division Schmettau", "infantry", "IR Nr. 21 Herzog von Braunschweig", 600, 1, 560, 760, EAST),
	u("prussia", "Division Schmettau", "infantry", "IR Nr. 30 Borcke", 600, 1, 560, 660, EAST),
	u("prussia", "Division Schmettau", "infantry", "IR Nr. 22 Pirch", 600, 1, 520, 860, EAST),
	u("prussia", "Division Schmettau", "infantry", "Grenadier-Bataillon Hanstein", 600, 2, 480, 700, EAST),
	u("prussia", "Division Schmettau", "artillery", "Batterie Schmettau", 120, 1, 430, 760, EAST),
	-- Wartensleben's division — left, over the Sonnenkuppe
	u("prussia", "Division Wartensleben", "infantry", "IR Nr. 23 Winning", 600, 1, 540, 500, EAST),
	u("prussia", "Division Wartensleben", "infantry", "IR Nr. 55 Manstein", 600, 1, 540, 400, EAST),
	u("prussia", "Division Wartensleben", "infantry", "Grenadier-Bataillon Rheinbaben", 600, 2, 460, 450, EAST),
	u("prussia", "Division Wartensleben", "artillery", "Batterie Wartensleben", 120, 1, 400, 500, EAST),
	u("prussia", "Division Wartensleben", "cavalry", "Dragoner-Regiment Königin Nr. 5", 400, 1, 560, 350, EAST),
	-- Orange's division — right, toward Poppel
	u("prussia", "Division Oranien", "infantry", "IR Nr. 19 Prinz von Oranien", 600, 1, 380, 1000, EAST),
	u("prussia", "Division Oranien", "infantry", "IR Nr. 25 Möllendorff", 600, 1, 380, 1100, EAST),
	u("prussia", "Division Oranien", "infantry", "Füsilier-Bataillon Oswald", 600, 1, 600, 1050, EAST),
	u("prussia", "Division Oranien", "artillery", "Batterie Oranien", 120, 1, 300, 1050, EAST),
	-- Kalckreuth's reserve — held back behind the Eckartsberg
	u("prussia", "Reserve · Kalckreuth", "infantry", "IR Nr. 15 Garde", 600, 2, 200, 850, EAST),
	u("prussia", "Reserve · Kalckreuth", "infantry", "Grenadier-Garde Nr. 6", 600, 2, 200, 750, EAST),
	-- Blücher's cavalry — the northern flank
	u("prussia", "Kavallerie · Blücher", "cavalry", "Garde du Corps Nr. 13", 400, 2, 480, 1200, EAST),
	u("prussia", "Kavallerie · Blücher", "cavalry", "Gensd'armes Kürassier Nr. 10", 400, 1, 420, 1250, EAST),
	u("prussia", "Kavallerie · Blücher", "cavalry", "Husaren-Regiment Blücher Nr. 8", 400, 1, 560, 1150, EAST),
	u("prussia", "Kavallerie · Blücher", "cavalry", "Leib-Kürassier-Regiment Nr. 3", 400, 1, 350, 1200, EAST),
	u("prussia", "Kavallerie · Blücher", "artillery", "Reitende Batterie Blücher", 120, 1, 300, 1150, EAST),
}

Scenarios.auerstedt = {
	id = "auerstedt",
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
	u("france", "HQ", "hq", "Napoléon — Imperial HQ (Zuran)", 40, 3, 450, 1250, EAST, { commander = true, general = "napoleon" }),
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
	u("russia", "HQ", "hq", "Kutuzov — Allied HQ", 40, 2, 1500, 950, WEST, { commander = true, general = "kutuzov" }),
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
}

Scenarios.austerlitz = {
	id = "austerlitz",
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
	u("france", "HQ", "hq", "Napoléon — Imperial HQ (Rossomme)", 40, 3, 1260, 240, NORTH, { commander = true, general = "napoleon" }),
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
	u("britain", "HQ", "hq", "Wellington — Army HQ", 40, 3, 1230, 1130, SOUTH, { commander = true, general = "wellington" }),
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
} :: Scenario
for _, d in WATERLOO_FRENCH do
	table.insert(Scenarios.waterloo.units, d)
end
for _, d in WATERLOO_ALLIED do
	table.insert(Scenarios.waterloo.units, d)
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
	units = {
		u("france", "HQ", "hq", "Général de brigade", 40, 2, 200, 100, NORTH, { commander = true }),
		u("france", "Brigade", "infantry", "1er bataillon, 18e de Ligne", 600, 1, 240, 200, NORTH),
		u("france", "Brigade", "infantry", "2e bataillon, 18e de Ligne", 600, 1, 320, 200, NORTH),
		u("france", "Brigade", "infantry", "3e bataillon, 18e de Ligne", 600, 1, 400, 200, NORTH),
		u("france", "Brigade", "infantry", "Conscrits de 1809", 500, 0, 270, 110, NORTH),
		u("france", "Brigade", "artillery", "Batterie à pied, 5e d'artillerie", 120, 1, 480, 150, NORTH),
		u("france", "Brigade", "cavalry", "8e Hussards", 400, 1, 540, 220, NORTH),
		u("austria", "HQ", "hq", "Brigade-Hauptquartier", 40, 1, 860, 740, SOUTH, { commander = true }),
		u("austria", "Vorposten", "infantry", "Grenz-Infanterie Nr. 1", 400, 1, 420, 430, SOUTH),
		u("austria", "Brigade", "infantry", "IR 4 Hoch- und Deutschmeister", 600, 1, 800, 430, WEST),
		u("austria", "Brigade", "infantry", "IR 49 Kerpen", 600, 1, 620, 690, SOUTH),
		u("austria", "Brigade", "cavalry", "Chevaulegers Nr. 3", 400, 1, 880, 640, WEST),
	},
	timeLimit = 60 * 60,
} :: Scenario

-- Battles in display order; fixtures (stress, skirmish) are not listed.
local DISPLAY_ORDER = { "jena", "auerstedt", "austerlitz", "waterloo" }

function Scenarios.list(): { ListEntry }
	local out: { ListEntry } = {}
	for _, id in DISPLAY_ORDER do
		local s = (Scenarios :: any)[id] :: Scenario
		out[#out + 1] = { id = s.id, name = s.name, date = s.date, map = s.map, factionNames = s.factionNames, summary = s.summary, difficultyNote = s.difficultyNote }
	end
	return out
end

function Scenarios.get(id: string): Scenario?
	local s = (Scenarios :: any)[id]
	if type(s) == "table" and s.units then
		return s
	end
	return nil
end

return Scenarios
