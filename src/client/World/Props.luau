--!strict
-- Decorative props derived from MapData: trees, houses, bridges, ground labels, objective
-- markers and the deployment zone outline. Anchored, non-colliding, non-queryable parts.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Vec = require(Shared.Vec)
local RNG = require(Shared.RNG)
local Factions = require(script.Parent.Parent.Factions)
local Terrain = require(script.Parent.Terrain)
local WorldLighting = require(script.Parent.Lighting)

local Props = {}

local P = Config.Visual.Palette
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local folder: Folder? = nil
local zoneFolder: Folder? = nil
local labelParts: { { part: Part, size: number, len: number } } = {}
local objectiveMarks: { [string]: { ring: { Part }, flag: Part } } = {}
local generation = 0
local currentMap: any = nil

local TREE_PRIORITY = { [1] = 0.55, [2] = 0.25, [3] = 0.0 } -- keep trees with priority >= this
local IDS = Config.TerrainIds

local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function part(parent: Instance, shape: EnumPartType?, size: Vector3, cf: CFrame, color: Color3, material: EnumMaterial?): Part
	local p = Instance.new("Part") :: Part
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function wedge(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: EnumMaterial?): WedgePart
	local p = Instance.new("WedgePart") :: WedgePart
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.Parent = parent
	return p
end

-- Ellipsoid: a block with the built-in sphere mesh (no asset), for poplars, conifers, bushes.
local function blob(parent: Instance, size: Vector3, cf: CFrame, color: Color3): Part
	local p = part(parent, nil, size, cf, color, Enum.Material.Grass)
	local m = Instance.new("SpecialMesh") :: SpecialMesh
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- Yaw so that local +X points along a sim heading (Roblox rotates +X toward -Z for +angle).
local function yaw(x: number, y: number, z: number, heading: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, -heading, 0)
end

-- Gable roof over `base` (eave level, ridge along local X): two wedges back to back along Z.
local function gable(parent: Instance, base: CFrame, length: number, span: number, height: number, color: Color3, material: EnumMaterial?)
	local mid = base * CFrame.new(0, height / 2, 0)
	wedge(parent, Vector3.new(length, height, span / 2), mid * CFrame.new(0, 0, -span / 4), color, material)
	wedge(parent, Vector3.new(length, height, span / 2), mid * CFrame.new(0, 0, span / 4) * CFrame.Angles(0, math.pi, 0), color, material)
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
	stookKind: number, -- Terrain.KIND the stooks stand in
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
local STONE = c3(156, 146, 128)

---------------------------------------------------------------------------------------- trees

local function crownColor(x: number, z: number): Color3
	local base = pick(look.crowns, h01(x * 3, z * 5, 41))
	return base:Lerp(c3(30, 40, 24), h01(z, x, 42) * 0.25)
end

local function deciduous(parent: Instance, x: number, z: number, r: number, trunk: boolean, y: number?, lobe: boolean?)
	local gy = y or groundY(x, z)
	local trunkH = r * 1.0
	if trunk then
		part(parent, Enum.PartType.Cylinder, Vector3.new(trunkH + 1, r * 0.26, r * 0.26), CFrame.new(x, gy + trunkH / 2, z) * CFrame.Angles(0, 0, math.pi / 2), TRUNK)
	end
	local col = crownColor(x, z)
	local a = h01(x, z, 43) * math.pi * 2
	part(parent, Enum.PartType.Ball, Vector3.one * r * 2, CFrame.new(x, gy + trunkH + r * 0.7, z), col)
	if trunk or lobe then
		-- a second, smaller lobe breaks the lollipop outline and makes a lumpy canopy
		local o = r * 0.55
		part(parent, Enum.PartType.Ball, Vector3.one * r * 1.4, CFrame.new(x + math.cos(a) * o, gy + trunkH + r * 1.05, z + math.sin(a) * o), col:Lerp(c3(120, 120, 70), 0.08))
	end
end

local function conifer(parent: Instance, x: number, z: number, r: number, y: number?)
	local gy = y or groundY(x, z)
	part(parent, Enum.PartType.Cylinder, Vector3.new(r * 0.8, r * 0.22, r * 0.22), CFrame.new(x, gy + r * 0.4, z) * CFrame.Angles(0, 0, math.pi / 2), TRUNK)
	blob(parent, Vector3.new(r * 1.3, r * 3.4, r * 1.3), CFrame.new(x, gy + r * 2.1, z), CONIFER:Lerp(c3(30, 44, 34), h01(x, z, 44) * 0.5))
end

local function poplar(parent: Instance, x: number, z: number, y: number?)
	local gy = y or groundY(x, z)
	local hgt = 15 + h01(x, z, 45) * 5
	part(parent, nil, Vector3.new(0.6, 3, 0.6), CFrame.new(x, gy + 1.5, z), TRUNK)
	blob(parent, Vector3.new(3.6, hgt, 3.6), CFrame.new(x, gy + 2 + hgt / 2, z), pick(look.crowns, h01(x, z, 46)):Lerp(c3(70, 96, 40), 0.25))
end

