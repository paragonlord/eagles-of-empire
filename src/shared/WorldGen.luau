--!strict
-- Pure world generation: from MapData to (a) a terrain column sampler the voxel writer reads
-- and (b) a list of part specs. No instances are made here; WorldBuild instantiates specs,
-- the server the "s" (structure) tier once per match, the client the "d" (detail) tier.
-- Deterministic: every random choice is RNG.hash of map coordinates and the map seed.

local Config = require(script.Parent.Config)
local Vec = require(script.Parent.Vec)
local RNG = require(script.Parent.RNG)
local Grid = require(script.Parent.Grid)
local Assets = require(script.Parent.Assets)

local WorldGen = {}

local IDS = Config.TerrainIds
local VOXEL = 4
local SKIRT = 160 -- cells (640 studs) of continuing country around every map
local SKIRT_FADE = 420 -- studs over which the skirt relaxes to a gentle plain
WorldGen.VOXEL = VOXEL
WorldGen.SKIRT = SKIRT

export type Spec = {
	group: string, -- folder under the world root
	q: number, -- lowest quality that shows it (1..3)
	tier: string, -- "s" structure (server) | "d" detail (client)
	class: string, -- "Part" | "WedgePart"
	shape: EnumPartType?,
	mesh: boolean?, -- SpecialMesh Sphere child
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: EnumMaterial,
	transparency: number?,
	castShadow: boolean,
	canQuery: boolean?,
	name: string?,
	buried: boolean?, -- meant to sit in the ground (piers, plinths, planes): the clip check skips it
	fileMesh: string?, -- Assets slot key: WorldBuild renders this part as that mesh
	texture: string?, -- Assets slot key: WorldBuild textures the part's faces when the slot has one
}

export type Options = {
	maxQ: number?, -- skip specs needing a higher quality (default 3)
	structure: boolean?, -- emit the "s" tier (default true)
	detail: boolean?, -- emit the "d" tier (default true)
	yield: (() -> ())?, -- called between jobs (task.wait on the engine)
}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Value noise in [0, 1) for the skirt (cosmetic only; never read by gameplay).
local function noise(x: number, z: number, scale: number, seed: number): number
	local fx, fz = x / scale, z / scale
	local ix, iz = math.floor(fx), math.floor(fz)
	local tx, tz = smooth(fx - ix), smooth(fz - iz)
	local a = RNG.hash(ix, iz, seed)
	local b = RNG.hash(ix + 1, iz, seed)
	local c = RNG.hash(ix, iz + 1, seed)
	local d = RNG.hash(ix + 1, iz + 1, seed)
	local top = a + (b - a) * tx
	return top + ((c + (d - c) * tx) - top) * tz
end

local function materialFor(cls: number, isBank: boolean): EnumMaterial
	if cls == IDS.woods then
		return Enum.Material.LeafyGrass
	elseif cls == IDS.village then
		return Enum.Material.Ground
	elseif cls == IDS.road then
		return Enum.Material.Ground -- a thin dark dirt line; Cobblestone and pale Mud read as rubble/snow
	elseif cls == IDS.steep then
		return Enum.Material.Grass -- slopes read through shading, as in the reference
	elseif cls == IDS.cliff then
		return Enum.Material.Rock
	elseif isBank then
		return Enum.Material.Sand
	end
	return Enum.Material.Grass
end

------------------------------------------------------------------------------------- farmland

-- Fields are open-field strips: the country is cut into Voronoi blocks (~FIELD studs), each
-- block ploughed in parallel strips of one crop, the strips laid along the nearest road.
-- Block borders are hedges, walls, fences, cart tracks or nothing (props build the solid ones).
-- Materials: Grass = meadow (the olive-gold base), LeafyGrass = green pasture / gardens / woods
-- floor, Limestone = wheat or stubble, Mud = plough.
local FIELD = 165
local KIND_MEADOW, KIND_PASTURE, KIND_WHEAT, KIND_PLOUGH = 1, 2, 3, 4
WorldGen.KIND = { meadow = KIND_MEADOW, pasture = KIND_PASTURE, wheat = KIND_WHEAT, plough = KIND_PLOUGH }
WorldGen.FIELD = FIELD

export type Season = {
	crops: { number }, -- cumulative weights meadow, pasture, wheat, plough
	borders: { number }, -- cumulative weights hedge, wall, fence, track, (open)
	grass: { number },
	leafy: { number },
	wheat: { number },
	plough: { number },
	-- tints over the painted ground (MaterialService variants), whose maps carry their own colour:
	-- grass, leafy, wheat, plough (tuned by eye in Studio, round 40)
	painted: { { number } },
}
-- Jena/Auerstedt mid-October: stubble and fresh plough; Austerlitz December: plough and pale
-- winter grass, few hedges (open Moravian fields); Waterloo June: tall rye, green, hedged.
local SEASONS: { [string]: Season } = {
	autumn = {
		crops = { 0.30, 0.44, 0.70, 1.0 },
		borders = { 0.34, 0.44, 0.54, 0.76 },
		grass = { 126, 136, 62 },
		leafy = { 84, 106, 44 },
		wheat = { 150, 132, 86 }, -- Limestone renders far brighter: 178,162,104 read neon lime
		plough = { 98, 76, 54 },
		painted = { { 180, 172, 112 }, { 136, 150, 92 }, { 168, 148, 104 }, { 104, 98, 96 } },
	},
	winter = {
		crops = { 0.36, 0.50, 0.60, 1.0 },
		borders = { 0.10, 0.15, 0.25, 0.62 },
		grass = { 122, 126, 70 },
		leafy = { 86, 102, 52 },
		wheat = { 141, 133, 99 }, -- 0.84x: Limestone renders bright
		plough = { 90, 72, 56 },
		painted = { { 174, 159, 126 }, { 139, 144, 109 }, { 158, 149, 120 }, { 95, 93, 100 } },
	},
	summer = {
		crops = { 0.24, 0.44, 0.84, 1.0 },
		borders = { 0.46, 0.51, 0.66, 0.82 },
		grass = { 116, 136, 58 },
		leafy = { 76, 108, 42 },
		wheat = { 143, 134, 76 }, -- 0.84x: Limestone renders bright
		plough = { 104, 82, 58 },
		painted = { { 166, 172, 105 }, { 123, 153, 88 }, { 160, 150, 92 }, { 110, 106, 103 } },
	},
}
local MAP_SEASON: { [string]: string } = { austerlitz = "winter", waterloo = "summer" }
local season: Season = SEASONS.autumn
local fieldSeed = 1
local seedCache: { [number]: { number } } = {}
local angleCache: { [number]: number } = {}
local blockInfo: { [number]: { number } } = {} -- seed x, z, strip normal x, z, strip width, meadow
local fieldRoads: { any } = {}

function WorldGen.seasonOf(mapId: string?): string
	return MAP_SEASON[mapId or ""] or "autumn"
end

function WorldGen.season(mapId: string?): Season
	return SEASONS[WorldGen.seasonOf(mapId)]
end

local function blockKey(i: number, j: number): number
	return (i + 512) * 2048 + (j + 512)
end

-- Jittered lattice point of block (i, j).
local function blockSeed(i: number, j: number): (number, number)
	local k = blockKey(i, j)
	local c = seedCache[k]
	if not c then
		c = {
			(i + 0.5 + (RNG.hash(i, j, fieldSeed) - 0.5) * 0.7) * FIELD,
			(j + 0.5 + (RNG.hash(j, i, fieldSeed + 3) - 0.5) * 0.7) * FIELD,
		}
		seedCache[k] = c
	end
	return c[1], c[2]
end

-- Strip direction of a block: along the nearest road within 260 studs, else random.
local function blockAngle(i: number, j: number): number
	local k = blockKey(i, j)
	local a = angleCache[k]
	if a then
		return a
	end
	local sx, sz = blockSeed(i, j)
	local p = { x = sx, z = sz }
	local best = 260
	a = RNG.hash(i, j, fieldSeed + 9) * math.pi
	for _, road in fieldRoads do
		local pts = road.points
		for n = 1, #pts - 1 do
			local d = Vec.distToSegment(p, pts[n], pts[n + 1])
			if d < best then
				best = d
				a = math.atan2(pts[n + 1].z - pts[n].z, pts[n + 1].x - pts[n].x)
			end
		end
	end
	angleCache[k] = a
	return a
end

-- Border kind between two blocks: 1 hedge, 2 wall, 3 fence, 4 track, 5 open.
local function borderKind(i1: number, j1: number, i2: number, j2: number): number
	local a, b = blockKey(i1, j1), blockKey(i2, j2)
	local r = RNG.hash(math.min(a, b), math.max(a, b), fieldSeed + 21)
	for n, w in season.borders do
		if r < w then
			return n
		end
	end
	return 5
end

-- Nearest two blocks at (x, z) and the distance to their shared border. Consecutive calls
-- mostly fall in the same lattice cell, so its 3x3 seed neighbourhood is kept.
local lastCi, lastCj = math.huge, math.huge
local nbX: { number } = table.create(9, 0)
local nbZ: { number } = table.create(9, 0)
local function nearestBlocks(x: number, z: number): (number, number, number, number, number)
	local ci, cj = math.floor(x / FIELD), math.floor(z / FIELD)
	if ci ~= lastCi or cj ~= lastCj then
		lastCi, lastCj = ci, cj
		local n = 0
		for di = -1, 1 do
			for dj = -1, 1 do
				n += 1
				nbX[n], nbZ[n] = blockSeed(ci + di, cj + dj)
			end
		end
	end
	local b1, b2 = math.huge, math.huge
	local n1, n2 = 5, 5
	for n = 1, 9 do
		local d = (x - nbX[n]) ^ 2 + (z - nbZ[n]) ^ 2
		if d < b1 then
			b2, n2 = b1, n1
			b1, n1 = d, n
		elseif d < b2 then
			b2, n2 = d, n
		end
	end
	local sep = math.sqrt((nbX[n1] - nbX[n2]) ^ 2 + (nbZ[n1] - nbZ[n2]) ^ 2)
	-- n = (di + 1) * 3 + (dj + 1) + 1
	local i1, j1 = ci + (n1 - 1) // 3 - 1, cj + (n1 - 1) % 3 - 1
	local i2, j2 = ci + (n2 - 1) // 3 - 1, cj + (n2 - 1) % 3 - 1
	return i1, j1, i2, j2, (b2 - b1) / (2 * sep)
end

-- Crop kind at (x, z), whether it is a cart track on a block border, and the across-strip
-- coordinate (studs) for furrow rows.
local function fieldAt(x: number, z: number): (number, boolean, number)
	local i1, j1, i2, j2, edge = nearestBlocks(x, z)
	if edge < 4.5 then
		local kind = borderKind(i1, j1, i2, j2)
		if kind == 4 and edge < 2.2 then
			return KIND_MEADOW, true, 0
		elseif kind ~= 5 then
			return KIND_MEADOW, false, 0 -- grass headland under hedges, walls and fences
		end
	end
	local key = blockKey(i1, j1)
	local blk = blockInfo[key]
	if not blk then
		local sx, sz = blockSeed(i1, j1)
		local a = blockAngle(i1, j1)
		-- whole-block meadows keep the patchwork from getting busy
		blk = { sx, sz, -math.sin(a), math.cos(a), 15 + RNG.hash(key, 11, fieldSeed + 31) * 16, if RNG.hash(key, 7, fieldSeed + 30) < 0.2 then 1 else 0 }
		blockInfo[key] = blk
	end
	if blk[6] == 1 then
		return KIND_MEADOW, false, 0
	end
	-- across-strip coordinate
	local u = (x - blk[1]) * blk[3] + (z - blk[2]) * blk[4]
	local strip = math.floor(u / blk[5])
	local r = RNG.hash(key, strip, fieldSeed + 32)
	for n, w in season.crops do
		if r < w then
			return n, false, u
		end
	end
	return KIND_MEADOW, false, u
end
WorldGen.fieldAt = fieldAt

local FIELD_MATERIAL = { Enum.Material.Grass, Enum.Material.LeafyGrass, Enum.Material.Limestone, Enum.Material.Mud }

-- Field surface at (x, z): plough strips show furrow ridges as alternating rows of Mud and
-- Ground; stubble shows a paler row every third; the rest is the crop's material.
local function fieldMaterial(x: number, z: number): EnumMaterial
	local kind, track, u = fieldAt(x, z)
	if track then
		return Enum.Material.Ground
	elseif kind == KIND_PLOUGH then
		return if math.floor(u / VOXEL) % 2 == 0 then Enum.Material.Mud else Enum.Material.Ground
	elseif kind == KIND_WHEAT then
		return if math.floor(u / VOXEL) % 3 == 0 then Enum.Material.Sand else Enum.Material.Limestone
	end
	return FIELD_MATERIAL[kind]
end

