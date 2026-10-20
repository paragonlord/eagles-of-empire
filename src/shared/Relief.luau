--!strict
-- The grand campaign board's geography over EuropeGeo (tools/geo.py, Natural Earth): land or
-- water at a point, the relief raised by the mountain chains, the province a piece of land
-- belongs to, and the rivers. Map units throughout (0..2000 × 0..1500, +z north); heights are
-- studs above the board's lowland. Pure, so the board and the tests agree.

local Geo = require(script.Parent.EuropeGeo)
local Europe = require(script.Parent.EuropeData)

local Relief = {}

-- Mountain chains in map units (x = (lon + 10) * 40, z = (lat - 36) * 62.5): Alps, Pyrenees,
-- Carpathians, Balkans, Apennines, Norway. Snowy chains stand higher and carry snow.
Relief.CHAINS = {
	{ snow = true, pts = { { 660, 560 }, { 700, 625 }, { 760, 650 }, { 840, 675 }, { 920, 690 }, { 990, 705 } } },
	{ snow = true, pts = { { 340, 420 }, { 400, 415 }, { 460, 418 }, { 520, 415 } } },
	{ snow = false, pts = { { 1120, 844 }, { 1240, 831 }, { 1360, 769 }, { 1420, 688 }, { 1420, 594 }, { 1320, 588 } } },
	{ snow = false, pts = { { 1320, 425 }, { 1400, 420 }, { 1480, 425 } } },
	{ snow = false, pts = { { 800, 519 }, { 870, 460 }, { 920, 406 }, { 1020, 281 } } },
	{ snow = true, pts = { { 660, 1380 }, { 700, 1430 }, { 740, 1480 } } },
} :: { { snow: boolean, pts: { { number } } } }

local PEAK_SNOW, PEAK = 12, 7 -- studs at a chain's spine
local SPREAD = 24 -- map units: a chain's half-width
local SNOW_LINE = 6.5

-- the land raster, decoded once: rows[r][c] is true on land
local rows: { { boolean } } = {}
for r, s in Geo.land do
	local row: { boolean } = table.create(Geo.Cols, false)
	local c, land = 1, false
	for _, n in string.split(s, ",") do
		local k = tonumber(n) or 0
		if land then
			for i = c, c + k - 1 do
				row[i] = true
			end
		end
		c += k
		land = not land
	end
	rows[r] = row
end

function Relief.isLand(x: number, z: number): boolean
	local r, c = math.floor(z / Geo.Cell) + 1, math.floor(x / Geo.Cell) + 1
	local row = rows[r]
	return row ~= nil and row[c] == true
end

-- Distance from (x, z) to segment a-b.
local function segDist(x: number, z: number, a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local t = math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / (dx * dx + dz * dz), 0, 1)
	local px, pz = a[1] + dx * t, a[2] + dz * t
	return math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
end

-- Height of the land (studs over the lowland) and whether the nearest chain is a snowy one.
local function relief(x: number, z: number): (number, boolean)
	local best, snowy = 0, false
	for _, chain in Relief.CHAINS do
		local d = math.huge
		for i = 1, #chain.pts - 1 do
			d = math.min(d, segDist(x, z, chain.pts[i], chain.pts[i + 1]))
		end
		local peak = if chain.snow then PEAK_SNOW else PEAK
		local h = peak * math.exp(-(d / SPREAD) ^ 2) * (0.75 + 0.5 * math.noise(x / 37, z / 37, 3.7))
		if h > best then
			best, snowy = h, chain.snow
		end
	end
	-- the lowland rolls a little, never above the province tint laid over it
	return math.max(best, 0.06 * (1 + math.noise(x / 53, z / 53, 1.3))), snowy
end

function Relief.height(x: number, z: number): number
	return (relief(x, z))
end

function Relief.snow(x: number, z: number): boolean
	local h, snowy = relief(x, z)
	return snowy and h > SNOW_LINE
end

-- The province a point of land belongs to: the nearest province centre (the same bisectors as
-- EuropeData's Voronoi outlines, without the sea sites that only shape the old coasts).
function Relief.provinceAt(x: number, z: number): string
	local best, bestD = Europe.Provinces[1].id, math.huge
	for _, p in Europe.Provinces do
		local d = (p.centre.x - x) ^ 2 + (p.centre.z - z) ^ 2
		if d < bestD then
			best, bestD = p.id, d
		end
	end
	return best
end

export type River = { name: string, pts: { { x: number, z: number } } }
local riverList: { River }? = nil
function Relief.rivers(): { River }
	local list = riverList
	if list then
		return list
	end
	local out: { River } = {}
	for _, r in Geo.rivers do
		local pts = {}
		for i = 2, #r - 1, 2 do
			table.insert(pts, { x = r[i] :: number, z = r[i + 1] :: number })
		end
		table.insert(out, { name = r[1] :: string, pts = pts })
	end
	riverList = out
	return out
end

return Relief
