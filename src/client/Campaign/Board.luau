--!strict
-- Grand-campaign tabletop: Europe as a painted relief on a walnut table, far from the
-- battlefield. The land is terrain (real coasts, rivers and mountains from Relief/EuropeGeo,
-- written locally on this client) under a tint of owner colours clipped to the coast. Static
-- geometry (terrain, tint strips, towns, forts, piers, names) builds once;
-- owner colours, borders, occupation hatching, armies, highlights and the path preview follow
-- each view. Map units (0..2000 × 0..1500, +z north) map to world X east, world -Z north, so
-- the default camera looking along -Z sees north at the top and east on the right.

local UserInputService = game:GetService("UserInputService") :: UserInputService
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Relief = require(Shared.Relief)
local Data = require(script.Parent.Data)
local Soldiers = require(script.Parent.Parent.World.Soldiers)
local Assets = require(Shared.Assets)
local Kit = require(script.Parent.Parent.UI.Kit)

local Board = {}

local ORIGIN = Vector3.new(8000, 0, 0) -- the battlefield spans 0..1600 × 0..1200
local S = 0.55 -- studs per map unit
local LAND = 2 -- the lowland's surface; hills rise from it
local TINT_Y = LAND + 0.35 -- the owner tint lies just over the lowland, so hills rise through it
local SEA_Y = 0 -- water surface
local CELL = 8 -- map units per land cell (EuropeGeo.Cell)
local VOX = 4 -- terrain voxel, studs
local TINT = 0.45 -- transparency of the owner tint over the land
local W, D = 2000 * S, 1500 * S

local PARCH = Color3.fromRGB(226, 212, 176)
local INK = Color3.fromRGB(42, 36, 32)
local STONE = Color3.fromRGB(150, 144, 134)
local WALL = Color3.fromRGB(196, 178, 146)
local ROOF = Color3.fromRGB(122, 66, 46)
local RED = Color3.fromRGB(196, 58, 44)

local folder: Folder? = nil
local dyn: Folder? = nil -- borders, hatching, armies (rebuilt per view)
local hi: Folder? = nil -- path preview (rebuilt per hover)
local landParts: { [string]: { BasePart } } = {}
local baseColour: { [string]: Color3 } = {}
type Edge = { a: { x: number, z: number }, b: { x: number, z: number }, provs: { string } }
local edges: { [string]: Edge } = {}
local armyModels: { [any]: Model } = {}
local moorings: { [string]: { at: Vector3, dir: Vector3 } } = {} -- each port's pier: where its fleets lie
local highlight: Highlight? = nil
type Label = { part: BasePart, base: number, at: Vector3 }
local labels: { Label } = {}
local labelK = 0
local FIG = 1.6 -- figure scale

-- A map point on the board; without `y` it stands on the ground (the tint, or a hill above it).
function Board.toWorld(x: number, z: number, y: number?): Vector3
	return Vector3.new(ORIGIN.X + x * S, ORIGIN.Y + (y or (TINT_Y + 0.1 + math.max(0, Relief.height(x, z) - 0.45))), ORIGIN.Z - z * S)
end

-- World-space rectangle of the board (x0 < x1, z0 < z1) and the base height.
function Board.bounds(): (number, number, number, number, number)
	return ORIGIN.X, ORIGIN.Z - D, ORIGIN.X + W, ORIGIN.Z, ORIGIN.Y
end

-- ------------------------------------------------------------------ primitives

local function part(parent: Instance, size: Vector3, cf: CFrame, colour: Color3, material: EnumMaterial?): Part
	local p = Instance.new("Part") :: Part
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cylinder(parent: Instance, pos: Vector3, h: number, d: number, colour: Color3, material: EnumMaterial?): Part
	local p = part(parent, Vector3.new(h, d, d), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), colour, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A bar lying from p to q (world points).
local function segment(parent: Instance, p: Vector3, q: Vector3, width: number, height: number, colour: Color3): Part?
	local len = (q - p).Magnitude
	if len < 0.05 then
		return nil
	end
	local s = part(parent, Vector3.new(width, height, len + width * 0.5), CFrame.lookAt((p + q) / 2, q), colour)
	s.CastShadow = false
	return s
end

-- A box turned 45° about its long axis, sunk to its middle: a gable roof or a mountain ridge.
local function ridge(parent: Instance, pos: Vector3, yaw: number, len: number, s: number, colour: Color3, material: EnumMaterial?): Part
	return part(parent, Vector3.new(len, s, s), CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(45), 0, 0), colour, material)
end

type Pt = { x: number, z: number }

local function key(p: Pt): string
	return string.format("%d,%d", math.round(p.x), math.round(p.z))
end

-- ------------------------------------------------------------------ static pieces

