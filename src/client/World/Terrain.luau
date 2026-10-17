--!strict
-- Writes the MapGen heightmap into workspace.Terrain as 4-stud voxels, chunk by chunk,
-- yielding between chunks. Everything comes from MapData; nothing is authored here.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local RNG = require(Shared.RNG)

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

local function applyPalette()
	local P = Config.Visual.Palette
	local t = workspace.Terrain
	-- Studio showed the palette olive reading brown under warm low light; these are tuned with
	-- World/Lighting (ClockTime 10.2) toward the reference's olive-gold and green.
	-- olive-gold with green (Studio: 162,150,58 read orange/desert under the low warm sun)
	t:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(126, 136, 62))
	t:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(52, 74, 30))
	t:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(112, 92, 58)) -- dirt: roads and village lanes
	t:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(98, 88, 68))
	t:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(176, 162, 120)) -- pale but not white banks
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

local function analyse(map: any): ({ [number]: number }, { [number]: boolean }, { [number]: boolean })
	local g = map.grid
	local cols, rows = g.cols, g.rows
	local water: { [number]: number } = {}
	local bank: { [number]: boolean } = {}
	local roadOff: { [number]: boolean } = {}
	for cz = 0, rows - 1 do
		for cx = 0, cols - 1 do
			local idx = cz * cols + cx + 1
			local cls = g.class[idx]
			if cls == IDS.road and not roadCore(map, (cx + 0.5) * g.cell, (cz + 0.5) * g.cell) then
				roadOff[idx] = true
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
	return water, bank, roadOff
end

local function clearPickPlanes()
	if pickFolder then
		pickFolder:Destroy()
		pickFolder = nil
	end
	table.clear(pickPlanes)
end

-- Invisible pick floor under the map and skirt, tiled because a part is capped at 2048 studs.
local function ensurePickPlane(map: any, minY: number)
	clearPickPlanes()
	local folder = Instance.new("Folder") :: Folder
	folder.Name = "EoEPickPlane"
	folder.Parent = workspace
	pickFolder = folder
	local margin = 2000
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
			p.Name = "EoEPickPlane"
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = true
			p.Transparency = 1
			p.CastShadow = false
			p.Size = Vector3.new(w, 1, d)
			p.CFrame = CFrame.new(x + w / 2, minY - 1, z + d / 2)
			p.Parent = folder
			table.insert(pickPlanes, p)
			z += d
		end
		x += w
	end
end

-- The folder holding every pick-plane tile; raycast include lists take descendants.
function Terrain.pickPlane(): Instance?
	return pickFolder
end

function Terrain.bounds()
	return bounds
end

-- Builds the whole map. Yields. Returns false if cleared/superseded mid-build.
function Terrain.build(map: any, onProgress: ((fraction: number) -> ())?): boolean
	generation += 1
	local myGen = generation
	local terrain = workspace.Terrain
	terrain:Clear()
	applyPalette()

	local g = map.grid
	local cols, rows = g.cols, g.rows
	local cell = g.cell
	local minH = math.huge
	for i = 1, cols * rows do
		minH = math.min(minH, g.height[i])
	end
	local water, bank, roadOff = analyse(map)
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
	ensurePickPlane(map, minH)

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
		-- rivers run on past the edge along their end segments; banks rise above the water
		local rd, rlvl, rhalf = riverOut(x, z)
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
		-- one continuous field colour: copy the edge's ground only where it is plain grass
		return h, Enum.Material.Grass, nil
	end

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