local function bush(parent: Instance, x: number, z: number, r: number)
	local p = blob(parent, Vector3.new(r * 2.2, r * 1.1, r * 1.8), yaw(x, groundY(x, z) + r * 0.35, z, h01(x, z, 47) * 3), look.hedge:Lerp(c3(56, 72, 40), h01(z, x, 48) * 0.4))
	p.CastShadow = false
end

local function buildWoodsTree(parent: Instance, t: any, highGround: number)
	local r = t.r
	local edge = false
	for k = 0, 3 do
		local a = k * math.pi / 2
		if classAt(t.x + math.cos(a) * r * 1.9, t.z + math.sin(a) * r * 1.9) ~= IDS.woods then
			edge = true
			break
		end
	end
	local y = groundY(t.x, t.z)
	local coniferShare = look.conifer + (if y > highGround then 0.35 else 0)
	if h01(t.x, t.z, 49) < coniferShare then
		conifer(parent, t.x, t.z, r * 0.9, y)
	else
		-- interior trees are crowns only (trunks are hidden by the canopy); edge trees get
		-- trunk, a second lobe and undergrowth on the open side
		deciduous(parent, t.x, t.z, r, edge, y, t.priority > 0.45)
	end
	if edge and h01(t.z, t.x, 50) < 0.6 then
		local a = h01(t.x, t.z, 51) * math.pi * 2
		bush(parent, t.x + math.cos(a) * r, t.z + math.sin(a) * r, r * 0.6)
	end
end

------------------------------------------------------------------------------------- buildings

-- Houses about 1.5x a soldier's height so villages read as dense clusters of steep roofs.
local WALL_H = 2.6

type HouseKind = "white" | "timber" | "brick" | "barn"

local function house(parent: Instance, x: number, z: number, heading: number, w: number, d: number, kind: HouseKind, salt: number)
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
	local body = yaw(x, y + wallH / 2 - 0.5, z, heading)
	part(parent, nil, Vector3.new(w, wallH + 1, d), body, wallC, if kind == "barn" then Enum.Material.WoodPlanks else Enum.Material.SmoothPlastic)
	if kind == "timber" then
		-- dark beams: a band at the upper floor and two posts that show on both long sides
		part(parent, nil, Vector3.new(w + 0.08, 0.3, d + 0.08), body * CFrame.new(0, 0.35, 0), BEAM)
		for sx = -1, 1, 2 do
			part(parent, nil, Vector3.new(0.3, wallH + 0.9, d + 0.08), body * CFrame.new(sx * w * 0.22, 0, 0), BEAM)
		end
	end
	local thatch = kind ~= "brick" and h01(z, x, salt + 1) < look.thatch
	local roofC = if thatch then c3(128, 112, 80) elseif kind == "barn" then c3(96, 58, 44) else pick(look.roofs, h01(z, x, salt + 2))
	local roofH = d * (if thatch then 0.7 else 0.62)
	gable(parent, yaw(x, y + wallH, z, heading), w + 0.6, d + 0.8, roofH, roofC, if thatch then Enum.Material.Grass else Enum.Material.Slate)
	if kind ~= "barn" and h01(x, z, salt + 3) < 0.45 then
		local cx = (h01(z, x, salt + 4) - 0.5) * w * 0.6
		part(parent, nil, Vector3.new(0.7, roofH + 0.9, 0.7), yaw(x, y + wallH + roofH * 0.5 + 0.2, z, heading) * CFrame.new(cx, 0, d * 0.12), c3(120, 96, 80))
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

local function buildBuilding(parent: Instance, b: any, centre: any, radius: number)
	local w = math.clamp(b.w * 0.55, 3.8, 6.5)
	local d = math.clamp(b.d * 0.62, 3.4, 5)
	local far = Vec.dist(b.pos, centre) > radius * 0.55
	if b.w >= 9 then
		local ux, uz = math.cos(b.heading), math.sin(b.heading)
		local off = w / 2 + 0.5
		local k = houseKind(b.pos.x, b.pos.z, b.w, far)
		if k == "barn" then
			house(parent, b.pos.x, b.pos.z, b.heading, w * 1.9, d * 1.25, "barn", 62)
		else
			house(parent, b.pos.x - ux * off, b.pos.z - uz * off, b.heading, w, d, k, 62)
			house(parent, b.pos.x + ux * off, b.pos.z + uz * off, b.heading + 0.06, w * 0.9, d, houseKind(b.pos.z, b.pos.x, 0, false), 63)
		end
	else
		house(parent, b.pos.x, b.pos.z, b.heading, w, d, houseKind(b.pos.x, b.pos.z, b.w, far), 64)
	end
end

