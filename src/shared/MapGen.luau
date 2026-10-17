--!strict
-- Deterministic battlefield generator. The same call on server and client yields identical
-- grids and feature lists; the server treats the grid as the only terrain truth, the client
-- renders it. Authored feature lists live in MAPS below; everything else is derived.

local Config = require(script.Parent.Config)
local Grid = require(script.Parent.Grid)
local RNG = require(script.Parent.RNG)
local Vec = require(script.Parent.Vec)

type Vec = Vec.Vec
type Grid = Grid.Grid

export type Hill = { name: string?, pos: Vec, rx: number, rz: number, h: number, k: number }
export type Building = { pos: Vec, heading: number, w: number, d: number, h: number }
export type Village = { name: string, pos: Vec, radius: number, buildings: { Building }, count: number }
export type Tree = { x: number, z: number, r: number, priority: number }
export type Woods = { name: string?, pos: Vec, rx: number, rz: number, trees: { Tree } }
export type Road = { points: { Vec }, width: number }
export type River = { name: string, points: { Vec }, width: number, level: number }
export type Bridge = { a: Vec, b: Vec, width: number }
export type Label = { text: string, pos: Vec, size: number }
export type Objective = { id: string, name: string, pos: Vec, radius: number }
export type Rect = { x0: number, z0: number, x1: number, z1: number }

export type MapData = {
	id: string,
	name: string,
	width: number,
	depth: number,
	grid: Grid,
	hills: { Hill },
	villages: { Village },
	woods: { Woods },
	roads: { Road },
	rivers: { River },
	bridges: { Bridge },
	labels: { Label },
	objectives: { Objective },
	deployZones: { [string]: Rect },
	seed: number,
}

type MapDef = {
	name: string,
	seed: number,
	width: number?, -- studs, multiple of 16; defaults to Config.Map.Width
	depth: number?,
	baseHeight: number,
	hills: { Hill },
	villages: { { name: string, pos: Vec, radius: number, count: number } },
	woods: { { name: string?, pos: Vec, rx: number, rz: number } },
	roads: { Road },
	rivers: { River },
	bridges: { Bridge },
	labels: { Label },
	objectives: { Objective },
	deployZones: { [string]: Rect },
	valley: { x0: number, x1: number, floor: number }?,
}

local IDS = Config.TerrainIds
local MapGen = {}

local function v(x: number, z: number): Vec
	return { x = x, z = z }
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Lattice hashes are memoised per generate() call: neighbouring cells share corners, and the
-- hash dominates pass 1 otherwise. Keys are exact integers so results stay deterministic.
local memo: { [number]: number } = {}
local function corner(ix: number, iz: number, seed: number): number
	local key = (seed * 8192 + iz + 4096) * 8192 + ix + 4096
	local h = memo[key]
	if h == nil then
		h = RNG.hash(ix, iz, seed)
		memo[key] = h
	end
	return h
end

-- Value noise in [0,1).
local function noise(x: number, z: number, scale: number, seed: number): number
	local fx, fz = x / scale, z / scale
	local ix, iz = math.floor(fx), math.floor(fz)
	local tx, tz = smooth(fx - ix), smooth(fz - iz)
	local a = corner(ix, iz, seed)
	local b = corner(ix + 1, iz, seed)
	local c = corner(ix, iz + 1, seed)
	local d = corner(ix + 1, iz + 1, seed)
	local top = a + (b - a) * tx
	local bottom = c + (d - c) * tx
	return top + (bottom - top) * tz
end

-- Irregular ellipse membership in [0, inf): < 1 inside.
local function blobDistance(p: Vec, pos: Vec, rx: number, rz: number, seed: number): number
	local dx, dz = (p.x - pos.x) / rx, (p.z - pos.z) / rz
	local d = math.sqrt(dx * dx + dz * dz)
	local wobble = (noise(p.x, p.z, 48, seed) - 0.5) * 0.5
	return d + wobble
end

local function bbox(points: { Vec }, pad: number): Rect
	local r = { x0 = math.huge, z0 = math.huge, x1 = -math.huge, z1 = -math.huge }
	for _, p in points do
		r.x0 = math.min(r.x0, p.x - pad)
		r.z0 = math.min(r.z0, p.z - pad)
		r.x1 = math.max(r.x1, p.x + pad)
		r.z1 = math.max(r.z1, p.z + pad)
	end
	return r
end

local function inRect(r: Rect, x: number, z: number): boolean
	return x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1
end

-- ---------------------------------------------------------------------------------------------
-- Authored maps. Jena: condensed, historically inspired, not a survey. +z is north.
-- ---------------------------------------------------------------------------------------------
local MAPS: { [string]: MapDef } = {}

