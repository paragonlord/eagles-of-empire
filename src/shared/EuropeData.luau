--!strict
-- Grand campaign data: Europe, January 1805 – December 1815 (docs/grand-campaign-contract.md).
-- Pure data plus a few pure helpers; shared by the server rules and the client campaign map.
--
-- Map units: 0..2000 (x, east) × 0..1500 (z, north). Province centres come from real towns via
-- `ll(lon, lat)` (x = (lon + 10) * 40, z = (lat - 36) * 62.5). Outlines are the Voronoi cells of
-- the province centres plus unlisted "sea sites", clipped to the map: they tile the land with no
-- gaps and leave the seas open. Rough by design, not a survey. Owners, armies, commanders,
-- wars and event dates are historical; incomes, manpower, unit numbers and every rule number are
-- balance choices (docs/campaign.md).

export type Vec = { x: number, z: number }

export type Nation = {
	id: string,
	name: string,
	adjective: string,
	colour: string, -- palette key (Config.Visual.Palette / client Factions)
	capital: string,
	playable: boolean,
	major: boolean,
	treasury: number, -- start
	manpower: number, -- start
	peaceResolve: number, -- AI accepts a losing peace at war score <= -peaceResolve
	quality: number, -- army fighting value multiplier (gameplay: French corps system, British infantry)
}

export type Province = {
	id: string,
	name: string,
	owner1805: string,
	occupied1805: string?, -- held by this nation in January 1805 (Hanover)
	centre: Vec,
	outline: { Vec },
	neighbours: { string },
	terrain: string,
	income: number,
	manpower: number,
	isCapital: boolean,
	isPort: boolean,
	fort: number, -- 0..2
	towns: { string }, -- real places in the province, for the battle map's villages and labels
	river: string?, -- the river a battle there is fought over, if any
}

export type UnitClass = {
	name: string,
	class: "infantry" | "cavalry" | "artillery", -- tactical sim class
	sim: string, -- tactical unit type (Config.UnitTypes)
	strength: number,
	cost: number,
	manpower: number,
	turns: number,
	upkeep: number,
	power: number, -- auto-resolve weight per man
	needs: "any" | "capital",
	building: { chain: string, level: number }, -- the province must have it (EuropeData.Buildings)
	tech: string?, -- the nation must have researched it (EuropeData.Techs)
	nations: { string }?, -- a national unit: only these nations raise it
	majorOnly: boolean,
	experience: number, -- experience on recruitment
}

export type StartArmy = { nation: string, name: string, province: string, general: { name: string, rating: number }?, experience: number, units: { [string]: number } }

export type Condition = { any }
export type Effect = { [string]: any }
export type Choice = { id: string, label: string, effects: { Effect } }
export type Event = {
	id: string,
	turn: number, -- earliest turn
	untilTurn: number?, -- latest turn (defaults to `turn`); fires at the first turn in the window whose conditions hold
	title: string,
	text: string,
	condition: { Condition }?, -- all must hold
	effects: { Effect },
	chooser: string?, -- nation that picks among `choices` (the player gets a pop-up, an AI takes choices[1])
	choices: { Choice }?,
	historical: string, -- what actually happened
}

export type SetPiece = { scenarioId: string, province: string, turnFrom: number, turnTo: number, attacker: string, defender: string }

local EuropeData = {}

