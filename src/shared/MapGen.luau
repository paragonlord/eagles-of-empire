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

-- Value noise in [0,1).
local function noise(x: number, z: number, scale: number, seed: number): number
	local fx, fz = x / scale, z / scale
	local ix, iz = math.floor(fx), math.floor(fz)
	local tx, tz = smooth(fx - ix), smooth(fz - iz)
	local a = RNG.hash(ix, iz, seed)
	local b = RNG.hash(ix + 1, iz, seed)
	local c = RNG.hash(ix, iz + 1, seed)
	local d = RNG.hash(ix + 1, iz + 1, seed)
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

local function polylineDistance(p: Vec, points: { Vec }): number
	local best = math.huge
	for i = 1, #points - 1 do
		local d = Vec.distToSegment(p, points[i], points[i + 1])
		if d < best then
			best = d
		end
	end
	return best
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
		{ a = v(1450, 150), b = v(1570, 150), width = 10 },
		{ a = v(1455, 820), b = v(1580, 820), width = 10 },
		{ a = v(820, 925), b = v(832, 965), width = 10 },
		{ a = v(330, 970), b = v(330, 1010), width = 10 },
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
	bridges = { { a = v(755, 600), b = v(850, 605), width = 10 } },
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

function MapGen.list(): { string }
	return { "jena", "bridge", "village" }
end

function MapGen.generate(mapId: string): MapData
	local def = MAPS[mapId]
	assert(def, "unknown map " .. tostring(mapId))
	local cell = Config.Map.CellSize
	local cols = Config.Map.Width // cell
	local rows = Config.Map.Depth // cell
	local g = Grid.new(cols, rows, cell)
	local seed = def.seed

	-- Precomputed bounding boxes for feature culling.
	local hillBox: { Rect } = {}
	for i, h in def.hills do
		hillBox[i] = { x0 = h.pos.x - h.rx, z0 = h.pos.z - h.rz, x1 = h.pos.x + h.rx, z1 = h.pos.z + h.rz }
	end
	local woodBox: { Rect } = {}
	for i, w in def.woods do
		woodBox[i] = { x0 = w.pos.x - w.rx * 1.3, z0 = w.pos.z - w.rz * 1.3, x1 = w.pos.x + w.rx * 1.3, z1 = w.pos.z + w.rz * 1.3 }
	end
	local roadBox: { Rect } = {}
	for i, r in def.roads do
		roadBox[i] = bbox(r.points, r.width)
	end
	local riverBox: { Rect } = {}
	for i, r in def.rivers do
		riverBox[i] = bbox(r.points, r.width / 2 + 30)
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
				if inRect(riverBox[i], x, z) then
					local d = polylineDistance(p, river.points)
					local half = river.width / 2
					if d < half then
						cls = IDS.water
						h = math.min(h, river.level - 3)
					elseif d < half + 24 then
						local t = smooth((d - half) / 24)
						h = math.min(h, (river.level + 0.5) + (h - (river.level + 0.5)) * t)
					end
				end
			end
			for i, road in def.roads do
				if inRect(roadBox[i], x, z) and cls ~= IDS.village and cls ~= IDS.water then
					if polylineDistance(p, road.points) < road.width / 2 then
						cls = IDS.road
					end
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
	for _, bridge in def.bridges do
		local ha = Grid.heightAt(g, bridge.a.x, bridge.a.z)
		local hb = Grid.heightAt(g, bridge.b.x, bridge.b.z)
		local deck = math.max(ha, hb)
		for cz = 0, rows - 1 do
			for cx = 0, cols - 1 do
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