MAPS.jena = {
	name = "Jena, 14 October 1806 (condensed)",
	seed = 1806,
	baseHeight = 22,
	hills = {
		{ name = "Landgrafenberg", pos = v(800, 230), rx = 430, rz = 180, h = 36, k = 0.35 },
		{ name = "Windknollen", pos = v(430, 340), rx = 120, rz = 95, h = 22, k = 0.6 },
		{ name = "Dornberg", pos = v(1180, 700), rx = 175, rz = 125, h = 26, k = 0.5 },
		{ pos = v(980, 560), rx = 130, rz = 75, h = 8, k = 0.8 },
		{ name = "Isserstedt heights", pos = v(300, 1000), rx = 270, rz = 170, h = 18, k = 0.7 },
		{ pos = v(900, 1120), rx = 520, rz = 100, h = 14, k = 0.7 },
	},
	villages = {
		{ name = "Jena", pos = v(1400, 150), radius = 80, count = 40 },
		{ name = "Closewitz", pos = v(1000, 520), radius = 46, count = 16 },
		{ name = "Cospeda", pos = v(540, 470), radius = 46, count = 16 },
		{ name = "Lützeroda", pos = v(330, 600), radius = 40, count = 12 },
		{ name = "Vierzehnheiligen", pos = v(760, 760), radius = 52, count = 20 },
		{ name = "Isserstedt", pos = v(330, 880), radius = 48, count = 16 },
		{ name = "Krippendorf", pos = v(830, 1040), radius = 42, count = 14 },
		{ name = "Kapellendorf", pos = v(170, 1120), radius = 40, count = 12 },
	},
	woods = {
		{ name = "Isserstedt Wood", pos = v(200, 760), rx = 150, rz = 110 },
		{ pos = v(1130, 440), rx = 110, rz = 80 },
		{ pos = v(380, 150), rx = 140, rz = 70 },
		{ pos = v(1260, 880), rx = 120, rz = 90 },
		{ pos = v(600, 900), rx = 70, rz = 50 },
		{ pos = v(1400, 1100), rx = 100, rz = 80 },
	},
	roads = {
		{ points = { v(1600, 150), v(1400, 150), v(1250, 300), v(1000, 520), v(760, 760), v(830, 1040), v(850, 1200) }, width = 6 },
		{ points = { v(1400, 150), v(1100, 120), v(800, 180), v(540, 470), v(330, 600), v(330, 880), v(170, 1120) }, width = 6 },
		{ points = { v(330, 600), v(560, 700), v(760, 760) }, width = 5 },
		{ points = { v(1000, 520), v(1180, 700), v(1300, 820), v(1600, 820) }, width = 6 },
		{ points = { v(330, 880), v(600, 930), v(830, 1040) }, width = 5 },
		{ points = { v(0, 600), v(330, 600) }, width = 5 },
	},
	rivers = {
		{ name = "Saale", points = { v(1500, 0), v(1520, 250), v(1490, 500), v(1530, 750), v(1500, 1000), v(1520, 1200) }, width = 52, level = 1 },
		{ name = "Rau-Bach", points = { v(0, 1010), v(250, 990), v(520, 960), v(800, 940), v(1100, 980), v(1340, 1000), v(1500, 1000) }, width = 14, level = 18 },
	},
	bridges = {
		{ a = v(1440, 150), b = v(1580, 150), width = 24 },
		{ a = v(1440, 820), b = v(1590, 820), width = 24 },
		{ a = v(818, 915), b = v(834, 975), width = 24 },
		{ a = v(330, 960), b = v(330, 1020), width = 24 },
	},
	labels = {
		{ text = "Landgrafenberg", pos = v(800, 250), size = 1.4 },
		{ text = "Windknollen", pos = v(430, 340), size = 1.0 },
		{ text = "Dornberg", pos = v(1180, 700), size = 1.1 },
		{ text = "Saale", pos = v(1560, 450), size = 1.0 },
		{ text = "Isserstedt Wood", pos = v(200, 760), size = 0.9 },
	},
	objectives = {
		{ id = "vierzehnheiligen", name = "Vierzehnheiligen", pos = v(760, 760), radius = 60 },
		{ id = "closewitz", name = "Closewitz", pos = v(1000, 520), radius = 60 },
		{ id = "dornberg", name = "Dornberg", pos = v(1180, 700), radius = 60 },
	},
	deployZones = {
		france = { x0 = 350, z0 = 60, x1 = 1300, z1 = 380 },
		prussia = { x0 = 250, z0 = 480, x1 = 1300, z1 = 920 },
	},
	valley = { x0 = 1340, x1 = 1460, floor = 3 },
}

