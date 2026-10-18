--!strict
-- Writes the MapGen heightmap into workspace.Terrain as 4-stud voxels, chunk by chunk,
-- yielding between chunks. Everything comes from MapData; nothing is authored here.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local RNG = require(Shared.RNG)
local Grid = require(Shared.Grid)

local Terrain = {}

local IDS = Config.TerrainIds
local VOXEL = 4
local CHUNK = 32 -- columns per chunk side
local CHUNKS_PER_YIELD = 2

local generation = 0
local pickPlanes: { Part } = {}
local pickFolder: Folder? = nil
local SKIRT = 160 -- cells (640 studs) of continuing country around every map
local SKIRT_FADE = 420 -- studs over which the skirt relaxes to a gentle plain
local bounds: { minY: number, maxY: number } = { minY = 0, maxY = 0 }
local skirtColumn: ((cx: number, cz: number) -> (number, EnumMaterial, number?))? = nil
local skirtCell = 4

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
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

-- Farmland. Fields are open-field strips: the country is cut into Voronoi blocks (~FIELD studs),
-- each block ploughed in parallel strips of one crop, the strips laid along the nearest road.
-- Block borders are hedges, walls, fences, cart tracks or nothing (Props builds the solid ones).
-- Cosmetic only: never read by the sim. Materials: Grass = meadow (the olive-gold base),
-- LeafyGrass = green pasture / gardens / woods floor, Limestone = wheat or stubble, Mud = plough.
local FIELD = 165
local KIND_MEADOW, KIND_PASTURE, KIND_WHEAT, KIND_PLOUGH = 1, 2, 3, 4
Terrain.KIND = { meadow = KIND_MEADOW, pasture = KIND_PASTURE, wheat = KIND_WHEAT, plough = KIND_PLOUGH }
Terrain.FIELD = FIELD

type Season = {
	crops: { number }, -- cumulative weights meadow, pasture, wheat, plough
	borders: { number }, -- cumulative weights hedge, wall, fence, track, (open)
	grass: { number },
	leafy: { number },
	wheat: { number },
	plough: { number },
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
	},
	winter = {
		crops = { 0.36, 0.50, 0.60, 1.0 },
		borders = { 0.10, 0.15, 0.25, 0.62 },
		grass = { 122, 126, 70 },
		leafy = { 86, 102, 52 },
		wheat = { 141, 133, 99 }, -- 0.84x: Limestone renders bright
		plough = { 90, 72, 56 },
	},
	summer = {
		crops = { 0.24, 0.44, 0.84, 1.0 },
		borders = { 0.46, 0.51, 0.66, 0.82 },
		grass = { 116, 136, 58 },
		leafy = { 76, 108, 42 },
		wheat = { 143, 134, 76 }, -- 0.84x: Limestone renders bright
		plough = { 104, 82, 58 },
	},
}
local MAP_SEASON: { [string]: string } = { austerlitz = "winter", waterloo = "summer" }
local season: Season = SEASONS.autumn
local fieldSeed = 1
local seedCache: { [number]: { number } } = {}
local angleCache: { [number]: number } = {}
local blockInfo: { [number]: { number } } = {} -- seed x, z, strip normal x, z, strip width, meadow
local fieldRoads: { any } = {}

function Terrain.seasonOf(mapId: string?): string
	return MAP_SEASON[mapId or ""] or "autumn"
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
Terrain.blockSeed = blockSeed

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
function Terrain.borderKind(i1: number, j1: number, i2: number, j2: number): number
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

-- Crop kind at (x, z), plus whether it is a cart track on a block border.
function Terrain.fieldAt(x: number, z: number): (number, boolean)
	local i1, j1, i2, j2, edge = nearestBlocks(x, z)
	if edge < 4.5 then
		local kind = Terrain.borderKind(i1, j1, i2, j2)
		if kind == 4 and edge < 2.2 then
			return KIND_MEADOW, true
		elseif kind ~= 5 then
			return KIND_MEADOW, false -- grass headland under hedges, walls and fences
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
		return KIND_MEADOW, false
	end
	-- across-strip coordinate
	local strip = math.floor(((x - blk[1]) * blk[3] + (z - blk[2]) * blk[4]) / blk[5])
	local r = RNG.hash(key, strip, fieldSeed + 32)
	for n, w in season.crops do
		if r < w then
			return n, false
		end
	end
	return KIND_MEADOW, false
