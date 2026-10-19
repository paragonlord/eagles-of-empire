--!strict
-- Grand-campaign tabletop: Europe as a painted relief board on a walnut table, far from the
-- battlefield. Static geometry (land, sea, mountains, towns, forts, piers, names) builds once;
-- owner colours, borders, occupation hatching, armies, highlights and the path preview follow
-- each view. Map units (0..2000 × 0..1500, +z north) map to world X east, world -Z north, so
-- the default camera looking along -Z sees north at the top and east on the right.

local UserInputService = game:GetService("UserInputService") :: UserInputService
local Data = require(script.Parent.Data)
local Kit = require(script.Parent.Parent.UI.Kit)

local Board = {}

local ORIGIN = Vector3.new(8000, 0, 0) -- the battlefield spans 0..1600 × 0..1200
local S = 0.55 -- studs per map unit
local LAND = 2 -- land top above the table base
local SEA_Y = 0.6
local W, D = 2000 * S, 1500 * S

local PARCH = Color3.fromRGB(226, 212, 176)
local INK = Color3.fromRGB(42, 36, 32)
local STONE = Color3.fromRGB(150, 144, 134)
local WALL = Color3.fromRGB(196, 178, 146)
local ROOF = Color3.fromRGB(122, 66, 46)
local RED = Color3.fromRGB(196, 58, 44)

-- Mountain chains in map units, from EuropeData's projection x = (lon + 10) * 40,
-- z = (lat - 36) * 62.5: Alps, Pyrenees, Carpathians, Balkans, Apennines, Norway.
local CHAINS: { { snow: boolean, pts: { { number } } } } = {
	{ snow = true, pts = { { 660, 560 }, { 700, 625 }, { 760, 650 }, { 840, 675 }, { 920, 690 }, { 990, 705 } } },
	{ snow = true, pts = { { 340, 420 }, { 400, 415 }, { 460, 418 }, { 520, 415 } } },
	{ snow = false, pts = { { 1120, 844 }, { 1240, 831 }, { 1360, 769 }, { 1420, 688 }, { 1420, 594 }, { 1320, 588 } } },
	{ snow = false, pts = { { 1320, 425 }, { 1400, 420 }, { 1480, 425 } } },
	{ snow = false, pts = { { 800, 519 }, { 870, 460 }, { 920, 406 }, { 1020, 281 } } },
	{ snow = true, pts = { { 660, 1380 }, { 700, 1430 }, { 740, 1480 } } },
}

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

function Board.toWorld(x: number, z: number, y: number?): Vector3
	return Vector3.new(ORIGIN.X + x * S, ORIGIN.Y + (y or LAND), ORIGIN.Z - z * S)
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

-- Flat triangle a,b,c (centre plane) of thickness t as two wedges (the standard split at the
-- foot of the altitude onto the longest edge).
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, t: number, colour: Color3, out: { BasePart })
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local n = ac:Cross(ab)
	if n.Magnitude < 1e-4 then
		return
	end
	local right = n.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.05 then
		return
	end
	for _, w in { { (a + b) / 2, right, back, math.abs(ab:Dot(back)) }, { (a + c) / 2, -right, -back, math.abs(ac:Dot(back)) } } do
		local depth = w[4] :: number
		if depth > 0.01 then
			local p = Instance.new("WedgePart") :: WedgePart
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.Size = Vector3.new(t, height, depth)
			p.CFrame = CFrame.fromMatrix(w[1] :: Vector3, w[2] :: Vector3, up, w[3] :: Vector3)
			p.Color = colour
			p.Material = Enum.Material.SmoothPlastic
			p.Parent = parent
			table.insert(out, p)
		end
	end
end

type Pt = { x: number, z: number }

local function cross(o: Pt, a: Pt, b: Pt): number
	return (a.x - o.x) * (b.z - o.z) - (a.z - o.z) * (b.x - o.x)
end