-- Auerstedt: Davout's III Corps on the Hassenhausen plateau, Prussians arriving from the west
-- over the Lissbach, the Kösen bridge over the Saale in the French rear (south-east).
MAPS.auerstedt = {
	name = "Auerstedt, 14 October 1806 (condensed)",
	seed = 1406,
	width = 2000,
	depth = 1504, -- 1500 rounded to the nav grid
	baseHeight = 20,
	hills = {
		{ name = "Eckartsberg", pos = v(280, 950), rx = 300, rz = 260, h = 28, k = 0.6 },
		{ name = "Sonnenkuppe", pos = v(480, 420), rx = 220, rz = 170, h = 24, k = 0.55 },
		{ name = "Hassenhausen plateau", pos = v(1150, 700), rx = 420, rz = 300, h = 10, k = 0.8 },
		{ name = "Spielberg rise", pos = v(1300, 1150), rx = 220, rz = 150, h = 12, k = 0.7 },
	},
	villages = {
		{ name = "Hassenhausen", pos = v(1150, 700), radius = 55, count = 20 },
		{ name = "Poppel", pos = v(690, 1060), radius = 45, count = 14 },
		{ name = "Spielberg", pos = v(1280, 1130), radius = 42, count = 12 },
		{ name = "Taugwitz", pos = v(690, 470), radius = 40, count = 12 },
		{ name = "Kösen", pos = v(1830, 200), radius = 45, count = 14 },
		{ name = "Rehausen", pos = v(1520, 980), radius = 38, count = 10 },
		{ name = "Eckartsberga", pos = v(250, 1300), radius = 50, count = 18 },
		{ name = "Gernstedt", pos = v(1050, 1350), radius = 36, count = 10 },
	},
	woods = {
		{ pos = v(420, 700), rx = 120, rz = 90 },
		{ pos = v(1500, 1250), rx = 130, rz = 90 },
		{ pos = v(1750, 600), rx = 110, rz = 80 },
		{ pos = v(900, 1250), rx = 90, rz = 60 },
		{ pos = v(1350, 150), rx = 120, rz = 70 },
		{ pos = v(150, 300), rx = 100, rz = 80 },
	},
	roads = {
		{ points = { v(2000, 180), v(1830, 200), v(1750, 240), v(1650, 340), v(1400, 540), v(1150, 700), v(900, 760), v(750, 760), v(450, 820), v(0, 860) }, width = 6 },
		{ points = { v(1150, 700), v(1280, 1130), v(1050, 1350), v(1000, 1500) }, width = 5 },
		{ points = { v(690, 470), v(700, 760), v(690, 1060), v(250, 1300) }, width = 5 },
		{ points = { v(690, 1060), v(750, 1000), v(1150, 700) }, width = 5 },
		{ points = { v(690, 470), v(750, 520), v(1150, 700) }, width = 5 },
		{ points = { v(1150, 700), v(1520, 980), v(2000, 1050) }, width = 5 },
	},
	rivers = {
		{ name = "Saale", points = { v(1560, 0), v(1620, 200), v(1780, 380), v(2000, 520) }, width = 50, level = 10 },
		{ name = "Lissbach", points = { v(740, 0), v(750, 520), v(750, 760), v(750, 1000), v(770, 1500) }, width = 12, level = 17 },
	},
	bridges = {
		{ a = v(1650, 340), b = v(1750, 240), width = 24 },
		{ a = v(720, 760), b = v(780, 760), width = 28 },
		{ a = v(720, 1000), b = v(780, 1000), width = 28 },
		{ a = v(720, 520), b = v(780, 520), width = 28 },
	},
	labels = {
		{ text = "Sonnenkuppe", pos = v(480, 420), size = 1.2 },
		{ text = "Eckartsberg", pos = v(280, 950), size = 1.2 },
		{ text = "Saale", pos = v(1700, 440), size = 1.0 },
		{ text = "Lissbach", pos = v(760, 900), size = 0.9 },
	},
	objectives = {
		{ id = "hassenhausen", name = "Hassenhausen", pos = v(1150, 700), radius = 60 },
		{ id = "poppel", name = "Poppel", pos = v(690, 1060), radius = 60 },
		{ id = "koesen", name = "Kösen bridge", pos = v(1700, 290), radius = 60 },
	},
	deployZones = {
		france = { x0 = 900, z0 = 320, x1 = 1760, z1 = 950 },
		prussia = { x0 = 60, z0 = 250, x1 = 620, z1 = 1350 },
	},
	valley = nil,
}

-- Austerlitz: the Goldbach and its villages west of centre, the Pratzen plateau in the middle,
-- the Santon in the north-west, the frozen Satschan ponds in the south.
MAPS.austerlitz = {
	name = "Austerlitz, 2 December 1805 (condensed)",
	seed = 1205,
	width = 2400,
	depth = 1792, -- 1800 rounded to the nav grid
	baseHeight = 18,
	hills = {
		{ name = "Pratzen Heights", pos = v(1450, 900), rx = 400, rz = 520, h = 30, k = 0.45 },
		{ name = "Staré Vinohrady", pos = v(1480, 1250), rx = 150, rz = 110, h = 10, k = 0.6 },
		{ name = "Pratzeberg", pos = v(1420, 600), rx = 150, rz = 110, h = 9, k = 0.6 },
		{ name = "Santon", pos = v(600, 1600), rx = 100, rz = 90, h = 22, k = 0.6 },
		{ name = "Zuran", pos = v(450, 1250), rx = 200, rz = 160, h = 18, k = 0.6 },
		{ pos = v(300, 600), rx = 350, rz = 300, h = 10, k = 0.7 },
		{ pos = v(1900, 1200), rx = 300, rz = 250, h = 12, k = 0.7 },
		{ pos = v(1300, 450), rx = 200, rz = 120, h = 8, k = 0.7 },
	},
	villages = {
		{ name = "Pratzen", pos = v(1330, 880), radius = 48, count = 16 },
		{ name = "Sokolnitz", pos = v(870, 450), radius = 52, count = 18 },
		{ name = "Telnitz", pos = v(940, 170), radius = 45, count = 14 },
		{ name = "Kobelnitz", pos = v(830, 760), radius = 42, count = 12 },
		{ name = "Puntowitz", pos = v(800, 1050), radius = 42, count = 12 },
		{ name = "Girzikowitz", pos = v(690, 1310), radius = 40, count = 12 },
		{ name = "Bosenitz", pos = v(650, 1480), radius = 38, count = 10 },
		{ name = "Augezd", pos = v(1250, 300), radius = 44, count = 14 },
		{ name = "Blasowitz", pos = v(1500, 1450), radius = 44, count = 14 },
		{ name = "Krzenowitz", pos = v(1800, 1300), radius = 46, count = 16 },
		{ name = "Holubitz", pos = v(1250, 1600), radius = 36, count = 10 },
		{ name = "Austerlitz", pos = v(2250, 760), radius = 70, count = 30 },
		{ name = "Schlapanitz", pos = v(350, 1050), radius = 44, count = 14 },
	},
	woods = {
		{ name = "Sokolnitz pheasantry", pos = v(930, 560), rx = 60, rz = 70 },
		{ pos = v(380, 1450), rx = 120, rz = 80 },
		{ pos = v(1900, 500), rx = 140, rz = 100 },
		{ pos = v(2100, 1500), rx = 150, rz = 100 },
		{ pos = v(1050, 1700), rx = 120, rz = 60 },
		{ pos = v(150, 300), rx = 120, rz = 90 },
		{ pos = v(1700, 150), rx = 110, rz = 70 },
	},
	roads = {
		{ points = { v(0, 1480), v(450, 1500), v(735, 1550), v(1000, 1580), v(1250, 1600), v(1700, 1650), v(2400, 1700) }, width = 6 },
		{ points = { v(0, 1100), v(350, 1050), v(745, 1050), v(800, 1050), v(1330, 880), v(1800, 820), v(2250, 760), v(2400, 740) }, width = 6 },
		{ points = { v(800, 1050), v(830, 760), v(870, 450), v(940, 170), v(1000, 0) }, width = 5 },
		{ points = { v(870, 450), v(1250, 300), v(1700, 350), v(2250, 760) }, width = 5 },
		{ points = { v(1330, 880), v(1500, 1450), v(1800, 1300), v(2400, 1250) }, width = 5 },
		{ points = { v(350, 1050), v(450, 1500) }, width = 5 },
		{ points = { v(0, 520), v(350, 620), v(777, 750), v(830, 760) }, width = 5 },
		{ points = { v(0, 150), v(500, 160), v(878, 180), v(940, 170) }, width = 5 },
		{ points = { v(650, 1480), v(690, 1310), v(730, 1300), v(800, 1050) }, width = 5 },
	},
	rivers = {
		{ name = "Goldbach", points = { v(740, 1800), v(730, 1300), v(745, 1050), v(777, 750), v(817, 450), v(878, 180), v(940, 0) }, width = 16, level = 14 },
		{ name = "Satschan pond", points = { v(1300, 110), v(1500, 90) }, width = 170, level = 9 },
		{ name = "Mönitz pond", points = { v(1000, 40), v(1150, 60) }, width = 110, level = 9 },
	},
	bridges = {
		{ a = v(703, 1550), b = v(767, 1550), width = 26 },
		{ a = v(698, 1300), b = v(762, 1300), width = 26 },
		{ a = v(713, 1050), b = v(777, 1050), width = 26 },
		{ a = v(745, 750), b = v(809, 750), width = 26 },
		{ a = v(785, 450), b = v(849, 450), width = 26 },
		{ a = v(846, 180), b = v(910, 180), width = 26 },
	},
	labels = {
		{ text = "Pratzen Heights", pos = v(1450, 960), size = 1.4 },
		{ text = "Staré Vinohrady", pos = v(1480, 1250), size = 0.9 },
		{ text = "Santon", pos = v(600, 1600), size = 1.0 },
		{ text = "Zuran", pos = v(450, 1250), size = 1.0 },
		{ text = "Goldbach", pos = v(760, 900), size = 0.9 },
		{ text = "Satschan ponds", pos = v(1400, 100), size = 1.0 },
	},
	objectives = {
		{ id = "pratzen", name = "Pratzen Heights", pos = v(1450, 900), radius = 70 },
		{ id = "sokolnitz", name = "Sokolnitz", pos = v(870, 450), radius = 60 },
		{ id = "santon", name = "Santon", pos = v(600, 1600), radius = 60 },
	},
	deployZones = {
		france = { x0 = 60, z0 = 120, x1 = 660, z1 = 1700 },
		russia = { x0 = 1000, z0 = 200, x1 = 2330, z1 = 1720 },
	},
	valley = nil,
}