-- Same technique as World/Props ground labels: a Top-face SurfaceGui (400×100 canvas) whose
-- text runs along the part's -Z, here turned -90° so it reads left-to-right looking along -Z.
local function groundLabel(parent: Instance, text: string, pos: Vector3, height: number): BasePart
	local len = height * 4
	local p = part(parent, Vector3.new(height, 0.2, len), CFrame.new(pos) * CFrame.Angles(0, -math.pi / 2, 0), Color3.new(1, 1, 1))
	p.Transparency = 1
	p.CastShadow = false
	local gui = Instance.new("SurfaceGui") :: SurfaceGui
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(400, 100)
	gui.LightInfluence = 0
	gui.Parent = p
	local l = Instance.new("TextLabel") :: TextLabel
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Garamond
	l.TextScaled = true
	l.Text = text
	-- dark ink with a pale halo reads on every owner tint and on the terrain (ivory did not)
	l.TextColor3 = INK
	l.TextStrokeColor3 = Kit.IVORY
	l.TextStrokeTransparency = 0.45
	l.TextTransparency = 0.05
	l.Parent = gui
	return p
end

-- A house: one of the battlefield's generated house meshes fitted to the box, or two parts.
local HOUSE_KEYS = { "houseA", "houseB", "barn" }
local function house(parent: Instance, pos: Vector3, w: number, d: number, h: number, yaw: number, key: string?)
	local slot = Assets.get(key or HOUSE_KEYS[math.floor(pos.X * 7 + pos.Z * 3) % #HOUSE_KEYS + 1])
	local native = if slot then slot.native else nil
	if slot and native then
		local hh = h * 1.6 -- the meshes carry their roof inside the box
		local p = part(parent, Vector3.new(w, hh, d), CFrame.new(pos + Vector3.new(0, hh / 2, 0)) * CFrame.Angles(0, yaw, 0), Color3.new(1, 1, 1))
		local m = Instance.new("SpecialMesh") :: SpecialMesh
		m.MeshType = Enum.MeshType.FileMesh
		m.MeshId = slot.mesh
		m.TextureId = slot.texture
		m.Scale = Vector3.new(w / native[1], hh / native[2], d / native[3])
		m.Parent = p
		return
	end
	local base = part(parent, Vector3.new(w, h, d), CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, yaw, 0), WALL)
	base.CastShadow = true
	ridge(parent, pos + Vector3.new(0, h, 0), yaw, w + 0.3, d * 0.72, ROOF)
end

-- A market town: a few houses round a point, so every province shows where its people live.
local function town(parent: Instance, c: Vector3, n: number)
	local rng = Random.new(math.floor(c.X * 17 + c.Z * 5))
	for i = 1, n do
		local a = i / n * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local r = if i == 1 then 0 else rng:NextNumber(2.2, 3.6)
		house(parent, c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), rng:NextNumber(2.2, 3.2), rng:NextNumber(1.6, 2.2), rng:NextNumber(1.2, 1.8), rng:NextInteger(0, 3) * math.pi / 2)
	end
end

local function capital(parent: Instance, c: Vector3)
	local rng = Random.new(math.floor(c.X * 13 + c.Z))
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local r = if i == 1 then 0 else rng:NextNumber(2.4, 4.2)
		house(parent, c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), rng:NextNumber(2, 3.4), rng:NextNumber(1.6, 2.4), rng:NextNumber(1.4, 2.6), rng:NextInteger(0, 1) * math.pi / 2)
	end
	-- cathedral tower and a gilded star above it
	part(parent, Vector3.new(1.4, 6, 1.4), CFrame.new(c + Vector3.new(0.4, 3, -1.2)), WALL)
	local starAt = c + Vector3.new(0.4, 8.2, -1.2)
	for _, rot in { 0, math.pi / 4 } do
		local s = part(parent, Vector3.new(2.2, 2.2, 0.3), CFrame.new(starAt) * CFrame.Angles(0, 0, rot), Kit.GILT_BRIGHT, Enum.Material.Foil)
		s.CastShadow = false
	end
end

local function bastion(parent: Instance, c: Vector3, level: number)
	local k = if level >= 2 then 1.4 else 1
	local half, h = 3 * k, 1.4 * k
	for _, sgn in { -1, 1 } do
		part(parent, Vector3.new(half * 2, h, 0.8), CFrame.new(c + Vector3.new(0, h / 2, sgn * half)), STONE)
		part(parent, Vector3.new(0.8, h, half * 2), CFrame.new(c + Vector3.new(sgn * half, h / 2, 0)), STONE)
		for _, sz in { -1, 1 } do
			part(parent, Vector3.new(2 * k, h * 1.1, 2 * k), CFrame.new(c + Vector3.new(sgn * half, h * 0.55, sz * half)) * CFrame.Angles(0, math.pi / 4, 0), STONE)
		end
	end
end

local function pier(parent: Instance, from: Vector3, dir: Vector3)
	local y = Vector3.new(0, ORIGIN.Y + SEA_Y + 0.5 - from.Y, 0)
	local a, b = from + y - dir * 1.5, from + y + dir * 9
	segment(parent, a, b, 2, 0.4, Color3.fromRGB(110, 84, 58))
	for _, t in { 0.45, 0.95 } do
		local p = a:Lerp(b, t)
		local side = Vector3.new(-dir.Z, 0, dir.X)
		for _, sgn in { -1, 1 } do
			cylinder(parent, p + side * sgn + Vector3.new(0, -0.3, 0), 1.2, 0.4, Color3.fromRGB(80, 60, 42))
		end
	end
end