-- Ear clipping for a simple polygon; returns index triples.
function Board.triangulate(pts: { Pt }): { { number } }
	local n = #pts
	local area = 0
	for i = 1, n do
		local p, q = pts[i], pts[i % n + 1]
		area += p.x * q.z - q.x * p.z
	end
	local sign = if area >= 0 then 1 else -1
	local idx = {}
	for i = 1, n do
		idx[i] = i
	end
	local tris = {}
	while #idx > 3 do
		local m = #idx
		local cut = false
		for i = 1, m do
			local i0, i1, i2 = idx[(i - 2) % m + 1], idx[i], idx[i % m + 1]
			local a, b, c = pts[i0], pts[i1], pts[i2]
			local cr = cross(a, b, c) * sign
			if cr > 1e-9 then
				local ear = true
				for _, j in idx do
					if j ~= i0 and j ~= i1 and j ~= i2 then
						local p = pts[j]
						if cross(a, b, p) * sign >= 0 and cross(b, c, p) * sign >= 0 and cross(c, a, p) * sign >= 0 then
							ear = false
							break
						end
					end
				end
				if ear then
					table.insert(tris, { i0, i1, i2 })
					table.remove(idx, i)
					cut = true
					break
				end
			end
		end
		if not cut then
			-- only collinear or degenerate corners left: drop a flat one, else give up
			local flat = nil
			for i = 1, m do
				if math.abs(cross(pts[idx[(i - 2) % m + 1]], pts[idx[i]], pts[idx[i % m + 1]])) <= 1e-9 then
					flat = i
					break
				end
			end
			if not flat then
				break
			end
			table.remove(idx, flat)
		end
	end
	if #idx == 3 then
		table.insert(tris, { idx[1], idx[2], idx[3] })
	end
	return tris
end

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
	l.TextColor3 = Kit.IVORY
	l.TextStrokeColor3 = INK
	l.TextStrokeTransparency = 0.55
	l.TextTransparency = 0.1
	l.Parent = gui
	return p
end

local function house(parent: Instance, pos: Vector3, w: number, d: number, h: number, yaw: number)
	local base = part(parent, Vector3.new(w, h, d), CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, yaw, 0), WALL)
	base.CastShadow = true
	ridge(parent, pos + Vector3.new(0, h, 0), yaw, w + 0.3, d * 0.72, ROOF)
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

local function mountains(parent: Instance)
	local rng = Random.new(1805)
	for _, chain in CHAINS do
		for i = 1, #chain.pts - 1 do
			local p0, p1 = chain.pts[i], chain.pts[i + 1]
			local steps = math.max(1, math.floor(math.sqrt((p1[1] - p0[1]) ^ 2 + (p1[2] - p0[2]) ^ 2) / 22))
			for k = 0, steps - 1 do
				local t = (k + rng:NextNumber()) / steps
				local x = p0[1] + (p1[1] - p0[1]) * t + rng:NextNumber(-14, 14)
				local z = p0[2] + (p1[2] - p0[2]) * t + rng:NextNumber(-14, 14)
				local s = rng:NextNumber(5, 9)
				local yaw = math.atan2(-(p1[2] - p0[2]), p1[1] - p0[1]) + rng:NextNumber(-0.5, 0.5)
				local pos = Board.toWorld(x, z)
				local len = rng:NextNumber(7, 14)
				ridge(parent, pos, yaw, len, s, Color3.fromRGB(128, 122, 114), Enum.Material.Slate)
				if chain.snow and s > 6.5 then
					local s2 = s * 0.42
					ridge(parent, pos + Vector3.new(0, (s - s2) * 0.707, 0), yaw, len * 0.6, s2, Color3.fromRGB(236, 234, 228), Enum.Material.Snow)
				end
			end
		end
	end
end