-- Resets the field patchwork caches for a map (both the terrain model and the props read them).
local fieldsMap: any = nil
local function beginFields(map: any)
	fieldsMap = map
	season = SEASONS[WorldGen.seasonOf(map.id)]
	fieldSeed = (map.seed or 1) + 313
	fieldRoads = map.roads
	table.clear(seedCache)
	table.clear(angleCache)
	table.clear(blockInfo)
	lastCi, lastCj = math.huge, math.huge
end

-- Gameplay cover from the field borders (Sim/Combat): the hedge (1) or stone wall (2) within `reach`
-- studs of (x, z) that a shot from (fromX, fromZ) has to cross, else nil. Same lattice as the props.
function WorldGen.borderCover(map: any, x: number, z: number, fromX: number, fromZ: number, reach: number): number?
	if fieldsMap ~= map then
		beginFields(map)
	end
	local i1, j1, i2, j2, edge = nearestBlocks(x, z)
	if edge > reach then
		return nil
	end
	local kind = borderKind(i1, j1, i2, j2)
	if kind ~= 1 and kind ~= 2 then
		return nil
	end
	-- a step from the target toward the shooter lands in the other block: the shot crosses it
	local d = math.sqrt((fromX - x) ^ 2 + (fromZ - z) ^ 2)
	if d < 1 then
		return nil
	end
	local k = (reach + 4) / d
	local a1, b1, _, _ = nearestBlocks(x + (fromX - x) * k, z + (fromZ - z) * k)
	if a1 == i1 and b1 == j1 then
		return nil
	end
	return kind
end

-------------------------------------------------------------------------------- terrain model

-- Water surface level for a cell, or nil when the cell is not inside a river channel.
local function waterLevelAt(map: any, x: number, z: number): number?
	local best: number? = nil
	for _, river in map.rivers do
		local pts = river.points
		local half = river.width / 2 + 1
		for i = 1, #pts - 1 do
			if Vec.distToSegment({ x = x, z = z }, pts[i], pts[i + 1]) < half then
				if best == nil or river.level > best then
					best = river.level
				end
				break
			end
		end
	end
	return best
end

-- Road cells whose centre lies within the road's own half-width minus a margin: the painted
-- line is one cell wide, never wider than the road (MapGen classes a band around it).
local function roadCore(map: any, x: number, z: number): boolean
	local p = { x = x, z = z }
	for _, road in map.roads do
		local keep = math.max(road.width / 2 - 1, 1.5)
		local pts = road.points
		for i = 1, #pts - 1 do
			if Vec.distToSegment(p, pts[i], pts[i + 1]) <= keep then
				return true
			end
		end
	end
	return false
end

type Marks = { [number]: boolean }
type Dist = { [number]: number }
-- Precompute per-cell water level and bank flags (cheap: only water/bridge cells scan rivers).
local function analyse(map: any): ({ [number]: number }, Marks, Marks, Dist, Marks, Dist)
	local g = map.grid
	local cols, rows = g.cols, g.rows
	local water: { [number]: number } = {}
	local bank: Marks = {}
	local roadOff: Marks = {}
	local verge: Dist = {} -- cells from a road or village: no crops there, 1 = the ditch
	local street: Marks = {} -- road cores through villages, cobbled
	local wet: Dist = {} -- cells from water (3..6): damp meadow
	for cz = 0, rows - 1 do
		for cx = 0, cols - 1 do
			local idx = cz * cols + cx + 1
			local cls = g.class[idx]
			if cls == IDS.road and not roadCore(map, (cx + 0.5) * g.cell, (cz + 0.5) * g.cell) then
				roadOff[idx] = true
			end
			if cls == IDS.village and roadCore(map, (cx + 0.5) * g.cell, (cz + 0.5) * g.cell) then
				street[idx] = true
			end
			if cls == IDS.road or cls == IDS.village then
				local r = if cls == IDS.road then 2 else 3
				local core = cls == IDS.village or not roadOff[idx]
				for dz = -r, r do
					for dx = -r, r do
						local nx, nz = cx + dx, cz + dz
						if nx >= 0 and nz >= 0 and nx < cols and nz < rows then
							local j = nz * cols + nx + 1
							local d = if core then math.max(math.abs(dx), math.abs(dz)) else 2
							if verge[j] == nil or d < verge[j] then
								verge[j] = d
							end
						end
					end
				end
			end
			if cls == IDS.water or cls == IDS.bridge or cls == IDS.ford then
				local c = { x = (cx + 0.5) * g.cell, z = (cz + 0.5) * g.cell }
				local lvl = waterLevelAt(map, c.x, c.z)
				if lvl then
					water[idx] = lvl
					if cls == IDS.water then
						for dz = -6, 6 do
							for dx = -6, 6 do
								local nx, nz = cx + dx, cz + dz
								if nx >= 0 and nz >= 0 and nx < cols and nz < rows then
									local j = nz * cols + nx + 1
									local d = math.max(math.abs(dx), math.abs(dz))
									if g.class[j] == IDS.open then
										if d <= 2 then
											bank[j] = true
										elseif wet[j] == nil or d < wet[j] then
											wet[j] = d
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return water, bank, roadOff, verge, street, wet
end

export type Orchard = { x: number, z: number, a: number, hx: number, hz: number }

-- Orchard plots beside the villages: grass under the trees, props plant them.
local function planOrchards(map: any): { Orchard }
	local orchards: { Orchard } = {}
	local g = map.grid
	for vi, v in map.villages do
		local n = if v.count >= 14 then 2 else 1
		for k = 1, n do
			local ang = RNG.hash(vi, k, fieldSeed + 50) * math.pi * 2
			local d = v.radius + 34
			local x, z = v.pos.x + math.cos(ang) * d, v.pos.z + math.sin(ang) * d
			if x > 30 and z > 30 and x < map.width - 30 and z < map.depth - 30 then
				local ok = true
				for _, off in { { 0, 0 }, { 18, 0 }, { -18, 0 }, { 0, 12 }, { 0, -12 } } do
					local cls = Grid.classAt(g, x + off[1], z + off[2])
					if cls ~= IDS.open then
						ok = false
					end
				end
				if ok then
					table.insert(orchards, { x = x, z = z, a = ang, hx = 22, hz = 15 })
				end
			end
		end
	end
	return orchards
end

export type TerrainModel = {
	cols: number,
	rows: number,
	cell: number,
	minH: number,
	planeY: number, -- visible ground plane under the skirt's outer edge
	season: Season,
	orchards: { Orchard },
	-- Column at cell (cx, cz), possibly outside the map: ground height, material, water level.
	column: (cx: number, cz: number) -> (number, EnumMaterial, number?),
	-- Ground height anywhere terrain is written, and whether it is water.
	heightAt: (x: number, z: number) -> (number, boolean),
}