-- The land as terrain, written on this client only (the server never sees the board). Columns
-- of 4-stud voxels: sea bed and water off the coast, ground up to the lowland or the hills
-- elsewhere, with rock on the slopes and snow on the high chains.
local function landMaterial(mx: number, mz: number, h: number): EnumMaterial
	if Relief.snow(mx, mz) then
		return Enum.Material.Snow
	elseif h > 2.5 then
		return Enum.Material.Rock
	end
	local coast = not (Relief.isLand(mx + CELL, mz) and Relief.isLand(mx - CELL, mz) and Relief.isLand(mx, mz + CELL) and Relief.isLand(mx, mz - CELL))
	if coast then
		return Enum.Material.Sand
	end
	local n = math.noise(mx / 61, mz / 61, 7.1)
	if mz < 300 and n > -0.15 then
		return Enum.Material.Ground -- the dry south: Iberia, southern Italy, Greece, Anatolia
	end
	return if n > 0.18 then Enum.Material.LeafyGrass else Enum.Material.Grass
end

local Y0, LAYERS = -8, 7 -- terrain floor and voxel layers (to y = 20)
local function writeRelief()
	local terrain = workspace.Terrain
	local gx0 = math.floor(ORIGIN.X / VOX)
	local gx1 = math.ceil((ORIGIN.X + W) / VOX) - 1
	local gz0 = math.floor((ORIGIN.Z - D) / VOX)
	local gz1 = math.ceil(ORIGIN.Z / VOX) - 1
	local CHUNK = 24
	for cx = gx0, gx1, CHUNK do
		local nx = math.min(CHUNK, gx1 - cx + 1)
		local nz = gz1 - gz0 + 1
		local mats: { { { EnumMaterial } } } = {}
		local occ: { { { number } } } = {}
		for i = 1, nx do
			local mi: { { EnumMaterial } } = {}
			local oi: { { number } } = {}
			for j = 1, LAYERS do
				mi[j] = table.create(nz, Enum.Material.Air)
				oi[j] = table.create(nz, 0)
			end
			mats[i], occ[i] = mi, oi
			local gx = cx + i - 1
			local mx = ((gx + 0.5) * VOX - ORIGIN.X) / S
			for k = 1, nz do
				local gz = gz0 + k - 1
				local mz = (ORIGIN.Z - (gz + 0.5) * VOX) / S
				local land = Relief.isLand(mx, mz)
				if land then
					local h = Relief.height(mx, mz)
					local top = LAND + h -- the surface, board y
					local m = landMaterial(mx, mz, h)
					for j = 1, LAYERS do
						local lo = Y0 + (j - 1) * VOX
						if top >= lo + VOX then
							mi[j][k], oi[j][k] = if j <= 2 or top - (lo + VOX) > VOX then Enum.Material.Rock else m, 1
						elseif top > lo then
							-- smooth terrain draws a part-full voxel's surface between its middle
							-- (nearly empty) and its top (full), measured in Studio
							mi[j][k], oi[j][k] = m, math.clamp((top - lo - VOX / 2) / (VOX / 2), 0.02, 1)
						end
					end
				else
					mi[1][k], oi[1][k] = Enum.Material.Sand, 1
					mi[2][k], oi[2][k] = Enum.Material.Water, 1
				end
			end
		end
		local lo = Vector3.new(cx * VOX, ORIGIN.Y + Y0, gz0 * VOX)
		local region = Region3.new(lo, lo + Vector3.new(nx * VOX, LAYERS * VOX, nz * VOX))
		terrain:WriteVoxels(region, VOX, mats, occ)
		task.wait()
	end
end

-- Owner tint over the land: one thin strip per row run of a province, clipped to the coast,
-- so a province's colour stops at its real shore. The strips are what a click picks.
local function tintStrips(parent: Instance)
	local cols, rows = math.floor(2000 / CELL), math.floor(1500 / CELL)
	for r = 1, rows do
		local zc = (r - 0.5) * CELL
		local runStart, runProv = 0, nil :: string?
		for c = 1, cols + 1 do
			local xc = (c - 0.5) * CELL
			local prov = if c <= cols and Relief.isLand(xc, zc) then Relief.provinceAt(xc, zc) else nil
			if prov ~= runProv then
				local rp = runProv
				if rp then
					local x0, x1 = (runStart - 1) * CELL, (c - 1) * CELL
					local strip = part(parent, Vector3.new((x1 - x0) * S, 0.03, CELL * S), CFrame.new(Board.toWorld((x0 + x1) / 2, zc, TINT_Y)), baseColour[rp] or PARCH)
					strip.Transparency = TINT
					strip.CastShadow = false
					strip.CanQuery = true
					strip:SetAttribute("prov", rp)
					table.insert(landParts[rp], strip)
				end
				runStart, runProv = c, prov
			end
		end
		if r % 16 == 0 then
			task.wait()
		end
	end
end