function Board.build()
	if folder then
		return
	end
	local f = Instance.new("Folder") :: Folder
	f.Name = "EoEGrandBoard"
	-- table, gilt edge and the sea
	local mid = ORIGIN + Vector3.new(W / 2, 0, -D / 2)
	part(f, Vector3.new(W + 140, 6, D + 140), CFrame.new(mid + Vector3.new(0, -3.2, 0)), Kit.WALNUT_LIGHT, Enum.Material.Wood)
	for _, e in { { Vector3.new(0, 0, -D / 2 - 4), Vector3.new(W + 8, 0, 0) }, { Vector3.new(0, 0, D / 2 + 4), Vector3.new(W + 8, 0, 0) }, { Vector3.new(-W / 2 - 4, 0, 0), Vector3.new(0, 0, D + 8) }, { Vector3.new(W / 2 + 4, 0, 0), Vector3.new(0, 0, D + 8) } } do
		local c, l = e[1], e[2]
		part(f, Vector3.new(math.max(l.X, 3), 1.2, math.max(l.Z, 3)), CFrame.new(mid + c + Vector3.new(0, 0.2, 0)), Kit.GILT, Enum.Material.Foil)
	end
	local sea = part(f, Vector3.new(W + 4, 1, D + 4), CFrame.new(mid + Vector3.new(0, SEA_Y - 0.5, 0)), Color3.fromRGB(86, 90, 160))
	sea.CastShadow = false
	local sg = Instance.new("SurfaceGui") :: SurfaceGui
	sg.Face = Enum.NormalId.Top
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = Vector2.new(256, 192)
	sg.LightInfluence = 1
	sg.Parent = sea
	local grad = Instance.new("Frame") :: Frame
	grad.Size = UDim2.fromScale(1, 1)
	grad.BackgroundColor3 = Color3.new(1, 1, 1)
	grad.BorderSizePixel = 0
	grad.Parent = sg
	Kit.gradient(grad, Color3.fromRGB(112, 116, 186), Color3.fromRGB(66, 66, 134), 35)

	local statics = Instance.new("Folder") :: Folder
	statics.Name = "Statics"
	statics.Parent = f
	for _, p in Data.Provinces do
		local pts = p.outline :: { Pt }
		local out: { BasePart } = {}
		local colour = Data.colour(p.owner1805):Lerp(PARCH, 0.22)
		for _, t in Board.triangulate(pts) do
			local a, b, c = pts[t[1]], pts[t[2]], pts[t[3]]
			triangle(f, Board.toWorld(a.x, a.z, LAND / 2), Board.toWorld(b.x, b.z, LAND / 2), Board.toWorld(c.x, c.z, LAND / 2), LAND, colour, out)
		end
		for _, w in out do
			w:SetAttribute("prov", p.id)
		end
		landParts[p.id] = out
		baseColour[p.id] = colour
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
			capital(statics, c + Vector3.new(-17, 0, -15))
		end
		if (p.fort or 0) > 0 then
			bastion(statics, c + Vector3.new(17, 0, -15), p.fort)
		end
	end
	-- piers on the nearest stretch of coast of each port
	for _, p in Data.Provinces do
		if p.isPort then
			local best, bestD = nil :: Edge?, math.huge
			for _, e in edges do
				if #e.provs == 1 and e.provs[1] == p.id then
					local mx, mz = (e.a.x + e.b.x) / 2, (e.a.z + e.b.z) / 2
					local d = (mx - p.centre.x) ^ 2 + (mz - p.centre.z) ^ 2
					if d < bestD then
						best, bestD = e, d
					end
				end
			end
			if best then
				local m = Board.toWorld((best.a.x + best.b.x) / 2, (best.a.z + best.b.z) / 2)
				local out = m - Board.toWorld(p.centre.x, p.centre.z)
				local dir = Vector3.new(out.X, 0, out.Z).Unit
				pier(statics, m, dir)
				moorings[p.id] = { at = m, dir = dir }
			end
		end
	end
	mountains(statics)
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
			local p = Board.toWorld(ox + dx * ts[i], oz + dz * ts[i], LAND + 0.06)
			local q = Board.toWorld(ox + dx * ts[i + 1], oz + dz * ts[i + 1], LAND + 0.06)
			local st = segment(parent, p, q, 2.2, 0.12, colour)
			if st then
				st.Transparency = 0.15
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
	local hull = piece(Vector3.new(9, 1.6, 3), Vector3.new(0, 0.6, 0), Color3.fromRGB(70, 48, 32), Enum.Material.Wood)
	piece(Vector3.new(9.05, 0.35, 3.05), Vector3.new(0, 1.1, 0), Color3.fromRGB(196, 160, 72))
	piece(Vector3.new(2, 1.2, 2.4), Vector3.new(3.6, 1.8, 0), Color3.fromRGB(70, 48, 32), Enum.Material.Wood)
	for _, x in { -2.4, 1 } do
		piece(Vector3.new(0.35, 7, 0.35), Vector3.new(x, 4.8, 0), Color3.fromRGB(60, 44, 30))
		piece(Vector3.new(3.4, 3.6, 0.2), Vector3.new(x, 5.2, 0.3), Color3.fromRGB(236, 228, 208), Enum.Material.Fabric)
	end
	piece(Vector3.new(1.6, 1, 0.15), Vector3.new(-1.6, 8.6, 0), Data.colour(fl.nation))
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
	for _, e in edges do
		local a, b = Board.toWorld(e.a.x, e.a.z, LAND + 0.1), Board.toWorld(e.b.x, e.b.z, LAND + 0.1)
		if #e.provs >= 2 and owner[e.provs[1]] ~= owner[e.provs[2]] then
			segment(d, a + Vector3.new(0, 0.1, 0), b + Vector3.new(0, 0.1, 0), 1.3, 0.45, Kit.GILT)
		else
			segment(d, a, b, if #e.provs >= 2 then 0.4 else 0.6, 0.25, INK)
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
	local prev = Board.toWorld(start.centre.x, start.centre.z, LAND + 0.3)
	for i, s in steps do
		local p = Data.byId[s.id]
		if not p then
			return
		end
		local here = Board.toWorld(p.centre.x, p.centre.z, LAND + 0.3)
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