-- Village church: nave with a steep roof, west tower with a spire (two crossed steep gables) or,
-- in Moravia, a baroque onion dome.
local function church(parent: Instance, x: number, z: number, heading: number)
	local y = groundY(x, z)
	local wall = look.walls[1]
	local roof = look.roofs[1]:Lerp(c3(60, 40, 34), 0.2)
	local nave = yaw(x, y, z, heading)
	part(parent, nil, Vector3.new(13, 6.5, 6.5), nave * CFrame.new(0, 2.75, 0), wall)
	gable(parent, nave * CFrame.new(0, 6, 0), 13.6, 7.4, 4.8, roof, Enum.Material.Slate)
	local tower = nave * CFrame.new(-8.6, 0, 0)
	part(parent, nil, Vector3.new(4.4, 14, 4.4), tower * CFrame.new(0, 6.5, 0), wall)
	if look.dome then
		part(parent, Enum.PartType.Ball, Vector3.one * 5.2, tower * CFrame.new(0, 14.6, 0), c3(84, 102, 84), Enum.Material.Metal)
		part(parent, nil, Vector3.new(0.5, 3.5, 0.5), tower * CFrame.new(0, 18.4, 0), c3(170, 150, 90), Enum.Material.Metal)
	else
		local spire = c3(70, 72, 76)
		gable(parent, tower * CFrame.new(0, 13.5, 0), 4.8, 4.8, 8.5, spire, Enum.Material.Slate)
		gable(parent, tower * CFrame.new(0, 13.5, 0) * CFrame.Angles(0, math.pi / 2, 0), 4.8, 4.8, 8.5, spire, Enum.Material.Slate)
	end
end

local function well(parent: Instance, x: number, z: number)
	local y = groundY(x, z)
	part(parent, Enum.PartType.Cylinder, Vector3.new(1.4, 2.4, 2.4), CFrame.new(x, y + 0.5, z) * CFrame.Angles(0, 0, math.pi / 2), STONE, Enum.Material.Cobblestone)
	part(parent, nil, Vector3.new(0.25, 3.2, 2.6), CFrame.new(x, y + 1.6, z), BEAM)
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

local function compound(parent: Instance, v: any, size: number, garden: boolean, heading: number)
	local x, z = v.pos.x, v.pos.z
	local y = groundY(x, z)
	local wallC = c3(196, 184, 162)
	local roofC = c3(112, 56, 42)
	local base = yaw(x, y, z, heading)
	local half = size / 2
	-- walls: three full sides, the road side (local +X) split by a gate
	part(parent, nil, Vector3.new(size, 4, 0.9), base * CFrame.new(0, 1.2, -half), wallC)
	part(parent, nil, Vector3.new(size, 4, 0.9), base * CFrame.new(0, 1.2, half), wallC)
	part(parent, nil, Vector3.new(0.9, 4, size), base * CFrame.new(-half, 1.2, 0), wallC)
	local seg = half - 3
	part(parent, nil, Vector3.new(0.9, 4, seg), base * CFrame.new(half, 1.2, -half + seg / 2), wallC)
	part(parent, nil, Vector3.new(0.9, 4, seg), base * CFrame.new(half, 1.2, half - seg / 2), wallC)
	-- ranges inside the walls: long barn at the back, house and stables on the sides
	local function range(cf: CFrame, len: number, depth: number, wall: Color3)
		part(parent, nil, Vector3.new(len, 4.2, depth), cf * CFrame.new(0, 1.6, 0), wall)
		gable(parent, cf * CFrame.new(0, 3.7, 0), len + 0.6, depth + 0.8, depth * 0.6, roofC, Enum.Material.Slate)
	end
	range(base * CFrame.new(-half + 3.6, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), size - 2, 6, c3(110, 84, 62))
	range(base * CFrame.new(0, 0, -half + 3.4), size - 10, 5.6, wallC)
	range(base * CFrame.new(1, 0, half - 3.4), size - 12, 5.6, c3(150, 84, 64))
	if garden then
		-- walled garden on the far side (Hougoumont's south garden), with a few fruit trees
		local g = base * CFrame.new(0, 0, half + size * 0.45)
		part(parent, nil, Vector3.new(size * 1.2, 3, 0.8), g * CFrame.new(0, 1, size * 0.45), wallC)
		for sx = -1, 1, 2 do
			part(parent, nil, Vector3.new(0.8, 3, size * 0.9), g * CFrame.new(sx * size * 0.6, 1, 0), wallC)
		end
		for k = -1, 1 do
			local p = g * CFrame.new(k * size * 0.3, 0, 0)
			deciduous(parent, p.X, p.Z, 2.4, true)
		end
	end
end

-- Post mill on a rise near a village: trestle, weatherboarded body, gable roof and four sails.
local function windmill(parent: Instance, x: number, z: number, heading: number)
	local y = groundY(x, z)
	local base = yaw(x, y, z, heading)
	part(parent, Enum.PartType.Cylinder, Vector3.new(4, 4, 4), base * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.pi / 2), STONE, Enum.Material.Cobblestone)
	part(parent, nil, Vector3.new(4.6, 6, 4), base * CFrame.new(0, 6.4, 0), c3(112, 88, 64), Enum.Material.WoodPlanks)
	gable(parent, base * CFrame.new(0, 9.4, 0), 5, 4.6, 2.4, c3(88, 70, 56), Enum.Material.WoodPlanks)
	local hub = base * CFrame.new(2.7, 7.8, 0)
	for k = 0, 1 do
		part(parent, nil, Vector3.new(0.3, 19, 1.7), hub * CFrame.Angles(math.pi / 4 + k * math.pi / 2, 0, 0), c3(206, 198, 176), Enum.Material.Fabric)
	end