function WorldGen.terrain(map: any): TerrainModel
	beginFields(map)
	local orchards = planOrchards(map)
	local function inOrchard(x: number, z: number): boolean
		for _, o in orchards do
			local dx, dz = x - o.x, z - o.z
			if math.abs(dx) < 40 and math.abs(dz) < 40 then
				local c, s = math.cos(o.a), math.sin(o.a)
				if math.abs(dx * c + dz * s) < o.hx + 3 and math.abs(-dx * s + dz * c) < o.hz + 3 then
					return true
				end
			end
		end
		return false
	end

	local g = map.grid
	local cols, rows = g.cols, g.rows
	local cell = g.cell
	local minH = math.huge
	for i = 1, cols * rows do
		minH = math.min(minH, g.height[i])
	end
	local water, bank, roadOff, verge, street, wet = analyse(map)
	-- the skirt relaxes toward the mean height of the map border
	local edgeSum, edgeN = 0, 0
	for cx = 0, cols - 1 do
		edgeSum += g.height[cx + 1] + g.height[(rows - 1) * cols + cx + 1]
		edgeN += 2
	end
	for cz = 0, rows - 1 do
		edgeSum += g.height[cz * cols + 1] + g.height[cz * cols + cols]
		edgeN += 2
	end
	local plain = edgeSum / edgeN
	local seed = (map.seed or 1) + 77
	-- the ground plane sits under the skirt's noise and below any river channel leaving the map
	local planeY = plain - 16
	for _, river in map.rivers do
		planeY = math.min(planeY, river.level - 8)
	end

	-- River ends that touch the border, extended 800 studs outward along their last segment.
	local outs: { { a: { x: number, z: number }, b: { x: number, z: number }, half: number, level: number } } = {}
	for _, river in map.rivers do
		local pts = river.points
		for _, ends in { { pts[1], pts[2] }, { pts[#pts], pts[#pts - 1] } } do
			local e, prev = ends[1], ends[2]
			if e and prev then
				local nearEdge = e.x < 60 or e.z < 60 or e.x > map.width - 60 or e.z > map.depth - 60
				if nearEdge then
					local dir = Vec.normalize(Vec.sub(e, prev))
					table.insert(outs, { a = e, b = Vec.add(e, Vec.scale(dir, 800)), half = river.width / 2, level = river.level })
				end
			end
		end
	end
	local function riverOut(x: number, z: number): (number, number?, number)
		local best, lvl, half = math.huge, nil, 0
		for _, o in outs do
			local d = Vec.distToSegment({ x = x, z = z }, o.a, o.b)
			if d < best then
				best, lvl, half = d, o.level, o.half
			end
		end
		return best, lvl, half
	end

	local function column(cx: number, cz: number): (number, EnumMaterial, number?)
		if cx >= 0 and cz >= 0 and cx < cols and cz < rows then
			local idx = cz * cols + cx + 1
			local cls = g.class[idx]
			local lvl = water[idx]
			-- a bridge cell carries the deck height; its voxels are the river bed beneath
			local h = if cls == IDS.bridge and lvl ~= nil then lvl - 3 else g.height[idx]
			if roadOff[idx] then
				cls = IDS.open
			end
			local x, z = (cx + 0.5) * cell, (cz + 0.5) * cell
			if (cls == IDS.open or cls == IDS.steep) and not bank[idx] then
				-- slope: bare earth and rock break through on steep ground, and erosion lines run
				-- down the fall line on the moderate slopes
				local hl = g.height[math.max(idx - 1, 1)]
				local hr = g.height[math.min(idx + 1, cols * rows)]
				local hu = g.height[math.max(idx - cols, 1)]
				local hd = g.height[math.min(idx + cols, cols * rows)]
				local gx, gz = (hr - hl) / (2 * cell), (hd - hu) / (2 * cell)
				local slope = math.sqrt(gx * gx + gz * gz)
				if slope > 0.3 then
					local n = RNG.hash(cx // 2, cz // 2, fieldSeed + 44)
					return h, if n < 0.4 then Enum.Material.Rock elseif n < 0.8 then Enum.Material.Ground else Enum.Material.Grass, lvl
				elseif slope > 0.16 then
					-- fall-line stripes: coordinate across the gradient, 6-stud spacing, noise gated
					local across = (-gz * x + gx * z) / slope
					if (across / 6) % 1 < 0.3 and RNG.hash(x // 24, z // 24, fieldSeed + 45) < 0.6 then
						return h, Enum.Material.Ground, lvl
					end
					return h, Enum.Material.Grass, lvl
				end
				local vd = verge[idx]
				if vd then
					-- ditch beside the road, then a grass verge
					return h, if vd == 1 then Enum.Material.LeafyGrass else Enum.Material.Grass, lvl
				end
				if inOrchard(x, z) then
					return h, Enum.Material.LeafyGrass, lvl
				end
				local m = fieldMaterial(x, z)
				if wet[idx] and (m == Enum.Material.Grass or m == Enum.Material.LeafyGrass) then
					-- damp meadow by the water, patchy
					return h, if RNG.hash(cx // 3, cz // 3, fieldSeed + 46) < 0.7 then Enum.Material.LeafyGrass else Enum.Material.Grass, lvl
				end
				return h, m, lvl
			elseif cls == IDS.road then
				-- rutted dirt: the odd muddy patch, and mud at the water's edge by the bridges
				if wet[idx] or RNG.hash(cx // 2, cz // 2, fieldSeed + 47) < 0.18 then
					return h, Enum.Material.Mud, lvl
				end
				return h, Enum.Material.Ground, lvl
			elseif cls == IDS.village then
				if street[idx] then
					return h, Enum.Material.Cobblestone, lvl
				end
				-- yards and kitchen gardens in ~12-stud plots
				local garden = RNG.hash(x // 12, z // 12, fieldSeed + 40) < 0.55
				return h, if garden then Enum.Material.LeafyGrass else Enum.Material.Ground, lvl
			end
			return h, materialFor(cls, bank[idx] == true), lvl
		end
		-- skirt: continue the edge, roughen it with noise, relax to a plain
		local ex = math.clamp(cx, 0, cols - 1)
		local ez = math.clamp(cz, 0, rows - 1)
		local eidx = ez * cols + ex + 1
		local x, z = (cx + 0.5) * cell, (cz + 0.5) * cell
		local d = math.sqrt(((cx - ex) * cell) ^ 2 + ((cz - ez) * cell) ^ 2)
		local s = smooth(d / SKIRT_FADE)
		local rough = math.min(1, d / 120)
		local h = g.height[eidx] + (plain - g.height[eidx]) * s
			+ ((noise(x, z, 150, seed) - 0.5) * 18 + (noise(x, z, 44, seed + 1) - 0.5) * 5) * rough
		local rd, rlvl, rhalf = riverOut(x, z)
		-- a ring of low hills crests ~480 studs out and dips again, so the cut edge of the
		-- terrain sits behind a skyline instead of ending in a visible slab; valleys stay open
		local crest = smooth((d - 200) / 280) * (1 - 0.45 * smooth((d - 500) / 140))
		local damp = if rlvl then smooth((rd - rhalf) / 220) else 1
		h += crest * damp * (14 + noise(x, z, 240, seed + 5) ^ 1.6 * 46)
		-- the last 100 studs ramp down onto the ground plane so the skirt ends in no step
		local ramp = smooth((d - (SKIRT * cell - 100)) / 100)
		if ramp > 0 then
			h += (planeY + 1 - h) * ramp
			if ramp > 0.5 and not rlvl then
				return h, Enum.Material.Grass, nil
			end
		end
		-- rivers run on past the edge along their end segments; banks rise above the water
		if rlvl then
			if rd < rhalf then
				return math.min(h, rlvl - 3), Enum.Material.Sand, rlvl
			elseif rd < rhalf + 30 then
				h = math.max(h, rlvl + 0.6 + (rd - rhalf) * 0.08)
				if rd < rhalf + 6 then
					return h, Enum.Material.Sand, nil
				end
			end
		end
		if d < 40 and g.class[eidx] == IDS.road and not roadOff[eidx] then
			return h, Enum.Material.Ground, nil
		end
		-- the patchwork runs on outside the map; the far hills are pasture and meadow
		if crest > 0.6 then
			local kind = fieldAt(x, z)
			return h, FIELD_MATERIAL[if kind == KIND_PASTURE then KIND_PASTURE else KIND_MEADOW], nil
		end
		return h, fieldMaterial(x, z), nil
	end

	return {
		cols = cols,
		rows = rows,
		cell = cell,
		minH = minH,
		planeY = planeY,
		season = season,
		orchards = orchards,
		column = column,
		heightAt = function(x: number, z: number): (number, boolean)
			local cx, cz = math.floor(x / cell), math.floor(z / cell)
			local h, _, lvl = column(cx, cz)
			if lvl then
				return math.max(h, lvl), true
			end
			if cx >= 0 and cz >= 0 and cx < cols and cz < rows then
				-- the drawn surface runs between cell centres; next to a cliff it bulges above the
				-- straight line, so lean part way toward the highest of the cells around the point
				local bi = Grid.heightAt(g, x, z)
				local hi = h
				for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local nx, nz = cx + o[1], cz + o[2]
					if nx >= 0 and nz >= 0 and nx < cols and nz < rows then
						hi = math.max(hi, g.height[nz * cols + nx + 1])
					end
				end
				return math.max(bi, bi + (hi - bi) * 0.35), false
			end
			return h, false
		end,
	}
end

---------------------------------------------------------------------------------- spec output

local out: { Spec } = {}
local wantS, wantD = true, true
local maxQ = 3
local emitTier = "s"
local emitQ = 1
local NONE: { Spec } = {} -- sink for filtered specs (callers may still set fields)

local function emit(group: string, class: string, shape: EnumPartType?, size: Vector3, cf: CFrame, color: Color3, material: EnumMaterial?): Spec
	local s: Spec = {
		group = group,
		q = emitQ,
		tier = emitTier,
		class = class,
		shape = shape,
		size = size,
		cframe = cf,
		color = color,
		material = material or Enum.Material.SmoothPlastic,
		castShadow = true,
	}
	if emitQ <= maxQ and (if emitTier == "s" then wantS else wantD) then
		table.insert(out, s)
	else
		NONE[1] = s
	end
	return s
end

local function part(group: string, shape: EnumPartType?, size: Vector3, cf: CFrame, color: Color3, material: EnumMaterial?): Spec
	return emit(group, "Part", shape, size, cf, color, material)
end

local function wedge(group: string, size: Vector3, cf: CFrame, color: Color3, material: EnumMaterial?): Spec
	return emit(group, "WedgePart", nil, size, cf, color, material)
end

-- Ellipsoid: a block with the built-in sphere mesh (no asset), for poplars, conifers, bushes.
local function blob(group: string, size: Vector3, cf: CFrame, color: Color3): Spec
	local p = part(group, nil, size, cf, color, Enum.Material.Grass)
	p.mesh = true
	return p
end

local currentMap: any = nil
local model: TerrainModel

-- Clipping. The points of a part that can touch the ground, by its true shape: box corners;
-- the lowest point of an ellipsoid (spheres, sphere meshes; Ball parts use the X extent);
-- the lowest points of a cylinder's two end circles (axis along local X). World space.
local CORNERS = { { -1, -1, -1 }, { 1, -1, -1 }, { -1, -1, 1 }, { 1, -1, 1 }, { -1, 1, -1 }, { 1, 1, -1 }, { -1, 1, 1 }, { 1, 1, 1 } }
export type ShapeKind = "box" | "ellipsoid" | "cylinder" | "base"

function WorldGen.lowPoints(cf: CFrame, size: Vector3, kind: ShapeKind): { Vector3 }
	-- world up in the part's local axes
	local ux, uy, uz = cf.XVector.Y, cf.YVector.Y, -cf.LookVector.Y
	if kind == "base" then
		-- a mesh object (tree, house) stands on the centre of its base; its box corners are air
		return { cf * Vector3.new(0, -size.Y / 2, 0) }
	elseif kind == "ellipsoid" then
		local a, b, c = size.X / 2, size.Y / 2, size.Z / 2
		local d = math.sqrt((a * ux) ^ 2 + (b * uy) ^ 2 + (c * uz) ^ 2)
		if d < 1e-6 then
			return { cf.Position }
		end
		local lowest = cf * Vector3.new(-a * a * ux / d, -b * b * uy / d, -c * c * uz / d)
		return { lowest, cf * Vector3.new(a * a * ux / d, b * b * uy / d, c * c * uz / d) }
	elseif kind == "cylinder" then
		local hl, r = size.X / 2, math.min(size.Y, size.Z) / 2
		local m = math.sqrt(uy * uy + uz * uz)
		local dy, dz = 1, 0
		if m >= 1e-6 then
			dy, dz = uy / m, uz / m
		end
		local pts = {}
		for _, e in { -hl, hl } do
			table.insert(pts, cf * Vector3.new(e, -r * dy, -r * dz))
			table.insert(pts, cf * Vector3.new(e, r * dy, r * dz))
		end
		return pts
	end
	local pts = {}
	for _, o in CORNERS do
		table.insert(pts, cf * Vector3.new(o[1] * size.X / 2, o[2] * size.Y / 2, o[3] * size.Z / 2))
	end
	return pts
end

local function shapeOf(s: Spec): ShapeKind
	if s.fileMesh then
		return "base"
	elseif s.shape == Enum.PartType.Ball or s.mesh then
		return "ellipsoid"
	elseif s.shape == Enum.PartType.Cylinder then
		return "cylinder"
	end
	return "box"
end

-- How far the lowest point of `s` sits below the terrain (positive = clipping), and the
-- world Y of its lowest point.
local function shortfall(s: Spec): (number, number)
	local worst, low = -math.huge, math.huge
	for _, q in WorldGen.lowPoints(s.cframe, s.size, shapeOf(s)) do
		local gy = model.heightAt(q.X, q.Z)
		worst = math.max(worst, gy - q.Y)
		low = math.min(low, q.Y)
	end
	return worst, low
end

-- Every object is placed on the surface, never through it: the specs a builder emits inside
-- `obj` are lifted together by the largest shortfall of their sample points against the
-- terrain model. Footprint objects (houses, churches, mills) that had to rise more than 0.15
-- get a stone plinth under the base down into the ground, so nothing floats on a slope.
type ObjKind = "point" | "linear" | "footprint"
type Footprint = { cframe: CFrame, w: number, d: number }
local STONE = c3(156, 146, 128)

local function settle(a: number, b: number, kind: ObjKind, fp: Footprint?)
	if b < a then
		return
	end
	local lift, lowY = 0, math.huge
	local lowSpec: Spec? = nil
	for i = a, b do
		local sp = out[i]
		if not sp.buried then
			local sf, low = shortfall(sp)
			lift = math.max(lift, sf)
			if low < lowY then
				lowY, lowSpec = low, sp
			end
		end
	end
	if lift <= 0.02 then
		return
	end
	local up = Vector3.new(0, lift, 0)
	for i = a, b do
		out[i].cframe = out[i].cframe + up
	end
	if kind == "footprint" and lift > 0.15 and lowSpec then
		local depth = lift + 0.6
		local cf: CFrame, w: number, d: number
		if fp then
			cf, w, d = fp.cframe, fp.w, fp.d
		else
			cf, w, d = lowSpec.cframe, lowSpec.size.X, lowSpec.size.Z
		end
		local rot = cf - cf.Position
		local top = lowY + lift
		local plinth = part(lowSpec.group, nil, Vector3.new(w + 0.3, depth, d + 0.3), rot + Vector3.new(cf.X, top - depth / 2 + 0.05, cf.Z), STONE:Lerp(c3(110, 104, 92), 0.3), Enum.Material.Cobblestone)
		plinth.buried = true
	end
end

local function obj(kind: ObjKind, f: () -> (), fp: Footprint?)
	local a = #out + 1
	f()
	settle(a, #out, kind, fp)
end

-- One mesh part in place of a part assembly when the Assets slot is filled (returned); nil otherwise.
-- "point" objects (trees) stand on the ground at their centre; "footprint" objects (houses,
-- church, mill) stand on the highest ground under their corners with a stone plinth down to the
-- lowest, so none sinks into a slope or floats off it; "deck" objects (bridges) put their top at
-- `deckY` and are buried (piers in the water).
type MeshMode = "point" | "footprint" | "deck"
local function meshObject(group: string, key: string, x: number, z: number, heading: number, w: number, h: number, d: number, mode: MeshMode?, deckY: number?): Spec?
	if not Assets.get(key) then
		return nil
	end
	local rot = CFrame.Angles(0, -heading, 0)
	local base = model.heightAt(x, z) -- the same terrain model the clip check uses
	local m = mode or "point"
	if m == "footprint" then
		local lo = base
		for _, o in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			local c = CFrame.new(x, 0, z) * rot * Vector3.new(o[1] * w / 2, 0, o[2] * d / 2)
			local gy = model.heightAt(c.X, c.Z)
			base = math.max(base, gy)
			lo = math.min(lo, gy)
		end
		if base - lo > 0.15 then
			local depth = base - lo + 0.6
			local plinth = part(group, nil, Vector3.new(w + 0.3, depth, d + 0.3), CFrame.new(x, base - depth / 2 + 0.05, z) * rot, STONE:Lerp(c3(110, 104, 92), 0.3), Enum.Material.Cobblestone)
			plinth.buried = true
		end
	end
	local cy = if m == "deck" and deckY then deckY + 0.5 - h / 2 else base + h / 2
	local p = part(group, nil, Vector3.new(w, h, d), CFrame.new(x, cy, z) * rot, Color3.new(1, 1, 1), Enum.Material.Plastic)
	p.fileMesh = key
	if m == "deck" then
		p.buried = true
	end
	return p
end

local function withQ(q: number, f: () -> ())
	local prev = emitQ
	emitQ = math.max(prev, q)
	f()
	emitQ = prev
end

-- Detail tier is quality 2 too (as the detail-only jobs are): without it the chimney-smoke
-- anchors went into "Smoke", the client looks for "SmokeQ2", and no smoke ever ran (round 24).
local function detail(f: () -> ())
	local prev = emitTier
	emitTier = "d"
	withQ(2, f)
	emitTier = prev
end

-- Yaw so that local +X points along a sim heading (Roblox rotates +X toward -Z for +angle).
local function yaw(x: number, y: number, z: number, heading: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, -heading, 0)
end

-- Gable roof over `base` (eave level, ridge along local X): two wedges back to back along Z.
local function gable(group: string, base: CFrame, length: number, span: number, height: number, color: Color3, material: EnumMaterial?, texture: string?)
	local mid = base * CFrame.new(0, height / 2, 0)
	wedge(group, Vector3.new(length, height, span / 2), mid * CFrame.new(0, 0, -span / 4), color, material).texture = texture
	wedge(group, Vector3.new(length, height, span / 2), mid * CFrame.new(0, 0, span / 4) * CFrame.Angles(0, math.pi, 0), color, material).texture = texture
end

local function groundY(x: number, z: number): number
	return Grid.heightAt(currentMap.grid, x, z)
end

local function classAt(x: number, z: number): number?
	local g = currentMap.grid
	if not Grid.inBounds(g, x, z) then
		return nil
	end
	return Grid.classAt(g, x, z)
end

local function isOpen(x: number, z: number): boolean
	local c = classAt(x, z)
	return c == IDS.open or c == IDS.steep
end

local function h01(a: number, b: number, salt: number): number
	return RNG.hash(math.floor(a), math.floor(b), (currentMap.seed or 1) + salt)
end

local function pick<T>(list: { T }, r: number): T
	return list[math.clamp(math.floor(r * #list) + 1, 1, #list)]
end

-- Per-season look: crowns, hedges, roofs, walls, roadside trees. Jena/Auerstedt are Thuringia in
-- mid-October (first autumn colour, timber framing, fruit-tree avenues); Austerlitz is Moravia in
-- December (dormant oaks, more conifers, whitewash, thatch, onion domes); Waterloo is Brabant in
-- June (full green, brick and whitewash farms, poplar rows, walled courtyards).
type Look = {
	crowns: { Color3 },
	conifer: number, -- share of conifers in woods (more on high ground)
	hedge: Color3,
	roofs: { Color3 },
	walls: { Color3 },
	timber: number, -- share of timber-framed houses
	brick: number, -- share of brick houses
	thatch: number, -- share of thatched roofs
	dome: boolean,
	avenue: "fruit" | "poplar",
	stook: Color3,
	stookKind: number, -- field KIND the stooks stand in
}
local CONIFER = c3(40, 58, 40)
local LOOKS: { [string]: Look } = {
	autumn = {
		crowns = { c3(56, 78, 34), c3(64, 86, 38), c3(74, 92, 40), c3(90, 98, 44), c3(108, 104, 50), c3(116, 92, 52) },
		conifer = 0.12,
		hedge = c3(84, 106, 50),
		roofs = { c3(122, 60, 42), c3(108, 54, 40), c3(132, 72, 50), c3(92, 56, 44), c3(116, 66, 48) },
		walls = { c3(222, 214, 194), c3(214, 204, 180), c3(206, 196, 172) },
		timber = 0.45,
		brick = 0.0,
		thatch = 0.0,
		dome = false,
		avenue = "fruit",
		stook = c3(196, 176, 112),
		stookKind = 3,
	},
	winter = {
		crowns = { c3(86, 84, 60), c3(96, 90, 64), c3(78, 80, 56), c3(104, 94, 70), c3(70, 78, 50) },
		conifer = 0.35,
		hedge = c3(100, 106, 72),
		roofs = { c3(118, 62, 46), c3(104, 58, 44), c3(128, 74, 54) },
		walls = { c3(226, 220, 204), c3(218, 212, 196), c3(210, 202, 184) },
		timber = 0.0,
		brick = 0.0,
		thatch = 0.3,
		dome = true,
		avenue = "fruit",
		stook = c3(176, 162, 120),
		stookKind = 3,
	},
	summer = {
		crowns = { c3(50, 80, 32), c3(58, 90, 36), c3(66, 98, 40), c3(76, 104, 44), c3(54, 74, 34) },
		conifer = 0.05,
		hedge = c3(74, 108, 46),
		roofs = { c3(120, 58, 42), c3(106, 52, 40), c3(76, 76, 82), c3(130, 68, 48) },
		walls = { c3(222, 216, 200), c3(212, 204, 186), c3(150, 82, 62), c3(140, 76, 58) },
		timber = 0.0,
		brick = 0.35,
		thatch = 0.0,
		dome = false,
		avenue = "poplar",
		stook = c3(184, 176, 106),
		stookKind = 1,
	},
}
local look: Look = LOOKS.autumn
local BEAM = c3(66, 48, 36)
local TRUNK = c3(70, 54, 40)


---------------------------------------------------------------------------------------- trees

local function crownColor(x: number, z: number): Color3
	local base = pick(look.crowns, h01(x * 3, z * 5, 41))
	return base:Lerp(c3(30, 40, 24), h01(z, x, 42) * 0.25)
end

-- Trees are built from a trunk, a branch or two and several overlapping flattened lobes in
-- two or three tones (lit top, mid, shaded underside), so a crown has a lumpy silhouette from
-- any height and a trunk you can see at the low camera. Each species has its own shape:
--   oak    broad, lobes spread wide, short thick trunk
--   beech  taller, lobes stacked upward, pale smooth trunk
--   pine   tiers of flattened cones (ellipsoids) up a straight trunk, dark blue-green
--   poplar narrow stacked spindles on a tall trunk (Brabant road rows)
--   willow short thick trunk, a low dome and drooping lobes, silvery (river banks)
-- `full` trees get branches and 5-7 lobes (8-10 parts); `lite` ones a trunk and 3 lobes.
type Species = "oak" | "beech" | "pine" | "poplar" | "willow"

local function trunkPart(group: string, x: number, gy: number, z: number, h: number, d: number, color: Color3)
	part(group, Enum.PartType.Cylinder, Vector3.new(h, d, d), CFrame.new(x, gy + h / 2, z) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Wood).texture = "bark"
end

local function branch(group: string, x: number, y: number, z: number, len: number, d: number, dirAngle: number, tilt: number, color: Color3)
	-- a thin cylinder from (x, y, z) leaning out `tilt` radians from vertical toward dirAngle
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, -dirAngle, 0) * CFrame.Angles(0, 0, math.pi / 2 - tilt) * CFrame.new(len / 2, 0, 0)
	part(group, Enum.PartType.Cylinder, Vector3.new(len, d, d), cf, color, Enum.Material.Wood)
end

local SPECIES_KEY: { [string]: string } = { oak = "treeOak", beech = "treeBeech", pine = "treePine", poplar = "treePoplar", willow = "treeWillow" }
local function treeParts(group: string, species: Species, x: number, z: number, r: number, full: boolean, y: number?)
	local gy = y or groundY(x, z)
	local seed = h01(x, z, 43)
	local base = crownColor(x, z)
	local lit = base:Lerp(c3(150, 150, 70), 0.18)
	local shade = base:Lerp(c3(24, 34, 20), 0.3)
	local bark = TRUNK:Lerp(c3(40, 32, 26), h01(z, x, 44) * 0.4)
	if species == "poplar" then
		local hgt = r * 3.2
		trunkPart(group, x, gy, z, hgt * 0.35, r * 0.18, bark)
		for i = 0, 2 do
			local w = r * (1.1 - i * 0.25)
			local f = i / 2
			blob(group, Vector3.new(w, hgt * 0.5, w), CFrame.new(x, gy + hgt * (0.3 + f * 0.33), z) * CFrame.Angles(0, seed * 3, 0), (if i == 2 then lit else base):Lerp(c3(70, 96, 40), 0.25))
		end
		return
	elseif species == "pine" then
		local hgt = r * 2.8
		trunkPart(group, x, gy, z, hgt * 0.55, r * 0.16, bark:Lerp(c3(110, 70, 50), 0.3))
		local tiers = if full then 4 else 3
		for i = 0, tiers - 1 do
			local f = i / (tiers - 1)
			local w = r * (1.5 - f * 1.1)
			local col = CONIFER:Lerp(c3(30, 44, 34), seed * 0.5):Lerp(c3(74, 96, 58), f * 0.35)
			blob(group, Vector3.new(w, r * 0.7, w), CFrame.new(x + (seed - 0.5) * 0.4 * f, gy + hgt * (0.35 + f * 0.6), z), col)
		end
		return
	elseif species == "willow" then
		trunkPart(group, x, gy, z, r * 0.8, r * 0.3, bark)
		local silver = c3(108, 122, 84):Lerp(base, 0.3)
		blob(group, Vector3.new(r * 2.2, r * 1.3, r * 2.2), CFrame.new(x, gy + r * 1.2, z), silver)
		for i = 0, (if full then 2 else 1) do
			local a = seed * 6 + i * 2.4
			blob(group, Vector3.new(r * 1.1, r * 1.5, r * 1.1), CFrame.new(x + math.cos(a) * r * 0.8, gy + r * 0.75, z + math.sin(a) * r * 0.8), silver:Lerp(shade, 0.35))
		end
		return
	end
	-- oak / beech
	local beech = species == "beech"
	local trunkH = if beech then r * 1.5 else r * 1.0
	local trunkD = if beech then r * 0.2 else r * 0.3
	trunkPart(group, x, gy, z, trunkH + 0.6, trunkD, if beech then bark:Lerp(c3(150, 142, 128), 0.45) else bark)
	if full then
		branch(group, x, gy + trunkH * 0.75, z, r * 0.9, trunkD * 0.45, seed * 6.28, if beech then 0.5 else 0.95, bark)
	end
	-- a few big lobes, each tilted and turned its own way and taller or flatter than the next,
	-- overlapping into one lumpy crown (flat, level lobes stacked up read as plates)
	local n = if full then 3 + math.floor(seed * 2) else 2
	for i = 0, n - 1 do
		local f = i / math.max(n - 1, 1)
		local a = seed * 6.28 + i * 2.39996 -- golden angle: lobes spread evenly around
		local spread = (if beech then r * 0.4 else r * 0.55) * (if full then 1 else 0.5)
		local off = spread * (0.35 + 0.65 * h01(x + i, z, 45))
		local w = r * (if beech then 1.3 else 1.55) * (1 - f * 0.25) * (if full then 1 else 1.15)
		local aspect = 0.65 + h01(x + i * 3, z, 54) * 0.6 -- 0.65 flat .. 1.25 tall
		local hgt = w * aspect * (if beech then 1.1 else 1)
		local ly = gy + trunkH + (if beech then r * 0.4 + f * r * 1.0 else r * 0.35 + f * r * 0.65)
		local col = if f < 0.34 then shade elseif f < 0.7 then base else lit
		local tilt = CFrame.Angles((h01(x, z + i, 55) - 0.5) * 0.7, a, (h01(z + i, x, 56) - 0.5) * 0.7)
		blob(group, Vector3.new(w, hgt, w * (0.8 + h01(z, x + i, 46) * 0.4)), CFrame.new(x + math.cos(a) * off, ly, z + math.sin(a) * off) * tilt, col)
	end
end

local function tree(group: string, species: Species, x: number, z: number, r: number, full: boolean, y: number?)
	local hgt = if species == "poplar" then r * 3.2 elseif species == "pine" then r * 2.8 elseif species == "willow" then r * 2 else r * 2.6
	if meshObject(group, SPECIES_KEY[species], x, z, h01(x, z, 43) * 6.28, r * 2.4, hgt, r * 2.4) then
		return
	end
	obj("point", function()
		treeParts(group, species, x, z, r, full, y)
	end)
end

local function bush(group: string, x: number, z: number, r: number)
	obj("point", function()
		local p = blob(group, Vector3.new(r * 2.2, r * 1.1, r * 1.8), yaw(x, groundY(x, z) + r * 0.55, z, h01(x, z, 47) * 3), look.hedge:Lerp(c3(56, 72, 40), h01(z, x, 48) * 0.4))
		p.castShadow = false
	end)
end

-- Woods: edge trees are full (trunk, branches, lobes, undergrowth); the interior is a closed
-- canopy of lite trees over dark trunks, thinned to half since the canopy hides the rest.
local function buildWoodsTree(group: string, t: any, highGround: number)
	local r = t.r
	local edge = false
	for k = 0, 3 do
		local a = k * math.pi / 2
		if classAt(t.x + math.cos(a) * r * 1.5, t.z + math.sin(a) * r * 1.5) ~= IDS.woods then
			edge = true
			break
		end
	end
	if not edge and t.priority < 0.58 then
		return
	end
	local y = groundY(t.x, t.z)
	local coniferShare = look.conifer + (if y > highGround then 0.35 else 0)
	local sp: Species = if h01(t.x, t.z, 49) < coniferShare then "pine" elseif h01(t.z, t.x, 52) < 0.3 then "beech" else "oak"
	tree(group, sp, t.x, t.z, if edge then r else r * 1.35, edge, y)
	if edge and h01(t.z, t.x, 50) < 0.6 then
		local a = h01(t.x, t.z, 51) * math.pi * 2
		bush(group, t.x + math.cos(a) * r, t.z + math.sin(a) * r, r * 0.6)
	end
end

------------------------------------------------------------------------------------- buildings

-- Houses about 1.5x a soldier's height so villages read as dense clusters of steep roofs.
local WALL_H = 2.6

type HouseKind = "white" | "timber" | "brick" | "barn"

local function houseParts(group: string, x: number, z: number, heading: number, w: number, d: number, kind: HouseKind, salt: number)
	local y = groundY(x, z)
	local wallH = if kind == "barn" then WALL_H + 0.6 else WALL_H
	local wallC: Color3
	if kind == "barn" then
		wallC = c3(104, 80, 58)
	elseif kind == "brick" then
		wallC = pick({ c3(150, 82, 62), c3(140, 76, 58), c3(158, 92, 70) }, h01(x, z, salt))
	else
		wallC = pick(look.walls, h01(x, z, salt))
	end
	local body = yaw(x, y + wallH / 2, z, heading)
	part(group, nil, Vector3.new(w, wallH, d), body, wallC, if kind == "barn" then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic).texture = if kind == "barn" then nil else "wall"
	if kind == "timber" then
		-- dark beams: a band at the upper floor and two posts that show on both long sides
		part(group, nil, Vector3.new(w + 0.08, 0.3, d + 0.08), body * CFrame.new(0, 0.35, 0), BEAM)
		for sx = -1, 1, 2 do
			part(group, nil, Vector3.new(0.3, wallH + 0.9, d + 0.08), body * CFrame.new(sx * w * 0.22, 0, 0), BEAM)
		end
	end
	local thatch = kind ~= "brick" and h01(z, x, salt + 1) < look.thatch
	local roofC = if thatch then c3(128, 112, 80) elseif kind == "barn" then c3(96, 58, 44) else pick(look.roofs, h01(z, x, salt + 2))
	local roofH = d * (if thatch then 0.7 else 0.62)
	gable(group, yaw(x, y + wallH, z, heading), w + 0.6, d + 0.8, roofH, roofC, if thatch then Enum.Material.Grass else Enum.Material.Slate, if thatch then "thatch" else "roofTile")
	if kind ~= "barn" and h01(x, z, salt + 3) < 0.45 then
		local cx = (h01(z, x, salt + 4) - 0.5) * w * 0.6
		local top = yaw(x, y + wallH + roofH * 0.5 + 0.2, z, heading) * CFrame.new(cx, 0, d * 0.12)
		part(group, nil, Vector3.new(0.7, roofH + 0.9, 0.7), top, c3(120, 96, 80))
		if h01(x + 1, z, salt + 5) < 0.5 then
			-- hearth smoke (detail tier): an invisible anchor at the chimney top; the client's Props
			-- puts a small slow ParticleEmitter on it and Lighting tints it to the sky
			detail(function()
				local anchor = part("Smoke", nil, Vector3.new(0.6, 0.3, 0.6), top * CFrame.new(0, roofH * 0.5 + 0.6, 0), c3(206, 204, 198))
				anchor.transparency = 1
				anchor.castShadow = false
				anchor.buried = true
			end)
		end
	end
	-- footprint variety: an L-wing at one end, or a lean-to shed along the back
	local variant = h01(x, z + 1, salt + 6)
	if kind ~= "barn" and variant < 0.22 then
		local wx = w / 2 - d * 0.35
		local wing = yaw(x, y, z, heading) * CFrame.new(wx, 0, d / 2 + w * 0.2) * CFrame.Angles(0, math.pi / 2, 0)
		part(group, nil, Vector3.new(w * 0.55, wallH + 0.6, d * 0.7), wing * CFrame.new(0, wallH / 2 - 0.3, 0), wallC)
		gable(group, wing * CFrame.new(0, wallH - 0.2, 0), w * 0.55 + 0.4, d * 0.7 + 0.6, roofH * 0.8, roofC, Enum.Material.Slate)
	elseif variant < 0.42 then
		wedge(group, Vector3.new(w * 0.7, 1.6, 2.2), yaw(x, y + wallH * 0.45, z, heading) * CFrame.new(0, 0, d / 2 + 1.1) * CFrame.Angles(0, math.pi, 0), roofC:Lerp(c3(70, 60, 50), 0.3), Enum.Material.WoodPlanks)
	end
end

-- Village furniture: a cart, barrels by the well, a haystack by a barn, a wayside shrine.
local function house(group: string, x: number, z: number, heading: number, w: number, d: number, kind: HouseKind, salt: number)
	local key = if kind == "barn" then "barn" else pick({ "houseA", "houseB", "houseC" }, h01(x, z, salt + 8))
	if meshObject(group, key, x, z, heading, w, WALL_H + d * 0.62, d, "footprint") then
		return
	end
	obj("footprint", function()
		houseParts(group, x, z, heading, w, d, kind, salt)
	end, { cframe = yaw(x, 0, z, heading), w = w, d = d })
end

local function cart(group: string, x: number, z: number, heading: number)
	-- the generated cart's shafts run along its Z, so it is turned a quarter to the heading
	if meshObject(group, "cart", x, z, heading + math.pi / 2, 2.4, 2.2, 5.6) then
		return
	end
	obj("point", function()
		local y = groundY(x, z)
		local base = yaw(x, y, z, heading)
		part(group, nil, Vector3.new(3.6, 0.9, 1.8), base * CFrame.new(0, 1.3, 0), c3(110, 86, 60), Enum.Material.WoodPlanks)
		for side = -1, 1, 2 do
			part(group, Enum.PartType.Cylinder, Vector3.new(0.2, 1.6, 1.6), base * CFrame.new(0.3, 0.8, side * 1.05), c3(70, 54, 40), Enum.Material.Wood)
		end
		part(group, nil, Vector3.new(2.6, 0.2, 0.2), base * CFrame.new(-3, 0.7, 0.5) * CFrame.Angles(0, 0, 0.15), BEAM)
	end)
end

local function barrels(group: string, x: number, z: number)
	obj("point", function()
		local y = groundY(x, z)
		for i = 0, 1 do
			part(group, Enum.PartType.Cylinder, Vector3.new(1.1, 0.8, 0.8), CFrame.new(x + i * 0.9, y + 0.55, z + i * 0.3) * CFrame.Angles(0, 0, math.pi / 2), c3(96, 74, 50), Enum.Material.Wood)
		end
	end)
end

local function haystack(group: string, x: number, z: number)
	obj("point", function()
		local y = groundY(x, z)
		local straw = look.stook:Lerp(c3(150, 130, 80), 0.25)
		-- a drum of hay with a domed top, built round a pole
		part(group, Enum.PartType.Cylinder, Vector3.new(2.0, 4.6, 4.6), CFrame.new(x, y + 1.0, z) * CFrame.Angles(0, 0, math.pi / 2), straw, Enum.Material.Sand)
		local dome = blob(group, Vector3.new(4.8, 3.0, 4.8), CFrame.new(x, y + 2.0, z) * CFrame.Angles(0, h01(x, z, 115) * 3, 0), straw:Lerp(c3(120, 104, 64), 0.2))
		dome.material = Enum.Material.Sand
		part(group, nil, Vector3.new(0.25, 4.8, 0.25), CFrame.new(x, y + 2.4, z), BEAM)
	end)
end

local function shrine(group: string, x: number, z: number, heading: number)
	obj("point", function()
		local y = groundY(x, z)
		local base = yaw(x, y, z, heading)
		part(group, nil, Vector3.new(0.5, 2.6, 0.5), base * CFrame.new(0, 1.3, 0), STONE, Enum.Material.Slate)
		part(group, nil, Vector3.new(1.4, 0.9, 1.0), base * CFrame.new(0, 2.8, 0), c3(214, 206, 190))
		gable(group, base * CFrame.new(0, 3.25, 0), 1.7, 1.3, 0.7, c3(100, 56, 42), Enum.Material.Slate)
	end)
end

-- A low wall round the churchyard, open toward the street.
local function churchyard(group: string, base: CFrame)
	local wall = c3(176, 166, 148)
	for _, seg in { { 0, 10.5, 30, 0 }, { -15, 0, 0, 21 }, { 15, 0, 0, 21 }, { -8, -10.5, 10, 0 }, { 8, -10.5, 10, 0 } } do
		obj("linear", function()
			part(group, nil, Vector3.new(math.max(seg[3], 0.7), 1.3, math.max(seg[4], 0.7)), base * CFrame.new(seg[1], 0.4, seg[2]), wall, Enum.Material.Cobblestone)
		end)
	end
end

local function houseKind(x: number, z: number, w: number, farFromCentre: boolean): HouseKind
	local r = h01(x, z, 60)
	if farFromCentre and w >= 10 and r < 0.22 then
		return "barn"
	end
	r = h01(z, x, 61)
	if r < look.timber then
		return "timber"
	elseif r < look.timber + look.brick then
		return "brick"
	end
	return "white"
end

local function buildBuilding(group: string, b: any, centre: any, radius: number)
	local w = math.clamp(b.w * 0.55, 3.8, 6.5)
	local d = math.clamp(b.d * 0.62, 3.4, 5)
	local far = Vec.dist(b.pos, centre) > radius * 0.55
	if b.w >= 9 then
		local ux, uz = math.cos(b.heading), math.sin(b.heading)
		local off = w / 2 + 0.5
		local k = houseKind(b.pos.x, b.pos.z, b.w, far)
		if k == "barn" then
			house(group, b.pos.x, b.pos.z, b.heading, w * 1.9, d * 1.25, "barn", 62)
		else
			house(group, b.pos.x - ux * off, b.pos.z - uz * off, b.heading, w, d, k, 62)
			house(group, b.pos.x + ux * off, b.pos.z + uz * off, b.heading + 0.06, w * 0.9, d, houseKind(b.pos.z, b.pos.x, 0, false), 63)
		end
	else
		house(group, b.pos.x, b.pos.z, b.heading, w, d, houseKind(b.pos.x, b.pos.z, b.w, far), 64)
	end
end

local churchParts
-- Village church: nave with a steep roof, west tower with a spire (two crossed steep gables) or,
-- in Moravia, a baroque onion dome.
local function church(group: string, x: number, z: number, heading: number)
	if meshObject(group, "church", x, z, heading, 22, 22, 7.4, "footprint") then
		return
	end
	obj("footprint", function()
		churchParts(group, x, z, heading)
	end, { cframe = yaw(x, 0, z, heading) * CFrame.new(-4, 0, 0), w = 22, d = 7.4 })
end

function churchParts(group: string, x: number, z: number, heading: number)
	local y = groundY(x, z)
	local wall = look.walls[1]
	local roof = look.roofs[1]:Lerp(c3(60, 40, 34), 0.2)
	local nave = yaw(x, y, z, heading)
	part(group, nil, Vector3.new(13, 6.5, 6.5), nave * CFrame.new(0, 3.25, 0), wall).texture = "wall"
	gable(group, nave * CFrame.new(0, 6.5, 0), 13.6, 7.4, 4.8, roof, Enum.Material.Slate, "roofTile")
	local tower = nave * CFrame.new(-8.6, 0, 0)
	part(group, nil, Vector3.new(4.4, 14, 4.4), tower * CFrame.new(0, 7, 0), wall).texture = "wall"
	if look.dome then
		part(group, Enum.PartType.Ball, Vector3.one * 5.2, tower * CFrame.new(0, 15.1, 0), c3(84, 102, 84), Enum.Material.Metal)
		part(group, nil, Vector3.new(0.5, 3.5, 0.5), tower * CFrame.new(0, 18.9, 0), c3(170, 150, 90), Enum.Material.Metal)
	else
		local spire = c3(70, 72, 76)
		gable(group, tower * CFrame.new(0, 14, 0), 4.8, 4.8, 8.5, spire, Enum.Material.Slate)
		gable(group, tower * CFrame.new(0, 14, 0) * CFrame.Angles(0, math.pi / 2, 0), 4.8, 4.8, 8.5, spire, Enum.Material.Slate)
	end
	-- the churchyard wall follows the ground, segment by segment
	churchyard(group, nave * CFrame.new(-2, 0, 0))
end

local function well(group: string, x: number, z: number)
	obj("point", function()
		local y = groundY(x, z)
		part(group, Enum.PartType.Cylinder, Vector3.new(1.4, 2.4, 2.4), CFrame.new(x, y + 0.5, z) * CFrame.Angles(0, 0, math.pi / 2), STONE, Enum.Material.Cobblestone)
		part(group, nil, Vector3.new(0.25, 3.2, 2.6), CFrame.new(x, y + 1.6, z), BEAM)
	end)
end

-- Brabant courtyard farm (Hougoumont, La Haye Sainte, Papelotte...): a walled square with the
-- house, barn and stables along the walls and a gate toward the road.
local COMPOUNDS: { [string]: { size: number, garden: boolean } } = {
	Hougoumont = { size = 40, garden = true },
	["La Haye Sainte"] = { size = 32, garden = false },
	Papelotte = { size = 32, garden = false },
	["Mont-Saint-Jean"] = { size = 34, garden = false },
	Frichermont = { size = 34, garden = true },
}

local function compound(group: string, v: any, size: number, garden: boolean, heading: number)
	local x, z = v.pos.x, v.pos.z
	local y = groundY(x, z)
	local wallC = c3(196, 184, 162)
	local roofC = c3(112, 56, 42)
	local base = yaw(x, y, z, heading)
	local half = size / 2
	-- walls in 8-stud segments that follow the ground: three full sides, the road side (local
	-- +X) split by a gate
	local function wallRun(lx0: number, lz0: number, lx1: number, lz1: number, height: number, thick: number)
		local p0, p1 = base * CFrame.new(lx0, 0, lz0), base * CFrame.new(lx1, 0, lz1)
		local len = (p1.Position - p0.Position).Magnitude
		local n = math.max(1, math.ceil(len / 8))
		for i = 0, n - 1 do
			local a = p0.Position:Lerp(p1.Position, i / n)
			local b = p0.Position:Lerp(p1.Position, (i + 1) / n)
			local ay, by = groundY(a.X, a.Z), groundY(b.X, b.Z)
			obj("linear", function()
				local cf = CFrame.lookAt(Vector3.new((a.X + b.X) / 2, (ay + by) / 2 + height / 2, (a.Z + b.Z) / 2), Vector3.new(b.X, by + height / 2, b.Z))
				part(group, nil, Vector3.new(thick, height, len / n + 0.3), cf, wallC)
			end)
		end
	end
	wallRun(-half, -half, half, -half, 4, 0.9)
	wallRun(-half, half, half, half, 4, 0.9)
	wallRun(-half, -half, -half, half, 4, 0.9)
	wallRun(half, -half, half, -3, 4, 0.9)
	wallRun(half, 3, half, half, 4, 0.9)
	-- ranges inside the walls: long barn at the back, house and stables on the sides
	local function range(cf: CFrame, len: number, depth: number, wall: Color3)
		obj("footprint", function()
			part(group, nil, Vector3.new(len, 4.2, depth), cf * CFrame.new(0, 2.1, 0), wall).texture = "wall"
			gable(group, cf * CFrame.new(0, 4.2, 0), len + 0.6, depth + 0.8, depth * 0.6, roofC, Enum.Material.Slate, "roofTile")
		end, { cframe = cf, w = len, d = depth })
	end
	range(base * CFrame.new(-half + 3.6, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), size - 2, 6, c3(110, 84, 62))
	range(base * CFrame.new(0, 0, -half + 3.4), size - 10, 5.6, wallC)
	range(base * CFrame.new(1, 0, half - 3.4), size - 12, 5.6, c3(150, 84, 64))
	if garden then
		-- walled garden on the far side (Hougoumont's south garden), with a few fruit trees
		local g = size * 0.45
		wallRun(-size * 0.6, half + g * 2, size * 0.6, half + g * 2, 3, 0.8)
		for sx = -1, 1, 2 do
			wallRun(sx * size * 0.6, half, sx * size * 0.6, half + g * 2, 3, 0.8)
		end
		local gb = base * CFrame.new(0, 0, half + g)
		for k = -1, 1 do
			local p = gb * CFrame.new(k * size * 0.3, 0, 0)
			tree(group, "oak", p.X, p.Z, 2.4, false)
		end
	end
end

local windmillParts
-- Post mill on a rise near a village: trestle, weatherboarded body, gable roof and four sails.
local function windmill(group: string, x: number, z: number, heading: number)
	if meshObject(group, "windmill", x, z, heading, 20, 20, 20, "footprint") then
		return
	end
	obj("footprint", function()
		windmillParts(group, x, z, heading)
	end, { cframe = yaw(x, 0, z, heading), w = 4.6, d = 4 })
end

function windmillParts(group: string, x: number, z: number, heading: number)
	local y = groundY(x, z)
	local base = yaw(x, y, z, heading)
	part(group, Enum.PartType.Cylinder, Vector3.new(4, 4, 4), base * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.pi / 2), STONE, Enum.Material.Cobblestone)
	part(group, nil, Vector3.new(4.6, 6, 4), base * CFrame.new(0, 6.4, 0), c3(112, 88, 64), Enum.Material.WoodPlanks)
	gable(group, base * CFrame.new(0, 9.4, 0), 5, 4.6, 2.4, c3(88, 70, 56), Enum.Material.WoodPlanks)
	local hub = base * CFrame.new(2.7, 7.8, 0)
	for k = 0, 1 do
		part(group, nil, Vector3.new(0.3, 15, 1.7), hub * CFrame.Angles(math.pi / 4 + k * math.pi / 2, 0, 0), c3(206, 198, 176), Enum.Material.Fabric)
	end
end

local function buildVillage(group: string, v: any)
	local heading = 0
	local best = math.huge
	for _, road in currentMap.roads do
		local pts = road.points
		for n = 1, #pts - 1 do
			local d = Vec.distToSegment(v.pos, pts[n], pts[n + 1])
			if d < best then
				best = d
				heading = Vec.heading(Vec.sub(pts[n + 1], pts[n]))
			end
		end
	end
	local comp = COMPOUNDS[v.name]
	local clearR = 0
	local skip: { [any]: boolean } = {}
	if comp and currentMap.id == "waterloo" then
		compound(group, v, comp.size, comp.garden, heading)
		clearR = comp.size * 0.75
	elseif v.count >= 12 then
		-- the church stands back from the main street, its tower toward the road
		local r = Vec.right(Vec.fromHeading(heading))
		local cpos = Vec.add(v.pos, Vec.scale(r, 14))
		church(group, cpos.x, cpos.z, heading)
		clearR = 0
		local wx, wz = v.pos.x - r.x * 9 + 6, v.pos.z - r.z * 9
		well(group, wx, wz)
		barrels(group, wx + 2.2, wz + 1.4)
		for _, b in v.buildings do
			if Vec.dist(b.pos, cpos) <= 12 then
				skip[b] = true
			end
		end
	else
		well(group, v.pos.x + 7, v.pos.z + 5)
	end
	local nb = 0
	for _, b in v.buildings do
		if not skip[b] and (clearR == 0 or Vec.dist(b.pos, v.pos) > clearR) then
			buildBuilding(group, b, v.pos, v.radius)
			nb += 1
			-- a haystack behind every fourth outlying house, a cart in a yard or two
			local far = Vec.dist(b.pos, v.pos) > v.radius * 0.5
			local k = h01(b.pos.x, b.pos.z, 116)
			local rr = Vec.right(Vec.fromHeading(b.heading))
			if far and k < 0.25 then
				local hx, hz = b.pos.x + rr.x * 7, b.pos.z + rr.z * 7
				if isOpen(hx, hz) or classAt(hx, hz) == IDS.village then
					haystack(group, hx, hz)
				end
			elseif nb % 6 == 3 then
				cart(group, b.pos.x - rr.x * 6, b.pos.z - rr.z * 6, b.heading + 0.4)
			end
		end
	end
	-- a wayside shrine where the road leaves the village
	local f = Vec.fromHeading(heading)
	local fr = Vec.right(f)
	local sx, sz = v.pos.x + f.x * (v.radius + 8) + fr.x * 5, v.pos.z + f.z * (v.radius + 8) + fr.z * 5
	if isOpen(sx, sz) then
		shrine(group, sx, sz, heading + math.pi / 2)
	end
end

------------------------------------------------------------------------------- water and roads

local function buildBridge(group: string, br: any)
	local a, b = br.a, br.b
	local dir = Vec.normalize(Vec.sub(b, a))
	local mid = Vec.lerp(a, b, 0.5)
	local heading = Vec.heading(dir)
	-- the deck spans the water plus a short ramp on each bank and follows the bank heights;
	-- the crossing's cells beyond it are plain ground (MapGen flattens the whole band)
	local half = Vec.dist(a, b) / 2 - 8
	for _, river in currentMap.rivers do
		local pts = river.points
		for n = 1, #pts - 1 do
			if Vec.distToSegment(mid, pts[n], pts[n + 1]) < river.width / 2 + 20 then
				half = math.min(half, river.width / 2)
			end
		end
	end
	local stoneBridge = half >= 20
	local waterY = groundY(mid.x, mid.z) + 3 -- the river level: MapGen bed is level - 3
	local ramp = if stoneBridge then 9 else 5
	local reach = half + ramp
	local e1 = Vec.sub(mid, Vec.scale(dir, reach))
	local e2 = Vec.add(mid, Vec.scale(dir, reach))
	local y1, y2 = groundY(e1.x, e1.z), groundY(e2.x, e2.z)
	local len = reach * 2
	local pitch = math.atan2(y2 - y1, len)
	local deck = yaw(mid.x, (y1 + y2) / 2, mid.z, heading) * CFrame.Angles(0, 0, pitch)
	local function pier(t: number, size: Vector3, color: Color3, material: EnumMaterial?): Spec
		local px, pz = e1.x + (e2.x - e1.x) * t, e1.z + (e2.z - e1.z) * t
		local top = y1 + (y2 - y1) * t
		local bottom = groundY(px, pz) - 2
		local ph = math.max(top - bottom, 1)
		local sp = part(group, nil, Vector3.new(size.X, ph, size.Z), yaw(px, bottom + ph / 2, pz, heading), color, material)
		sp.buried = true
		return sp
	end
	if meshObject(group, if stoneBridge then "bridgeStone" else "bridgeTimber", mid.x, mid.z, heading, len, 6, br.width, "deck", (y1 + y2) / 2) then
		return
	end
	local a0 = #out + 1
	if stoneBridge then
		-- stone bridge: deck, parapets with coping, piers with cutwaters down to the bed
		local stone = c3(150, 140, 122)
		part(group, nil, Vector3.new(len, 1.4, br.width), deck * CFrame.new(0, 0.3, 0), stone, Enum.Material.Cobblestone)
		for side = -1, 1, 2 do
			part(group, nil, Vector3.new(len, 1.6, 0.9), deck * CFrame.new(0, 1.6, side * (br.width / 2 - 0.45)), stone, Enum.Material.Slate)
		end
		local dark = stone:Lerp(c3(60, 56, 50), 0.25)
		for i = 0, 2 do
			local t = 0.25 + i * 0.25
			pier(t, Vector3.new(3.4, 0, br.width - 1), dark, Enum.Material.Slate)
			local px, pz = e1.x + (e2.x - e1.x) * t, e1.z + (e2.z - e1.z) * t
			local bottom = groundY(px, pz) - 2
			local ph = math.max(y1 + (y2 - y1) * t - bottom, 1)
			part(group, nil, Vector3.new(2.4, ph, 2.4), yaw(px, bottom + ph / 2, pz, heading) * CFrame.new(0, 0, br.width / 2) * CFrame.Angles(0, math.pi / 4, 0), dark, Enum.Material.Slate).buried = true
			-- foam where the current breaks on the cutwater
			local foam = blob(group, Vector3.new(4.5, 0.4, 7), yaw(px, waterY + 0.15, pz, heading) * CFrame.new(0, 0, br.width / 2 + 1.5), c3(236, 236, 230))
			foam.material = Enum.Material.SmoothPlastic
			foam.transparency = 0.35
			foam.castShadow = false
		end
	else
		-- timber bridge over a brook: plank deck, trestles and a post-and-rail on both sides
		local wood = c3(104, 80, 58)
		part(group, nil, Vector3.new(len, 0.6, br.width - 6), deck * CFrame.new(0, 0.2, 0), wood, Enum.Material.WoodPlanks)
		local n = math.max(2, math.floor(len / 7))
		for side = -1, 1, 2 do
			local zOff = side * (br.width / 2 - 3.3)
			part(group, nil, Vector3.new(len, 0.25, 0.25), deck * CFrame.new(0, 1.7, zOff), wood)
			for k = 0, n do
				part(group, nil, Vector3.new(0.3, 1.8, 0.3), deck * CFrame.new(-len / 2 + k * len / n, 0.9, zOff), BEAM)
			end
		end
		for k = 1, n - 1 do
			pier(k / n, Vector3.new(0.7, 0, br.width - 7), BEAM)
		end
	end
	-- the deck and rails rise as one so no end dips into a bank
	settle(a0, #out, "linear", nil)
end

local function nearBridge(x: number, z: number, pad: number): boolean
	for _, br in currentMap.bridges do
		if Vec.distToSegment({ x = x, z = z }, br.a, br.b) < br.width / 2 + pad then
			return true
		end
	end
	return false
end

type Job = { tag: string, run: () -> () } -- tag: "s" structure only, "d" detail only, "sd" both

-- Reeds on the water's edge (quality 2) and willows on the banks.
local function buildRiverside(group: string, river: any, jobs: { Job })
	local pts = river.points
	local half = river.width / 2
	for n = 1, #pts - 1 do
		local a, b = pts[n], pts[n + 1]
		local len = Vec.dist(a, b)
		local dir = Vec.normalize(Vec.sub(b, a))
		local right = Vec.right(dir)
		table.insert(jobs, { tag = "s", run = function()
			local s = 0
			while s < len do
				local c = Vec.add(a, Vec.scale(dir, s))
				for side = -1, 1, 2 do
					local k = h01(c.x + side, c.z, 70)
					if k < 0.55 then
						local p = Vec.add(c, Vec.scale(right, side * (half + 1.5 + k * 3)))
						if classAt(p.x, p.z) ~= nil and classAt(p.x, p.z) ~= IDS.water and classAt(p.x, p.z) ~= IDS.ford and not nearBridge(p.x, p.z, 6) then
							-- a reed bed: the generated clump (reeds, a few cattails), or clusters of thin tall
							-- stems, each leaning its own way, khaki-green
							withQ(2, function()
								obj("point", function()
									local hd = Vec.heading(dir)
									if Assets.get("reeds") then
										local hh = 2.2 + k * 1.2
										local wide = hh * 0.9
										local r = part(group, nil, Vector3.new(wide * 1.3, hh, wide), yaw(p.x, groundY(p.x, p.z) + hh / 2 - 0.25, p.z, hd + k * 6), c3(128, 132, 76), Enum.Material.Grass)
										r.fileMesh = "reeds"
										r.castShadow = false
										return
									end
									for j = -1, 1 do
										local q = Vec.add(p, Vec.scale(dir, j * 1.6))
										local hh = 2.0 + k * 1.2 + h01(q.x, q.z, 71) * 0.8
										local lean = CFrame.Angles((h01(q.x, q.z, 72) - 0.5) * 0.45, 0, (h01(q.z, q.x, 73) - 0.5) * 0.45)
										local r = part(group, nil, Vector3.new(1.3, hh, 0.3), yaw(q.x, groundY(q.x, q.z) + hh / 2, q.z, hd + (k - 0.3) * 0.5 + j * 0.3) * lean, c3(128, 132, 76):Lerp(c3(96, 104, 58), k), Enum.Material.Grass)
										r.castShadow = false
									end
								end)
							end)
						end
					end
					if k > 0.86 then
						local p = Vec.add(c, Vec.scale(right, side * (half + 8 + k * 5)))
						if isOpen(p.x, p.z) and not nearBridge(p.x, p.z, 10) then
							tree(group, "willow", p.x, p.z, 4 + k * 2, true)
						end
					end
				end
				s += 7
			end
		end })
	end
end

-- Wayside stones and crosses every few hundred studs along the roads, outside villages.
local function buildMarkers(group: string, jobs: { Job })
	for ri, road in currentMap.roads do
		table.insert(jobs, { tag = "s", run = function()
			local pts = road.points
			local acc = 110 + h01(ri, 1, 140) * 100
			for n = 1, #pts - 1 do
				local a, b = pts[n], pts[n + 1]
				local len = Vec.dist(a, b)
				local dir = Vec.normalize(Vec.sub(b, a))
				local right = Vec.right(dir)
				local s = 0
				while s < len do
					if s >= acc then
						acc = s + 200 + h01(ri, s, 141) * 120
						local c = Vec.add(a, Vec.scale(dir, s))
						local p = Vec.add(c, Vec.scale(right, road.width / 2 + 2.2))
						if isOpen(p.x, p.z) then
							local y = groundY(p.x, p.z)
							obj("point", function()
								if h01(p.x, p.z, 142) < 0.5 then
									-- milestone
									part(group, nil, Vector3.new(0.7, 1.6, 0.5), yaw(p.x, y + 0.8, p.z, Vec.heading(dir)), STONE, Enum.Material.Slate)
								else
									-- wayside cross
									part(group, nil, Vector3.new(0.3, 3.4, 0.3), CFrame.new(p.x, y + 1.7, p.z), BEAM, Enum.Material.Wood)
									part(group, nil, Vector3.new(1.4, 0.3, 0.3), yaw(p.x, y + 2.7, p.z, Vec.heading(dir)), BEAM, Enum.Material.Wood)
								end
							end)
						end
					end
					s += 10
				end
				acc -= len
			end
		end })
	end
end

-- A watermill on the bank at the first brook bridge of each river: a mill house with a wheel.
local function buildMills(group: string)
	for _, river in currentMap.rivers do
		if river.width <= 40 then
			for _, br in currentMap.bridges do
				local mid = Vec.lerp(br.a, br.b, 0.5)
				local pts = river.points
				local near = false
				for n = 1, #pts - 1 do
					if Vec.distToSegment(mid, pts[n], pts[n + 1]) < river.width then
						near = true
					end
				end
				if near then
					local dir = Vec.normalize(Vec.sub(br.b, br.a))
					local right = Vec.right(dir)
					local p = Vec.add(Vec.add(mid, Vec.scale(dir, river.width / 2 + 7)), Vec.scale(right, br.width / 2 + 6))
					if isOpen(p.x, p.z) then
						local heading = Vec.heading(right)
						house(group, p.x, p.z, heading, 7, 5, "white", 143)
						local y = groundY(p.x, p.z)
						local wx = Vec.add(p, Vec.scale(dir, -4.2))
						obj("point", function()
							part(group, Enum.PartType.Cylinder, Vector3.new(0.6, 4.2, 4.2), yaw(wx.x, y + 2.1, wx.z, heading + math.pi / 2), BEAM, Enum.Material.Wood)
							part(group, Enum.PartType.Cylinder, Vector3.new(0.7, 2.6, 2.6), yaw(wx.x, y + 2.1, wx.z, heading + math.pi / 2), c3(130, 104, 74), Enum.Material.Wood)
						end)
					end
					break
				end
			end
		end
	end
end

-- Avenues: fruit trees (Thuringia, Moravia) or poplars (Brabant) along stretches of road
-- between villages.
local function buildAvenues(group: string, jobs: { Job })
	for ri, road in currentMap.roads do
		local pts = road.points
		for n = 1, #pts - 1 do
			local a, b = pts[n], pts[n + 1]
			table.insert(jobs, { tag = "s", run = function()
				local len = Vec.dist(a, b)
				local dir = Vec.normalize(Vec.sub(b, a))
				local right = Vec.right(dir)
				local step = if look.avenue == "poplar" then 13 else 11
				local s = step / 2
				while s < len do
					local c = Vec.add(a, Vec.scale(dir, s))
					local stretch = h01(ri * 97 + n, c.x // 140 + c.z // 140, 80)
					if stretch < 0.42 then
						for side = -1, 1, 2 do
							-- single-sided rows on some stretches
							if stretch > 0.15 or side == 1 then
								local p = Vec.add(c, Vec.scale(right, side * (road.width / 2 + 4)))
								if isOpen(p.x, p.z) and h01(p.x, p.z, 81) < 0.9 then
									if look.avenue == "poplar" then
										tree(group, "poplar", p.x, p.z, 4.5 + h01(p.z, p.x, 82), false)
									else
										tree(group, "oak", p.x, p.z, 2.6 + h01(p.z, p.x, 82), false)
									end
								end
							end
						end
					end
					s += step
				end
			end })
		end
	end
end

-------------------------------------------------------------------------------------- farmland

-- Hedges, dry-stone walls and post-and-rail fences (quality 2) on the field-block borders,
-- with the odd hedgerow oak; gaps where a border meets a road, village or wood.
local function borderPiece(group: string, kind: number, ax: number, az: number, bx: number, bz: number)
	local ay, by = groundY(ax, az), groundY(bx, bz)
	local mx, mz = (ax + bx) / 2, (az + bz) / 2
	local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local function along(height: number, width: number, lift: number, color: Color3, material: EnumMaterial, extra: number?): Spec
		local cf = CFrame.lookAt(Vector3.new(mx, (ay + by) / 2 + lift, mz), Vector3.new(bx, by + lift, bz))
		return part(group, nil, Vector3.new(width, height, len + (extra or 0)), cf, color, material)
	end
	if kind == 1 then
		local hh = 2.6 + h01(mx, mz, 90) * 1.2
		obj("linear", function()
			local hedge = along(hh, 2.6, hh / 2 - 0.3, look.hedge:Lerp(c3(52, 68, 36), h01(mz, mx, 91) * 0.3), Enum.Material.Grass, 1.2)
			if Assets.get("hedge") then
				hedge.fileMesh = "hedge" -- the generated hedgerow, fitted to this piece's box
			end
		end)
		if h01(mx, mz, 92) < 0.13 then
			tree(group, "oak", mx, mz, 4 + h01(mz, mx, 93) * 2, true)
		end
	elseif kind == 2 then
		obj("linear", function()
			local wall = along(1.5, 1.0, 0.75, STONE:Lerp(c3(120, 112, 96), h01(mx, mz, 94)), Enum.Material.Cobblestone, 0.4)
			if Assets.get("stoneWall") then
				wall.fileMesh = "stoneWall" -- the generated dry-stone wall, its own end pillars hiding the joins
			else
				-- a squared pillar at the join hides the step between tilted pieces
				part(group, nil, Vector3.new(1.2, 1.8, 1.2), CFrame.new(ax, ay + 0.9, az), STONE:Lerp(c3(100, 94, 82), 0.3), Enum.Material.Cobblestone)
			end
		end)
	elseif kind == 3 then
		withQ(2, function()
			obj("linear", function()
				local wood = c3(112, 92, 70)
				along(0.25, 0.25, 1.7, wood, Enum.Material.Wood).castShadow = false
				along(0.25, 0.25, 0.9, wood, Enum.Material.Wood).castShadow = false
				part(group, nil, Vector3.new(0.35, 2.3, 0.35), CFrame.new(ax, ay + 1.15, az), BEAM).castShadow = false
			end)
		end)
	end
end

local function buildBorders(group: string, jobs: { Job })
	local F = FIELD
	local W, D = currentMap.width, currentMap.depth
	local function nearestIs(x: number, z: number, i1: number, j1: number, i2: number, j2: number): boolean
		local ci, cj = math.floor(x / F), math.floor(z / F)
		local best, bi, bj = math.huge, 0, 0
		for di = -1, 1 do
			for dj = -1, 1 do
				local sx, sz = blockSeed(ci + di, cj + dj)
				local d = (x - sx) ^ 2 + (z - sz) ^ 2
				if d < best then
					best, bi, bj = d, ci + di, cj + dj
				end
			end
		end
		return (bi == i1 and bj == j1) or (bi == i2 and bj == j2)
	end
	for i = -1, math.ceil(W / F) do
		table.insert(jobs, { tag = "s", run = function()
			for j = -1, math.ceil(D / F) do
				for _, o in { { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } do
					local i2, j2 = i + o[1], j + o[2]
					local kind = borderKind(i, j, i2, j2)
					if kind <= 3 then
						local ax, az = blockSeed(i, j)
						local bx, bz = blockSeed(i2, j2)
						local mx, mz = (ax + bx) / 2, (az + bz) / 2
						local nx, nz = bx - ax, bz - az
						local nl = math.sqrt(nx * nx + nz * nz)
						local dx, dz = -nz / nl, nx / nl
						local t0, t1 = math.huge, -math.huge
						for t = -F * 1.2, F * 1.2, 4 do
							if nearestIs(mx + dx * t, mz + dz * t, i, j, i2, j2) then
								t0 = math.min(t0, t)
								t1 = math.max(t1, t)
							end
						end
						local pieceLen = 8
						local t = t0
						while t + pieceLen <= t1 + 2 do
							local px, pz = mx + dx * t, mz + dz * t
							local qx, qz = mx + dx * (t + pieceLen), mz + dz * (t + pieceLen)
							local cx, cz = (px + qx) / 2, (pz + qz) / 2
							if px > 0 and pz > 0 and qx > 0 and qz > 0 and px < W and qx < W and pz < D and qz < D
								and isOpen(px, pz) and isOpen(qx, qz) and isOpen(cx, cz) then
								borderPiece(group, kind, px, pz, qx, qz)
							end
							t += pieceLen
						end
					end
				end
			end
		end })
	end
end

-- Hay stooks (quality 2): rows in a few harvested (autumn, winter) or mown (summer) strips.
local function buildStooks(group: string, jobs: { Job })
	local F = FIELD
	for i = 0, math.ceil(currentMap.width / F) do
		table.insert(jobs, { tag = "s", run = function()
			for j = 0, math.ceil(currentMap.depth / F) do
				if h01(i, j, 100) < 0.3 then
					local sx, sz = blockSeed(i, j)
					local a = h01(j, i, 101) * math.pi
					local ca, sa = math.cos(a), math.sin(a)
					for u = -48, 48, 11 do
						for w = -48, 48, 9 do
							local x, z = sx + u * ca - w * sa, sz + u * sa + w * ca
							if isOpen(x, z) and fieldAt(x, z) == look.stookKind and h01(x, z, 102) < 0.7 then
								obj("point", function()
									local p = blob(group, Vector3.new(1.8, 2.3, 1.8), CFrame.new(x, groundY(x, z) + 1.15, z), look.stook:Lerp(c3(150, 130, 80), h01(z, x, 103) * 0.4))
									p.material = Enum.Material.Sand -- Fabric and Grass render straw near-black (Studio)
								end)
							end
						end
					end
				end
			end
		end })
	end
end

local function buildOrchard(group: string, o: Orchard)
	local ca, sa = math.cos(o.a), math.sin(o.a)
	for u = -o.hx + 3, o.hx - 3, 7 do
		for w = -o.hz + 3, o.hz - 3, 7 do
			local x = o.x + u * ca - w * sa + (h01(u, w, 110) - 0.5) * 1.5
			local z = o.z + u * sa + w * ca + (h01(w, u, 111) - 0.5) * 1.5
			if isOpen(x, z) then
				local y = groundY(x, z)
				tree(group, "oak", x, z, 2.1 + h01(x, z, 112) * 0.5, false, y)
			end
		end
	end
end

-- Windmills on the highest open ground near the larger villages (at most two a map).
local function buildWindmills(group: string)
	type Spot = { x: number, z: number, gain: number }
	local cands: { Spot } = {}
	for vi, v in currentMap.villages do
		local vy = groundY(v.pos.x, v.pos.z)
		local best: Spot? = nil
		for k = 0, 15 do
			local a = k / 16 * math.pi * 2 + h01(vi, k, 120)
			for _, d in { v.radius + 50, v.radius + 90, v.radius + 130 } do
				local x, z = v.pos.x + math.cos(a) * d, v.pos.z + math.sin(a) * d
				if isOpen(x, z) and isOpen(x + 4, z + 4) and isOpen(x - 4, z - 4) then
					local gain = groundY(x, z) - vy
					if gain > 5 and (best == nil or gain > best.gain) then
						best = { x = x, z = z, gain = gain }
					end
				end
			end
		end
		if best then
			table.insert(cands, best)
		end
	end
	table.sort(cands, function(a: Spot, b: Spot): boolean
		return a.gain > b.gain
	end)
	for n = 1, math.min(2, #cands) do
		windmill(group, cands[n].x, cands[n].z, h01(cands[n].x, cands[n].z, 121) * math.pi * 2)
	end
end

-- Ground fog in the valleys at dawn (detail tier, quality 2): three or four invisible anchor
-- boxes on the lowest level ground, laid along the valley. The client's Props puts a
-- ParticleEmitter of slow soft mist puffs on each; Lighting runs them only under the fog grade.
-- (Flat disc parts read as ovals lying on the field, whatever their transparency.)
local function buildGroundFog(group: string, jobs: { Job })
	local g = currentMap.grid
	local lo, hi = math.huge, -math.huge
	for _, h in g.height do
		lo = math.min(lo, h)
		hi = math.max(hi, h)
	end
	local floorY = lo + (hi - lo) * 0.3
	table.insert(jobs, { tag = "d", run = function()
		type Site = { x: number, z: number, y: number }
		local sites: { Site } = {}
		for x = 100, currentMap.width - 100, 60 do
			for z = 100, currentMap.depth - 100, 60 do
				local y = groundY(x, z)
				local sx = (groundY(x + 40, z) - groundY(x - 40, z)) / 80
				local sz = (groundY(x, z + 40) - groundY(x, z - 40)) / 80
				if y < floorY and sx * sx + sz * sz < 0.05 * 0.05 and classAt(x, z) ~= IDS.water then
					table.insert(sites, { x = x, z = z, y = y })
				end
			end
		end
		table.sort(sites, function(p: Site, q: Site): boolean
			return p.y < q.y or (p.y == q.y and (p.x < q.x or (p.x == q.x and p.z < q.z)))
		end)
		local chosen: { Site } = {}
		local function take(s: Site, apart: number): boolean
			for _, c in chosen do
				if (s.x - c.x) ^ 2 + (s.z - c.z) ^ 2 < apart * apart then
					return false
				end
			end
			table.insert(chosen, s)
			return true
		end
		-- one at every bridge, one every 250 studs along the rivers where the ground is low
		for _, br in currentMap.bridges do
			local m = Vec.lerp(br.a, br.b, 0.5)
			take({ x = m.x, z = m.z, y = groundY(m.x, m.z) }, 120)
		end
		for _, river in currentMap.rivers do
			if river.width <= 60 then
				local pts = river.points
				local acc = 125
				for n = 1, #pts - 1 do
					local a, b = pts[n], pts[n + 1]
					local len = Vec.dist(a, b)
					local d = acc
					while d < len do
						local q = Vec.lerp(a, b, d / len)
						if q.x > 40 and q.z > 40 and q.x < currentMap.width - 40 and q.z < currentMap.depth - 40 then
							local y = groundY(q.x, q.z)
							if y < floorY + (hi - lo) * 0.15 then
								take({ x = q.x, z = q.z, y = y }, 200)
							end
						end
						d += 250
					end
					acc = d - len
				end
			end
		end
		-- then the lowest open ground away from them
		for _, s in sites do
			if #chosen >= 10 then
				break
			end
			take(s, 320)
		end
		for _, s in chosen do
			-- along the valley: the nearest river's direction, else the contour direction
			local a = h01(s.x, s.z, 156) * math.pi
			local best = 400
			for _, river in currentMap.rivers do
				local pts = river.points
				for n = 1, #pts - 1 do
					local d = Vec.distToSegment({ x = s.x, z = s.z }, pts[n], pts[n + 1])
					if d < best then
						best = d
						a = math.atan2(pts[n + 1].z - pts[n].z, pts[n + 1].x - pts[n].x)
					end
				end
			end
			local p = part(group, nil, Vector3.new(110, 3, 50), yaw(s.x, s.y + 4, s.z, a), c3(222, 220, 214))
			p.transparency = 1
			p.castShadow = false
			p.buried = true -- invisible emitter box; may overlap a bank
		end
	end })
end

-------------------------------------------------------------------------------- distant country

-- Woods and hedgerow trees in the countryside beyond the playable area, so the horizon is a
-- layered line of trees and hills rather than a cut edge: the generated oak and beech where the
-- slots are filled (the engine draws them at a coarse level of detail out there), else crowns
-- only; no shadows either way.
local function buildCountry(group: string, jobs: { Job })
	local W, D = currentMap.width, currentMap.depth
	local per = 2 * (W + D)
	local step = 150
	local spacing = 16
	for k = 0, math.floor(per / step) - 1 do
		table.insert(jobs, { tag = "s", run = function()
			if h01(k, 3, 130) > 0.6 then
				return
			end
			-- point on the perimeter and its outward normal
			local s = k * step
			local x, z, nx, nz
			if s < W then
				x, z, nx, nz = s, 0, 0, -1
			elseif s < W + D then
				x, z, nx, nz = W, s - W, 1, 0
			elseif s < 2 * W + D then
				x, z, nx, nz = W - (s - W - D), D, 0, 1
			else
				x, z, nx, nz = 0, D - (s - 2 * W - D), -1, 0
			end
			local out_ = 70 + h01(k, 5, 131) * 420
			local cx, cz = x + nx * out_, z + nz * out_
			local rx, rz = 40 + h01(k, 6, 132) * 70, 26 + h01(k, 7, 133) * 40
			local tilt = h01(k, 8, 134) * math.pi
			local ct, st = math.cos(tilt), math.sin(tilt)
			for u = -rx, rx, spacing do
				for w = -rz, rz, spacing do
					local e = (u / rx) ^ 2 + (w / rz) ^ 2
					if e < 1 - h01(u + k, w, 135) * 0.35 then
						local px = cx + u * ct - w * st + (h01(u, w + k, 136) - 0.5) * spacing * 0.8
						local pz = cz + u * st + w * ct + (h01(w, u + k, 137) - 0.5) * spacing * 0.8
						local inside = px > -20 and pz > -20 and px < W + 20 and pz < D + 20
						local y, wet = model.heightAt(px, pz)
						if not inside and not wet then
							local r = 7 + h01(px, pz, 138) * 4
							local sp = if h01(pz, px, 139) < 0.35 then "beech" else "oak"
							local m = meshObject(group, SPECIES_KEY[sp], px, pz, h01(px, pz, 140) * 6.28, r * 2.4, r * 2.4, r * 2.4)
							if m then
								m.castShadow = false
							else
								obj("point", function()
									local p = part(group, Enum.PartType.Ball, Vector3.one * r * 2, CFrame.new(px, y + r * 1.15, pz), crownColor(px, pz))
									p.castShadow = false
								end)
							end
						end
					end
				end
			end
		end })
	end
end

-- Tiled plane (a part is capped at 2048 studs) `margin` studs beyond the map on every side.
local function tilePlane(map: any, margin: number, y: number, setup: (Spec) -> ())
	local TILE = 2048
	local x0, z0 = -margin, -margin
	local x1, z1 = map.width + margin, map.depth + margin
	local x = x0
	while x < x1 do
		local w = math.min(TILE, x1 - x)
		local z = z0
		while z < z1 do
			local d = math.min(TILE, z1 - z)
			local p = part("PickPlane", nil, Vector3.new(w, 1, d), CFrame.new(x + w / 2, y, z + d / 2), Color3.new(1, 1, 1), Enum.Material.Plastic)
			p.castShadow = false
			p.buried = true
			setup(p)
			z += d
		end
		x += w
	end
end

-- Invisible pick floor under the map and skirt, and a visible ground plane under the skirt's
-- outer edge so the country runs to the horizon from any height.
local function buildPlanes(map: any)
	local groundY_ = model.planeY
	tilePlane(map, 2000, math.min(model.minH, groundY_) - 1, function(p: Spec)
		p.name = "EoEPickPlane"
		p.canQuery = true
		p.transparency = 1
	end)
	local ground = rgb(model.season.grass):Lerp(Color3.new(0, 0, 0), 0.12)
	tilePlane(map, 5000, groundY_, function(p: Spec)
		p.name = "EoEGround"
		p.material = Enum.Material.Grass
		p.color = ground
	end)
end

-- Part specs for a map. `terrain` is WorldGen.terrain(map) (orchards, skirt heights). Yields
-- through opts.yield between jobs when given. Order is fixed, so the list is deterministic.
function WorldGen.props(map: any, terrain: TerrainModel, opts: Options?): { Spec }
	local o: Options = opts or {}
	beginFields(map)
	currentMap = map
	model = terrain
	look = LOOKS[WorldGen.seasonOf(map.id)]
	out = {}
	wantS = o.structure ~= false
	wantD = o.detail ~= false
	maxQ = o.maxQ or 3
	emitTier = "s"
	emitQ = 1

	-- conifers favour the top quarter of the map's height range
	local lo, hi = math.huge, -math.huge
	for _, hgt in map.grid.height do
		lo = math.min(lo, hgt)
		hi = math.max(hi, hgt)
	end
	local highGround = lo + (hi - lo) * 0.72

	local jobs: { Job } = {}
	local function job(tag: string, q: number, run: () -> ())
		table.insert(jobs, { tag = tag, run = function()
			emitQ = q
			run()
			emitQ = 1
		end })
	end
	job("s", 1, function()
		buildPlanes(map)
	end)
	for _, w in map.woods do
		for _, t in w.trees do
			-- quality 1 keeps the important trees, quality 2 (the server's cap) most of them
			local q = if t.priority >= 0.55 then 1 else 2
			if t.priority >= 0.25 then
				job("s", q, function()
					buildWoodsTree("Woods", t, highGround)
				end)
			end
		end
	end
	for _, v in map.villages do
		job("sd", 1, function()
			buildVillage("Villages", v)
		end)
	end
	for _, orch in terrain.orchards do
		job("s", 2, function()
			buildOrchard("Villages", orch)
		end)
	end
	job("s", 1, function()
		buildWindmills("Villages")
	end)
	for _, br in map.bridges do
		job("s", 1, function()
			buildBridge("Water", br)
		end)
	end
	for _, river in map.rivers do
		buildRiverside("Water", river, jobs)
	end
	buildAvenues("Fields", jobs)
	buildMarkers("Fields", jobs)
	job("sd", 1, function()
		buildMills("Water")
	end)
	buildGroundFog("GroundFog", jobs)
	buildBorders("Fields", jobs)
	local n0 = #jobs
	buildStooks("Fields", jobs)
	for i = n0 + 1, #jobs do
		local run = jobs[i].run
		jobs[i].run = function()
			emitQ = 2
			run()
			emitQ = 1
		end
	end
	buildCountry("Country", jobs)
	-- detail-only jobs (ground fog) emit the detail tier, at quality 2
	for _, j in jobs do
		if j.tag == "d" then
			local run = j.run
			j.run = function()
				emitTier = "d"
				emitQ = 2
				run()
				emitQ = 1
				emitTier = "s"
			end
		end
	end

	for _, j in jobs do
		if (j.tag ~= "d" and wantS) or (j.tag ~= "s" and wantD) then
			j.run()
			if o.yield then
				o.yield()
			end
		end
	end
	local result = out
	out = {}
	return result
end

-- Count of specs per class/material, for diffs and tests.
-- How far below the terrain model the lowest sample point of a spec sits (<= 0: clear).
function WorldGen.shortfall(s: Spec, terrain: TerrainModel): number
	local prev = model
	model = terrain
	local sf = shortfall(s)
	model = prev
	return sf
end

function WorldGen.tally(specs: { Spec }): { [string]: number }
	local t: { [string]: number } = {}
	for _, s in specs do
		local k = s.class .. "/" .. tostring(s.material.Name)
		t[k] = (t[k] or 0) + 1
	end
	return t
end

return WorldGen
