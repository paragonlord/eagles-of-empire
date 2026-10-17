--!strict
-- Decorative props derived from MapData: trees, houses, bridges, ground labels, objective
-- markers and the deployment zone outline. Anchored, non-colliding, non-queryable parts.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Vec = require(Shared.Vec)

local Props = {}

local P = Config.Visual.Palette
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local folder: Folder? = nil
local zoneFolder: Folder? = nil
local labelParts: { { part: Part, size: number } } = {}
local objectiveMarks: { [string]: { ring: { Part }, flag: Part } } = {}
local generation = 0
local currentMap: any = nil

local TREE_PRIORITY = { [1] = 0.55, [2] = 0.25, [3] = 0.0 } -- keep trees with priority >= this
local CROWNS = { [1] = 2, [2] = 3, [3] = 3 }
local CROWN = Color3.fromRGB(52, 74, 36) -- dense dark green (reference), not the lighter palette crown
local ROOF = Color3.fromRGB(58, 40, 30) -- very dark brown pitched roofs
local WALL = Color3.fromRGB(104, 78, 58)

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

local function wedge(parent: Instance, size: Vector3, cf: CFrame, color: Color3): WedgePart
	local p = Instance.new("WedgePart") :: WedgePart
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.Parent = parent
	return p
end

-- Yaw so that local +X points along a sim heading (Roblox rotates +X toward -Z for +angle).
local function yaw(x: number, y: number, z: number, heading: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, -heading, 0)
end

local function groundY(x: number, z: number): number
	return Grid.heightAt(currentMap.grid, x, z)
end