end

local function buildVillage(parent: Instance, v: any)
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
	if comp and currentMap.id == "waterloo" then
		compound(parent, v, comp.size, comp.garden, heading)
		clearR = comp.size * 0.75
	elseif v.count >= 12 then
		-- the church stands back from the main street, its tower toward the road
		local r = Vec.right(Vec.fromHeading(heading))
		local cpos = Vec.add(v.pos, Vec.scale(r, 14))
		church(parent, cpos.x, cpos.z, heading)
		well(parent, v.pos.x - r.x * 9 + 6, v.pos.z - r.z * 9)
		for _, b in v.buildings do
			if Vec.dist(b.pos, cpos) > 12 then
				buildBuilding(parent, b, v.pos, v.radius)
			end
		end
		return
	else
		well(parent, v.pos.x + 7, v.pos.z + 5)
	end
	for _, b in v.buildings do
		if clearR == 0 or Vec.dist(b.pos, v.pos) > clearR then
			buildBuilding(parent, b, v.pos, v.radius)
		end
	end
end

------------------------------------------------------------------------------- water and roads

local function buildBridge(parent: Instance, br: any)
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
	local ramp = if stoneBridge then 9 else 5
	local reach = half + ramp
	local e1 = Vec.sub(mid, Vec.scale(dir, reach))
	local e2 = Vec.add(mid, Vec.scale(dir, reach))
	local y1, y2 = groundY(e1.x, e1.z), groundY(e2.x, e2.z)
	local len = reach * 2
	local pitch = math.atan2(y2 - y1, len)
	local deck = yaw(mid.x, (y1 + y2) / 2, mid.z, heading) * CFrame.Angles(0, 0, pitch)
	local function pier(t: number, size: Vector3, color: Color3, material: EnumMaterial?)
		local px, pz = e1.x + (e2.x - e1.x) * t, e1.z + (e2.z - e1.z) * t
		local top = y1 + (y2 - y1) * t
		local bottom = groundY(px, pz) - 2
		local ph = math.max(top - bottom, 1)
		return part(parent, nil, Vector3.new(size.X, ph, size.Z), yaw(px, bottom + ph / 2, pz, heading), color, material)
	end
	if stoneBridge then
		-- stone bridge: deck, parapets with coping, piers with cutwaters down to the bed
		local stone = c3(150, 140, 122)
		part(parent, nil, Vector3.new(len, 1.4, br.width), deck * CFrame.new(0, 0.3, 0), stone, Enum.Material.Cobblestone)
		for side = -1, 1, 2 do
			part(parent, nil, Vector3.new(len, 1.6, 0.9), deck * CFrame.new(0, 1.6, side * (br.width / 2 - 0.45)), stone, Enum.Material.Slate)
		end
		local dark = stone:Lerp(c3(60, 56, 50), 0.25)
		for i = 0, 2 do
			local t = 0.25 + i * 0.25
			pier(t, Vector3.new(3.4, 0, br.width - 1), dark, Enum.Material.Slate)
			local px, pz = e1.x + (e2.x - e1.x) * t, e1.z + (e2.z - e1.z) * t
			local bottom = groundY(px, pz) - 2
			local ph = math.max(y1 + (y2 - y1) * t - bottom, 1)
			part(parent, nil, Vector3.new(2.4, ph, 2.4), yaw(px, bottom + ph / 2, pz, heading) * CFrame.new(0, 0, br.width / 2) * CFrame.Angles(0, math.pi / 4, 0), dark, Enum.Material.Slate)
		end
	else
		-- timber bridge over a brook: plank deck, trestles and a post-and-rail on both sides
		local wood = c3(104, 80, 58)
		part(parent, nil, Vector3.new(len, 0.6, br.width - 6), deck * CFrame.new(0, 0.2, 0), wood, Enum.Material.WoodPlanks)
		local n = math.max(2, math.floor(len / 7))
		for side = -1, 1, 2 do
			local zOff = side * (br.width / 2 - 3.3)
			part(parent, nil, Vector3.new(len, 0.25, 0.25), deck * CFrame.new(0, 1.7, zOff), wood)
			for k = 0, n do
				part(parent, nil, Vector3.new(0.3, 1.8, 0.3), deck * CFrame.new(-len / 2 + k * len / n, 0.9, zOff), BEAM)
			end
		end
		for k = 1, n - 1 do
			pier(k / n, Vector3.new(0.7, 0, br.width - 7), BEAM)
		end
	end
end

local function nearBridge(x: number, z: number, pad: number): boolean
	for _, br in currentMap.bridges do
		if Vec.distToSegment({ x = x, z = z }, br.a, br.b) < br.width / 2 + pad then
			return true
		end
	end
	return false
end

