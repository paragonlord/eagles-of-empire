--!strict
-- Writes the MapGen heightmap into workspace.Terrain as 4-stud voxels, chunk by chunk,
-- yielding between chunks. Everything comes from MapData; nothing is authored here.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)

local Terrain = {}

local IDS = Config.TerrainIds
local VOXEL = 4
local CHUNK = 32 -- columns per chunk side
local CHUNKS_PER_YIELD = 2

local generation = 0
local pickPlane: Part? = nil
local bounds: { minY: number, maxY: number } = { minY = 0, maxY = 0 }

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function materialFor(cls: number, isBank: boolean): EnumMaterial
	if cls == IDS.woods then
		return Enum.Material.LeafyGrass
	elseif cls == IDS.village then
		return Enum.Material.Ground
	elseif cls == IDS.road then
		return Enum.Material.Cobblestone
	elseif cls == IDS.steep then
		return Enum.Material.Ground
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
	t:SetMaterialColor(Enum.Material.Grass, rgb(P.TerrainGrass):Lerp(Color3.fromRGB(176, 150, 72), 0.3)) -- olive-gold on lit plateaus
	t:SetMaterialColor(Enum.Material.LeafyGrass, rgb(P.TerrainWoodsFloor):Lerp(Color3.new(0, 0, 0), 0.25))
	t:SetMaterialColor(Enum.Material.Ground, rgb(P.TerrainSlope))
	t:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(96, 84, 70))
	t:SetMaterialColor(Enum.Material.Cobblestone, Color3.fromRGB(196, 184, 156)) -- roads read as thin pale lines
	t:SetMaterialColor(Enum.Material.Sand, rgb(P.Bank))
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
local function analyse(map: any): ({ [number]: number }, { [number]: boolean })
	local g = map.grid
	local cols, rows = g.cols, g.rows
	local water: { [number]: number } = {}
	local bank: { [number]: boolean } = {}
	for cz = 0, rows - 1 do
		for cx = 0, cols - 1 do
			local idx = cz * cols + cx + 1
			local cls = g.class[idx]
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
	return water, bank
end

local function ensurePickPlane(map: any, minY: number)
	if pickPlane then
		pickPlane:Destroy()
	end
	local p = Instance.new("Part") :: Part
	p.Name = "EoEPickPlane"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.Transparency = 1
	p.CastShadow = false
	p.Size = Vector3.new(map.width + 4000, 1, map.depth + 4000)
	p.CFrame = CFrame.new(map.width / 2, minY - 1, map.depth / 2)
	p.Parent = workspace
	pickPlane = p
end

function Terrain.pickPlane(): Part?
	return pickPlane
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
	local minH, maxH = math.huge, -math.huge
	for i = 1, cols * rows do
		local h = g.height[i]
		if h < minH then
			minH = h
		end
		if h > maxH then
			maxH = h
		end
	end
	local water, bank = analyse(map)
	for _, lvl in water do
		if lvl > maxH then
			maxH = lvl
		end
	end
	local y0 = math.floor((minH - 8) / VOXEL) * VOXEL
	local y1 = math.ceil((maxH + 4) / VOXEL) * VOXEL
	local ny = (y1 - y0) // VOXEL
	bounds = { minY = y0, maxY = y1 }
	ensurePickPlane(map, minH)

	local AIR = Enum.Material.Air
	local WATER = Enum.Material.Water
	local nChunksX = math.ceil(cols / CHUNK)
	local nChunksZ = math.ceil(rows / CHUNK)
	local total = nChunksX * nChunksZ
	local done = 0

	for chz = 0, nChunksZ - 1 do
		for chx = 0, nChunksX - 1 do
			if generation ~= myGen then
				return false
			end
			local cx0 = chx * CHUNK
			local cz0 = chz * CHUNK
			local nx = math.min(CHUNK, cols - cx0)
			local nz = math.min(CHUNK, rows - cz0)
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
				local cz = cz0 + iz - 1
				for ix = 1, nx do
					local cx = cx0 + ix - 1
					local idx = cz * cols + cx + 1
					local cls = g.class[idx]
					local lvl = water[idx]
					-- a bridge cell carries the deck height; its voxels are the river bed beneath
					local h = if cls == IDS.bridge and lvl ~= nil then lvl - 3 else g.height[idx]
					local mat = materialFor(cls, bank[idx] == true)
					for iy = 1, ny do
						-- + half a voxel: Roblox draws the surface VOXEL/2 above a linear fill (measured
						-- in Studio: +2.0 everywhere), and props/figures sit on Grid.heightAt
						local yBase = y0 + (iy - 1) * VOXEL + VOXEL / 2
						local groundOcc = math.clamp((h - yBase) / VOXEL, 0, 1)
						if lvl ~= nil then
							-- river bed below, water column up to the surface level
							local waterOcc = math.clamp((lvl - yBase) / VOXEL, 0, 1)
							if groundOcc > 0.5 then
								mats[ix][iy][iz] = Enum.Material.Sand
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
			local region = Region3.new(
				Vector3.new(cx0 * VOXEL, y0, cz0 * VOXEL),
				Vector3.new((cx0 + nx) * VOXEL, y1, (cz0 + nz) * VOXEL)
			)
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
	if pickPlane then
		pickPlane:Destroy()
		pickPlane = nil
	end
end

return Terrain