local function buildTree(parent: Instance, t: any, crowns: number)
	local r = t.r
	local y = groundY(t.x, t.z)
	local trunkH = r * 1.1
	part(parent, Enum.PartType.Cylinder, Vector3.new(trunkH, r * 0.28, r * 0.28), CFrame.new(t.x, y + trunkH / 2, t.z) * CFrame.Angles(0, 0, math.pi / 2), rgb(P.TreeTrunk))
	-- dark disc underneath gives the "depth beneath the canopy"
	part(parent, Enum.PartType.Cylinder, Vector3.new(0.3, r * 2.1, r * 2.1), CFrame.new(t.x, y + 0.2, t.z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(38, 46, 28))
	local crown = CROWN
	local seed = (t.x * 7 + t.z * 13) % 10 / 10
	for i = 1, crowns do
		local f = (i - 1) / math.max(crowns - 1, 1)
		local cr = r * (1.0 - f * 0.35)
		local off = (i - 1) * r * 0.35
		local ang = seed * math.pi * 2 + i * 2.1
		part(parent, Enum.PartType.Ball, Vector3.new(cr * 2, cr * 2, cr * 2), CFrame.new(t.x + math.cos(ang) * off, y + trunkH + cr * 0.6 + off * 0.8, t.z + math.sin(ang) * off), crown:Lerp(Color3.fromRGB(30, 46, 22), f * 0.35))
	end
end

local function buildBuilding(parent: Instance, b: any)
	local y = groundY(b.pos.x, b.pos.z)
	local base = yaw(b.pos.x, y + b.h / 2 - 0.5, b.pos.z, b.heading)
	part(parent, nil, Vector3.new(b.w, b.h, b.d), base, WALL)
	local roofH = b.h * 0.55
	local roofColor = if (b.w * 3 + b.d) % 2 < 1 then ROOF else ROOF:Lerp(Color3.fromRGB(28, 22, 18), 0.4)
	local roofBase = yaw(b.pos.x, y + b.h - 0.5 + roofH / 2, b.pos.z, b.heading)
	-- two wedges back to back along local Z form a gable with the ridge along local X
	wedge(parent, Vector3.new(b.w + 0.6, roofH, b.d / 2 + 0.3), roofBase * CFrame.new(0, 0, -b.d / 4), roofColor)
	wedge(parent, Vector3.new(b.w + 0.6, roofH, b.d / 2 + 0.3), roofBase * CFrame.new(0, 0, b.d / 4) * CFrame.Angles(0, math.pi, 0), roofColor)
end

local function buildBridge(parent: Instance, br: any)
	local a, b = br.a, br.b
	local len = Vec.dist(a, b)
	local dir = Vec.normalize(Vec.sub(b, a))
	local h = math.max(groundY(a.x, a.z), groundY(b.x, b.z))
	local mid = Vec.lerp(a, b, 0.5)
	local heading = Vec.heading(dir)
	local stone = Color3.fromRGB(150, 140, 125)
	part(parent, nil, Vector3.new(len + 4, 1.2, br.width), yaw(mid.x, h + 0.4, mid.z, heading), stone, Enum.Material.Slate)
	for side = -1, 1, 2 do
		part(parent, nil, Vector3.new(len + 4, 1.4, 0.8), yaw(mid.x, h + 1.5, mid.z, heading) * CFrame.new(0, 0, side * (br.width / 2 - 0.4)), stone, Enum.Material.Slate)
	end
	-- piers down to the water bed
	for i = 0, 2 do
		local t = 0.2 + i * 0.3
		local px, pz = a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t
		local bottom = groundY(px, pz)
		local ph = math.max(h - bottom, 1)
		part(parent, nil, Vector3.new(3, ph, br.width - 1), yaw(px, bottom + ph / 2, pz, heading), stone:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Slate)
	end
end

local function buildLabel(parent: Instance, l: any)
	local size = 20 * l.size -- modest, mixed case, cream serif
	local y = groundY(l.pos.x, l.pos.z)
	-- A Top-face gui runs its text along the part's -Z (checked in Studio), so the plate is long
	-- in Z and turned 90° to read left-to-right from the default north-facing camera.
	local p = part(parent, nil, Vector3.new(size, 0.2, size * 4), CFrame.new(l.pos.x, y + 0.35, l.pos.z) * CFrame.Angles(0, math.pi / 2, 0), Color3.new(1, 1, 1))
	p.Transparency = 1
	p.CastShadow = false
	local gui = Instance.new("SurfaceGui") :: SurfaceGui
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(400, 100) -- TextScaled stops at 100 px, so the canvas is 100 tall
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
	text.TextTransparency = 0.4
	text.Parent = gui
	table.insert(labelParts, { part = p, size = size })
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
	local crowns = CROWNS[q]

	local jobs: { () -> () } = {}
	for _, w in map.woods do
		for _, t in w.trees do
			if t.priority >= threshold then
				table.insert(jobs, function()
					buildTree(f, t, crowns)
				end)
			end
		end
	end
	for _, v in map.villages do
		for _, b in v.buildings do
			table.insert(jobs, function()
				buildBuilding(f, b)
			end)
		end
	end
	for _, br in map.bridges do
		table.insert(jobs, function()
			buildBridge(f, br)
		end)
	end
	for _, l in map.labels do
		table.insert(jobs, function()
			buildLabel(f, l)
		end)
	end
	for _, o in map.objectives do
		table.insert(jobs, function()
			buildObjective(f, o)
		end)
	end
	local total = #jobs
	for i, job in jobs do
		if generation ~= myGen then
			return false
		end
		job()
		if i % 120 == 0 then
			if onProgress then
				onProgress(i / total)
			end
			task.wait()
		end
	end
	if onProgress then
		onProgress(1)
	end
	return generation == myGen
end

-- Ground labels grow with camera height so they stay readable from any zoom.
local lastLabelK = -1
function Props.updateLabels(cameraHeight: number)
	local k = math.clamp(cameraHeight / 420, 0.7, 2.0)
	if math.abs(k - lastLabelK) < 0.05 then
		return
	end
	lastLabelK = k
	for _, l in labelParts do
		local s = l.size * k
		l.part.Size = Vector3.new(s, 0.2, s * 4)
	end
end

local function factionColour(faction: string?): Color3
	if faction == "france" then
		return rgb(P.France)
	elseif faction == "prussia" then
		return rgb(P.Prussia)
	end
	return rgb(P.Cream)
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
	table.clear(objectiveMarks)
end

return Props