-- Reeds on the water's edge and willows on the banks.
local function buildRiverside(parent: Instance, river: any, q: number, jobs: { () -> () })
	local pts = river.points
	local half = river.width / 2
	for n = 1, #pts - 1 do
		local a, b = pts[n], pts[n + 1]
		local len = Vec.dist(a, b)
		local dir = Vec.normalize(Vec.sub(b, a))
		local right = Vec.right(dir)
		table.insert(jobs, function()
			local s = 0
			while s < len do
				local c = Vec.add(a, Vec.scale(dir, s))
				for side = -1, 1, 2 do
					local k = h01(c.x + side, c.z, 70)
					if q >= 2 and k < 0.55 then
						local p = Vec.add(c, Vec.scale(right, side * (half + 1.5 + k * 3)))
						if classAt(p.x, p.z) ~= nil and not nearBridge(p.x, p.z, 6) then
							-- a thin pale fringe of reed bed along the water's edge
							local r = part(parent, nil, Vector3.new(7, 1.2 + k * 1.2, 0.5), yaw(p.x, groundY(p.x, p.z) + 0.5, p.z, Vec.heading(dir) + (k - 0.3) * 0.5), c3(186, 172, 112):Lerp(c3(150, 150, 90), k), Enum.Material.Sand)
							r.CastShadow = false
						end
					end
					if k > 0.86 then
						local p = Vec.add(c, Vec.scale(right, side * (half + 8 + k * 5)))
						if isOpen(p.x, p.z) and not nearBridge(p.x, p.z, 10) then
							-- willow: silvery, low and broad
							local y = groundY(p.x, p.z)
							part(parent, Enum.PartType.Cylinder, Vector3.new(3, 1.1, 1.1), CFrame.new(p.x, y + 1.5, p.z) * CFrame.Angles(0, 0, math.pi / 2), TRUNK)
							blob(parent, Vector3.new(9, 6, 9), CFrame.new(p.x, y + 5, p.z), c3(108, 120, 82))
						end
					end
				end
				s += 7
			end
		end)
	end
end

-- Avenues: fruit trees (Thuringia, Moravia) or poplars (Brabant) along stretches of road
-- between villages.
local function buildAvenues(parent: Instance, jobs: { () -> () })
	for ri, road in currentMap.roads do
		local pts = road.points
		for n = 1, #pts - 1 do
			local a, b = pts[n], pts[n + 1]
			table.insert(jobs, function()
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
										poplar(parent, p.x, p.z)
									else
										deciduous(parent, p.x, p.z, 2.6 + h01(p.z, p.x, 82), true)
									end
								end
							end
						end
					end
					s += step
				end
			end)
		end
	end
end

-------------------------------------------------------------------------------------- farmland

-- Hedges, dry-stone walls and post-and-rail fences on the field-block borders (Terrain's
-- patchwork), with the odd hedgerow oak; gaps where a border meets a road, village or wood.
local function borderPiece(parent: Instance, kind: number, ax: number, az: number, bx: number, bz: number, q: number)
	local ay, by = groundY(ax, az), groundY(bx, bz)
	local mx, mz = (ax + bx) / 2, (az + bz) / 2
	local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local function along(height: number, width: number, lift: number, color: Color3, material: EnumMaterial, extra: number?): Part
		local cf = CFrame.lookAt(Vector3.new(mx, (ay + by) / 2 + lift, mz), Vector3.new(bx, by + lift, bz))
		return part(parent, nil, Vector3.new(width, height, len + (extra or 0)), cf, color, material)
	end
	if kind == 1 then
		local hh = 2.6 + h01(mx, mz, 90) * 1.2
		along(hh, 2.6, hh / 2 - 0.5, look.hedge:Lerp(c3(52, 68, 36), h01(mz, mx, 91) * 0.3), Enum.Material.Grass, 1.2)
		if h01(mx, mz, 92) < 0.13 then
			deciduous(parent, mx, mz, 4 + h01(mz, mx, 93) * 2, true)
		end
	elseif kind == 2 then
		along(1.5, 1.0, 0.45, STONE:Lerp(c3(120, 112, 96), h01(mx, mz, 94)), Enum.Material.Cobblestone, 0.4)
	elseif kind == 3 and q >= 2 then
		local wood = c3(112, 92, 70)
		along(0.25, 0.25, 1.7, wood, Enum.Material.Wood).CastShadow = false
		along(0.25, 0.25, 0.9, wood, Enum.Material.Wood).CastShadow = false
		part(parent, nil, Vector3.new(0.35, 2.3, 0.35), CFrame.new(ax, ay + 0.8, az), BEAM).CastShadow = false
	end
end

