--!strict
-- TEMPORARY stand-in for src/shared/EuropeData.luau (contract shape only). Delete when it lands.

local function v(i: number, j: number): { x: number, z: number }
	return { x = 400 + 300 * i + ((i * 7 + j * 3) % 5 - 2) * 15, z = 500 + 300 * j + ((i * 3 + j * 5) % 5 - 2) * 15 }
end

local CELLS: { any } = {
	{ "paris", "Île-de-France", "france", 0, 1, true, true, 1 },
	{ "lyon", "Lyonnais", "france", 0, 0, false, false, 1 },
	{ "westphalia", "Westphalia", "prussia", 1, 1, false, false, 0 },
	{ "bavaria", "Bavaria", "bavaria", 1, 0, true, false, 0 },
	{ "brandenburg", "Brandenburg", "prussia", 2, 1, true, true, 2 },
	{ "bohemia", "Bohemia", "austria", 2, 0, false, false, 1 },
	{ "poland", "Poland", "russia", 3, 1, true, false, 0 },
	{ "vienna", "Lower Austria", "austria", 3, 0, true, false, 2 },
}

local Provinces = {}
local byCell: { [string]: string } = {}
for _, c in CELLS do
	byCell[c[4] .. "," .. c[5]] = c[1] :: string
end
for _, c in CELLS do
	local i, j = c[4] :: number, c[5] :: number
	local nb = {}
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local id = byCell[(i + d[1]) .. "," .. (j + d[2])]
		if id then
			table.insert(nb, id)
		end
	end
	table.insert(Provinces, {
		id = c[1], name = c[2], owner1805 = c[3],
		centre = { x = 550 + 300 * i, z = 650 + 300 * j },
		outline = { v(i, j), v(i + 1, j), v(i + 1, j + 1), v(i, j + 1) },
		neighbours = nb, terrain = "jena", income = 10, manpower = 500,
		isCapital = c[6], isPort = c[7], fort = c[8],
	})
end

local function nation(id: string, name: string, colour: string, capital: string, major: boolean): any
	return { id = id, name = name, adjective = name, colour = colour, capital = capital, playable = major, major = major }
end

return {
	Nations = {
		france = nation("france", "France", "France", "paris", true),
		prussia = nation("prussia", "Prussia", "Prussia", "brandenburg", true),
		austria = nation("austria", "Austria", "Austria", "vienna", true),
		russia = nation("russia", "Russia", "Russia", "poland", true),
		bavaria = nation("bavaria", "Bavaria", "Bavaria", "bavaria", false),
	},
	Provinces = Provinces,
}