EuropeData.TurnLength = "2 months"
EuropeData.StartTurn = 1 -- Jan 1805
EuropeData.EndTurn = 66 -- Nov–Dec 1815
EuropeData.StartYear = 1805
EuropeData.Width = 2000
EuropeData.Depth = 1500

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- "May 1805" for the first month of the turn.
function EuropeData.dateOf(turn: number): string
	local m = (turn - 1) * 2
	return MONTHS[m % 12 + 1] .. " " .. tostring(EuropeData.StartYear + m // 12)
end

-- First turn of a given month/year (1-based month).
function EuropeData.turnOf(month: number, year: number): number
	return ((year - EuropeData.StartYear) * 12 + month - 1) // 2 + 1
end

local function ll(lon: number, lat: number): Vec
	return { x = math.floor((lon + 10) * 40 + 0.5), z = math.floor((lat - 36) * 62.5 + 0.5) }
end

-- Nations -----------------------------------------------------------------------------------------

local function nation(id: string, name: string, adjective: string, colour: string, capital: string, major: boolean, treasury: number, manpower: number, peaceResolve: number?): Nation
	return { id = id, name = name, adjective = adjective, colour = colour, capital = capital, playable = major, major = major, treasury = treasury, manpower = manpower, peaceResolve = peaceResolve or 20, quality = if id == "france" then 1.15 elseif id == "britain" then 1.1 else 1 }
end

-- Turn order: majors first, then minors, in this order.
EuropeData.NationOrder = { "france", "britain", "austria", "prussia", "russia", "spain", "portugal", "netherlands", "italy", "naples", "bavaria", "saxony", "wurttemberg", "sweden", "denmark", "ottoman" }

EuropeData.Nations = {
	france = nation("france", "French Empire", "French", "France", "paris", true, 1500, 6000, 25),
	britain = nation("britain", "United Kingdom", "British", "Britain", "england", true, 2500, 3000, 60),
	austria = nation("austria", "Austrian Empire", "Austrian", "Austria", "vienna", true, 900, 5000, 20),
	prussia = nation("prussia", "Kingdom of Prussia", "Prussian", "Prussia", "brandenburg", true, 900, 4000, 20),
	russia = nation("russia", "Russian Empire", "Russian", "Russia", "stpetersburg", true, 900, 6000, 35),
	spain = nation("spain", "Kingdom of Spain", "Spanish", "Spain", "madrid", false, 500, 2500),
	portugal = nation("portugal", "Kingdom of Portugal", "Portuguese", "Portugal", "lisbon", false, 300, 1000),
	netherlands = nation("netherlands", "Batavian Republic", "Dutch", "Netherlands", "holland", false, 400, 1000),
	italy = nation("italy", "Kingdom of Italy", "Italian", "Italy", "lombardy", false, 400, 1500),
	naples = nation("naples", "Kingdom of Naples", "Neapolitan", "Naples", "naples", false, 300, 1200),
	bavaria = nation("bavaria", "Electorate of Bavaria", "Bavarian", "Bavaria", "bavaria", false, 300, 1200),
	saxony = nation("saxony", "Electorate of Saxony", "Saxon", "Saxony", "saxony", false, 300, 1200),
	wurttemberg = nation("wurttemberg", "Electorate of Württemberg", "Württemberg", "Wurttemberg", "wurttemberg", false, 250, 800),
	sweden = nation("sweden", "Kingdom of Sweden", "Swedish", "Sweden", "stockholm", false, 300, 1000),
	denmark = nation("denmark", "Denmark–Norway", "Danish", "Denmark", "denmark", false, 300, 1000),
	ottoman = nation("ottoman", "Ottoman Empire", "Ottoman", "Ottoman", "constantinople", false, 500, 2500),
} :: { [string]: Nation }

EuropeData.Majors = { "france", "britain", "austria", "prussia", "russia" }

-- Provinces ---------------------------------------------------------------------------------------

type POpts = { capital: boolean?, port: boolean?, fort: number?, occupied: string? }

local function prov(id: string, name: string, lon: number, lat: number, owner: string, terrain: string, income: number, manpower: number, neighbours: { string }, o: POpts?): Province
	local opts: POpts = o or {}
	return {
		id = id,
		name = name,
		owner1805 = owner,
		occupied1805 = opts.occupied,
		centre = ll(lon, lat),
		outline = {},
		neighbours = neighbours,
		terrain = terrain,
		income = income,
		manpower = manpower,
		isCapital = opts.capital == true,
		isPort = opts.port == true,
		fort = opts.fort or 0,
		towns = {},
		river = nil,
	}
end

-- Neighbours are land borders plus the sea lanes listed in EuropeData.SeaLanes (port to port).
EuropeData.Provinces = {
	-- France (with Belgium, the left bank of the Rhine and Piedmont)
	prov("paris", "Île-de-France", 2.35, 48.85, "france", "village", 300, 1500, { "normandy", "champagne", "belgium", "aquitaine", "provence" }, { capital = true, fort = 1 }),
	prov("normandy", "Normandy & Brittany", -1.6, 48.6, "france", "waterloo", 140, 900, { "paris", "aquitaine", "belgium", "england" }, { port = true }),
	prov("aquitaine", "Aquitaine", -0.4, 44.9, "france", "waterloo", 120, 800, { "normandy", "paris", "provence", "madrid" }, { port = true }),
	prov("provence", "Provence & Lyonnais", 5.2, 44.3, "france", "austerlitz", 130, 900, { "paris", "aquitaine", "champagne", "piedmont", "catalonia" }, { port = true, fort = 1 }),
	prov("champagne", "Champagne & Lorraine", 5.2, 48.6, "france", "auerstedt", 110, 800, { "paris", "belgium", "rhineland", "provence", "wurttemberg" }, { fort = 2 }),
	prov("belgium", "Belgium", 4.3, 50.8, "france", "waterloo", 130, 600, { "paris", "normandy", "champagne", "rhineland", "holland", "england" }, { port = true, fort = 1 }),
	prov("rhineland", "Rhineland", 7.3, 50.3, "france", "bridge", 100, 600, { "belgium", "champagne", "holland", "westphalia", "wurttemberg", "thuringia" }, { fort = 1 }),
	prov("piedmont", "Piedmont", 7.4, 44.9, "france", "jena", 80, 500, { "provence", "lombardy" }, { fort = 1 }),
	-- French satellites
	prov("holland", "Holland", 5.0, 52.3, "netherlands", "waterloo", 160, 400, { "belgium", "rhineland", "westphalia", "england" }, { capital = true, port = true, fort = 1 }),
	prov("lombardy", "Lombardy", 10.2, 45.2, "italy", "bridge", 140, 700, { "piedmont", "venetia", "tyrol", "naples" }, { capital = true, fort = 1 }),
	-- Britain (Hanover in personal union, occupied by Mortier's French since 1803)
	prov("england", "England & Scotland", -2.0, 53.3, "britain", "waterloo", 450, 900, { "ireland", "normandy", "belgium", "holland", "denmark", "lisbon" }, { capital = true, port = true, fort = 1 }),
	prov("ireland", "Ireland", -8.0, 53.3, "britain", "waterloo", 80, 700, { "england" }, { port = true }),
	prov("hanover", "Hanover", 10.0, 53.0, "britain", "waterloo", 70, 400, { "westphalia", "thuringia", "brandenburg", "denmark" }, { port = true, occupied = "france" }),
	-- Austria
	prov("vienna", "Lower Austria", 15.8, 47.9, "austria", "bridge", 200, 1000, { "tyrol", "venetia", "bavaria", "bohemia", "moravia", "hungary" }, { capital = true, fort = 1 }),
	prov("venetia", "Venetia", 12.6, 45.9, "austria", "village", 100, 500, { "lombardy", "tyrol", "dalmatia", "vienna" }, { port = true, fort = 1 }),
	prov("dalmatia", "Dalmatia & Croatia", 16.5, 44.3, "austria", "jena", 40, 300, { "venetia", "hungary", "serbia" }, { port = true }),
	prov("tyrol", "Tyrol", 11.2, 46.9, "austria", "jena", 50, 300, { "lombardy", "venetia", "bavaria", "wurttemberg", "vienna" }),
	prov("bohemia", "Bohemia", 14.2, 50.0, "austria", "jena", 120, 900, { "vienna", "bavaria", "saxony", "silesia", "moravia" }, { fort = 1 }),
	prov("moravia", "Moravia", 17.2, 49.5, "austria", "austerlitz", 80, 600, { "vienna", "bohemia", "silesia", "hungary", "galicia" }, { fort = 1 }),
	prov("hungary", "Hungary", 19.5, 47.2, "austria", "auerstedt", 130, 1200, { "vienna", "moravia", "galicia", "dalmatia", "serbia" }),
	prov("galicia", "Galicia", 22.5, 49.8, "austria", "austerlitz", 80, 900, { "moravia", "hungary", "silesia", "warsaw", "ukraine" }),
	-- Prussia
	prov("brandenburg", "Brandenburg & Pomerania", 13.0, 52.8, "prussia", "auerstedt", 160, 900, { "saxony", "silesia", "warsaw", "eastprussia", "hanover", "thuringia" }, { capital = true, fort = 1 }),
	prov("silesia", "Silesia", 17.0, 51.0, "prussia", "auerstedt", 120, 800, { "brandenburg", "saxony", "bohemia", "moravia", "galicia", "warsaw" }, { fort = 1 }),
	prov("eastprussia", "East Prussia", 21.0, 54.3, "prussia", "bridge", 80, 600, { "brandenburg", "warsaw", "lithuania", "stockholm" }, { port = true, fort = 2 }),
	prov("westphalia", "Westphalia", 7.8, 51.6, "prussia", "waterloo", 70, 500, { "holland", "rhineland", "hanover", "thuringia" }),
	prov("warsaw", "South Prussia (Warsaw)", 19.5, 52.3, "prussia", "bridge", 70, 700, { "brandenburg", "silesia", "galicia", "eastprussia", "lithuania", "ukraine" }),
	-- German minors
	prov("saxony", "Saxony", 13.5, 51.4, "saxony", "jena", 90, 500, { "brandenburg", "silesia", "bohemia", "thuringia", "bavaria" }, { capital = true, fort = 1 }),
	prov("thuringia", "Thuringia", 11.0, 50.9, "saxony", "jena", 60, 400, { "saxony", "brandenburg", "hanover", "westphalia", "rhineland", "bavaria" }),
	prov("bavaria", "Bavaria", 11.8, 48.3, "bavaria", "bridge", 100, 600, { "wurttemberg", "tyrol", "vienna", "bohemia", "saxony", "thuringia" }, { capital = true, fort = 1 }),
	prov("wurttemberg", "Württemberg & Baden", 9.0, 48.6, "wurttemberg", "village", 70, 400, { "champagne", "rhineland", "bavaria", "tyrol" }, { capital = true }),
	-- Russia
	prov("stpetersburg", "St Petersburg", 30.3, 59.5, "russia", "waterloo", 180, 800, { "lithuania", "smolensk", "moscow", "stockholm" }, { capital = true, port = true, fort = 2 }),
	prov("lithuania", "Lithuania & Courland", 24.0, 55.8, "russia", "auerstedt", 80, 800, { "eastprussia", "warsaw", "smolensk", "stpetersburg", "ukraine" }, { port = true }),
	prov("smolensk", "Smolensk", 31.0, 54.5, "russia", "bridge", 70, 900, { "lithuania", "stpetersburg", "moscow", "ukraine" }, { fort = 1 }),
	prov("moscow", "Moscow", 37.6, 55.75, "russia", "auerstedt", 160, 1400, { "smolensk", "stpetersburg", "ukraine" }),
	prov("ukraine", "Volhynia & Ukraine", 29.0, 50.0, "russia", "austerlitz", 90, 1300, { "warsaw", "galicia", "lithuania", "smolensk", "moscow", "serbia" }),
	-- Iberia
	prov("madrid", "Castile", -3.7, 40.4, "spain", "jena", 150, 800, { "aquitaine", "catalonia", "andalusia", "lisbon" }, { capital = true }),
	prov("catalonia", "Catalonia & Aragon", 1.0, 41.7, "spain", "jena", 90, 500, { "madrid", "provence", "andalusia" }, { port = true, fort = 1 }),
	prov("andalusia", "Andalusia", -5.0, 37.6, "spain", "austerlitz", 110, 600, { "madrid", "catalonia", "lisbon" }, { port = true, fort = 1 }),
	prov("lisbon", "Portugal", -8.3, 39.6, "portugal", "waterloo", 90, 400, { "madrid", "andalusia", "england" }, { capital = true, port = true, fort = 1 }),
	-- Italy south
	prov("naples", "Naples & the Papal States", 14.0, 41.8, "naples", "austerlitz", 90, 500, { "lombardy", "sicily" }, { capital = true, port = true }),
	prov("sicily", "Sicily", 14.2, 37.6, "naples", "waterloo", 50, 300, { "naples" }, { port = true }),
	-- North and east
	prov("stockholm", "Sweden", 16.5, 59.0, "sweden", "waterloo", 80, 400, { "stpetersburg", "denmark", "eastprussia" }, { capital = true, port = true, fort = 1 }),
	prov("denmark", "Denmark & Holstein", 10.3, 55.45, "denmark", "waterloo", 90, 400, { "hanover", "stockholm", "england" }, { capital = true, port = true, fort = 1 }),
	prov("constantinople", "Rumelia", 26.5, 41.6, "ottoman", "austerlitz", 140, 1000, { "serbia" }, { capital = true, port = true, fort = 2 }),
	prov("serbia", "Serbia & the Danube", 21.5, 44.3, "ottoman", "bridge", 50, 600, { "dalmatia", "hungary", "constantinople", "ukraine" }),
}

-- Real places for province battle maps (`MapGen.generate("province:<id>")`, docs/campaign.md):
-- three towns each (first = main village) and the river, if the landscape has one.
local PLACES: { [string]: { any } } = {
	paris = { { "Meaux", "Saint-Denis", "Versailles" }, "Seine" },
	normandy = { { "Caen", "Rouen", "Rennes" }, "Orne" },
	aquitaine = { { "Bordeaux", "Bayonne", "Agen" }, "Garonne" },
	provence = { { "Lyon", "Avignon", "Toulon" }, "Rhône" },
	champagne = { { "Reims", "Metz", "Nancy" }, "Moselle" },
	belgium = { { "Ligny", "Wavre", "Quatre-Bras" }, "Dyle" },
	rhineland = { { "Mainz", "Koblenz", "Cologne" }, "Rhine" },
	piedmont = { { "Marengo", "Alessandria", "Turin" }, "Bormida" },
	holland = { { "Utrecht", "Arnhem", "Haarlem" }, "Waal" },
	lombardy = { { "Lodi", "Mantua", "Milan" }, "Adda" },
	england = { { "Canterbury", "Maidstone", "Dover" }, "Medway" },
	ireland = { { "Wexford", "Kilkenny", "Athlone" }, "Shannon" },
	hanover = { { "Celle", "Stade", "Hanover" }, "Leine" },
	vienna = { { "Aspern", "Essling", "Wagram" }, "Danube" },
	venetia = { { "Caldiero", "Verona", "Vicenza" }, "Adige" },
	dalmatia = { { "Knin", "Zara", "Spalato" }, "Krka" },
	tyrol = { { "Innsbruck", "Brixen", "Wörgl" }, "Inn" },
	bohemia = { { "Kulm", "Pilsen", "Prague" }, "Elbe" },
	moravia = { { "Znaim", "Olmütz", "Brünn" }, "Thaya" },
	hungary = { { "Raab", "Komorn", "Pest" }, "Raab" },
	galicia = { { "Tarnów", "Cracow", "Lemberg" }, "Vistula" },
	brandenburg = { { "Potsdam", "Spandau", "Küstrin" }, "Havel" },
	silesia = { { "Schweidnitz", "Glogau", "Breslau" }, "Oder" },
	eastprussia = { { "Eylau", "Friedland", "Königsberg" }, "Alle" },
	westphalia = { { "Minden", "Paderborn", "Münster" }, "Weser" },
	warsaw = { { "Pultusk", "Golymin", "Praga" }, "Narew" },
	saxony = { { "Lützen", "Bautzen", "Dresden" }, "Elbe" },
	thuringia = { { "Saalfeld", "Schleiz", "Erfurt" }, "Saale" },
	bavaria = { { "Eckmühl", "Abensberg", "Landshut" }, "Isar" },
	wurttemberg = { { "Elchingen", "Ulm", "Stuttgart" }, "Danube" },
	stpetersburg = { { "Narva", "Pskov", "Novgorod" }, "Luga" },
	lithuania = { { "Kovno", "Vilna", "Riga" }, "Niemen" },
	smolensk = { { "Krasnoi", "Valutino", "Smolensk" }, "Dnieper" },
	moscow = { { "Borodino", "Mozhaisk", "Maloyaroslavets" }, "Kolocha" },
	ukraine = { { "Dubno", "Brody", "Kiev" }, "Styr" },
	madrid = { { "Talavera", "Ocaña", "Somosierra" }, "Tagus" },
	catalonia = { { "Gerona", "Saragossa", "Barcelona" }, "Ebro" },
	andalusia = { { "Bailén", "Seville", "Cádiz" }, "Guadalquivir" },
	lisbon = { { "Vimeiro", "Roliça", "Oporto" }, "Douro" },
	naples = { { "Maida", "Capua", "Gaeta" }, "Volturno" },
	sicily = { { "Messina", "Palermo", "Syracuse" } },
	stockholm = { { "Uppsala", "Norrköping", "Örebro" } },
	denmark = { { "Køge", "Kiel", "Copenhagen" }, "Eider" },
	constantinople = { { "Adrianople", "Philippopolis", "Sofia" }, "Maritsa" },
	serbia = { { "Nish", "Rustchuk", "Belgrade" }, "Morava" },
}
for _, p in EuropeData.Provinces do
	local pl = PLACES[p.id]
	if pl then
		p.towns = pl[1]
		p.river = pl[2]
	end
end

-- Port-to-port crossings (also listed in both provinces' neighbours). Only ports may use them.
EuropeData.SeaLanes = {
	{ "england", "ireland" },
	{ "england", "normandy" },
	{ "england", "belgium" },
	{ "england", "holland" },
	{ "england", "denmark" },
	{ "england", "lisbon" },
	{ "naples", "sicily" },
	{ "stockholm", "denmark" },
	{ "stockholm", "stpetersburg" },
	{ "stockholm", "eastprussia" },
}

-- The navy. Fleets lie in ports and sail port to port along these lanes (the army crossings and
-- the coastal passages around them); an army crosses a sea lane only from a port where its side
-- has a fleet.
EuropeData.FleetLanes = {
	{ "england", "ireland" }, { "england", "normandy" }, { "england", "belgium" }, { "england", "holland" },
	{ "england", "denmark" }, { "england", "lisbon" }, { "naples", "sicily" }, { "stockholm", "denmark" },
	{ "stockholm", "stpetersburg" }, { "stockholm", "eastprussia" },
	{ "normandy", "aquitaine" }, { "aquitaine", "lisbon" }, { "lisbon", "andalusia" }, { "andalusia", "catalonia" },
	{ "catalonia", "provence" }, { "provence", "naples" }, { "naples", "dalmatia" }, { "dalmatia", "venetia" },
	{ "sicily", "constantinople" }, { "belgium", "holland" }, { "holland", "hanover" }, { "hanover", "denmark" },
	{ "denmark", "eastprussia" }, { "eastprussia", "lithuania" }, { "lithuania", "stpetersburg" },
}

export type ShipClass = { name: string, cost: number, power: number }
EuropeData.ShipClasses = {
	frigate = { name = "Frigate", cost = 400, power = 1 },
	line = { name = "Ship of the line", cost = 900, power = 3 },
} :: { [string]: ShipClass }

export type StartFleet = { nation: string, name: string, port: string, line: number, frigates: number }
EuropeData.StartFleets = {
	{ nation = "britain", name = "Channel Fleet", port = "england", line = 10, frigates = 6 },
	{ nation = "britain", name = "Mediterranean Fleet", port = "lisbon", line = 8, frigates = 4 },
	{ nation = "britain", name = "Cork Squadron", port = "ireland", line = 2, frigates = 3 },
	{ nation = "france", name = "Brest Squadron", port = "normandy", line = 6, frigates = 3 },
	{ nation = "france", name = "Toulon Squadron", port = "provence", line = 8, frigates = 4 },
	{ nation = "spain", name = "Cádiz Squadron", port = "andalusia", line = 8, frigates = 3 },
	{ nation = "netherlands", name = "Batavian Squadron", port = "holland", line = 3, frigates = 2 },
	{ nation = "denmark", name = "Danish Fleet", port = "denmark", line = 4, frigates = 2 },
	{ nation = "sweden", name = "Swedish Fleet", port = "stockholm", line = 3, frigates = 2 },
	{ nation = "russia", name = "Baltic Fleet", port = "stpetersburg", line = 6, frigates = 3 },
	{ nation = "ottoman", name = "Ottoman Fleet", port = "constantinople", line = 4, frigates = 3 },
} :: { StartFleet }

-- Water between the provinces: Voronoi sites that shape coastlines but belong to no province.
local SEA_SITES: { Vec } = {
	-- Atlantic, Biscay, Channel, Irish Sea, North Sea
	ll(-12, 58), ll(-12, 50), ll(-12, 45), ll(-12, 40), ll(-11, 36), ll(-6, 57.5), ll(-4.6, 54.6), ll(-6.5, 50.5), ll(-5, 46.2),
	ll(-2.5, 50.3), ll(1.0, 50.6), ll(2.5, 53.5), ll(3.5, 56.5), ll(6.5, 57.5), ll(-1.5, 58.6), ll(6.0, 54.2),
	-- Baltic
	ll(14.5, 55.2), ll(18.0, 56.2), ll(20.0, 58.0), ll(23.5, 59.0), ll(12.0, 58.6),
	-- Mediterranean, Adriatic, Aegean, Black Sea, North Africa, Anatolia
	ll(-2.0, 36.6), ll(2.5, 39.0), ll(5.0, 42.0), ll(8.0, 43.0), ll(9.0, 40.0), ll(11.5, 39.5), ll(15.5, 43.5), ll(17.5, 41.8),
	ll(18.5, 38.0), ll(22.0, 36.4), ll(25.5, 38.5), ll(30.0, 37.5), ll(32.0, 44.0), ll(34.0, 41.5), ll(30.0, 46.4),
	ll(6.0, 36.4), ll(11.0, 36.4), ll(-6.5, 36.0),
}

-- Geometry (pure): Voronoi cells by successive half-plane clipping ------------------------------

local function clip(poly: { Vec }, a: Vec, b: Vec): { Vec }
	-- keep points closer to a than to b: dot(p, b - a) <= (|b|² - |a|²) / 2
	local nx, nz = b.x - a.x, b.z - a.z
	local c = (b.x * b.x + b.z * b.z - a.x * a.x - a.z * a.z) / 2
	local out: { Vec } = {}
	local n = #poly
	for i = 1, n do
		local p, q = poly[i], poly[i % n + 1]
		local dp, dq = p.x * nx + p.z * nz - c, q.x * nx + q.z * nz - c
		if dp <= 0 then
			out[#out + 1] = p
		end
		if (dp < 0 and dq > 0) or (dp > 0 and dq < 0) then
			local t = dp / (dp - dq)
			out[#out + 1] = { x = p.x + (q.x - p.x) * t, z = p.z + (q.z - p.z) * t }
		end
	end
	return out
end

local function buildOutlines()
	local sites: { Vec } = {}
	for _, p in EuropeData.Provinces do
		sites[#sites + 1] = p.centre
	end
	for _, s in SEA_SITES do
		sites[#sites + 1] = s
	end
	for i, p in EuropeData.Provinces do
		local poly: { Vec } = { { x = 0, z = 0 }, { x = EuropeData.Width, z = 0 }, { x = EuropeData.Width, z = EuropeData.Depth }, { x = 0, z = EuropeData.Depth } }
		for j, s in sites do
			if j ~= i then
				poly = clip(poly, p.centre, s)
			end
		end
		local rounded: { Vec } = {}
		for _, v in poly do
			local r = { x = math.floor(v.x + 0.5), z = math.floor(v.z + 0.5) }
			local last = rounded[#rounded]
			if not last or last.x ~= r.x or last.z ~= r.z then
				rounded[#rounded + 1] = r
			end
		end
		if #rounded > 1 and rounded[1].x == rounded[#rounded].x and rounded[1].z == rounded[#rounded].z then
			rounded[#rounded] = nil
		end
		p.outline = rounded
	end
end
buildOutlines()

local byId: { [string]: Province } = {}
EuropeData.ProvinceIds = {} :: { string }
for _, p in EuropeData.Provinces do
	byId[p.id] = p
	table.insert(EuropeData.ProvinceIds, p.id)
end

function EuropeData.province(id: string): Province?
	return byId[id]
end

local seaLane: { [string]: boolean } = {}
for _, l in EuropeData.SeaLanes do
	seaLane[l[1] .. "|" .. l[2]] = true
	seaLane[l[2] .. "|" .. l[1]] = true
end

function EuropeData.isSeaLane(a: string, b: string): boolean
	return seaLane[a .. "|" .. b] == true
end

local fleetLane: { [string]: boolean } = {}
for _, l in EuropeData.FleetLanes do
	fleetLane[l[1] .. "|" .. l[2]] = true
	fleetLane[l[2] .. "|" .. l[1]] = true
end

function EuropeData.isFleetLane(a: string, b: string): boolean
	return fleetLane[a .. "|" .. b] == true
end

-- Signed polygon area (positive = counter-clockwise with +z north).
function EuropeData.area(poly: { Vec }): number
	local s = 0
	for i = 1, #poly do
		local p, q = poly[i], poly[i % #poly + 1]
		s += p.x * q.z - q.x * p.z
	end
	return s / 2
end

-- Units ---------------------------------------------------------------------------------------------

-- Campaign unit types, mapped onto the tactical sim classes. Strength in tactical men (the sim's
-- scale); cost in treasury, manpower in men, turns to raise, upkeep per turn.
EuropeData.UnitClasses = {
	line = { name = "Line infantry", sim = "line", class = "infantry", strength = 600, cost = 300, manpower = 600, turns = 1, upkeep = 12, power = 1.0, needs = "any", building = { chain = "barracks", level = 1 }, majorOnly = false, experience = 0 },
	light = { name = "Light infantry", sim = "light", class = "infantry", strength = 600, cost = 350, manpower = 600, turns = 1, upkeep = 14, power = 1.1, needs = "any", building = { chain = "barracks", level = 1 }, majorOnly = false, experience = 1 },
	guard = { name = "Guard infantry", sim = "guard", class = "infantry", strength = 700, cost = 700, manpower = 700, turns = 3, upkeep = 25, power = 1.5, needs = "capital", building = { chain = "barracks", level = 3 }, majorOnly = true, experience = 3 },
	cavalry = { name = "Light cavalry", sim = "lightCav", class = "cavalry", strength = 400, cost = 450, manpower = 400, turns = 2, upkeep = 18, power = 1.3, needs = "any", building = { chain = "stables", level = 1 }, majorOnly = false, experience = 0 },
	heavy = { name = "Heavy cavalry", sim = "heavyCav", class = "cavalry", strength = 400, cost = 600, manpower = 400, turns = 2, upkeep = 24, power = 1.6, needs = "any", building = { chain = "stables", level = 2 }, majorOnly = false, experience = 1 },
	artillery = { name = "Foot artillery", sim = "footArt", class = "artillery", strength = 120, cost = 400, manpower = 120, turns = 2, upkeep = 20, power = 3.0, needs = "any", building = { chain = "foundry", level = 1 }, majorOnly = false, experience = 0 },
	-- unlocked by technology (EuropeData.Techs)
	rifles = { name = "Rifles", sim = "rifle", class = "infantry", strength = 600, cost = 450, manpower = 600, turns = 2, upkeep = 16, power = 1.2, needs = "any", building = { chain = "barracks", level = 2 }, tech = "rifles", majorOnly = false, experience = 1 },
	lancers = { name = "Lancers", sim = "lancer", class = "cavalry", strength = 400, cost = 500, manpower = 400, turns = 2, upkeep = 20, power = 1.45, needs = "any", building = { chain = "stables", level = 2 }, tech = "lancers", majorOnly = false, experience = 0 },
	horseart = { name = "Horse artillery", sim = "horseArt", class = "artillery", strength = 120, cost = 500, manpower = 120, turns = 2, upkeep = 24, power = 3.0, needs = "any", building = { chain = "foundry", level = 2 }, tech = "horseArtillery", majorOnly = false, experience = 0 },
	howitzer = { name = "Howitzers", sim = "howitzer", class = "artillery", strength = 120, cost = 550, manpower = 120, turns = 3, upkeep = 24, power = 3.2, needs = "any", building = { chain = "foundry", level = 3 }, tech = "howitzers", majorOnly = false, experience = 0 },
	-- national units (docs/campaign.md "National rosters")
	oldguard = { name = "Old Guard", sim = "guard", class = "infantry", strength = 700, cost = 950, manpower = 700, turns = 4, upkeep = 30, power = 1.75, needs = "capital", building = { chain = "barracks", level = 3 }, nations = { "france" }, majorOnly = true, experience = 3 },
	voltigeurs = { name = "Voltigeurs", sim = "light", class = "infantry", strength = 600, cost = 380, manpower = 600, turns = 1, upkeep = 14, power = 1.15, needs = "any", building = { chain = "barracks", level = 2 }, nations = { "france" }, majorOnly = false, experience = 2 },
	highlanders = { name = "Highlanders", sim = "grenadier", class = "infantry", strength = 600, cost = 400, manpower = 600, turns = 2, upkeep = 15, power = 1.2, needs = "any", building = { chain = "barracks", level = 2 }, nations = { "britain" }, majorOnly = false, experience = 1 },
	landwehr = { name = "Landwehr", sim = "militia", class = "infantry", strength = 600, cost = 150, manpower = 600, turns = 1, upkeep = 6, power = 0.75, needs = "any", building = { chain = "barracks", level = 1 }, nations = { "prussia" }, majorOnly = false, experience = 0 },
	jager = { name = "Jäger", sim = "rifle", class = "infantry", strength = 600, cost = 420, manpower = 600, turns = 2, upkeep = 15, power = 1.2, needs = "any", building = { chain = "barracks", level = 2 }, nations = { "prussia", "austria" }, majorOnly = false, experience = 1 },
	grenzer = { name = "Grenzer", sim = "light", class = "infantry", strength = 600, cost = 280, manpower = 600, turns = 1, upkeep = 11, power = 1.05, needs = "any", building = { chain = "barracks", level = 1 }, nations = { "austria" }, majorOnly = false, experience = 1 },
	grenadiers = { name = "Grenadiers", sim = "grenadier", class = "infantry", strength = 600, cost = 420, manpower = 600, turns = 2, upkeep = 16, power = 1.25, needs = "any", building = { chain = "barracks", level = 2 }, nations = { "austria", "russia", "prussia" }, majorOnly = false, experience = 1 },
	cossacks = { name = "Cossacks", sim = "lightCav", class = "cavalry", strength = 400, cost = 250, manpower = 400, turns = 1, upkeep = 8, power = 1.0, needs = "any", building = { chain = "stables", level = 1 }, nations = { "russia" }, majorOnly = false, experience = 0 },
} :: { [string]: UnitClass }

EuropeData.UnitTypeOrder = { "line", "light", "guard", "cavalry", "heavy", "artillery", "rifles", "lancers", "horseart", "howitzer", "oldguard", "voltigeurs", "highlanders", "landwehr", "jager", "grenzer", "grenadiers", "cossacks" }

-- Is `unitType` in `nation`'s roster (national units only for their nations)?
function EuropeData.inRoster(unitType: string, nation: string): boolean
	local c = EuropeData.UnitClasses[unitType]
	return c ~= nil and (c.nations == nil or table.find(c.nations, nation) ~= nil)
end

-- Technology (docs/campaign.md "Technology"). One research at a time; points a turn come from the
-- nation (20 a great power, 10 a minor) and its schools (15 a level), +50 % with Enlightenment.
export type Tech = { id: string, name: string, branch: string, cost: number, requires: { string }, text: string }
EuropeData.Techs = {
	{ id = "drill", name = "Platoon fire", branch = "military", cost = 400, requires = {}, text = "Line and guard infantry fire by rank in battle: a quarter faster reloading, halted in line." },
	{ id = "squares", name = "Squares from column", branch = "military", cost = 450, requires = { "drill" }, text = "Infantry forms square a third faster in battle." },
	{ id = "rifles", name = "Rifled muskets", branch = "military", cost = 550, requires = { "drill" }, text = "Raise rifle battalions (barracks 2): long range, accurate, may skirmish." },
	{ id = "canister", name = "Improved canister", branch = "military", cost = 400, requires = {}, text = "Canister kills a quarter more in battle." },
	{ id = "horseArtillery", name = "Horse artillery", branch = "military", cost = 500, requires = { "canister" }, text = "Raise horse artillery (foundry 2): guns that keep up with the cavalry." },
	{ id = "howitzers", name = "Howitzers", branch = "military", cost = 600, requires = { "horseArtillery" }, text = "Raise howitzers (foundry 3): shells over crests and walls." },
	{ id = "lancers", name = "Lancers", branch = "military", cost = 450, requires = {}, text = "Raise lancers (stables 2): light horse with a heavy charge." },
	{ id = "corps", name = "Corps system", branch = "military", cost = 800, requires = { "squares" }, text = "Armies under a general fight a tenth better in auto-resolved battles." },
	{ id = "rotation", name = "Crop rotation", branch = "industry", cost = 400, requires = {}, text = "Farms yield double: +10 % income a level." },
	{ id = "banking", name = "Banking", branch = "industry", cost = 500, requires = { "rotation" }, text = "Trade yields +15 % income a level." },
	{ id = "conscription", name = "Conscription", branch = "industry", cost = 500, requires = {}, text = "+25 % manpower." },
	{ id = "ironworks", name = "Iron works", branch = "industry", cost = 600, requires = { "banking" }, text = "Buildings cost a fifth less." },
	{ id = "enlightenment", name = "Enlightenment", branch = "philosophy", cost = 400, requires = {}, text = "+50 % research." },
	{ id = "civilcode", name = "Civil code", branch = "philosophy", cost = 600, requires = { "enlightenment" }, text = "Unrest −1 in every province." },
	{ id = "nationalism", name = "Nationalism", branch = "philosophy", cost = 700, requires = { "civilcode" }, text = "Every regiment +5 morale in battle." },
} :: { Tech }
EuropeData.TechById = {} :: { [string]: Tech }
for _, t in EuropeData.Techs do
	EuropeData.TechById[t.id] = t
end
-- What each nation knew in 1805 (gameplay: Wellington's line and rifles, Cossack lances). France's
-- corps system is already in its quality (1.15), so the Corps tech is for the others to catch up.
EuropeData.StartTechs = {
	france = { "drill", "squares", "canister", "horseArtillery" },
	britain = { "drill", "rifles", "canister", "horseArtillery" },
	prussia = { "drill" },
	austria = { "canister" },
	russia = { "lancers" },
} :: { [string]: { string } }

-- Lands where a winter campaign costs men (Economy: winter attrition, Nov–Feb).
EuropeData.HarshWinter = { stpetersburg = true, lithuania = true, smolensk = true, moscow = true, ukraine = true, eastprussia = true, warsaw = true, galicia = true, stockholm = true, tyrol = true } :: { [string]: boolean }

-- Is this turn (two months) a winter turn: Nov–Dec or Jan–Feb?
function EuropeData.isWinter(turn: number): boolean
	local m = ((turn - 1) * 2) % 12
	return m == 0 or m == 10
end

-- Buildings (docs/campaign.md "Buildings"). Each province raises chains of three levels, one
-- construction at a time; cost and turns are per level. Effects live in Economy: farms +5 % and
-- trade +10 % of the province's income per level, government -1 unrest per level, fort = the
-- province's fortress level (siege turns), school = research; barracks, stables and foundry
-- unlock recruits (UnitClasses.building).
export type BuildingChain = { name: string, levels: { string }, cost: { number }, turns: { number } }
EuropeData.Buildings = {
	government = { name = "Government", levels = { "Prefecture", "Ministry", "Palace" }, cost = { 250, 500, 1000 }, turns = { 2, 3, 4 } },
	barracks = { name = "Barracks", levels = { "Drill ground", "Barracks", "Military school" }, cost = { 200, 450, 900 }, turns = { 1, 2, 3 } },
	stables = { name = "Stables", levels = { "Stables", "Cavalry school", "Stud" }, cost = { 250, 500, 900 }, turns = { 2, 2, 3 } },
	foundry = { name = "Foundry", levels = { "Foundry", "Cannon works", "Arsenal" }, cost = { 300, 600, 1000 }, turns = { 2, 3, 3 } },
	farms = { name = "Farms", levels = { "Farms", "Enclosures", "Estates" }, cost = { 150, 350, 700 }, turns = { 1, 2, 3 } },
	trade = { name = "Trade", levels = { "Market", "Trade hall", "Exchange" }, cost = { 250, 550, 1100 }, turns = { 2, 3, 4 } },
	fort = { name = "Fortifications", levels = { "Earthworks", "Fortress", "Citadel" }, cost = { 300, 700, 1400 }, turns = { 2, 3, 4 } },
	school = { name = "School", levels = { "School", "College", "University" }, cost = { 250, 500, 1000 }, turns = { 2, 3, 4 } },
} :: { [string]: BuildingChain }
EuropeData.BuildingOrder = { "government", "barracks", "stables", "foundry", "farms", "trade", "fort", "school" }
EuropeData.BuildingMax = 3

-- January 1805: every province has a drill ground, stables and its fortress; fortresses and
-- capitals a cavalry school and a foundry; capitals a government, a school and better barracks (a great power's
-- capital trains its guard). Farms and trade start at nothing, so 1805 incomes are as they were.
function EuropeData.startBuildings(p: Province): { [string]: number }
	local b: { [string]: number } = { barracks = 1, stables = 1 }
	if p.fort > 0 then
		b.fort = p.fort
	end
	if p.fort > 0 or p.isCapital then
		b.stables = 2 -- heavy cavalry was raised in the fortress towns
		b.foundry = 1
	end
	if p.isCapital then
		local owner = EuropeData.Nations[p.owner1805]
		b.government = 1
		b.school = 1
		b.stables = 2
		b.barracks = if owner and owner.major then 3 else 2
	end
	return b
end

-- Per-nation unit names: "%s" takes the regiment ordinal ("1er", "3rd", "4.", by nation).
-- Other nations: "<adjective> <class name> <n>".
EuropeData.UnitNames = {
	france = { line = "%s de Ligne", light = "%s Légère", guard = "%s Régiment de la Garde", cavalry = "%s Chasseurs à cheval", heavy = "%s Cuirassiers", artillery = "%s Artillerie à pied", lancers = "%s Chevau-légers lanciers", horseart = "%s Artillerie à cheval", howitzer = "%s Obusiers", oldguard = "%s Grenadiers à pied de la Garde", voltigeurs = "%s Voltigeurs" },
	britain = { line = "%s Foot", light = "%s Light Infantry", guard = "%s Foot Guards", cavalry = "%s Light Dragoons", heavy = "%s Dragoon Guards", artillery = "%s Battery RA", rifles = "%s Rifles", horseart = "%s Troop RHA", highlanders = "%s Highlanders" },
	austria = { line = "%s Linien-Infanterie", light = "%s Leichte Infanterie", guard = "%s Grenadier-Bataillon", cavalry = "%s Husaren", heavy = "%s Kürassiere", artillery = "%s Batterie", grenzer = "%s Grenz-Regiment", jager = "%s Jäger-Bataillon", grenadiers = "%s Grenadier-Bataillon" },
	prussia = { line = "%s Musketier-Regiment", light = "%s Füsilier-Bataillon", guard = "%s Garde-Regiment", cavalry = "%s Husaren", heavy = "%s Kürassiere", artillery = "%s Batterie", landwehr = "%s Landwehr-Regiment", jager = "%s Jäger-Bataillon", grenadiers = "%s Grenadier-Bataillon" },
	russia = { line = "%s Musketeers", light = "%s Jägers", guard = "%s Leib-Guard", cavalry = "%s Hussars", heavy = "%s Cuirassiers", artillery = "%s Artillery Brigade", lancers = "%s Uhlans", cossacks = "%s Don Cossacks", grenadiers = "%s Grenadiers" },
} :: { [string]: { [string]: string } }

-- Generals and starting armies (January 1805) -------------------------------------------------------

local function ordinal(nation: string, n: number): string
	if nation == "france" then
		return if n == 1 then "1er" else tostring(n) .. "e"
	elseif nation == "britain" or nation == "russia" then
		local m100, m10 = n % 100, n % 10
		local suf = if m100 >= 11 and m100 <= 13 then "th" elseif m10 == 1 then "st" elseif m10 == 2 then "nd" elseif m10 == 3 then "rd" else "th"
		return tostring(n) .. suf
	end
	return tostring(n) .. "."
end

-- The `n`th regiment of a type raised by a nation: "3e de Ligne", "95th Rifles", "Bavarian Line infantry 2".
function EuropeData.unitName(nation: string, unitType: string, n: number): string
	local names = EuropeData.UnitNames[nation]
	if names and names[unitType] then
		return string.format(names[unitType], ordinal(nation, n))
	end
	return string.format("%s %s %d", EuropeData.Nations[nation].adjective, EuropeData.UnitClasses[unitType].name, n)
end

-- Generals a major can appoint later (rating 2), in order; a name already in service is skipped.
EuropeData.GeneralPool = {
	france = { "Augereau", "Mortier", "Victor", "Bessières", "Oudinot", "Suchet", "Macdonald", "Grouchy", "Junot", "Gouvion Saint-Cyr", "Lefebvre", "Poniatowski" },
	britain = { "Moore", "Hill", "Picton", "Beresford", "Graham", "Uxbridge", "Craufurd", "Cathcart" },
	austria = { "Schwarzenberg", "Bellegarde", "Hiller", "Kollowrat", "Liechtenstein", "Klenau", "Archduke Ferdinand" },
	prussia = { "Gneisenau", "Yorck", "Bülow", "Kleist", "Scharnhorst", "Tauentzien", "Rüchel" },
	russia = { "Barclay de Tolly", "Bennigsen", "Buxhöwden", "Wittgenstein", "Tormasov", "Miloradovich", "Raevsky", "Dokhturov", "Platov" },
} :: { [string]: { string } }

local function g(name: string, rating: number): { name: string, rating: number }
	return { name = name, rating = rating }
end

local function army(nationId: string, name: string, province: string, general: { name: string, rating: number }?, experience: number, units: { [string]: number }): StartArmy
	return { nation = nationId, name = name, province = province, general = general, experience = experience, units = units }
end

EuropeData.StartArmies = {
	-- The Army of England in the Boulogne camps; Bernadotte in Hanover, Marmont in Holland, Masséna in Italy.
	army("france", "Grande Armée", "normandy", g("Napoléon", 5), 2, { guard = 2, line = 4, light = 2, heavy = 2, artillery = 2 }),
	army("france", "IV Corps", "normandy", g("Soult", 3), 2, { line = 4, light = 1, cavalry = 1, artillery = 1 }),
	army("france", "III Corps", "belgium", g("Davout", 4), 2, { line = 4, light = 1, cavalry = 1, artillery = 1 }),
	army("france", "V Corps", "paris", g("Lannes", 4), 2, { line = 3, light = 1, cavalry = 1, artillery = 1 }),
	army("france", "VI Corps", "champagne", g("Ney", 3), 2, { line = 3, light = 1, cavalry = 1, artillery = 1 }),
	army("france", "Cavalry Reserve", "paris", g("Murat", 3), 2, { cavalry = 3, heavy = 2 }),
	army("france", "I Corps", "hanover", g("Bernadotte", 2), 1, { line = 3, cavalry = 1, artillery = 1 }),
	army("france", "II Corps", "holland", g("Marmont", 2), 1, { line = 3, artillery = 1 }),
	army("france", "Army of Italy", "lombardy", g("Masséna", 4), 1, { line = 4, light = 1, cavalry = 1, artillery = 1 }),
	army("netherlands", "Batavian Army", "holland", nil, 0, { line = 2, cavalry = 1 }),
	army("italy", "Royal Italian Army", "lombardy", g("Eugène de Beauharnais", 2), 0, { line = 2, cavalry = 1 }),
	-- Britain: Wellesley returned from India in 1805; the home army and the Irish garrison.
	army("britain", "Home Army", "england", g("Wellington", 4), 1, { guard = 1, line = 4, light = 1, cavalry = 2, artillery = 1 }),
	army("britain", "Irish Garrison", "ireland", nil, 0, { line = 2 }),
	-- Austria: Charles in Italy, Mack's army on the Inn, John in the Tyrol, the Hungarian insurrection.
	army("austria", "Army of Italy", "venetia", g("Archduke Charles", 4), 1, { line = 6, light = 2, cavalry = 2, artillery = 2 }),
	army("austria", "Army of Germany", "vienna", g("Mack", 1), 1, { line = 6, light = 1, cavalry = 2, artillery = 1 }),
	army("austria", "Army of the Tyrol", "tyrol", g("Archduke John", 2), 1, { line = 3, light = 2 }),
	army("austria", "Hungarian Insurrection", "hungary", nil, 0, { line = 2, cavalry = 2 }),
	-- Russia: Kutuzov's Podolian army, Bagration, the Guard at the capital.
	army("russia", "Army of Podolia", "ukraine", g("Kutuzov", 3), 1, { line = 6, light = 1, cavalry = 2, artillery = 2 }),
	army("russia", "Army of Lithuania", "lithuania", g("Bagration", 3), 1, { line = 4, light = 2, cavalry = 2, artillery = 1 }),
	army("russia", "Imperial Guard", "stpetersburg", g("Grand Duke Constantine", 1), 2, { guard = 2, line = 2, heavy = 1, artillery = 1 }),
	army("russia", "Moscow Garrison", "moscow", nil, 0, { line = 3 }),
	-- Prussia: the army of Frederick the Great's heirs.
	army("prussia", "Main Army", "brandenburg", g("Brunswick", 2), 1, { guard = 1, line = 5, cavalry = 2, heavy = 1, artillery = 2 }),
	army("prussia", "Army of Silesia", "silesia", g("Hohenlohe", 1), 1, { line = 4, light = 1, cavalry = 2, artillery = 1 }),
	army("prussia", "Westphalian Corps", "westphalia", g("Blücher", 3), 1, { line = 3, cavalry = 2, artillery = 1 }),
	army("prussia", "East Prussian Corps", "eastprussia", g("L'Estocq", 2), 1, { line = 3, cavalry = 1 }),
	-- Minors
	army("spain", "Royal Army", "madrid", g("Godoy", 1), 0, { line = 4, cavalry = 2, artillery = 1 }),
	army("spain", "Army of Andalusia", "andalusia", g("Castaños", 2), 0, { line = 2, cavalry = 1 }),
	army("portugal", "Portuguese Army", "lisbon", nil, 0, { line = 2, cavalry = 1 }),
	army("naples", "Neapolitan Army", "naples", g("Roger de Damas", 1), 0, { line = 3, cavalry = 1 }),
	army("naples", "Sicilian Garrison", "sicily", nil, 0, { line = 1 }),
	army("bavaria", "Bavarian Army", "bavaria", g("Wrede", 2), 1, { line = 3, light = 1, cavalry = 1, artillery = 1 }),
	army("saxony", "Saxon Army", "saxony", g("Zezschwitz", 1), 1, { line = 3, cavalry = 2, artillery = 1 }),
	army("wurttemberg", "Württemberg Army", "wurttemberg", nil, 0, { line = 2, cavalry = 1 }),
	army("sweden", "Swedish Army", "stockholm", g("Gustav IV Adolf", 1), 1, { line = 3, cavalry = 1, artillery = 1 }),
	army("denmark", "Danish Army", "denmark", g("Crown Prince Frederick", 1), 0, { line = 3, cavalry = 1 }),
	army("ottoman", "Army of Rumelia", "constantinople", g("Hafız İsmail Pasha", 1), 0, { line = 4, cavalry = 3 }),
	army("ottoman", "Danube Garrisons", "serbia", nil, 0, { line = 2, cavalry = 2 }),
}

-- Diplomacy, January 1805 ---------------------------------------------------------------------------

-- Britain has been at war with France since May 1803; Spain joined France against Britain in December
-- 1804; the Batavian Republic and the Italian Republic are French satellites at war with Britain.
EuropeData.StartWars = {
	{ "britain", "france" },
	{ "britain", "spain" },
	{ "britain", "netherlands" },
	{ "britain", "italy" },
}

EuropeData.StartAlliances = {
	{ "france", "netherlands" },
	{ "france", "italy" },
	{ "france", "spain" },
}

-- Pairwise -100..100; unlisted pairs are 0.
EuropeData.StartRelations = {
	{ "france", "britain", -100 },
	{ "france", "netherlands", 80 },
	{ "france", "italy", 90 },
	{ "france", "spain", 50 },
	{ "france", "bavaria", 40 },
	{ "france", "wurttemberg", 30 },
	{ "france", "austria", -40 },
	{ "france", "russia", -40 },
	{ "france", "naples", -30 },
	{ "france", "sweden", -50 },
	{ "france", "portugal", -10 },
	{ "france", "ottoman", 20 },
	{ "france", "denmark", 10 },
	{ "britain", "russia", 50 },
	{ "britain", "austria", 40 },
	{ "britain", "sweden", 50 },
	{ "britain", "portugal", 70 },
	{ "britain", "naples", 40 },
	{ "britain", "spain", -60 },
	{ "britain", "netherlands", -60 },
	{ "britain", "italy", -40 },
	{ "austria", "russia", 50 },
	{ "austria", "bavaria", -40 },
	{ "prussia", "russia", 30 },
	{ "prussia", "saxony", 50 },
	{ "russia", "ottoman", -30 },
	{ "russia", "sweden", 30 },
	{ "russia", "naples", 30 },
	{ "spain", "portugal", -20 },
}

-- Victory (docs/campaign.md) ---------------------------------------------------------------------

EuropeData.Victory = {
	CapitalsToHold = 3, -- foreign major capitals France must control...
	CapitalsFromTurn = 61, -- ...on or after this turn (Jan 1815)
}

-- Scripted events -------------------------------------------------------------------------------
-- Conditions: { "atWar", a, b } { "notAtWar", a, b } { "allied", a, b } { "notAllied", a, b }
-- { "controls", nation, province } { "notControls", nation, province } { "enemyControls", nation,
-- province } (a nation at war with `nation` controls it) { "flag", name } { "notFlag", name }
-- { "lostTo", loser, winner } (their last peace was dictated by winner) { "any", cond, cond, ... }.
-- Effects (op = ...): war {a, b}, coalition {members, against}, alliance {a, b}, breakAlliance {a, b},
-- peace {a, b}, flag {name, value?}, relation {a, b, delta}, treasury {nation, amount}, attrition
-- {nation, inOwnedBy, fraction}, spawnArmy {nation, provinces, name, general?, units, experience},
-- abdicate {nation}.

local T = EuropeData.turnOf

EuropeData.Events = {
	{
		id = "thirdCoalition",
		turn = T(7, 1805),
		untilTurn = T(11, 1805),
		title = "The Third Coalition",
		text = "Britain's subsidies and the Tsar's ambitions have bound Vienna and St Petersburg together. Austria mobilises on the Inn and Russian columns march west; Bavaria and Württemberg turn to France for protection.",
		condition = { { "notAtWar", "austria", "france" }, { "atWar", "britain", "france" } },
		effects = {
			{ op = "alliance", a = "france", b = "bavaria" },
			{ op = "alliance", a = "france", b = "wurttemberg" },
		},
		chooser = "austria",
		choices = {
			{ id = "war", label = "Join the coalition", effects = { { op = "coalition", members = { "austria", "russia", "britain", "sweden", "naples" }, against = "france" } } },
			{ id = "wait", label = "Stay out of the war", effects = { { op = "relation", a = "austria", b = "britain", delta = -30 }, { op = "coalition", members = { "russia", "britain", "sweden" }, against = "france" } } },
		},
		historical = "Austria joined the Anglo-Russian alliance on 9 August 1805 and invaded Bavaria in September.",
	},
	{
		id = "trafalgar",
		turn = T(9, 1805),
		title = "Trafalgar",
		text = "Nelson has destroyed the combined French and Spanish fleets off Cape Trafalgar. The Royal Navy rules the seas: without ships no French army can cross the water.",
		condition = { { "atWar", "britain", "france" }, { "notControls", "france", "england" } },
		effects = { { op = "flag", name = "navalSupremacy" }, { op = "sinkFleets", nations = { "france", "spain" } }, { op = "relation", a = "spain", b = "france", delta = -15 } },
		historical = "21 October 1805: Villeneuve's Franco-Spanish fleet was destroyed; Nelson was killed.",
	},
	{
		id = "confederation",
		turn = T(7, 1806),
		untilTurn = T(11, 1806),
		title = "The Confederation of the Rhine",
		text = "With Austria humbled, the German princes look to Paris. The Holy Roman Empire can be dissolved and Bavaria, Württemberg and the lesser states bound to France in a Confederation of the Rhine.",
		condition = { { "lostTo", "austria", "france" }, { "notAtWar", "austria", "france" } },
		effects = {},
		chooser = "france",
		choices = {
			{ id = "found", label = "Found the Confederation", effects = { { op = "flag", name = "confederation" }, { op = "alliance", a = "france", b = "bavaria" }, { op = "alliance", a = "france", b = "wurttemberg" }, { op = "relation", a = "france", b = "prussia", delta = -40 }, { op = "treasury", nation = "france", amount = 300 } } },
			{ id = "spare", label = "Leave the Empire standing", effects = { { op = "relation", a = "france", b = "prussia", delta = 20 }, { op = "relation", a = "france", b = "austria", delta = 20 } } },
		},
		historical = "12 July 1806; Francis II dissolved the Holy Roman Empire on 6 August.",
	},
	{
		id = "fourthCoalition",
		turn = T(9, 1806),
		untilTurn = T(3, 1807),
		title = "The Fourth Coalition",
		text = "Berlin's war party has its way: Prussia demands that French troops leave Germany and mobilises with Saxony beside her. Russia and Britain promise help.",
		condition = { { "notAtWar", "prussia", "france" }, { "any", { "flag", "confederation" }, { "controls", "france", "hanover" } } },
		effects = {},
		chooser = "prussia",
		choices = {
			{ id = "war", label = "Send the ultimatum", effects = { { op = "alliance", a = "prussia", b = "saxony" }, { op = "coalition", members = { "prussia", "saxony", "russia", "britain" }, against = "france" } } },
			{ id = "wait", label = "Keep the peace", effects = { { op = "relation", a = "prussia", b = "france", delta = 20 }, { op = "relation", a = "prussia", b = "russia", delta = -20 } } },
		},
		historical = "Prussia's ultimatum expired on 8 October 1806; Jena and Auerstedt were fought on the 14th.",
	},
	{
		id = "continentalSystem",
		turn = T(11, 1806),
		untilTurn = T(11, 1807),
		title = "The Continental System",
		text = "From Berlin the Emperor decrees a blockade of the British Isles: no port under French control or alliance may trade with Britain. British income falls; France and her allies suffer too.",
		condition = { { "atWar", "britain", "france" }, { "any", { "controls", "france", "brandenburg" }, { "lostTo", "prussia", "france" }, { "lostTo", "austria", "france" } } },
		effects = { { op = "flag", name = "continentalSystem" } },
		historical = "Berlin Decree, 21 November 1806; Milan Decree, December 1807.",
	},
	{
		id = "saxonyKingdom",
		turn = T(11, 1806),
		untilTurn = T(11, 1807),
		title = "The Kingdom of Saxony",
		text = "Dresden sues for terms. The Elector becomes a King and joins the Confederation on the French side.",
		condition = { { "atWar", "saxony", "france" }, { "controls", "france", "saxony" } },
		effects = { { op = "peace", a = "saxony", b = "france" }, { op = "breakAlliance", a = "saxony", b = "prussia" }, { op = "alliance", a = "saxony", b = "france" } },
		historical = "Treaty of Posen, 11 December 1806.",
	},
	{
		id = "invasionOfPortugal",
		turn = T(9, 1807),
		untilTurn = T(1, 1808),
		title = "The Invasion of Portugal",
		text = "Lisbon will not close its ports to the British. By the Treaty of Fontainebleau, France and Spain agree to march on Portugal and divide it.",
		condition = { { "flag", "continentalSystem" }, { "allied", "spain", "france" }, { "notAllied", "portugal", "france" } },
		effects = { { op = "war", a = "france", b = "portugal" }, { op = "war", a = "spain", b = "portugal" }, { op = "war", a = "britain", b = "spain" }, { op = "alliance", a = "britain", b = "portugal" } },
		historical = "Treaty of Fontainebleau, 27 October 1807; Junot entered Lisbon on 30 November.",
	},
	{
		id = "peninsularWar",
		turn = T(5, 1808),
		untilTurn = T(11, 1808),
		title = "Dos de Mayo",
		text = "Madrid has risen against the French. The Bourbons are at Bayonne in your hands: you may give the Spanish throne to Joseph Bonaparte, or let them go home and keep an unreliable ally.",
		condition = { { "allied", "spain", "france" } },
		effects = {},
		chooser = "france",
		choices = {
			{ id = "joseph", label = "Crown Joseph King of Spain", effects = {
				{ op = "breakAlliance", a = "spain", b = "france" },
				{ op = "peace", a = "spain", b = "britain" },
				{ op = "peace", a = "spain", b = "portugal" },
				{ op = "war", a = "spain", b = "france" },
				{ op = "alliance", a = "spain", b = "britain" },
				{ op = "alliance", a = "spain", b = "portugal" },
				{ op = "flag", name = "guerrilla" },
				{ op = "spawnArmy", nation = "spain", provinces = { "andalusia", "madrid", "catalonia" }, name = "Army of Andalusia", general = { name = "Castaños", rating = 2 }, experience = 0, units = { line = 4, light = 2, cavalry = 1 } },
			} },
			{ id = "bourbons", label = "Restore the Bourbons", effects = { { op = "relation", a = "spain", b = "france", delta = -30 }, { op = "treasury", nation = "france", amount = -400 } } },
		},
		historical = "2 May 1808 rising in Madrid; Joseph proclaimed king in June; Dupont surrendered at Bailén on 22 July.",
	},
	{
		id = "fifthCoalition",
		turn = T(3, 1809),
		untilTurn = T(9, 1809),
		title = "The Fifth Coalition",
		text = "With the Emperor's best troops tied down in Spain, Vienna sees its chance. Archduke Charles's reformed army crosses the Inn; Britain promises money and a landing.",
		condition = { { "notAtWar", "austria", "france" }, { "controls", "austria", "vienna" }, { "atWar", "britain", "france" } },
		effects = {},
		chooser = "austria",
		choices = {
			{ id = "war", label = "Declare war", effects = { { op = "coalition", members = { "austria", "britain" }, against = "france" } } },
			{ id = "wait", label = "Bide our time", effects = { { op = "relation", a = "austria", b = "france", delta = 10 } } },
		},
		historical = "Austria invaded Bavaria on 10 April 1809; Aspern-Essling in May, Wagram in July.",
	},
	{
		id = "russia1812",
		turn = T(5, 1812),
		untilTurn = T(9, 1812),
		title = "The Niemen",
		text = "The Tsar has reopened his ports to neutral shipping and the alliance of Tilsit is dead. The Grande Armée of twenty nations waits on the Niemen; Prussia and Austria are bound to send contingents.",
		condition = { { "notAtWar", "france", "russia" }, { "controls", "france", "paris" } },
		effects = {},
		chooser = "france",
		choices = {
			{ id = "invade", label = "Cross the Niemen", effects = {
				{ op = "war", a = "france", b = "russia" },
				{ op = "forcedAlliance", a = "france", b = "prussia" },
				{ op = "forcedAlliance", a = "france", b = "austria" },
				{ op = "flag", name = "russianCampaign" },
			} },
			{ id = "peace", label = "Keep the peace", effects = { { op = "flag", name = "continentalSystem", value = false }, { op = "relation", a = "france", b = "russia", delta = 20 } } },
		},
		historical = "The Grande Armée crossed the Niemen on 24 June 1812; Borodino 7 September; Moscow burned.",
	},
	{
		id = "russianWinter",
		turn = T(11, 1812),
		untilTurn = T(1, 1813),
		title = "General Winter",
		text = "The Russian winter falls on armies far from their magazines. Every French army in Russia loses a third of its men.",
		condition = { { "atWar", "france", "russia" } },
		effects = { { op = "attrition", nation = "france", inOwnedBy = "russia", fraction = 0.35 } },
		historical = "The retreat from Moscow, October–December 1812; fewer than 100,000 recrossed the Niemen.",
	},
	{
		id = "sixthCoalition",
		turn = T(3, 1813),
		untilTurn = T(7, 1813),
		title = "The Sixth Coalition",
		text = "Yorck has gone over to the Russians at Tauroggen and Prussia rises. Sweden, under its new Crown Prince, joins Britain and Russia against France.",
		condition = { { "atWar", "france", "russia" } },
		effects = { { op = "coalition", members = { "russia", "britain", "sweden" }, against = "france" } },
		chooser = "prussia",
		choices = {
			{ id = "rise", label = "Call the nation to arms", effects = { { op = "breakAlliance", a = "prussia", b = "france" }, { op = "coalition", members = { "prussia" }, against = "france" } } },
			{ id = "loyal", label = "Stay loyal to France", effects = { { op = "relation", a = "prussia", b = "russia", delta = -30 } } },
		},
		historical = "Prussia declared war on 16 March 1813; Lützen and Bautzen in May.",
	},
	{
		id = "austria1813",
		turn = T(7, 1813),
		untilTurn = T(11, 1813),
		title = "Metternich's Ultimatum",
		text = "The armistice is over. Austria's terms have been refused, and Vienna joins the coalition.",
		condition = { { "notAtWar", "austria", "france" }, { "any", { "atWar", "france", "russia" }, { "atWar", "france", "prussia" } } },
		effects = {},
		chooser = "austria",
		choices = {
			{ id = "war", label = "Join the coalition", effects = { { op = "breakAlliance", a = "austria", b = "france" }, { op = "coalition", members = { "austria" }, against = "france" } } },
			{ id = "neutral", label = "Armed neutrality", effects = { { op = "breakAlliance", a = "austria", b = "france" } } },
		},
		historical = "Austria declared war on 12 August 1813; Leipzig, the Battle of the Nations, 16–19 October.",
	},
	{
		id = "bavariaDefects",
		turn = T(9, 1813),
		untilTurn = T(3, 1814),
		title = "The Treaty of Ried",
		text = "Bavaria and Württemberg read the map and change sides.",
		condition = { { "atWar", "france", "austria" }, { "atWar", "france", "russia" } },
		effects = {
			{ op = "breakAlliance", a = "bavaria", b = "france" },
			{ op = "breakAlliance", a = "wurttemberg", b = "france" },
			{ op = "coalition", members = { "bavaria", "wurttemberg" }, against = "france" },
		},
		historical = "Treaty of Ried, 8 October 1813; Württemberg followed in November.",
	},
	{
		id = "hundredDays",
		turn = T(3, 1815),
		untilTurn = T(5, 1815),
		title = "The Hundred Days",
		text = "The Congress at Vienna has declared the Emperor an outlaw. Every power in Europe marches on France: Wellington and Blücher gather in the Low Countries.",
		condition = { { "controls", "france", "paris" } },
		effects = {
			{ op = "coalition", members = { "britain", "prussia", "austria", "russia" }, against = "france" },
			{ op = "spawnArmy", nation = "britain", provinces = { "belgium", "holland", "england" }, name = "Anglo-Allied Army", general = { name = "Wellington", rating = 4 }, experience = 1, units = { guard = 1, line = 5, light = 2, cavalry = 2, heavy = 1, artillery = 2 } },
			{ op = "spawnArmy", nation = "prussia", provinces = { "rhineland", "westphalia", "brandenburg" }, name = "Army of the Lower Rhine", general = { name = "Blücher", rating = 3 }, experience = 1, units = { line = 6, light = 1, cavalry = 2, artillery = 2 } },
			{ op = "spawnArmy", nation = "france", provinces = { "paris" }, name = "Armée du Nord", general = { name = "Napoléon", rating = 5 }, experience = 2, units = { guard = 2, line = 4, heavy = 2, artillery = 2 } },
		},
		historical = "Napoleon landed from Elba on 1 March 1815 and was beaten at Waterloo on 18 June.",
	},
	{
		id = "abdication",
		turn = 1,
		untilTurn = 66,
		title = "The Emperor Abdicates",
		text = "The allies are in Paris. The marshals refuse to fight on and the Senate deposes the Emperor; France sues for peace on the victors' terms.",
		condition = { { "enemyControls", "france", "paris" } },
		effects = { { op = "abdicate", nation = "france" } },
		historical = "Paris capitulated on 31 March 1814; Napoleon abdicated at Fontainebleau on 6 April.",
	},
} :: { Event }

EuropeData.EventById = {} :: { [string]: Event }
for _, e in EuropeData.Events do
	EuropeData.EventById[e.id] = e
end

-- Historical battles offered when an army battle happens in that province in that window.
-- attacker/defender: the battle sides must contain these nations (or their allies) on opposite sides.
EuropeData.SetPieces = {
	{ scenarioId = "austerlitz", province = "moravia", turnFrom = T(9, 1805), turnTo = T(3, 1806), attacker = "france", defender = "russia" },
	{ scenarioId = "jena", province = "thuringia", turnFrom = T(7, 1806), turnTo = T(3, 1807), attacker = "france", defender = "prussia" },
	{ scenarioId = "auerstedt", province = "thuringia", turnFrom = T(7, 1806), turnTo = T(3, 1807), attacker = "prussia", defender = "france" },
	{ scenarioId = "waterloo", province = "belgium", turnFrom = T(1, 1815), turnTo = T(11, 1815), attacker = "france", defender = "britain" },
} :: { SetPiece }

return EuropeData