-- Waterloo: two east-west ridges, the Brussels road through the middle, Hougoumont and La Haye
-- Sainte in front of the Anglo-allied line, Plancenoit and the Bois de Paris in the south-east.
MAPS.waterloo = {
	name = "Waterloo, 18 June 1815 (condensed)",
	seed = 1815,
	width = 2400,
	depth = 1600,
	baseHeight = 20,
	hills = {
		{ name = "Mont-Saint-Jean ridge", pos = v(1200, 1060), rx = 1100, rz = 170, h = 20, k = 0.6 },
		{ pos = v(1200, 1080), rx = 250, rz = 120, h = 6, k = 0.8 },
		{ name = "La Belle Alliance ridge", pos = v(1200, 440), rx = 1000, rz = 160, h = 14, k = 0.6 },
		{ name = "Rossomme", pos = v(1200, 200), rx = 500, rz = 140, h = 8, k = 0.7 },
		{ pos = v(2100, 1300), rx = 300, rz = 200, h = 8, k = 0.7 },
	},
	villages = {
		{ name = "La Haye Sainte", pos = v(1200, 920), radius = 32, count = 7 },
		{ name = "Hougoumont", pos = v(760, 790), radius = 52, count = 14 },
		{ name = "Papelotte", pos = v(1760, 950), radius = 38, count = 10 },
		{ name = "La Haye", pos = v(1860, 990), radius = 28, count = 6 },
		{ name = "Frichermont", pos = v(2080, 900), radius = 36, count = 10 },
		{ name = "Plancenoit", pos = v(1650, 290), radius = 50, count = 18 },
		{ name = "La Belle Alliance", pos = v(1200, 470), radius = 26, count = 5 },
		{ name = "Rossomme", pos = v(1200, 190), radius = 28, count = 6 },
		{ name = "Mont-Saint-Jean", pos = v(1200, 1320), radius = 44, count = 14 },
		{ name = "Braine-l'Alleud", pos = v(280, 1330), radius = 64, count = 24 },
		{ name = "Merbe-Braine", pos = v(560, 1260), radius = 36, count = 10 },
		{ name = "Smohain", pos = v(1920, 1050), radius = 28, count = 6 },
	},
	woods = {
		{ name = "Hougoumont wood", pos = v(770, 680), rx = 95, rz = 65 },
		{ name = "Bois de Paris", pos = v(2150, 480), rx = 170, rz = 190 },
		{ pos = v(2080, 760), rx = 70, rz = 60 },
		{ name = "Forêt de Soignes", pos = v(1200, 1575), rx = 1300, rz = 55 },
		{ pos = v(400, 500), rx = 90, rz = 60 },
		{ pos = v(1500, 150), rx = 80, rz = 50 },
	},
	roads = {
		{ points = { v(1200, 0), v(1200, 190), v(1200, 470), v(1200, 920), v(1200, 1060), v(1200, 1320), v(1200, 1600) }, width = 8 },
		{ points = { v(150, 1010), v(560, 1040), v(900, 1060), v(1200, 1060), v(1500, 1050), v(1760, 1010), v(1980, 960), v(2250, 920) }, width = 8 },
		{ points = { v(1200, 1060), v(900, 1200), v(560, 1260), v(280, 1330), v(0, 1380) }, width = 6 },
		{ points = { v(760, 790), v(900, 1060) }, width = 4 },
		{ points = { v(760, 790), v(560, 1040) }, width = 4 },
		{ points = { v(1200, 470), v(1650, 290), v(2000, 200), v(2400, 150) }, width = 5 },
		{ points = { v(1760, 950), v(1860, 990), v(1950, 950), v(2080, 900), v(2400, 850) }, width = 5 },
		{ points = { v(1650, 290), v(2050, 800), v(2150, 1300) }, width = 4 },
	},
	rivers = {
		{ name = "Smohain brook", points = { v(1900, 1150), v(1950, 950), v(2050, 800), v(2250, 650), v(2400, 560) }, width = 10, level = 17 },
	},
	bridges = {
		{ a = v(1915, 950), b = v(1985, 950), width = 24 },
		{ a = v(2015, 790), b = v(2085, 810), width = 24 },
	},
	labels = {
		{ text = "Mont-Saint-Jean ridge", pos = v(1200, 1130), size = 1.4 },
		{ text = "Chemin d'Ohain", pos = v(900, 1080), size = 0.9 },
		{ text = "La Belle Alliance ridge", pos = v(1000, 420), size = 1.1 },
		{ text = "Bois de Paris", pos = v(2150, 480), size = 1.0 },
		{ text = "Forêt de Soignes", pos = v(1200, 1560), size = 1.0 },
	},
	objectives = {
		{ id = "lahayesainte", name = "La Haye Sainte", pos = v(1200, 920), radius = 60 },
		{ id = "hougoumont", name = "Hougoumont", pos = v(760, 790), radius = 60 },
		{ id = "crossroads", name = "Mont-Saint-Jean crossroads", pos = v(1200, 1060), radius = 60 },
	},
	deployZones = {
		france = { x0 = 150, z0 = 120, x1 = 2250, z1 = 640 },
		britain = { x0 = 150, z0 = 720, x1 = 2250, z1 = 1440 },
	},
	valley = nil,
}