-- The point where a port's coast is nearest its centre, and the way out to sea.
local function coastOf(p: any): (Vector3?, Vector3?)
	local best: { x: number, z: number, dx: number, dz: number }? = nil
	local bestR = math.huge
	for a = 0, 23 do
		local dx, dz = math.cos(a / 24 * math.pi * 2), math.sin(a / 24 * math.pi * 2)
		for r = 4, 160, 4 do
			local x, z = p.centre.x + dx * r, p.centre.z + dz * r
			if not Relief.isLand(x, z) then
				if r < bestR then
					bestR, best = r, { x = x - dx * 4, z = z - dz * 4, dx = dx, dz = dz }
				end
				break
			end
		end
	end
	local b = best
	if not b then
		return nil, nil
	end
	return Board.toWorld(b.x, b.z), Vector3.new(b.dx, 0, -b.dz)
end

-- The server clears all terrain when it builds a battle map, the board's local relief with it;
-- reopening the board writes it again.
local function reliefMissing(): boolean
	local c = Data.Provinces[1].centre
	local at = Board.toWorld(c.x, c.z, LAND - 1)
	local lo = Vector3.new(math.floor(at.X / VOX) * VOX, math.floor(at.Y / VOX) * VOX, math.floor(at.Z / VOX) * VOX)
	local mats = workspace.Terrain:ReadVoxels(Region3.new(lo, lo + Vector3.one * VOX), VOX)
	return mats[1][1][1] == Enum.Material.Air
end