end

local FIELD_MATERIAL = { Enum.Material.Grass, Enum.Material.LeafyGrass, Enum.Material.Limestone, Enum.Material.Mud }

local function applyPalette(mapId: string?)
	local P = Config.Visual.Palette
	local t = workspace.Terrain
	season = SEASONS[Terrain.seasonOf(mapId)]
	-- Grass stays olive-gold with green (Studio: 162,150,58 read orange/desert under a low warm sun).
	t:SetMaterialColor(Enum.Material.Grass, rgb(season.grass))
	t:SetMaterialColor(Enum.Material.LeafyGrass, rgb(season.leafy))
	t:SetMaterialColor(Enum.Material.Limestone, rgb(season.wheat))
	t:SetMaterialColor(Enum.Material.Mud, rgb(season.plough))
	t:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(112, 92, 58)) -- dirt: roads, tracks, yards
	t:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(122, 112, 98)) -- village streets
	t:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(98, 88, 68))
	t:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(160, 150, 112)) -- pale but not white banks
	t.WaterColor = rgb(P.Water)
	t.WaterTransparency = 0.35
	t.WaterWaveSize = 0.05
	t.WaterWaveSpeed = 4
	t.WaterReflectance = 0.2
end

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

-- Precompute per-cell water level and bank flags (cheap: only water/bridge cells scan rivers).
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
local function analyse(map: any): ({ [number]: number }, Marks, Marks, Marks, Marks)
	local g = map.grid
	local cols, rows = g.cols, g.rows
	local water: { [number]: number } = {}
	local bank: Marks = {}
	local roadOff: Marks = {}
	local verge: Marks = {} -- grass verges along roads and around villages: no crops there
	local street: Marks = {} -- road cores through villages, cobbled
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
				for dz = -r, r do
					for dx = -r, r do
						local nx, nz = cx + dx, cz + dz
						if nx >= 0 and nz >= 0 and nx < cols and nz < rows then
							verge[nz * cols + nx + 1] = true
						end
					end
				end
			end
			if cls == IDS.water or cls == IDS.bridge then
				local c = { x = (cx + 0.5) * g.cell, z = (cz + 0.5) * g.cell }
				local lvl = waterLevelAt(map, c.x, c.z)
				if lvl then
					water[idx] = lvl
					if cls == IDS.water then
						for dz = -2, 2 do
							for dx = -2, 2 do
								local nx, nz = cx + dx, cz + dz
								if nx >= 0 and nz >= 0 and nx < cols and nz < rows then
									local j = nz * cols + nx + 1
									if g.class[j] == IDS.open then
										bank[j] = true
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return water, bank, roadOff, verge, street
end

local function clearPickPlanes()
	if pickFolder then
		pickFolder:Destroy()
		pickFolder = nil
	end
	table.clear(pickPlanes)
end

-- Tiled plane (a part is capped at 2048 studs) `margin` studs beyond the map on every side.
local function tilePlane(folder: Folder, map: any, margin: number, y: number, setup: (Part) -> ())
	local TILE = 2048
	local x0, z0 = -margin, -margin
	local x1, z1 = map.width + margin, map.depth + margin
	local x = x0
	while x < x1 do
		local w = math.min(TILE, x1 - x)
		local z = z0
		while z < z1 do
			local d = math.min(TILE, z1 - z)
			local p = Instance.new("Part") :: Part
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.Size = Vector3.new(w, 1, d)
			p.CFrame = CFrame.new(x + w / 2, y, z + d / 2)
			setup(p)
			p.Parent = folder
			z += d
		end
		x += w
	end