-- Compact variants for the campaign (Release B) reuse the same generator with smaller feature sets.
MAPS.bridge = {
	name = "Camsdorf bridge approach",
	seed = 2201,
	baseHeight = 20,
	hills = {
		{ name = "Eastern rise", pos = v(1250, 600), rx = 300, rz = 260, h = 20, k = 0.6 },
		{ name = "Western rise", pos = v(300, 600), rx = 260, rz = 260, h = 16, k = 0.6 },
	},
	villages = { { name = "Camsdorf", pos = v(920, 620), radius = 50, count = 18 }, { name = "Wenigenjena", pos = v(660, 520), radius = 44, count = 14 } },
	woods = { { pos = v(420, 980), rx = 150, rz = 100 }, { pos = v(1200, 220), rx = 140, rz = 90 } },
	roads = {
		{ points = { v(0, 600), v(660, 520), v(760, 600), v(920, 620), v(1600, 640) }, width = 6 },
		{ points = { v(660, 520), v(700, 1200) }, width = 5 },
	},
	rivers = { { name = "Saale", points = { v(800, 0), v(790, 400), v(810, 800), v(790, 1200) }, width = 50, level = 1 } },
	bridges = { { a = v(740, 600), b = v(860, 605), width = 24 } },
	labels = { { text = "Saale", pos = v(800, 300), size = 1.0 } },
	objectives = { { id = "bridge", name = "Camsdorf bridge", pos = v(800, 602), radius = 60 }, { id = "camsdorf", name = "Camsdorf", pos = v(920, 620), radius = 60 } },
	deployZones = {
		france = { x0 = 60, z0 = 200, x1 = 620, z1 = 1000 },
		prussia = { x0 = 900, z0 = 200, x1 = 1540, z1 = 1000 },
	},
	valley = nil,
}

MAPS.village = {
	name = "Defence of Vierzehnheiligen",
	seed = 3307,
	baseHeight = 24,
	hills = {
		{ name = "Village rise", pos = v(800, 700), rx = 260, rz = 180, h = 14, k = 0.6 },
		{ pos = v(800, 150), rx = 500, rz = 160, h = 18, k = 0.5 },
	},
	villages = { { name = "Vierzehnheiligen", pos = v(800, 700), radius = 60, count = 24 }, { name = "Krippendorf", pos = v(500, 1050), radius = 42, count = 14 } },
	woods = { { pos = v(260, 600), rx = 160, rz = 120 }, { pos = v(1330, 760), rx = 150, rz = 110 } },
	roads = {
		{ points = { v(800, 0), v(800, 700), v(500, 1050), v(480, 1200) }, width = 6 },
		{ points = { v(0, 760), v(800, 700), v(1600, 720) }, width = 5 },
	},
	rivers = {},
	bridges = {},
	labels = {},
	objectives = { { id = "village", name = "Vierzehnheiligen", pos = v(800, 700), radius = 60 } },
	deployZones = {
		france = { x0 = 200, z0 = 60, x1 = 1400, z1 = 380 },
		prussia = { x0 = 300, z0 = 560, x1 = 1300, z1 = 1000 },
	},
	valley = nil,
}