local function buildBorders(parent: Instance, q: number, jobs: { () -> () })
	local F = Terrain.FIELD
	local W, D = currentMap.width, currentMap.depth
	local function nearestIs(x: number, z: number, i1: number, j1: number, i2: number, j2: number): boolean
		local ci, cj = math.floor(x / F), math.floor(z / F)
		local best, bi, bj = math.huge, 0, 0
		for di = -1, 1 do
			for dj = -1, 1 do
				local sx, sz = Terrain.blockSeed(ci + di, cj + dj)
				local d = (x - sx) ^ 2 + (z - sz) ^ 2
				if d < best then
					best, bi, bj = d, ci + di, cj + dj
				end
			end
		end
		return (bi == i1 and bj == j1) or (bi == i2 and bj == j2)
	end
	for i = -1, math.ceil(W / F) do
		table.insert(jobs, function()
			for j = -1, math.ceil(D / F) do
				for _, o in { { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } do
					local i2, j2 = i + o[1], j + o[2]
					local kind = Terrain.borderKind(i, j, i2, j2)
					if kind <= 3 then
						local ax, az = Terrain.blockSeed(i, j)
						local bx, bz = Terrain.blockSeed(i2, j2)
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
						local pieceLen = 12
						local t = t0
						while t + pieceLen <= t1 + 2 do
							local px, pz = mx + dx * t, mz + dz * t
							local qx, qz = mx + dx * (t + pieceLen), mz + dz * (t + pieceLen)
							local cx, cz = (px + qx) / 2, (pz + qz) / 2
							if px > 0 and pz > 0 and qx > 0 and qz > 0 and px < W and qx < W and pz < D and qz < D
								and isOpen(px, pz) and isOpen(qx, qz) and isOpen(cx, cz) then
								borderPiece(parent, kind, px, pz, qx, qz, q)
							end
							t += pieceLen
						end
					end
				end
			end
		end)
	end
end

-- Hay stooks: rows in a few harvested (autumn, winter) or mown (summer) strips.
local function buildStooks(parent: Instance, jobs: { () -> () })
	local F = Terrain.FIELD
	for i = 0, math.ceil(currentMap.width / F) do
		table.insert(jobs, function()
			for j = 0, math.ceil(currentMap.depth / F) do
				if h01(i, j, 100) < 0.3 then
					local sx, sz = Terrain.blockSeed(i, j)
					local a = h01(j, i, 101) * math.pi
					local ca, sa = math.cos(a), math.sin(a)
					for u = -48, 48, 11 do
						for w = -48, 48, 9 do
							local x, z = sx + u * ca - w * sa, sz + u * sa + w * ca
							if isOpen(x, z) and Terrain.fieldAt(x, z) == look.stookKind and h01(x, z, 102) < 0.7 then
								local p = blob(parent, Vector3.new(1.8, 2.3, 1.8), CFrame.new(x, groundY(x, z) + 0.8, z), look.stook:Lerp(c3(150, 130, 80), h01(z, x, 103) * 0.4))
								p.Material = Enum.Material.Sand -- Fabric and Grass render straw near-black (Studio)
							end
						end
					end
				end
			end
		end)
	end
end

local function buildOrchard(parent: Instance, o: any)
	local ca, sa = math.cos(o.a), math.sin(o.a)
	for u = -o.hx + 3, o.hx - 3, 7 do
		for w = -o.hz + 3, o.hz - 3, 7 do
			local x = o.x + u * ca - w * sa + (h01(u, w, 110) - 0.5) * 1.5
			local z = o.z + u * sa + w * ca + (h01(w, u, 111) - 0.5) * 1.5
			if isOpen(x, z) then
				local y = groundY(x, z)
				part(parent, Enum.PartType.Cylinder, Vector3.new(2.2, 0.6, 0.6), CFrame.new(x, y + 1.1, z) * CFrame.Angles(0, 0, math.pi / 2), TRUNK)
				part(parent, Enum.PartType.Ball, Vector3.one * (4.4 + h01(x, z, 112)), CFrame.new(x, y + 3.6, z), crownColor(x, z):Lerp(c3(96, 116, 52), 0.3))
			end
		end
	end
end

-- Windmills on the highest open ground near the larger villages (at most two a map).
local function buildWindmills(parent: Instance)
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
		windmill(parent, cands[n].x, cands[n].z, h01(cands[n].x, cands[n].z, 121) * math.pi * 2)
	end
end

-------------------------------------------------------------------------------- distant country

-- Woods and hedgerow trees in the countryside beyond the playable area, so the horizon is a
-- layered line of trees and hills rather than a cut edge. Crowns only, no shadows.
local function buildCountry(parent: Instance, q: number, jobs: { () -> () })
	local W, D = currentMap.width, currentMap.depth
	local per = 2 * (W + D)
	local step = 150
	local spacing = if q >= 3 then 13 else 16
	for k = 0, math.floor(per / step) - 1 do
		table.insert(jobs, function()
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
			local out = 70 + h01(k, 5, 131) * 420
			local cx, cz = x + nx * out, z + nz * out
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
						local y, wet = Terrain.heightAt(px, pz)
						if not inside and not wet then
							local r = 7 + h01(px, pz, 138) * 4
							local p = part(parent, Enum.PartType.Ball, Vector3.one * r * 2, CFrame.new(px, y + r * 1.15, pz), crownColor(px, pz))
							p.CastShadow = false
						end
					end
				end
			end
		end)
	end
end

local LABEL_MAX_K = 2.0 -- largest camera-height scale applied in updateLabels
local LABEL_MAX_RISE = 5 -- studs of terrain rise tolerated under a plate before it is shortened

-- Highest ground under a plate of half-length `hl` (world X) and half-depth `hd` (world Z).
local function maxGroundUnder(x: number, z: number, hl: number, hd: number): (number, number)
	local hi, lo = -math.huge, math.huge
	for i = -6, 6 do
		for j = -1, 1 do
			local h = groundY(x + hl * i / 6, z + hd * j)
			hi = math.max(hi, h)
			lo = math.min(lo, h)
		end
	end
	return hi, lo
end

local function buildLabel(parent: Instance, l: any, isVillage: boolean)
	-- Villages are the names players navigate by: larger and steadier than terrain features,
	-- which no longer dwarf them (Landgrafenberg vs Closewitz in Studio).
	local size = if isVillage then 24 else math.clamp(17 * l.size, 13, 22)
	-- plate length follows the name so long names keep their letter height
	local len = size * math.max(3, 0.56 * #l.text)
	-- Shorten the plate on steep ground (it clipped at the ends on slopes in Studio), then lift it
	-- above the highest terrain under its largest scaled footprint.
	local hi, lo = maxGroundUnder(l.pos.x, l.pos.z, len * LABEL_MAX_K / 2, size * LABEL_MAX_K / 2)
	local minLen = len * 0.55
	while hi - lo > LABEL_MAX_RISE and len > minLen do
		len *= 0.85
		hi, lo = maxGroundUnder(l.pos.x, l.pos.z, len * LABEL_MAX_K / 2, size * LABEL_MAX_K / 2)
	end
	local y = hi
	-- A Top-face gui runs its text along the part's -Z (checked in Studio), so the plate is long
	-- in Z and turned 90° to read left-to-right from the default north-facing camera.
	local p = part(parent, nil, Vector3.new(size, 0.2, len), CFrame.new(l.pos.x, y + 0.5, l.pos.z) * CFrame.Angles(0, math.pi / 2, 0), Color3.new(1, 1, 1))
	p.Transparency = 1
	p.CastShadow = false
	local gui = Instance.new("SurfaceGui") :: SurfaceGui
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(math.floor(100 * len / size), 100) -- TextScaled stops at 100 px, so the canvas is 100 tall
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = p
	local text = Instance.new("TextLabel") :: TextLabel
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Garamond
	text.TextScaled = true
	text.Text = l.text
	text.TextColor3 = rgb(P.Cream)
	text.TextTransparency = 0.12
	text.TextStrokeColor3 = Color3.fromRGB(40, 34, 24)
	text.TextStrokeTransparency = 0.6
	text.Parent = gui
	table.insert(labelParts, { part = p, size = size, len = len })
end

local function buildObjective(parent: Instance, o: any)
	local y = groundY(o.pos.x, o.pos.z)
	local ring: { Part } = {}
	local n = 20
	local r = o.radius
	for i = 1, n do
		local a0 = (i - 1) / n * math.pi * 2
		local a1 = i / n * math.pi * 2
		local x0, z0 = o.pos.x + math.cos(a0) * r, o.pos.z + math.sin(a0) * r
		local x1, z1 = o.pos.x + math.cos(a1) * r, o.pos.z + math.sin(a1) * r
		local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
		local seg = part(parent, nil, Vector3.new(Vec.dist({ x = x0, z = z0 }, { x = x1, z = z1 }) + 0.4, 0.3, 1.2), yaw(mx, groundY(mx, mz) + 0.4, mz, math.atan2(z1 - z0, x1 - x0)), rgb(P.Cream))
		seg.Transparency = 0.5
		seg.CastShadow = false
		ring[i] = seg
	end
	part(parent, Enum.PartType.Cylinder, Vector3.new(22, 0.5, 0.5), CFrame.new(o.pos.x, y + 11, o.pos.z) * CFrame.Angles(0, 0, math.pi / 2), rgb(P.Ink))
	local flag = part(parent, nil, Vector3.new(7, 4.5, 0.3), CFrame.new(o.pos.x + 3.7, y + 19.5, o.pos.z), rgb(P.Cream))
	flag.CastShadow = false
	objectiveMarks[o.id] = { ring = ring, flag = flag }
end

-- Builds everything for a map. Yields. Returns false when superseded by clear()/rebuild.
function Props.build(map: any, quality: number, onProgress: ((fraction: number) -> ())?): boolean
	Props.clear()
	generation += 1
	local myGen = generation
	currentMap = map
	local f = Instance.new("Folder") :: Folder
	f.Name = "EoEProps"
	f.Parent = workspace
	folder = f
	local q = math.clamp(quality, 1, 3)
	local threshold = TREE_PRIORITY[q]
	local season = Terrain.seasonOf(map.id)
	look = LOOKS[season]
	WorldLighting.setMap(map.id)
	local function sub(name: string): Folder
		local d = Instance.new("Folder") :: Folder
		d.Name = name
		d.Parent = f
		return d
	end
	local woodsF, villagesF, fieldsF, waterF, countryF = sub("Woods"), sub("Villages"), sub("Fields"), sub("Water"), sub("Country")

	-- conifers favour the top quarter of the map's height range
	local lo, hi = math.huge, -math.huge
	for _, hgt in map.grid.height do
		lo = math.min(lo, hgt)
		hi = math.max(hi, hgt)
	end
	local highGround = lo + (hi - lo) * 0.72

	local jobs: { () -> () } = {}
	for _, w in map.woods do
		for _, t in w.trees do
			if t.priority >= threshold then
				table.insert(jobs, function()
					buildWoodsTree(woodsF, t, highGround)
				end)
			end
		end
	end
	for _, v in map.villages do
		table.insert(jobs, function()
			buildVillage(villagesF, v)
		end)
	end
	for _, o in Terrain.orchards() do
		if q >= 2 then
			table.insert(jobs, function()
				buildOrchard(villagesF, o)
			end)
		end
	end
	table.insert(jobs, function()
		buildWindmills(villagesF)
	end)
	for _, br in map.bridges do
		table.insert(jobs, function()
			buildBridge(waterF, br)
		end)
	end
	for _, river in map.rivers do
		buildRiverside(waterF, river, q, jobs)
	end
	buildAvenues(fieldsF, jobs)
	buildBorders(fieldsF, q, jobs)
	if q >= 2 then
		buildStooks(fieldsF, jobs)
	end
	buildCountry(countryF, q, jobs)
	local villageNames: { [string]: boolean } = {}
	for _, v in map.villages do
		villageNames[v.name] = true
	end
	for _, l in map.labels do
		table.insert(jobs, function()
			buildLabel(f, l, villageNames[l.text] == true)
		end)
	end
	for _, o in map.objectives do
		table.insert(jobs, function()
			buildObjective(f, o)
		end)
	end
	local total = #jobs
	local slice = os.clock()
	for i, job in jobs do
		if generation ~= myGen then
			return false
		end
		job()
		if os.clock() - slice > 0.01 then
			if onProgress then
				onProgress(i / total)
			end
			task.wait()
			slice = os.clock()
		end
	end
	if onProgress then
		onProgress(1)
	end
	return generation == myGen
end

-- Ground labels turn with the camera in 90° steps so they never read upside down. `yaw` is
-- the camera's (Camera.getYaw); the plates were built for the north-facing default (π/2).
local lastLabelYaw = math.pi / 2
function Props.setLabelYaw(yaw: number)
	local step = math.round(yaw / (math.pi / 2)) * (math.pi / 2)
	if math.abs(step - lastLabelYaw) < 0.01 then
		return
	end
	lastLabelYaw = step
	for _, l in labelParts do
		l.part.CFrame = CFrame.new(l.part.Position) * CFrame.Angles(0, math.pi - step, 0)
	end
end

-- Ground labels grow with camera height so they stay readable from any zoom.
local lastLabelK = -1
function Props.updateLabels(cameraHeight: number)
	local k = math.clamp(cameraHeight / 420, 0.7, LABEL_MAX_K)
	if math.abs(k - lastLabelK) < 0.05 then
		return
	end
	lastLabelK = k
	for _, l in labelParts do
		l.part.Size = Vector3.new(l.size * k, 0.2, l.len * k)
	end
end

local function factionColour(faction: string?): Color3
	if faction == nil or faction == "" then
		return rgb(P.Cream)
	end
	return Factions.colour(faction)
end

function Props.updateObjectives(objectives: { any })
	for _, o in objectives do
		local m = objectiveMarks[o.id]
		if m then
			local c = factionColour(o.owner)
			m.flag.Color = c
			local ringC = if o.contested then rgb(P.Hostile) else c
			local t = if o.contested then 0.2 else 0.55
			for _, seg in m.ring do
				seg.Color = ringC
				seg.Transparency = t
			end
		end
	end
end

-- Rect {x0,z0,x1,z1} or nil to hide. Translucent wall segments following the terrain.
function Props.setDeployZone(rect: any?, faction: string?)
	if zoneFolder then
		zoneFolder:Destroy()
		zoneFolder = nil
	end
	if not rect or not currentMap then
		return
	end
	WorldLighting.beginBattle() -- deployment: the light starts from this battle's own weather
	local zf = Instance.new("Folder") :: Folder
	zf.Name = "EoEDeployZone"
	zf.Parent = workspace
	zoneFolder = zf
	local c = factionColour(faction)
	local step = 32
	local function edge(ax: number, az: number, bx: number, bz: number)
		local len = Vec.dist({ x = ax, z = az }, { x = bx, z = bz })
		local n = math.max(1, math.ceil(len / step))
		local heading = math.atan2(bz - az, bx - ax)
		for i = 1, n do
			local t0, t1 = (i - 1) / n, i / n
			local mx = ax + (bx - ax) * (t0 + t1) / 2
			local mz = az + (bz - az) * (t0 + t1) / 2
			local seg = part(zf, nil, Vector3.new(len / n + 0.5, 6, 0.6), yaw(mx, groundY(mx, mz) + 3, mz, heading), c)
			seg.Transparency = 0.65
			seg.CastShadow = false
		end
	end
	edge(rect.x0, rect.z0, rect.x1, rect.z0)
	edge(rect.x1, rect.z0, rect.x1, rect.z1)
	edge(rect.x1, rect.z1, rect.x0, rect.z1)
	edge(rect.x0, rect.z1, rect.x0, rect.z0)
end

function Props.clear()
	generation += 1
	if folder then
		folder:Destroy()
		folder = nil
	end
	if zoneFolder then
		zoneFolder:Destroy()
		zoneFolder = nil
	end
	table.clear(labelParts)
	lastLabelK = -1
	table.clear(objectiveMarks)
end

return Props