function Board.build()
	if folder then
		if reliefMissing() then
			writeRelief()
		end
		return
	end
	local f = Instance.new("Folder") :: Folder
	f.Name = "EoEGrandBoard"
	-- the walnut table and its gilt edge; the land and the sea are terrain (writeRelief)
	local mid = ORIGIN + Vector3.new(W / 2, 0, -D / 2)
	part(f, Vector3.new(W + 140, 6, D + 140), CFrame.new(mid + Vector3.new(0, Y0 - 3, 0)), Kit.WALNUT_LIGHT, Enum.Material.Wood)
	for _, e in { { Vector3.new(0, 0, -D / 2 - 4), Vector3.new(W + 8, 0, 0) }, { Vector3.new(0, 0, D / 2 + 4), Vector3.new(W + 8, 0, 0) }, { Vector3.new(-W / 2 - 4, 0, 0), Vector3.new(0, 0, D + 8) }, { Vector3.new(W / 2 + 4, 0, 0), Vector3.new(0, 0, D + 8) } } do
		local c, l = e[1], e[2]
		part(f, Vector3.new(math.max(l.X, 3), LAND - Y0 + 1, math.max(l.Z, 3)), CFrame.new(mid + c + Vector3.new(0, (LAND + Y0) / 2, 0)), Kit.GILT, Enum.Material.Foil)
	end

	local statics = Instance.new("Folder") :: Folder
	statics.Name = "Statics"
	statics.Parent = f
	for _, p in Data.Provinces do
		local pts = p.outline :: { Pt }
		landParts[p.id] = {}
		baseColour[p.id] = Data.colour(p.owner1805):Lerp(PARCH, 0.22)
		for i = 1, #pts do
			local a, b = pts[i], pts[i % #pts + 1]
			local ka, kb = key(a), key(b)
			local k = if ka < kb then ka .. "|" .. kb else kb .. "|" .. ka
			local e = edges[k]
			if e then
				table.insert(e.provs, p.id)
			else
				edges[k] = { a = a, b = b, provs = { p.id } }
			end
		end
		local c = Board.toWorld(p.centre.x, p.centre.z)
		local nation = Data.Nations[p.owner1805]
		local base = if p.isCapital and nation and nation.capital == p.id and nation.major then 9 elseif p.isCapital then 7.5 else 6
		local at = c + Vector3.new(0, 0.25, 0)
		table.insert(labels, { part = groundLabel(statics, p.name, at + Vector3.new(0, 0, 14 + base * 0.5), base), base = base, at = at })
		if p.isCapital then
			capital(statics, Board.toWorld(p.centre.x - 17 / S, p.centre.z + 15 / S))
		else
			town(statics, Board.toWorld(p.centre.x - 17 / S, p.centre.z + 15 / S), 3)
		end
		if (p.fort or 0) > 0 then
			bastion(statics, Board.toWorld(p.centre.x + 17 / S, p.centre.z + 15 / S), p.fort)
		end
	end
	tintStrips(f)
	-- rivers: thin blue lines over the tint, as on a campaign map
	for _, r in Relief.rivers() do
		for i = 1, #r.pts - 1 do
			local a, b = r.pts[i], r.pts[i + 1]
			local ra = segment(statics, Board.toWorld(a.x, a.z, TINT_Y + 0.08), Board.toWorld(b.x, b.z, TINT_Y + 0.08), 0.9, 0.12, Color3.fromRGB(78, 104, 150))
			if ra then
				ra.Transparency = 0.1
			end
		end
	end
	-- piers where each port's coast is nearest its centre
	for _, p in Data.Provinces do
		if p.isPort then
			local at, dir = coastOf(p)
			if at and dir then
				pier(statics, at, dir)
				moorings[p.id] = { at = at, dir = dir }
			end
		end
	end
	writeRelief()
	local dy = Instance.new("Folder") :: Folder
	dy.Name = "Dynamic"
	dy.Parent = f
	local h = Instance.new("Folder") :: Folder
	h.Name = "Path"
	h.Parent = f
	dyn, hi = dy, h
	f.Parent = workspace
	folder = f
end

-- ------------------------------------------------------------------ dynamic layer

-- Stripes across a polygon (map units), clipped by pairing edge crossings along each line.
local function hatch(parent: Instance, pts: { Pt }, colour: Color3)
	local dx, dz = 0.7071, 0.7071 -- stripe direction
	local nx, nz = 0.7071, -0.7071 -- sweep direction
	local lo, hiS = math.huge, -math.huge
	for _, p in pts do
		local s = p.x * nx + p.z * nz
		lo, hiS = math.min(lo, s), math.max(hiS, s)
	end
	local s = lo + 9
	while s < hiS do
		local ox, oz = nx * s, nz * s
		local ts = {}
		for i = 1, #pts do
			local a, b = pts[i], pts[i % #pts + 1]
			local ex, ez = b.x - a.x, b.z - a.z
			local den = dx * ez - dz * ex
			if math.abs(den) > 1e-9 then
				local wx, wz = a.x - ox, a.z - oz
				local t = (wx * ez - wz * ex) / den
				local u = (wx * dz - wz * dx) / den
				if u >= 0 and u < 1 then
					table.insert(ts, t)
				end
			end
		end
		table.sort(ts)
		for i = 1, #ts - 1, 2 do
			-- in coast-length pieces, so the stripes stop at the shore
			local n = math.max(1, math.ceil((ts[i + 1] - ts[i]) / CELL))
			for k = 0, n - 1 do
				local t0 = ts[i] + (ts[i + 1] - ts[i]) * k / n
				local t1 = ts[i] + (ts[i + 1] - ts[i]) * (k + 1) / n
				local tm = (t0 + t1) / 2
				if Relief.isLand(ox + dx * tm, oz + dz * tm) then
					local st = segment(parent, Board.toWorld(ox + dx * t0, oz + dz * t0, TINT_Y + 0.1), Board.toWorld(ox + dx * t1, oz + dz * t1, TINT_Y + 0.1), 2.2, 0.12, colour)
					if st then
						st.Transparency = 0.15
					end
				end
			end
		end
		s += 18
	end
end

local function flagCloth(parent: Instance, nation: string, at: Vector3)
	local fl = Data.flag(nation)
	local w, h = 3.6, 2.4
	local bands = fl.bands
	if bands then
		for i, c in bands do
			part(parent, Vector3.new(w / #bands, h, 0.15), CFrame.new(at + Vector3.new((i - 0.5) / #bands * w - w / 2, 0, 0)), c)
		end
	else
		part(parent, Vector3.new(w, h, 0.15), CFrame.new(at), fl.field or Kit.IVORY)
		local m = fl.mark
		if m == "x" or m == "diagonal" then
			part(parent, Vector3.new(w * 1.1, 0.35, 0.18), CFrame.new(at) * CFrame.Angles(0, 0, math.atan2(h, w)), fl.markColour)
		end
		if m == "x" then
			part(parent, Vector3.new(w * 1.1, 0.35, 0.18), CFrame.new(at) * CFrame.Angles(0, 0, -math.atan2(h, w)), fl.markColour)
		elseif m == "plus" or m == "double" then
			part(parent, Vector3.new(w, 0.35, 0.18), CFrame.new(at), fl.markColour)
		end
	end
end

-- A mounted general on a plinth with his nation's flag and a strength plate.
local function figure(parent: Instance, a: any, pos: Vector3): Model
	local m = Instance.new("Model") :: Model
	m.Name = "Army"
	m:SetAttribute("army", a.id)
	local coat = Data.colour(a.nation)
	local horse = Color3.fromRGB(92, 64, 44)
	local function piece(size: Vector3, offset: Vector3, colour: Color3, rot: CFrame?): Part
		local p = part(m, size, CFrame.new(pos + offset) * (rot or CFrame.identity), colour)
		p.CanQuery = true
		return p
	end
	local plinth = cylinder(m, pos + Vector3.new(0, 0.6, 0), 1.2, 7, Kit.WALNUT, Enum.Material.Wood)
	plinth.CanQuery = true
	cylinder(m, pos + Vector3.new(0, 1.15, 0), 0.25, 7.3, Kit.GILT, Enum.Material.Foil)
	local top = 1.2
	local kit = Soldiers.mountedKit(a.nation)
	if kit then
		-- the nation's generated horse and rider, twice battle size, as a painted token
		for _, k in kit do
			local p = k.part
			p.CFrame = CFrame.new(pos + Vector3.new(0, top, 0)) * CFrame.new(k.cf.Position * 2) * k.cf.Rotation
			p.Size *= 2
			local m2 = p:FindFirstChildOfClass("SpecialMesh") :: SpecialMesh?
			if m2 then
				m2.Scale *= 2
			end
			p.CanQuery = true
			p.Parent = m
		end
	else
		piece(Vector3.new(4.4, 1.9, 1.8), Vector3.new(0, top + 3.1, 0), horse)
		for _, l in { { 1.6, 0.6 }, { 1.6, -0.6 }, { -1.6, 0.6 }, { -1.6, -0.6 } } do
			piece(Vector3.new(0.5, 2.3, 0.5), Vector3.new(l[1], top + 1.15, l[2]), horse)
		end
		piece(Vector3.new(1, 2.2, 1), Vector3.new(2.3, top + 4.4, 0), horse, CFrame.Angles(0, 0, math.rad(-30)))
		piece(Vector3.new(1.8, 0.9, 0.9), Vector3.new(3.1, top + 5.4, 0), horse)
		piece(Vector3.new(1.3, 2.2, 1.2), Vector3.new(-0.2, top + 5.1, 0), coat)
		local head = piece(Vector3.new(0.95, 0.95, 0.95), Vector3.new(-0.2, top + 6.7, 0), Color3.fromRGB(226, 190, 160))
		head.Shape = Enum.PartType.Ball
		piece(Vector3.new(2, 0.6, 0.8), Vector3.new(-0.2, top + 7.3, 0), INK)
	end
	local poleX = -2.9
	cylinder(m, pos + Vector3.new(poleX, top + 5, 0), 10, 0.25, Kit.GILT_DARK)
	flagCloth(m, a.nation, pos + Vector3.new(poleX + 1.9, top + 8.6, 0))
	local bb = Instance.new("BillboardGui") :: BillboardGui
	bb.Size = UDim2.new(7, 64, 1.4, 16) -- grows when zoomed in, never below 64×16 px
	bb.StudsOffset = Vector3.new(0, -2.5, 0)
	bb.LightInfluence = 0
	bb.Adornee = plinth
	bb.Parent = m
	local plate = Kit.label(bb, string.format("%d · %d", math.floor(tonumber(a.men or a.strength) or 0), math.floor(tonumber(a.unitCount) or 0)), { size = UDim2.fromScale(1, 1), textSize = 13, font = Enum.Font.Garamond, align = Enum.TextXAlignment.Center, colour = Kit.IVORY })
	plate.TextScaled = true
	plate.BackgroundTransparency = 0.1
	plate.BackgroundColor3 = Kit.WALNUT
	local st = Instance.new("UIStroke") :: UIStroke
	st.Color = Kit.GILT
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = plate
	m.WorldPivot = CFrame.new(pos)
	m:ScaleTo(FIG)
	m.Parent = parent
	return m
end

-- A fleet: a two-decker under sail flying its nation's colours, with a "line · frigates" plate.
-- Drawn broadside to the board camera (which looks north), sails square to it, like a map token.
local function shipFigure(parent: Instance, fl: any, pos: Vector3): Model
	local m = Instance.new("Model") :: Model
	m.Name = "Fleet"
	m:SetAttribute("fleet", fl.id)
	local function piece(size: Vector3, offset: Vector3, colour: Color3, material: EnumMaterial?): Part
		local p = part(m, size, CFrame.new(pos + offset), colour, material)
		p.CanQuery = true
		return p
	end
	local hull: Part
	local slot = Assets.get("ship")
	local native = if slot then slot.native else nil
	if slot and native then
		-- the generated ship of the line, broadside to the board camera, with the nation's pennant
		local k = 9 / native[3] -- nine studs from bow to stern
		hull = piece(Vector3.new(native[1], native[2], native[3]) * k, Vector3.new(0, native[2] * k / 2 - 0.4, 0), Color3.new(1, 1, 1))
		hull.CFrame *= CFrame.Angles(0, math.pi / 2, 0) -- the keel (the mesh's Z) along the board's east-west
		local mesh = Instance.new("SpecialMesh") :: SpecialMesh
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = slot.mesh
		mesh.TextureId = slot.texture
		mesh.Scale = Vector3.one * k
		mesh.Parent = hull
		piece(Vector3.new(1.6, 1, 0.15), Vector3.new(0, native[2] * k + 0.2, 0), Data.colour(fl.nation))
	else
		hull = piece(Vector3.new(9, 1.6, 3), Vector3.new(0, 0.6, 0), Color3.fromRGB(70, 48, 32), Enum.Material.Wood)
		piece(Vector3.new(9.05, 0.35, 3.05), Vector3.new(0, 1.1, 0), Color3.fromRGB(196, 160, 72))
		piece(Vector3.new(2, 1.2, 2.4), Vector3.new(3.6, 1.8, 0), Color3.fromRGB(70, 48, 32), Enum.Material.Wood)
		for _, x in { -2.4, 1 } do
			piece(Vector3.new(0.35, 7, 0.35), Vector3.new(x, 4.8, 0), Color3.fromRGB(60, 44, 30))
			piece(Vector3.new(3.4, 3.6, 0.2), Vector3.new(x, 5.2, 0.3), Color3.fromRGB(236, 228, 208), Enum.Material.Fabric)
		end
		piece(Vector3.new(1.6, 1, 0.15), Vector3.new(-1.6, 8.6, 0), Data.colour(fl.nation))
	end
	local bb = Instance.new("BillboardGui") :: BillboardGui
	bb.Size = UDim2.new(6, 52, 1.2, 14)
	bb.StudsOffset = Vector3.new(0, 1.5, 0) -- above the waterline, or the sea hides it
	bb.LightInfluence = 0
	bb.Adornee = hull
	bb.Parent = m
	local plate = Kit.label(bb, string.format("%d · %d", math.floor(tonumber(fl.line) or 0), math.floor(tonumber(fl.frigates) or 0)), { size = UDim2.fromScale(1, 1), textSize = 13, font = Enum.Font.Garamond, align = Enum.TextXAlignment.Center, colour = Kit.IVORY })
	plate.TextScaled = true
	plate.BackgroundTransparency = 0.1
	plate.BackgroundColor3 = Color3.fromRGB(36, 52, 74)
	m.WorldPivot = CFrame.new(pos)
	m:ScaleTo(FIG)
	m.Parent = parent
	return m
end

-- The player's spy: a cloaked figure on a small plinth (picked as "spy").
local function spyFigure(parent: Instance, ag: any, pos: Vector3): Model
	local m = Instance.new("Model") :: Model
	m.Name = "Spy"
	m:SetAttribute("spy", ag.id)
	local plinth = cylinder(m, pos + Vector3.new(0, 0.5, 0), 1, 5.5, Kit.WALNUT, Enum.Material.Wood)
	plinth.CanQuery = true
	cylinder(m, pos + Vector3.new(0, 1.05, 0), 0.2, 5.8, Kit.GILT, Enum.Material.Foil)
	local cloak = cylinder(m, pos + Vector3.new(0, 3.2, 0), 4.2, 2.4, INK)
	cloak.CanQuery = true
	local head = part(m, Vector3.new(1.2, 1.2, 1.2), CFrame.new(pos + Vector3.new(0, 5.9, 0)), Color3.fromRGB(226, 190, 160))
	head.Shape = Enum.PartType.Ball
	head.CanQuery = true
	local hat = cylinder(m, pos + Vector3.new(0, 6.6, 0), 0.35, 2.6, INK)
	hat.CanQuery = true
	m.WorldPivot = CFrame.new(pos)
	m:ScaleTo(FIG)
	m.Parent = parent
	return m
end

-- Recolours provinces, redraws borders, hatching and armies from a view (nil: the 1805 map).
function Board.setView(view: any?)
	local d = dyn
	if not d then
		return
	end
	d:ClearAllChildren()
	table.clear(armyModels)
	highlight = nil
	local provs = if view then view.provinces or {} else {}
	local owner: { [string]: string } = {}
	for _, p in Data.Provinces do
		local ps = provs[p.id]
		owner[p.id] = if ps and ps.owner then ps.owner else p.owner1805
		baseColour[p.id] = Data.colour(owner[p.id]):Lerp(PARCH, 0.22)
		if ps and ps.occupiedBy and ps.occupiedBy ~= owner[p.id] then
			hatch(d, p.outline, Data.colour(ps.occupiedBy))
		end
	end
	-- borders between provinces, drawn only over land (the coast is the terrain's own shore):
	-- gilt where the owners differ, a fine ink line inside one nation
	for _, e in edges do
		if #e.provs >= 2 then
			local foreign = owner[e.provs[1]] ~= owner[e.provs[2]]
			local len = math.sqrt((e.b.x - e.a.x) ^ 2 + (e.b.z - e.a.z) ^ 2)
			local n = math.max(1, math.ceil(len / CELL))
			for i = 0, n - 1 do
				local t0, t1 = i / n, (i + 1) / n
				local ax, az = e.a.x + (e.b.x - e.a.x) * t0, e.a.z + (e.b.z - e.a.z) * t0
				local bx, bz = e.a.x + (e.b.x - e.a.x) * t1, e.a.z + (e.b.z - e.a.z) * t1
				if Relief.isLand((ax + bx) / 2, (az + bz) / 2) then
					local y = TINT_Y + 0.15
					if foreign then
						segment(d, Board.toWorld(ax, az, y + 0.1), Board.toWorld(bx, bz, y + 0.1), 1.3, 0.45, Kit.GILT)
					else
						segment(d, Board.toWorld(ax, az, y), Board.toWorld(bx, bz, y), 0.4, 0.25, INK)
					end
				end
			end
		end
	end
	if not view then
		return
	end
	local byProv: { [string]: { any } } = {}
	for _, a in view.armies or {} do
		local list = byProv[a.provinceId]
		if not list then
			list = {}
			byProv[a.provinceId] = list
		end
		table.insert(list, a)
	end
	for pid, list in byProv do
		local p = Data.byId[pid]
		if p then
			table.sort(list, function(x: any, y: any): boolean
				return tostring(x.id) < tostring(y.id)
			end)
			local c = Board.toWorld(p.centre.x, p.centre.z)
			local n = #list
			local r = if n == 1 then 0 else 5 + 2.4 * n * FIG
			for i, a in list do
				local ang = math.pi + (i - 1) / n * 2 * math.pi -- two armies sit west and east
				armyModels[a.id] = figure(d, a, c + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r * 0.8))
			end
		end
	end
	local inPort: { [string]: number } = {}
	for _, fl in view.fleets or {} do
		local moor = moorings[fl.provinceId]
		if moor then
			local n = inPort[fl.provinceId] or 0
			inPort[fl.provinceId] = n + 1
			local side = Vector3.new(-moor.dir.Z, 0, moor.dir.X)
			local at = Vector3.new(moor.at.X, ORIGIN.Y + SEA_Y, moor.at.Z) + moor.dir * 16 + side * (n * 16 * FIG)
			armyModels[fl.id] = shipFigure(d, fl, at)
		end
	end
	for _, ag in view.agents or {} do
		local p = Data.byId[ag.provinceId]
		if p then
			-- south-east of the centre, clear of the armies' ring
			armyModels[ag.id] = spyFigure(d, ag, Board.toWorld(p.centre.x, p.centre.z) + Vector3.new(9, 0, 9) * FIG)
		end
	end
end

-- Province tint: reachable ones lighter, the selected one gilt; the selected army glows.
function Board.setSelection(armyId: any?, provinceId: string?, reachable: { [string]: boolean }?)
	for id, list in landParts do
		local c = baseColour[id] or PARCH
		if id == provinceId then
			c = c:Lerp(Kit.GILT_BRIGHT, 0.4)
		elseif reachable and reachable[id] then
			c = c:Lerp(Color3.new(1, 1, 1), 0.35)
		end
		for _, w in list do
			w.Color = c
		end
	end
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	local m = if armyId ~= nil then armyModels[armyId] else nil
	if m then
		local h = Instance.new("Highlight") :: Highlight
		h.FillColor = Kit.GILT_BRIGHT
		h.FillTransparency = 0.7
		h.OutlineColor = Kit.GILT_BRIGHT
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = m
		highlight = h
	end
end

local Logic = require(script.Parent.Logic)
export type Step = Logic.Step

-- Dotted march from `fromId` through `steps`; a numbered marker ends each turn's leg, red
-- where the march halts in an enemy zone of control.
function Board.setPath(fromId: string?, steps: { Step }?)
	local h = hi
	if not h then
		return
	end
	h:ClearAllChildren()
	local start = if fromId then Data.byId[fromId] else nil
	if not start or not steps or #steps == 0 then
		return
	end
	local prev = Board.toWorld(start.centre.x, start.centre.z, TINT_Y + 0.3)
	for i, s in steps do
		local p = Data.byId[s.id]
		if not p then
			return
		end
		local here = Board.toWorld(p.centre.x, p.centre.z, TINT_Y + 0.3)
		local colour = if s.stop then RED elseif s.turn == 1 then Kit.IVORY else Kit.MUTED
		local len = (here - prev).Magnitude
		local n = math.max(1, math.floor(len / 4))
		for k = 1, n - 1 do
			local dot = cylinder(h, prev:Lerp(here, k / n), 0.25, 1.3, colour)
			dot.CastShadow = false
		end
		local last = i == #steps or steps[i + 1].turn ~= s.turn
		if last or s.stop then
			local mk = cylinder(h, here + Vector3.new(0, 0.1, 0), 0.4, 3.4, if s.stop then RED else Kit.GILT, Enum.Material.Foil)
			mk.CastShadow = false
			local bb = Instance.new("BillboardGui") :: BillboardGui
			bb.Size = UDim2.fromOffset(22, 22)
			bb.StudsOffset = Vector3.new(0, 2.5, 0)
			bb.LightInfluence = 0
			bb.Adornee = mk
			bb.Parent = mk
			local l = Kit.label(bb, if s.stop then "!" else tostring(s.turn), { size = UDim2.fromScale(1, 1), textSize = 15, font = Enum.Font.Garamond, align = Enum.TextXAlignment.Center, colour = Kit.IVORY })
			l.BackgroundColor3 = if s.stop then RED else Kit.BLUE
			l.BackgroundTransparency = 0.05
			local c = Instance.new("UICorner") :: UICorner
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = l
		end
		prev = here
	end
end

-- What is under the mouse: ("army", id) or ("province", id) or nil.
function Board.pick(): (string?, any)
	local f = folder
	local cam = workspace.CurrentCamera
	if not f or not cam then
		return nil, nil
	end
	local m = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { f }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 6000, params)
	local inst: Instance? = if res then res.Instance else nil
	while inst and inst ~= (f :: Instance) do
		local a = inst:GetAttribute("army")
		if a ~= nil then
			return "army", a
		end
		local sp = inst:GetAttribute("spy")
		if sp ~= nil then
			return "spy", sp
		end
		local fl = inst:GetAttribute("fleet")
		if fl ~= nil then
			return "fleet", fl
		end
		local p = inst:GetAttribute("prov")
		if p ~= nil then
			return "province", p
		end
		inst = inst.Parent
	end
	return nil, nil
end

function Board.destroy()
	if folder then
		folder:Destroy()
	end
	folder, dyn, hi, highlight = nil, nil, nil, nil
	table.clear(landParts)
	table.clear(baseColour)
	table.clear(edges)
	table.clear(armyModels)
	table.clear(labels)
	labelK = 0
end

-- Names grow with the camera height so they stay readable (never below their table size).
function Board.updateLabels(cameraHeight: number)
	local k = math.clamp(cameraHeight / 220, 1, 2.6)
	if math.abs(k - labelK) < 0.03 then
		return
	end
	labelK = k
	for _, l in labels do
		local h = l.base * k
		l.part.Size = Vector3.new(h, 0.2, h * 4)
		l.part.CFrame = CFrame.new(l.at + Vector3.new(0, 0, 14 + h * 0.5)) * CFrame.Angles(0, -math.pi / 2, 0)
	end
end

return Board