-- Tutorial field: a ridge, a wood, a stream with one bridge and a village beyond it. Small on
-- purpose (1024 x 800) so every lesson happens within a camera's reach.
MAPS.tutorial = {
	name = "Training ground (tutorial)",
	seed = 1809,
	width = 1024,
	depth = 800,
	baseHeight = 20,
	hills = {
		{ name = "The ridge", pos = v(420, 330), rx = 260, rz = 70, h = 12, k = 0.7 },
		{ pos = v(620, 740), rx = 220, rz = 90, h = 6, k = 0.8 },
	},
	villages = { { name = "Ebersdorf", pos = v(620, 690), radius = 50, count = 18 } },
	woods = { { name = "Fasanerie wood", pos = v(220, 650), rx = 110, rz = 70 } },
	roads = { { points = { v(620, 0), v(600, 300), v(620, 540), v(620, 690), v(640, 800) }, width = 6 } },
	rivers = { { name = "Mühlbach", points = { v(0, 560), v(300, 548), v(620, 540), v(1024, 530) }, width = 12, level = 16 } },
	bridges = { { a = v(620, 510), b = v(620, 570), width = 24 } },
	labels = {
		{ text = "The ridge", pos = v(420, 330), size = 1.0 },
		{ text = "Mühlbach", pos = v(900, 520), size = 0.8 },
	},
	objectives = { { id = "ebersdorf", name = "Ebersdorf", pos = v(620, 690), radius = 60 } },
	deployZones = {
		france = { x0 = 60, z0 = 40, x1 = 600, z1 = 260 },
		austria = { x0 = 300, z0 = 380, x1 = 1000, z1 = 780 },
	},
	valley = nil,
}

-- Episode maps (quick battles, Scenarios `mode = "episode"`): the same ground as a full battle
-- (same features and seed, so an identical grid) with their own deployment zones and objectives.
-- Home edges are north/south (Sim.homeEdge): each side's zone centre stays on its own half.
local function episode(base: string, objectives: { Objective }, zones: { [string]: Rect }): MapDef
	local d = table.clone(MAPS[base])
	d.objectives = objectives
	d.deployZones = zones
	return d
end

MAPS.austerlitz_pratzen = episode("austerlitz", {
	{ id = "pratzen", name = "Pratzen Heights", pos = v(1450, 900), radius = 70 },
	{ id = "vinohrady", name = "Staré Vinohrady", pos = v(1480, 1250), radius = 60 },
}, { france = { x0 = 800, z0 = 560, x1 = 1120, z1 = 1000 }, russia = { x0 = 1360, z0 = 900, x1 = 1950, z1 = 1400 } })
MAPS.austerlitz_sokolnitz = episode("austerlitz", {
	{ id = "sokolnitz", name = "Sokolnitz", pos = v(870, 450), radius = 60 },
	{ id = "telnitz", name = "Telnitz", pos = v(940, 170), radius = 60 },
}, { france = { x0 = 480, z0 = 120, x1 = 960, z1 = 600 }, russia = { x0 = 1040, z0 = 700, x1 = 1560, z1 = 1100 } })
MAPS.jena_vierzehnheiligen = episode("jena", {
	{ id = "vierzehnheiligen", name = "Vierzehnheiligen", pos = v(760, 760), radius = 60 },
}, { france = { x0 = 450, z0 = 420, x1 = 1120, z1 = 640 }, prussia = { x0 = 400, z0 = 830, x1 = 1150, z1 = 920 } })
MAPS.jena_landgrafenberg = episode("jena", {
	{ id = "closewitz", name = "Closewitz", pos = v(1000, 520), radius = 60 },
	{ id = "cospeda", name = "Cospeda", pos = v(540, 470), radius = 60 },
}, { france = { x0 = 550, z0 = 100, x1 = 1200, z1 = 360 }, prussia = { x0 = 420, z0 = 440, x1 = 1280, z1 = 800 } })
MAPS.auerstedt_hassenhausen = episode("auerstedt", {
	{ id = "hassenhausen", name = "Hassenhausen", pos = v(1150, 700), radius = 60 },
	{ id = "lissbach", name = "Lissbach bridge", pos = v(750, 760), radius = 60 },
}, { france = { x0 = 950, z0 = 480, x1 = 1420, z1 = 920 }, prussia = { x0 = 260, z0 = 420, x1 = 920, z1 = 1150 } })
MAPS.auerstedt_spielberg = episode("auerstedt", {
	{ id = "spielberg", name = "Spielberg", pos = v(1280, 1130), radius = 60 },
	{ id = "poppel", name = "Poppel", pos = v(690, 1060), radius = 60 },
}, { france = { x0 = 1250, z0 = 500, x1 = 1700, z1 = 980 }, prussia = { x0 = 260, z0 = 880, x1 = 660, z1 = 1380 } })
MAPS.waterloo_hougoumont = episode("waterloo", {
	{ id = "hougoumont", name = "Hougoumont", pos = v(760, 790), radius = 60 },
}, { france = { x0 = 420, z0 = 360, x1 = 1120, z1 = 600 }, britain = { x0 = 560, z0 = 730, x1 = 1060, z1 = 1160 } })
MAPS.waterloo_lahayesainte = episode("waterloo", {
	{ id = "lahayesainte", name = "La Haye Sainte", pos = v(1200, 920), radius = 60 },
	{ id = "crossroads", name = "Mont-Saint-Jean crossroads", pos = v(1200, 1060), radius = 60 },
}, { france = { x0 = 880, z0 = 400, x1 = 1520, z1 = 640 }, britain = { x0 = 940, z0 = 880, x1 = 1500, z1 = 1260 } })

function MapGen.list(): { string }
	return { "jena", "auerstedt", "austerlitz", "waterloo", "bridge", "village" }
end