end

-- Invisible pick floor under the map and skirt, and a visible ground plane under the skirt's
-- outer edge so the country runs to the horizon from any height (the skirt alone ended in a
-- cut edge over the sky from the intro sweep's 700 studs).
local function ensurePickPlane(map: any, minY: number, groundY: number, ground: Color3)
	clearPickPlanes()
	local folder = Instance.new("Folder") :: Folder
	folder.Name = "EoEPickPlane"
	folder.Parent = workspace
	pickFolder = folder
	tilePlane(folder, map, 2000, minY - 1, function(p: Part)
		p.Name = "EoEPickPlane"
		p.CanQuery = true
		p.Transparency = 1
		p.CastShadow = false
		table.insert(pickPlanes, p)
	end)
	tilePlane(folder, map, 5000, groundY, function(p: Part)
		p.Name = "EoEGround"
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.Grass
		p.Color = ground
	end)
end

-- The folder holding every pick-plane tile; raycast include lists take descendants.
function Terrain.pickPlane(): Instance?
	return pickFolder
end

function Terrain.bounds()
	return bounds
end

-- Ground height anywhere the last build wrote terrain, inside or outside the map (props use it
-- for the distant country; inside the map it equals the grid height).
function Terrain.heightAt(x: number, z: number): (number, boolean)
	local col = skirtColumn
	if not col then
		return 0, false
	end
	local h, _, lvl = col(math.floor(x / skirtCell), math.floor(z / skirtCell))
	return h, lvl ~= nil
end

-- Orchard plots beside the villages of the last build: { x, z, angle, hx, hz } (grass under the
-- trees here; Props plants them).
export type Orchard = { x: number, z: number, a: number, hx: number, hz: number }
local orchards: { Orchard } = {}
function Terrain.orchards(): { Orchard }
	return orchards
end

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

local function planOrchards(map: any)
	table.clear(orchards)
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
end

-- Builds the whole map. Yields. Returns false if cleared/superseded mid-build.
function Terrain.build(map: any, onProgress: ((fraction: number) -> ())?): boolean
	generation += 1
	local myGen = generation
	local terrain = workspace.Terrain
	terrain:Clear()
	applyPalette(map.id)
	fieldSeed = (map.seed or 1) + 313
	fieldRoads = map.roads
	table.clear(seedCache)
	table.clear(angleCache)
	table.clear(blockInfo)
	lastCi, lastCj = math.huge, math.huge
	planOrchards(map)

	local g = map.grid
	local cols, rows = g.cols, g.rows
	local cell = g.cell
	local minH = math.huge
	for i = 1, cols * rows do
		minH = math.min(minH, g.height[i])
	end
	local water, bank, roadOff, verge, street = analyse(map)
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
	bounds = { minY = math.floor((minH - 8) / VOXEL) * VOXEL, maxY = 0 }
	-- the ground plane sits under the skirt's noise and below any river channel leaving the map
	local planeY = plain - 16
	for _, river in map.rivers do
		planeY = math.min(planeY, river.level - 8)
	end
	ensurePickPlane(map, math.min(minH, planeY), planeY, rgb(season.grass):Lerp(Color3.new(0, 0, 0), 0.12))

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

	-- Column at cell (cx, cz), possibly outside the map: ground height, material, water level.
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
			if cls == IDS.open and not bank[idx] and not verge[idx] then
				if inOrchard(x, z) then
					return h, Enum.Material.LeafyGrass, lvl
				end
				local kind, track = Terrain.fieldAt(x, z)
				return h, if track then Enum.Material.Ground else FIELD_MATERIAL[kind], lvl
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
		local kind, track = Terrain.fieldAt(x, z)
		if crest > 0.6 and kind ~= KIND_PASTURE then
			kind = KIND_MEADOW
		end
		return h, if track then Enum.Material.Ground else FIELD_MATERIAL[kind], nil
	end
	skirtColumn = column
	skirtCell = cell

	local AIR = Enum.Material.Air
	local WATER = Enum.Material.Water
	local SAND = Enum.Material.Sand
	local cxA, czA = -SKIRT, -SKIRT
	local cxB, czB = cols + SKIRT, rows + SKIRT
	local nChunksX = math.ceil((cxB - cxA) / CHUNK)
	local nChunksZ = math.ceil((czB - czA) / CHUNK)
	local total = nChunksX * nChunksZ
	local done = 0
	local colH = table.create(CHUNK * CHUNK, 0)
	local colM: { EnumMaterial } = table.create(CHUNK * CHUNK, AIR)
	local colW: { number | false } = table.create(CHUNK * CHUNK, false)

	for chz = 0, nChunksZ - 1 do
		for chx = 0, nChunksX - 1 do
			if generation ~= myGen then
				return false
			end
			local cx0 = cxA + chx * CHUNK
			local cz0 = czA + chz * CHUNK
			local nx = math.min(CHUNK, cxB - cx0)
			local nz = math.min(CHUNK, czB - cz0)
			-- sample the columns first so the voxel slab is only as tall as this chunk needs
			local lo, hi = math.huge, -math.huge
			for iz = 1, nz do
				for ix = 1, nx do
					local h, m, lvl = column(cx0 + ix - 1, cz0 + iz - 1)
					local k = (iz - 1) * CHUNK + ix
					colH[k], colM[k], colW[k] = h, m, lvl or false
					lo = math.min(lo, h)
					hi = math.max(hi, if lvl then math.max(h, lvl) else h)
				end
			end
			local y0 = math.floor((lo - 8) / VOXEL) * VOXEL
			local y1 = math.ceil((hi + 4) / VOXEL) * VOXEL
			local ny = (y1 - y0) // VOXEL
			if y1 > bounds.maxY then
				bounds.maxY = y1
			end
			local mats: { { { EnumMaterial } } } = {}
			local occs: { { { number } } } = {}
			for ix = 1, nx do
				local mx: { { EnumMaterial } } = {}
				local ox: { { number } } = {}
				mats[ix] = mx
				occs[ix] = ox
				for iy = 1, ny do
					mx[iy] = table.create(nz, AIR)
					ox[iy] = table.create(nz, 0)
				end
			end
			for iz = 1, nz do
				for ix = 1, nx do
					local k = (iz - 1) * CHUNK + ix
					local h, mat, lvl = colH[k], colM[k], colW[k]
					for iy = 1, ny do
						-- + half a voxel: Roblox draws the surface VOXEL/2 above a linear fill (measured
						-- in Studio: +2.0 everywhere), and props/figures sit on Grid.heightAt
						local yBase = y0 + (iy - 1) * VOXEL + VOXEL / 2
						local groundOcc = math.clamp((h - yBase) / VOXEL, 0, 1)
						if lvl then
							-- river bed below, water column up to the surface level
							local waterOcc = math.clamp((lvl - yBase) / VOXEL, 0, 1)
							if groundOcc > 0.5 then
								mats[ix][iy][iz] = SAND
								occs[ix][iy][iz] = groundOcc
							elseif waterOcc > 0 then
								mats[ix][iy][iz] = WATER
								occs[ix][iy][iz] = waterOcc
							end
						elseif groundOcc > 0 then
							mats[ix][iy][iz] = mat
							occs[ix][iy][iz] = groundOcc
						end
					end
				end
			end
			local region = Region3.new(Vector3.new(cx0 * VOXEL, y0, cz0 * VOXEL), Vector3.new((cx0 + nx) * VOXEL, y1, (cz0 + nz) * VOXEL))
			terrain:WriteVoxels(region, VOXEL, mats, occs)
			done += 1
			if onProgress then
				onProgress(done / total)
			end
			if done % CHUNKS_PER_YIELD == 0 then
				task.wait()
			end
		end
	end
	return generation == myGen
end

function Terrain.clear()
	generation += 1
	workspace.Terrain:Clear()
	clearPickPlanes()
end

return Terrain
