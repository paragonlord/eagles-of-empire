--!strict
-- Engine side of the world pipeline: writes WorldGen's terrain model into workspace.Terrain
-- and instantiates WorldGen part specs. Server (structure tier, voxels) and client (detail
-- tier) share it. Every part is fully set up before it is parented, and parts are parented in
-- batches so replication arrives in a few bursts instead of thousands.

local Config = require(script.Parent.Config)
local WorldGen = require(script.Parent.WorldGen)
local Assets = require(script.Parent.Assets)

local WorldBuild = {}

local VOXEL = WorldGen.VOXEL
local CHUNK = 32 -- columns per chunk side
local CHUNKS_PER_YIELD = 2
WorldBuild.BATCH = 300 -- parts parented per frame

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- Terrain material colours and water for a map's season (replicates when the server sets it).
function WorldBuild.applyPalette(map: any)
	local P = Config.Visual.Palette
	local t = workspace.Terrain
	local season = WorldGen.season(map.id)
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
	t.WaterTransparency = 0.5
	t.WaterWaveSize = 0.08
	t.WaterWaveSpeed = 6
	t.WaterReflectance = 0.4
end

-- Writes the map and its skirt as 4-stud voxels, chunk by chunk, yielding between chunks.
-- Returns false when `alive` says the build was superseded.
function WorldBuild.writeVoxels(model: WorldGen.TerrainModel, alive: () -> boolean, onProgress: ((fraction: number) -> ())?): boolean
	local terrain = workspace.Terrain
	local SKIRT = WorldGen.SKIRT
	local column = model.column
	local AIR = Enum.Material.Air
	local WATER = Enum.Material.Water
	local SAND = Enum.Material.Sand
	local cxA, czA = -SKIRT, -SKIRT
	local cxB, czB = model.cols + SKIRT, model.rows + SKIRT
	local nChunksX = math.ceil((cxB - cxA) / CHUNK)
	local nChunksZ = math.ceil((czB - czA) / CHUNK)
	local total = nChunksX * nChunksZ
	local done = 0
	local colH = table.create(CHUNK * CHUNK, 0)
	local colM: { EnumMaterial } = table.create(CHUNK * CHUNK, AIR)
	local colW: { number | false } = table.create(CHUNK * CHUNK, false)

	for chz = 0, nChunksZ - 1 do
		for chx = 0, nChunksX - 1 do
			if not alive() then
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
	return alive()
end

-- One part from a spec, fully configured, unparented.
function WorldBuild.instance(s: WorldGen.Spec): BasePart
	local p: BasePart
	if s.class == "WedgePart" then
		p = Instance.new("WedgePart") :: WedgePart
	else
		local pp = Instance.new("Part") :: Part
		if s.shape then
			pp.Shape = s.shape
		end
		p = pp
	end
	if s.name then
		p.Name = s.name
	end
	p.Size = s.size
	p.CFrame = s.cframe
	p.Color = s.color
	p.Material = s.material
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = s.canQuery == true
	p.CastShadow = s.castShadow
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if s.transparency then
		p.Transparency = s.transparency
	end
	if s.mesh then
		local m = Instance.new("SpecialMesh") :: SpecialMesh
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	if s.buried then
		p:SetAttribute("Buried", true)
	end
	-- Creator Store assets: a filled mesh slot replaces the part's look with that mesh, a
	-- filled texture slot wraps the part's side faces (roof wedges: the slope)
	local slot = if s.fileMesh then Assets.get(s.fileMesh) else nil
	if s.fileMesh and slot then
		local m = Instance.new("SpecialMesh") :: SpecialMesh
		m.MeshType = Enum.MeshType.FileMesh
		m.MeshId = slot.mesh
		m.TextureId = slot.texture
		-- fit the mesh's native size to this object's box (trees vary in size), then the slot's tweak
		local n = slot.native
		local fit = if n then Vector3.new(s.size.X / n[1], s.size.Y / n[2], s.size.Z / n[3]) else Vector3.one
		m.Scale = fit * Vector3.new(slot.scale[1], slot.scale[2], slot.scale[3])
		m.Offset = Vector3.new(slot.offset[1], slot.offset[2], slot.offset[3])
		m.Parent = p
	end
	local tex = if s.texture then Assets.textureOf(s.texture) else nil
	if tex then
		-- a cylinder's axis is X, so its round side is Top/Bottom/Front/Back (Left/Right are the ends)
		local faces = if s.class == "WedgePart" then { Enum.NormalId.Top } elseif s.shape == Enum.PartType.Cylinder then { Enum.NormalId.Top, Enum.NormalId.Bottom, Enum.NormalId.Front, Enum.NormalId.Back } else { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
		for _, face in faces do
			local t = Instance.new("Texture") :: Texture
			t.Texture = tex
			t.Face = face
			t.StudsPerTileU = 4
			t.StudsPerTileV = 4
			-- tinted by the part so roofs and walls keep their own colours; bark stays as drawn
			-- (tinted by the dark trunk colour it went black in Studio)
			if s.texture ~= "bark" then
				t.Color3 = p.Color
			end
			t.Parent = p
		end
	end
	return p
end

-- Group folder name: specs needing quality 2 go in "<group>Q2" so a client can hide them.
function WorldBuild.groupName(s: WorldGen.Spec): string
	return if s.q >= 2 then s.group .. "Q2" else s.group
end

-- Instantiates specs under `root` in batches of BATCH parts, one yield per batch, each batch
-- parented as one folder so clients receive it as one replication burst. Returns the number
-- of parts made, or nil when `alive` says the build was superseded.
function WorldBuild.spawn(specs: { WorldGen.Spec }, root: Instance, alive: () -> boolean, onProgress: ((fraction: number) -> ())?): number?
	local groups: { [string]: Folder } = {}
	local function groupFolder(name: string): Folder
		local f = groups[name]
		if not f then
			f = Instance.new("Folder") :: Folder
			f.Name = name
			f.Parent = root
			groups[name] = f
		end
		return f
	end
	local batches: { [string]: Folder } = {}
	local inBatch = 0
	local made = 0
	local function flush()
		for name, b in batches do
			b.Parent = groupFolder(name)
		end
		table.clear(batches)
		inBatch = 0
	end
	for i, s in specs do
		local name = WorldBuild.groupName(s)
		local b = batches[name]
		if not b then
			b = Instance.new("Folder") :: Folder
			b.Name = "Batch"
			batches[name] = b
		end
		WorldBuild.instance(s).Parent = b
		inBatch += 1
		made += 1
		if inBatch >= WorldBuild.BATCH then
			flush()
			if onProgress then
				onProgress(i / #specs)
			end
			task.wait()
			if not alive() then
				return nil
			end
		end
	end
	flush()
	if onProgress then
		onProgress(1)
	end
	return made
end

return WorldBuild