function MapGen.generate(mapId: string): MapData
	local def = MAPS[mapId]
	assert(def, "unknown map " .. tostring(mapId))
	local cell = Config.Map.CellSize
	local cols = (def.width or Config.Map.Width) // cell
	local rows = (def.depth or Config.Map.Depth) // cell
	local g = Grid.new(cols, rows, cell)
	local seed = def.seed
	memo = {}

	-- Precomputed bounding boxes for feature culling. Polylines are culled per segment so a
	-- road or river crossing the whole map does not cost a distance test on every cell.
	local hillBox: { Rect } = {}
	for i, h in def.hills do
		hillBox[i] = { x0 = h.pos.x - h.rx, z0 = h.pos.z - h.rz, x1 = h.pos.x + h.rx, z1 = h.pos.z + h.rz }
	end
	local woodBox: { Rect } = {}
	for i, w in def.woods do
		woodBox[i] = { x0 = w.pos.x - w.rx * 1.3, z0 = w.pos.z - w.rz * 1.3, x1 = w.pos.x + w.rx * 1.3, z1 = w.pos.z + w.rz * 1.3 }
	end
	type Seg = { a: Vec, b: Vec, box: Rect }
	local function segments(points: { Vec }, pad: number): { Seg }
		local out: { Seg } = {}
		for i = 1, #points - 1 do
			out[i] = { a = points[i], b = points[i + 1], box = bbox({ points[i], points[i + 1] }, pad) }
		end
		return out
	end
	local function nearest(segs: { Seg }, p: Vec): number
		local best = math.huge
		for _, s in segs do
			if inRect(s.box, p.x, p.z) then
				local d = Vec.distToSegment(p, s.a, s.b)
				if d < best then
					best = d
				end
			end
		end
		return best
	end
	local roadSegs: { { Seg } } = {}
	for i, r in def.roads do
		roadSegs[i] = segments(r.points, r.width)
	end
	local riverSegs: { { Seg } } = {}
	for i, r in def.rivers do
		riverSegs[i] = segments(r.points, r.width / 2 + 30)
	end
	local bridgeBox: { Rect } = {}
	for i, b in def.bridges do
		bridgeBox[i] = bbox({ b.a, b.b }, b.width / 2 + 2)
	end

	local function woodsInside(p: Vec, i: number): boolean
		local w = def.woods[i]
		return blobDistance(p, w.pos, w.rx, w.rz, seed + 11 + i) < 1
	end

	local function villageInside(p: Vec, i: number): boolean
		local vl = def.villages[i]
		local d = Vec.dist(p, vl.pos) / vl.radius
		return d + (noise(p.x, p.z, 30, seed + 31 + i) - 0.5) * 0.4 < 1
	end

	-- Pass 1: heights and classes.
	local heightArr = g.height
	local classArr = g.class
	for cz = 0, rows - 1 do
		for cx = 0, cols - 1 do
			local x = (cx + 0.5) * cell
			local z = (cz + 0.5) * cell
			local p = v(x, z)
			local h = def.baseHeight + (noise(x, z, 150, seed + 1) - 0.5) * 10 + (noise(x, z, 42, seed + 2) - 0.5) * 3
			for i, hill in def.hills do
				if inRect(hillBox[i], x, z) then
					local dx, dz = (x - hill.pos.x) / hill.rx, (z - hill.pos.z) / hill.rz
					local d = math.sqrt(dx * dx + dz * dz) + (noise(x, z, 90, seed + 100 + i) - 0.5) * 0.18
					if d < 1 then
						h += hill.h * smooth((1 - d) / hill.k)
					end
				end
			end
			if def.valley then
				local t = smooth((x - def.valley.x0) / (def.valley.x1 - def.valley.x0))
				h = h + (def.valley.floor - h) * t
			end
			local cls = IDS.open
			for i = 1, #def.woods do
				if inRect(woodBox[i], x, z) and woodsInside(p, i) then
					cls = IDS.woods
					break
				end
			end
			for i = 1, #def.villages do
				if Vec.dist2(p, def.villages[i].pos) < (def.villages[i].radius * 1.3) ^ 2 and villageInside(p, i) then
					cls = IDS.village
					break
				end
			end
			for i, river in def.rivers do
				local d = nearest(riverSegs[i], p)
				local half = river.width / 2
				if d < half then
					cls = IDS.water
					h = math.min(h, river.level - 3)
				elseif d < half + 24 then
					local t = smooth((d - half) / 24)
					h = math.min(h, (river.level + 0.5) + (h - (river.level + 0.5)) * t)
				end
			end
			for i, road in def.roads do
				if cls ~= IDS.village and cls ~= IDS.water and nearest(roadSegs[i], p) < road.width / 2 then
					cls = IDS.road
				end
			end
			for i, bridge in def.bridges do
				if inRect(bridgeBox[i], x, z) and Vec.distToSegment(p, bridge.a, bridge.b) < bridge.width / 2 then
					cls = IDS.bridge
					local hb = math.max(Grid.heightAt(g, bridge.a.x, bridge.a.z), 0)
					h = math.max(h, hb)
				end
			end
			local idx = cz * cols + cx + 1
			heightArr[idx] = h
			classArr[idx] = cls
		end
	end

	-- Bridges sit at bank height: resample now that heights exist.
	for i, bridge in def.bridges do
		local ha = Grid.heightAt(g, bridge.a.x, bridge.a.z)
		local hb = Grid.heightAt(g, bridge.b.x, bridge.b.z)
		local deck = math.max(ha, hb)
		local box = bridgeBox[i]
		local cx0, cz0 = Grid.cellOf(g, box.x0, box.z0)
		local cx1, cz1 = Grid.cellOf(g, box.x1, box.z1)
		for cz = cz0, cz1 do
			for cx = cx0, cx1 do
				local idx = cz * cols + cx + 1
				if classArr[idx] == IDS.bridge then
					local p = Grid.cellCenter(g, cx, cz)
					if Vec.distToSegment(p, bridge.a, bridge.b) < bridge.width / 2 then
						heightArr[idx] = deck
					end
				end
			end
		end
	end

	-- Pass 2: slope classes on natural ground.
	for cz = 0, rows - 1 do
		for cx = 0, cols - 1 do
			local idx = cz * cols + cx + 1
			local cls = classArr[idx]
			if cls == IDS.open or cls == IDS.woods then
				local p = Grid.cellCenter(g, cx, cz)
				local s = Grid.slopeMagnitude(g, p.x, p.z)
				if s > Config.Slope.Impassable then
					classArr[idx] = IDS.cliff
				elseif s > Config.Slope.Steep and cls == IDS.open then
					classArr[idx] = IDS.steep
				end
			end
		end
	end

	Grid.computeClearance(g)

	-- Feature lists for the client (trees, buildings) derived deterministically.
	local woods: { Woods } = {}
	for i, w in def.woods do
		local trees: { Tree } = {}
		local spacing = 9
		local x0 = math.floor((w.pos.x - w.rx * 1.3) / spacing) * spacing
		local z0 = math.floor((w.pos.z - w.rz * 1.3) / spacing) * spacing
		local x = x0
		while x <= w.pos.x + w.rx * 1.3 do
			local z = z0
			while z <= w.pos.z + w.rz * 1.3 do
				local jx = (RNG.hash(x, z, seed + 500 + i) - 0.5) * spacing * 0.9
				local jz = (RNG.hash(z, x, seed + 600 + i) - 0.5) * spacing * 0.9
				local px, pz = x + jx, z + jz
				if Grid.inBounds(g, px, pz) and Grid.classAt(g, px, pz) == IDS.woods then
					trees[#trees + 1] = {
						x = px,
						z = pz,
						r = 4.5 + RNG.hash(x, z, seed + 700) * 3.5,
						priority = RNG.hash(x, z, seed + 800),
					}
				end
				z += spacing
			end
			x += spacing
		end
		woods[i] = { name = w.name, pos = w.pos, rx = w.rx, rz = w.rz, trees = trees }
	end

	local villages: { Village } = {}
	for i, vl in def.villages do
		local buildings: { Building } = {}
		-- Houses line the road segments that pass through the village.
		for ri, road in def.roads do
			for si = 1, #road.points - 1 do
				local a, b = road.points[si], road.points[si + 1]
				local segLen = Vec.dist(a, b)
				local dir = Vec.normalize(Vec.sub(b, a))
				local right = Vec.right(dir)
				local s = 6
				while s < segLen do
					local c = Vec.add(a, Vec.scale(dir, s))
					if Vec.dist(c, vl.pos) < vl.radius then
						for side = -1, 1, 2 do
							local k = RNG.hash(ri * 1000 + si, math.floor(s), seed + 900 + side)
							if k < 0.8 then
								local off = side * (road.width / 2 + 6 + k * 4)
								local pos = Vec.add(c, Vec.scale(right, off))
								if Grid.inBounds(g, pos.x, pos.z) then
									local cls = Grid.classAt(g, pos.x, pos.z)
									if cls == IDS.village or cls == IDS.open then
										buildings[#buildings + 1] = {
											pos = pos,
											heading = Vec.heading(dir),
											w = 8 + k * 5,
											d = 6 + RNG.hash(math.floor(s), ri, seed + 950) * 4,
											h = 5 + RNG.hash(ri, math.floor(s), seed + 960) * 3,
										}
									end
								end
							end
						end
					end
					s += 14
				end
			end
		end
		-- Fill the rest of the quota with houses scattered around the centre.
		local attempts = 0
		while #buildings < vl.count and attempts < vl.count * 6 do
			attempts += 1
			local ang = RNG.hash(i, attempts, seed + 970) * math.pi * 2
			local rad = 10 + RNG.hash(attempts, i, seed + 980) * (vl.radius - 14)
			local pos = v(vl.pos.x + math.cos(ang) * rad, vl.pos.z + math.sin(ang) * rad)
			local ok = Grid.inBounds(g, pos.x, pos.z) and Grid.classAt(g, pos.x, pos.z) == IDS.village
			if ok then
				for _, bld in buildings do
					if Vec.dist2(bld.pos, pos) < 12 * 12 then
						ok = false
						break
					end
				end
			end
			if ok then
				buildings[#buildings + 1] = {
					pos = pos,
					heading = RNG.hash(attempts, i, seed + 990) * math.pi,
					w = 8 + RNG.hash(i, attempts, seed + 991) * 4,
					d = 6 + RNG.hash(i, attempts, seed + 992) * 3,
					h = 5 + RNG.hash(i, attempts, seed + 993) * 3,
				}
			end
		end
		villages[i] = { name = vl.name, pos = vl.pos, radius = vl.radius, buildings = buildings, count = vl.count }
	end

	local labels: { Label } = {}
	for _, l in def.labels do
		labels[#labels + 1] = l
	end
	for _, vl in def.villages do
		labels[#labels + 1] = { text = vl.name, pos = v(vl.pos.x, vl.pos.z - vl.radius - 14), size = 1.0 }
	end

	return {
		id = mapId,
		name = def.name,
		width = g.width,
		depth = g.depth,
		grid = g,
		hills = def.hills,
		villages = villages,
		woods = woods,
		roads = def.roads,
		rivers = def.rivers,
		bridges = def.bridges,
		labels = labels,
		objectives = def.objectives,
		deployZones = def.deployZones,
		seed = seed,
	}
end

function MapGen.inZone(map: MapData, faction: string, p: Vec): boolean
	local r = map.deployZones[faction]
	if not r then
		return false
	end
	return inRect(r, p.x, p.z)
end

return MapGen
