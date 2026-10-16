--!strict
-- Formation visuals: procedural figures (near LOD) or rank blocks (far LOD), nameplate
-- markers, selection rings, destination ghosts and route lines. Purely cosmetic: nothing here
-- is read for gameplay. Parts are anchored and moved with workspace:BulkMoveTo.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Vec = require(Shared.Vec)
local BattleState = require(script.Parent.BattleState)
local Selection = require(script.Parent.Selection)
local Settings = require(script.Parent.Settings)

local Figures = {}

local P = Config.Visual.Palette
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end
local CREAM = rgb(P.Cream)
local INK = rgb(P.Ink)
local SELECT = rgb(P.Select)
local HOSTILE = rgb(P.Hostile)
local SKIN = Color3.fromRGB(214, 180, 140)
local HORSE = Color3.fromRGB(96, 70, 48)
local WOOD = Color3.fromRGB(70, 50, 34)

local SNAP_DT = 0.1
local MAX_EXTRAP = 0.15
local LABEL_INTERVAL = 0.15

type Slot = { x: number, z: number, sx: number, sz: number, phase: number } -- local offset + scatter
type Marker = {
	parts: { BasePart },
	locals: { CFrame },
	plate: Part,
	gui: SurfaceGui,
	nameLabel: TextLabel,
	statusLabel: TextLabel,
	bar: Frame,
	barFill: Frame,
	height: number,
	priority: number,
}
type Group = {
	id: number,
	faction: string,
	class: string,
	colour: Color3,
	ghost: boolean,
	lod: string, -- "near" | "far"
	parts: { BasePart },
	locals: { CFrame },
	slots: { Slot },
	partSlot: { number }, -- part index -> slot index (0 = formation-relative, no bob)
	musketIdx: { number }, -- part indices of muskets (pose changes)
	layoutKey: string,
	p0x: number,
	p0z: number,
	p0h: number,
	p1x: number,
	p1z: number,
	p1h: number,
	t1: number,
	rx: number,
	rz: number,
	rh: number,
	dirty: boolean,
	phase: number,
	marker: Marker,
	ring: { BasePart }?,
	ringColour: Color3?,
	dest: { BasePart },
	route: { BasePart },
	destKey: string,
}

local folder: Folder? = nil
local groups: { [number]: Group } = {}
local previews: { BasePart } = {}
local thinK = 1
local labelClock = 0
local pendingKey = ""
local prevSelected: { [number]: boolean } = {}
local figureHeight = 3.2

-- ------------------------------------------------------------------ part helpers

local function mk(className: string, size: Vector3, color: Color3): BasePart
	local p = Instance.new(className) :: BasePart
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function ball(size: number, color: Color3): BasePart
	local p = mk("Part", Vector3.new(size, size, size), color) :: Part
	p.Shape = Enum.PartType.Ball
	return p
end

local function cylinder(length: number, radius: number, color: Color3): BasePart
	local p = mk("Part", Vector3.new(length, radius * 2, radius * 2), color) :: Part
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function groundY(x: number, z: number): number
	local m = BattleState.map
	return if m then Grid.heightAt(m.grid, x, z) else 0
end

-- Yaw so local +X points along a sim heading and local +Z is the formation's right.
local function frame(x: number, y: number, z: number, heading: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, -heading, 0)
end

local function factionColour(faction: string, colourKey: string?): Color3
	local key = colourKey or (if faction == "france" then "France" elseif faction == "prussia" then "Prussia" else nil)
	local t = if key then (P :: any)[key] else nil
	return if t then rgb(t) else Color3.fromRGB(120, 120, 120)
end

local function desaturate(c: Color3): Color3
	local g = (c.R + c.G + c.B) / 3
	return Color3.new(g, g, g):Lerp(c, 0.25):Lerp(Color3.new(0.75, 0.72, 0.68), 0.3)
end

local function figureCount(class: string, strength: number?): number
	strength = strength or 0
	if class == "hq" then
		return 2
	elseif class == "artillery" then
		return math.max(1, math.ceil(strength / Config.Visual.CrewPerGun))
	end
	return math.max(1, math.ceil(strength / Config.Visual.SoldiersPerFigure))
end

-- ------------------------------------------------------------------ layout

-- Returns local (x forward, z right) offsets for n figures in the formation footprint.
local function layoutSlots(class: string, shape: string, n: number, width: number, depth: number, k: number, seed: number): { Slot }
	local cells: { { number } } = {} -- {file, rank, files, ranks}
	local shapeDef = (Config.Shapes :: any)[shape]
	local ranks = if shapeDef then shapeDef.ranks else 3
	if class == "hq" then
		cells = { { 0, 0, 2, 1 }, { 1, 0, 2, 1 } }
	elseif shape == "square" then
		local side = math.max(2, math.ceil(math.sqrt(n)))
		local list: { { number } } = {}
		for i = 0, side - 1 do
			for j = 0, side - 1 do
				table.insert(list, { i, j, side, side, math.min(i, j, side - 1 - i, side - 1 - j) })
			end
		end
		table.sort(list, function(a: { number }, b: { number })
			if a[5] ~= b[5] then
				return a[5] < b[5]
			end
			return a[1] * side + a[2] < b[1] * side + b[2]
		end)
		for i = 1, math.min(n, #list) do
			cells[i] = list[i]
		end
	elseif shape == "wedge" then
		local placed, r, rows = 0, 0, {}
		while placed < n do
			local w = math.min(2 * r + 1, n - placed)
			table.insert(rows, w)
			placed += w
			r += 1
		end
		local maxW = rows[#rows]
		for ri, w in rows do
			for f = 0, w - 1 do
				table.insert(cells, { f + (maxW - w) / 2, ri - 1, maxW, #rows })
			end
		end
	else
		if ranks <= 0 then
			ranks = 3
		end
		ranks = math.min(ranks, n)
		local files = math.ceil(n / ranks)
		for i = 0, n - 1 do
			local rank = i // files
			local file = i % files
			table.insert(cells, { file, rank, files, ranks })
		end
	end
	local slots: { Slot } = {}
	local rng = Random.new(seed)
	for i, c in cells do
		local file, rank, files, rks = c[1], c[2], c[3], c[4]
		-- thinning keeps the outline (first/last file and rank) and every k-th interior figure
		local edge = file == 0 or file >= files - 1 or rank == 0 or rank >= rks - 1
		if k <= 1 or edge or i % k == 0 then
			local fileSp = width / files
			local rankSp = depth / rks
			table.insert(slots, {
				x = depth / 2 - (rank + 0.5) * rankSp,
				z = (file + 0.5) * fileSp - width / 2,
				sx = (rng:NextNumber() - 0.5) * 6,
				sz = (rng:NextNumber() - 0.5) * 6,
				phase = rng:NextNumber() * math.pi * 2,
			})
		end
	end
	return slots
end

-- ------------------------------------------------------------------ builders
-- Each builder appends parts + local CFrames (relative to the figure origin at ground level).

local function addPart(g: Group, p: BasePart, cf: CFrame, slot: number)
	table.insert(g.parts, p)
	table.insert(g.locals, cf)
	table.insert(g.partSlot, slot)
	p.Parent = folder
end

local function buildInfantryFigure(g: Group, slot: number, legs: Color3)
	local s = figureHeight / 3.2
	addPart(g, mk("Part", Vector3.new(0.6 * s, 1.0 * s, 0.8 * s), legs), CFrame.new(0, 0.5 * s, 0), slot)
	addPart(g, mk("Part", Vector3.new(0.65 * s, 1.3 * s, 1.0 * s), g.colour), CFrame.new(0, 1.65 * s, 0), slot)
	addPart(g, ball(0.6 * s, SKIN), CFrame.new(0, 2.55 * s, 0), slot)
	addPart(g, mk("Part", Vector3.new(0.55 * s, 0.6 * s, 0.55 * s), INK), CFrame.new(0, 3.05 * s, 0), slot)
	-- musket shouldered: vertical rod at the right shoulder; firing pose swaps this CFrame
	local m = mk("Part", Vector3.new(0.12 * s, 2.6 * s, 0.12 * s), WOOD)
	addPart(g, m, CFrame.new(0.1 * s, 2.2 * s, 0.45 * s) * CFrame.Angles(0, 0, math.rad(10)), slot)
	table.insert(g.musketIdx, #g.parts)
end

local function buildCavalryFigure(g: Group, slot: number)
	local s = figureHeight / 3.2
	addPart(g, mk("Part", Vector3.new(2.4 * s, 1.1 * s, 0.9 * s), HORSE), CFrame.new(0, 1.25 * s, 0), slot)
	addPart(g, mk("Part", Vector3.new(0.7 * s, 0.6 * s, 0.5 * s), HORSE), CFrame.new(1.3 * s, 1.9 * s, 0), slot)
	addPart(g, mk("Part", Vector3.new(0.6 * s, 1.2 * s, 0.9 * s), g.colour), CFrame.new(0, 2.4 * s, 0), slot)
	addPart(g, ball(0.55 * s, SKIN), CFrame.new(0, 3.25 * s, 0), slot)
	addPart(g, mk("Part", Vector3.new(0.5 * s, 0.5 * s, 0.5 * s), INK), CFrame.new(0, 3.7 * s, 0), slot)
end

local function buildGun(g: Group, slot: number)
	local s = figureHeight / 3.2
	addPart(g, cylinder(3.2 * s, 0.22 * s, INK), CFrame.new(0.4 * s, 1.1 * s, 0) * CFrame.Angles(0, 0, math.rad(-4)), slot)
	for side = -1, 1, 2 do
		local w = cylinder(0.25 * s, 0.9 * s, rgb(P.Roof))
		addPart(g, w, CFrame.new(-0.3 * s, 0.9 * s, side * 0.9 * s) * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), slot)
	end
	addPart(g, mk("Part", Vector3.new(1.6 * s, 0.4 * s, 1.2 * s), WOOD), CFrame.new(-1.0 * s, 0.6 * s, 0), slot)
	for side = -1, 1, 2 do
		addPart(g, mk("Part", Vector3.new(0.6 * s, 2.2 * s, 0.8 * s), g.colour), CFrame.new(-1.2 * s, 1.1 * s, side * 1.8 * s), slot)
		addPart(g, ball(0.55 * s, SKIN), CFrame.new(-1.2 * s, 2.5 * s, side * 1.8 * s), slot)
	end
end

local function buildNear(g: Group, f: any)
	local n = figureCount(g.class, f.strength)
	g.slots = layoutSlots(g.class, f.shape, n, f.width, f.depth, thinK, g.id * 7919)
	local legs = if g.faction == "france" then Color3.fromRGB(225, 220, 205) else Color3.fromRGB(120, 118, 112)
	for i = 1, #g.slots do
		if g.class == "infantry" then
			buildInfantryFigure(g, i, legs)
		elseif g.class == "cavalry" or g.class == "hq" then
			buildCavalryFigure(g, i)
		elseif g.class == "artillery" then
			buildGun(g, i)
		end
	end
end

local function buildFar(g: Group, f: any)
	local c = if g.ghost then desaturate(g.colour) else g.colour
	local top = c:Lerp(Color3.new(1, 1, 1), 0.35)
	local h = 2.4
	local function block(cx: number, cz: number, sx: number, sz: number)
		local b = mk("Part", Vector3.new(sx, h, sz), c)
		local t = mk("Part", Vector3.new(sx, 0.2, sz), top)
		t.CastShadow = false
		if g.ghost then
			b.Transparency = 0.4
			t.Transparency = 0.4
		end
		addPart(g, b, CFrame.new(cx, h / 2, cz), 0)
		addPart(g, t, CFrame.new(cx, h + 0.1, cz), 0)
	end
	if g.class == "cavalry" then
		local w = mk("WedgePart", Vector3.new(f.width, h * 1.3, f.depth), c)
		if g.ghost then
			w.Transparency = 0.4
		end
		-- wedge thin edge forward: WedgePart slopes toward its -Z, so turn it to face local +X
		addPart(g, w, CFrame.new(0, h * 0.65, 0) * CFrame.Angles(0, math.pi / 2, 0), 0)
	elseif g.class == "artillery" then
		local n = figureCount("artillery", f.strength)
		for i = 1, n do
			local z = (i - 0.5) / n * f.width - f.width / 2
			addPart(g, cylinder(5, 0.5, c), CFrame.new(0.5, 1.8, z), 0)
			for side = -1, 1, 2 do
				addPart(g, cylinder(0.5, 1.6, c), CFrame.new(-0.5, 1.6, z + side * 1.6) * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), 0)
			end
		end
	elseif g.class == "hq" then
		block(0, 0, math.max(f.depth, 3), math.max(f.width, 4))
	elseif f.shape == "square" then
		local t = math.max(f.depth * 0.22, 2.5)
		block(f.depth / 2 - t / 2, 0, t, f.width)
		block(-f.depth / 2 + t / 2, 0, t, f.width)
		block(0, f.width / 2 - t / 2, f.depth - 2 * t, t)
		block(0, -f.width / 2 + t / 2, f.depth - 2 * t, t)
	else
		local shapeDef = (Config.Shapes :: any)[f.shape]
		local ranks = math.max(1, math.min(if shapeDef then shapeDef.ranks else 3, figureCount(g.class, f.strength)))
		local rankSp = f.depth / ranks
		for r = 0, ranks - 1 do
			block(f.depth / 2 - (r + 0.5) * rankSp, 0, rankSp * 0.8, f.width)
		end
	end
end

local function buildMarker(g: Group, f: any): Marker
	local hq = g.class == "hq"
	local scale = if hq then 1.5 else 1
	local poleH = 13 * scale
	local plateW = (if hq then 11 else 8)
	local plateH = 2.6 * scale
	local parts: { BasePart } = {}
	local locals: { CFrame } = {}
	local pole = cylinder(poleH, 0.12, INK)
	pole.CastShadow = false
	table.insert(parts, pole)
	table.insert(locals, CFrame.new(0, poleH / 2, 0) * CFrame.Angles(0, 0, math.pi / 2))
	local framePart = mk("Part", Vector3.new(plateW + 0.5, plateH + 0.5, 0.22), INK) :: Part
	framePart.CastShadow = false
	local plate = mk("Part", Vector3.new(plateW, plateH, 0.3), CREAM) :: Part
	plate.CastShadow = false
	table.insert(parts, framePart)
	table.insert(locals, CFrame.new(0, poleH + plateH / 2, 0.08))
	table.insert(parts, plate)
	table.insert(locals, CFrame.new(0, poleH + plateH / 2, 0))
	local flag = mk("Part", Vector3.new(2.6 * scale, 1.8 * scale, 0.15), if g.ghost then desaturate(g.colour) else g.colour) :: Part
	flag.CastShadow = false
	table.insert(parts, flag)
	table.insert(locals, CFrame.new(1.4 * scale, poleH - 1.4 * scale, 0))
	for _, p in parts do
		p.Parent = folder
	end

	local gui = Instance.new("SurfaceGui") :: SurfaceGui
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(plateW * 60, plateH * 60)
	gui.LightInfluence = 0
	gui.Parent = plate
	local nameLabel = Instance.new("TextLabel") :: TextLabel
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, -12, 0.55, 0)
	nameLabel.Position = UDim2.new(0, 6, 0, 2)
	nameLabel.Font = Enum.Font.Garamond
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = INK
	nameLabel.Text = f.name or ("#" .. g.id)
	nameLabel.Parent = gui
	local statusLabel = Instance.new("TextLabel") :: TextLabel
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, -12, 0.3, 0)
	statusLabel.Position = UDim2.new(0, 6, 0.55, 0)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextScaled = true
	statusLabel.TextColor3 = INK
	statusLabel.Text = ""
	statusLabel.Parent = gui
	local bar = Instance.new("Frame") :: Frame
	bar.Size = UDim2.new(1, -12, 0, 8)
	bar.Position = UDim2.new(0, 6, 1, -10)
	bar.BackgroundColor3 = INK
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = gui
	local fill = Instance.new("Frame") :: Frame
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = g.colour
	fill.BorderSizePixel = 0
	fill.Parent = bar
	return {
		parts = parts,
		locals = locals,
		plate = plate,
		gui = gui,
		nameLabel = nameLabel,
		statusLabel = statusLabel,
		bar = bar,
		barFill = fill,
		height = poleH + plateH / 2,
		priority = if hq then 4 else 1,
	}
end

local function destroyParts(list: { BasePart })
	for _, p in list do
		p:Destroy()
	end
	table.clear(list)
end

local function rebuildBody(g: Group, f: any)
	destroyParts(g.parts)
	table.clear(g.locals)
	table.clear(g.partSlot)
	table.clear(g.musketIdx)
	table.clear(g.slots)
	if g.lod == "near" and not g.ghost then
		buildNear(g, f)
	else
		buildFar(g, f)
	end
	g.dirty = true
end

local function layoutKeyOf(g: Group, f: any): string
	return string.format("%s|%d|%d|%d|%d|%d", f.shape, math.round(f.width), math.round(f.depth), figureCount(g.class, f.strength), thinK, if g.lod == "near" then 1 else 0)
end

local function newGroup(id: number, f: any, ghost: boolean): Group
	local colour = factionColour(f.faction, f.colour)
	local g: Group = {
		id = id,
		faction = f.faction,
		class = f.class,
		colour = colour,
		ghost = ghost,
		lod = "far",
		parts = {},
		locals = {},
		slots = {},
		partSlot = {},
		musketIdx = {},
		layoutKey = "",
		p0x = f.x,
		p0z = f.z,
		p0h = f.heading,
		p1x = f.x,
		p1z = f.z,
		p1h = f.heading,
		t1 = os.clock(),
		rx = f.x,
		rz = f.z,
		rh = f.heading,
		dirty = true,
		phase = 0,
		marker = nil :: any,
		ring = nil,
		ringColour = nil,
		dest = {},
		route = {},
		destKey = "",
	}
	g.marker = buildMarker(g, f)
	return g
end

local function destroyGroup(g: Group)
	destroyParts(g.parts)
	destroyParts(g.marker.parts)
	if g.ring then
		destroyParts(g.ring)
	end
	destroyParts(g.dest)
	destroyParts(g.route)
end

-- ------------------------------------------------------------------ snapshot intake

local function budget(): number
	return if Settings.get().quality >= 3 then Config.Visual.MaxFiguresHigh elseif Settings.get().quality == 2 then (Config.Visual.MaxFiguresHigh + Config.Visual.MaxFiguresLow) // 2 else Config.Visual.MaxFiguresLow
end

local function onSnapshot()
	if not folder then
		return
	end
	local now = os.clock()
	local seen: { [number]: boolean } = {}
	local total = 0
	for id, f in BattleState.formations do
		seen[id] = true
		total += figureCount(f.class, f.strength)
		local existing: Group? = groups[id]
		if existing and existing.ghost then
			destroyGroup(existing)
			groups[id] = nil
			existing = nil
		end
		local g: Group
		if existing then
			g = existing
			if f.x ~= g.p1x or f.z ~= g.p1z or f.heading ~= g.p1h then
				g.p0x, g.p0z, g.p0h = g.rx, g.rz, g.rh
				g.p1x, g.p1z, g.p1h = f.x, f.z, f.heading
				g.t1 = now + SNAP_DT
			else
				-- unchanged this snapshot: it has stopped, so settle on p1 (no extrapolation)
				g.p0x, g.p0z, g.p0h = g.p1x, g.p1z, g.p1h
				g.t1 = now
			end
		else
			g = newGroup(id, f, false)
			groups[id] = g
		end
		if f.state == "destroyed" or f.state == "exited" then
			destroyGroup(g)
			groups[id] = nil
			seen[id] = nil
		end
	end
	for id, lk in BattleState.lastKnown do
		seen[id] = true
		local existing: Group? = groups[id]
		if existing and not existing.ghost then
			destroyGroup(existing)
			groups[id] = nil
			existing = nil
		end
		local g: Group
		if existing then
			g = existing
		else
			g = newGroup(id, lk, true)
			groups[id] = g
		end
		g.rx, g.rz, g.rh = lk.x, lk.z, lk.heading
		g.p1x, g.p1z, g.p1h = lk.x, lk.z, lk.heading
		g.marker.statusLabel.Text = string.format("last seen %ds ago", math.floor(lk.ageSeconds))
	end
	for id, g in groups do
		if not seen[id] then
			destroyGroup(g)
			groups[id] = nil
		end
	end
	local newK = math.max(1, math.ceil(total / budget()))
	if newK ~= thinK then
		thinK = newK
	end
end

-- ------------------------------------------------------------------ overlays

local function ringParts(g: Group, colour: Color3, alpha: number): { BasePart }
	local list: { BasePart } = {}
	for _ = 1, 4 do
		local p = mk("Part", Vector3.new(1, 0.25, 1), colour)
		p.CastShadow = false
		p.Transparency = alpha
		p.Parent = folder
		table.insert(list, p)
	end
	g.ringColour = colour
	return list
end

local function placeRing(list: { BasePart }, cfs: { CFrame }, ring: { BasePart }, cf: CFrame, w: number, d: number)
	local pad = 2
	local hw, hd = w / 2 + pad, d / 2 + pad
	ring[1].Size = Vector3.new(0.4, 0.25, hw * 2)
	ring[2].Size = Vector3.new(0.4, 0.25, hw * 2)
	ring[3].Size = Vector3.new(hd * 2, 0.25, 0.4)
	ring[4].Size = Vector3.new(hd * 2, 0.25, 0.4)
	local offs = { CFrame.new(hd, 0.3, 0), CFrame.new(-hd, 0.3, 0), CFrame.new(0, 0.3, hw), CFrame.new(0, 0.3, -hw) }
	for i = 1, 4 do
		table.insert(list, ring[i])
		table.insert(cfs, cf * offs[i])
	end
end

-- Translucent footprint + facing chevron at a destination. Returns parts (3).
local function ghostParts(colour: Color3, alpha: number): { BasePart }
	local rect = mk("Part", Vector3.new(1, 0.3, 1), colour)
	rect.Transparency = alpha
	rect.CastShadow = false
	local a = mk("Part", Vector3.new(3, 0.3, 0.4), colour)
	local b = mk("Part", Vector3.new(3, 0.3, 0.4), colour)
	a.Transparency = alpha * 0.6
	b.Transparency = alpha * 0.6
	a.CastShadow = false
	b.CastShadow = false
	rect.Parent = folder
	a.Parent = folder
	b.Parent = folder
	return { rect, a, b }
end

local function placeGhost(parts: { BasePart }, x: number, z: number, heading: number, w: number, d: number)
	local cf = frame(x, groundY(x, z) + 0.4, z, heading)
	parts[1].Size = Vector3.new(d, 0.3, w)
	parts[1].CFrame = cf
	parts[2].CFrame = cf * CFrame.new(d / 2 + 1.2, 0, 1.0) * CFrame.Angles(0, math.rad(40), 0)
	parts[3].CFrame = cf * CFrame.new(d / 2 + 1.2, 0, -1.0) * CFrame.Angles(0, math.rad(-40), 0)
end

local function routeSegment(parent: Instance, colour: Color3, a: { x: number, z: number }, b: { x: number, z: number }): BasePart
	local p = mk("Part", Vector3.new(1, 0.2, 0.6), colour)
	p.CastShadow = false
	p.Transparency = 0.35
	local len = Vec.dist(a, b)
	local mx, mz = (a.x + b.x) / 2, (a.z + b.z) / 2
	p.Size = Vector3.new(math.max(len, 0.5), 0.2, 0.6)
	p.CFrame = frame(mx, (groundY(a.x, a.z) + groundY(b.x, b.z)) / 2 + 0.5, mz, math.atan2(b.z - a.z, b.x - a.x))
	p.Parent = parent
	return p
end

-- Destination ghosts + route lines for a selected own formation (server dest + queue, plus
-- pending orders not yet acknowledged). Rebuilt only when the key changes.
local function updateOrders(g: Group, f: any, selected: boolean)
	local key = ""
	if selected and not g.ghost and f.faction == BattleState.viewerFaction then
		if f.dest then
			key = string.format("d%.0f,%.0f,%.2f", f.dest.x, f.dest.z, f.destHeading or f.heading)
		end
		if f.queue then
			for _, q in f.queue do
				key ..= string.format("q%.0f,%.0f", q.x, q.z)
			end
		end
		key ..= pendingKey
	end
	if key == g.destKey then
		return
	end
	g.destKey = key
	destroyParts(g.dest)
	destroyParts(g.route)
	if key == "" or not folder then
		return
	end
	local fl = folder :: Folder
	local last = { x = g.rx, z = g.rz }
	if f.dest then
		local parts = ghostParts(g.colour, 0.6)
		placeGhost(parts, f.dest.x, f.dest.z, f.destHeading or f.heading, f.width, f.depth)
		for _, p in parts do
			table.insert(g.dest, p)
		end
		table.insert(g.route, routeSegment(fl, g.colour, last, f.dest))
		last = f.dest
	end
	if f.queue then
		for _, q in f.queue do
			table.insert(g.route, routeSegment(fl, g.colour, last, q))
			last = q
		end
	end
	for _, pend in BattleState.pending do
		if pend.pos and table.find(pend.ids, g.id) then
			local parts = ghostParts(SELECT, 0.7)
			placeGhost(parts, pend.pos.x, pend.pos.z, pend.heading or f.heading, pend.frontage or f.width, f.depth)
			for _, p in parts do
				table.insert(g.dest, p)
			end
			table.insert(g.route, routeSegment(fl, SELECT, last, pend.pos))
		end
	end
end

-- ------------------------------------------------------------------ labels

local function deconflictLabels(cam: Camera)
	local vp = cam.ViewportSize
	local list: { { g: Group, x: number, y: number, w: number, h: number, pri: number } } = {}
	local hovered = Selection.hovered()
	local fov = math.rad(cam.FieldOfView)
	for id, g in groups do
		local m = g.marker
		local pri = m.priority
		if Selection.isSelected(id) then
			pri = math.max(pri, 3)
		elseif id == hovered then
			pri = math.max(pri, 2)
		end
		local world = Vector3.new(g.rx, groundY(g.rx, g.rz) + m.height, g.rz)
		local sp, onScreen = cam:WorldToViewportPoint(world)
		if onScreen and sp.Z > 0 then
			local scale = vp.Y / (2 * sp.Z * math.tan(fov / 2))
			local w = m.plate.Size.X * scale
			local h = m.plate.Size.Y * scale
			table.insert(list, { g = g, x = sp.X, y = sp.Y, w = w, h = h, pri = pri })
		else
			m.gui.Enabled = false
		end
	end
	table.sort(list, function(a: { g: Group, x: number, y: number, w: number, h: number, pri: number }, b: { g: Group, x: number, y: number, w: number, h: number, pri: number })
		if a.pri ~= b.pri then
			return a.pri > b.pri
		end
		return a.g.id < b.g.id
	end)
	local accepted: { { x: number, y: number, w: number, h: number } } = {}
	for _, e in list do
		local ok = true
		for _, a in accepted do
			if math.abs(a.x - e.x) < (a.w + e.w) / 2 and math.abs(a.y - e.y) < (a.h + e.h) / 2 then
				ok = false
				break
			end
		end
		e.g.marker.gui.Enabled = ok
		if ok then
			table.insert(accepted, { x = e.x, y = e.y, w = e.w, h = e.h })
		end
	end
end

local STATUS_WORD: { [string]: string } = {
	idle = "Holding",
	moving = "Marching",
	reforming = "Reforming",
	firing = "Firing",
	charging = "Charging",
	melee = "In melee",
	retreating = "Retreating",
	routing = "Routing",
	rallying = "Rallying",
	destroyed = "Destroyed",
	exited = "Left the field",
}

local function statusText(f: any): string
	local s = STATUS_WORD[f.state] or f.state
	if f.moraleBand == "shaken" then
		s ..= " · Shaken"
	elseif f.moraleBand == "shattered" then
		s = "Shattered"
	end
	if f.status and f.status ~= "" then
		s ..= " · " .. f.status
	end
	return s
end

-- ------------------------------------------------------------------ public

function Figures.init()
	if folder then
		return
	end
	local f = Instance.new("Folder") :: Folder
	f.Name = "EoEFigures"
	f.Parent = workspace
	folder = f
	thinK = 1
end

function Figures.onSnapshot()
	onSnapshot()
end

function Figures.onPendingChanged()
	local parts = {}
	for id, p in BattleState.pending do
		table.insert(parts, id)
	end
	table.sort(parts)
	pendingKey = table.concat(parts, ",")
end

-- Drag preview ghosts: list of {x, z, heading, width, depth}.
function Figures.setPreview(list: { { x: number, z: number, heading: number, width: number, depth: number } }?)
	destroyParts(previews)
	if not list or not folder then
		return
	end
	for _, e in list do
		local parts = ghostParts(SELECT, 0.55)
		placeGhost(parts, e.x, e.z, e.heading, e.width, e.depth)
		for _, p in parts do
			table.insert(previews, p)
		end
	end
end

function Figures.update(dt: number)
	if not folder then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local now = os.clock()
	local moveParts: { BasePart } = {}
	local moveCfs: { CFrame } = {}
	local hovered = Selection.hovered()
	local farD = Config.Visual.FarLodDistance

	for id, g in groups do
		local f: any = if g.ghost then BattleState.lastKnown[id] else BattleState.formations[id]
		if f then
			-- interpolate ≈ one snapshot behind, extrapolate at most MAX_EXTRAP
			if not g.ghost then
				local t = (now - (g.t1 - SNAP_DT)) / SNAP_DT
				if t > 1 + MAX_EXTRAP / SNAP_DT then
					t = 1 + MAX_EXTRAP / SNAP_DT
				end
				t = math.max(t, 0)
				local nx = g.p0x + (g.p1x - g.p0x) * t
				local nz = g.p0z + (g.p1z - g.p0z) * t
				local nh = g.p0h + Vec.angleDiff(g.p0h, g.p1h) * math.min(t, 1)
				if nx ~= g.rx or nz ~= g.rz or nh ~= g.rh then
					g.rx, g.rz, g.rh = nx, nz, nh
					g.dirty = true
				end
			end
			-- LOD with hysteresis
			local dist = (camPos - Vector3.new(g.rx, groundY(g.rx, g.rz), g.rz)).Magnitude
			local wantLod = if g.ghost then "far" elseif g.lod == "near" then (if dist > farD * 1.1 then "far" else "near") else (if dist < farD then "near" else "far")
			if wantLod ~= g.lod then
				g.lod = wantLod
			end
			local key = layoutKeyOf(g, f)
			if key ~= g.layoutKey then
				g.layoutKey = key
				rebuildBody(g, f)
			end

			local animating = not g.ghost and g.lod == "near" and (f.state == "moving" or f.state == "charging" or f.state == "routing" or f.state == "retreating" or f.state == "melee")
			if animating then
				g.phase += dt * (if f.state == "charging" or f.state == "routing" then 9 else 5)
				g.dirty = true
			end
			local firing = f.state == "firing"
			if g.dirty then
				g.dirty = false
				local baseY = groundY(g.rx, g.rz)
				local cf = frame(g.rx, baseY, g.rz, g.rh)
				local routing = f.state == "routing"
				local slotCf: { CFrame } = {}
				for si, s in g.slots do
					local sx, sz = s.x, s.z
					if routing then
						sx += s.sx
						sz += s.sz
					end
					local wp = cf * Vector3.new(sx, 0, sz)
					local y = groundY(wp.X, wp.Z)
					if animating then
						y += math.abs(math.sin(g.phase + s.phase)) * 0.3
					end
					slotCf[si] = frame(wp.X, y, wp.Z, g.rh + (if routing then (s.phase - math.pi) * 0.25 else 0))
				end
				local isMusket: { [number]: boolean } = {}
				for _, mi in g.musketIdx do
					isMusket[mi] = true
				end
				for i, p in g.parts do
					local slot = g.partSlot[i]
					local base = if slot > 0 then slotCf[slot] else cf
					local lc = g.locals[i]
					if firing and isMusket[i] then
						lc = CFrame.new(0.9, 2.3, 0.4) * CFrame.Angles(0, 0, math.rad(-90))
					end
					table.insert(moveParts, p)
					table.insert(moveCfs, base * lc)
				end
				-- marker: pole/flag in formation space, plate turned to the camera
				local m = g.marker
				local markerBase = CFrame.new(g.rx, baseY, g.rz)
				local plateY = baseY + m.height
				local face = CFrame.lookAt(Vector3.new(g.rx, plateY, g.rz), Vector3.new(camPos.X, plateY, camPos.Z))
				for i, p in m.parts do
					table.insert(moveParts, p)
					if i == 2 or i == 3 then
						table.insert(moveCfs, face * CFrame.new(0, 0, if i == 2 then 0.12 else 0))
					else
						table.insert(moveCfs, markerBase * m.locals[i])
					end
				end
				-- selection / hover ring
				local selected = Selection.isSelected(id)
				local wantRing: Color3? = if selected then SELECT elseif id == hovered then (if g.faction == BattleState.viewerFaction then CREAM else HOSTILE) else nil
				local needNew = g.ring == nil or g.ringColour ~= wantRing
				if wantRing ~= nil and needNew then
					if g.ring then
						destroyParts(g.ring)
					end
					g.ring = ringParts(g, wantRing, if selected then 0.1 else 0.5)
				elseif not wantRing and g.ring then
					destroyParts(g.ring)
					g.ring = nil
				end
				if g.ring then
					placeRing(moveParts, moveCfs, g.ring, cf, f.width, f.depth)
				end
			else
				-- the plate still has to follow the camera; cheap enough per frame
				local m = g.marker
				local plateY = groundY(g.rx, g.rz) + m.height
				local face = CFrame.lookAt(Vector3.new(g.rx, plateY, g.rz), Vector3.new(camPos.X, plateY, camPos.Z))
				table.insert(moveParts, m.parts[2])
				table.insert(moveCfs, face * CFrame.new(0, 0, 0.12))
				table.insert(moveParts, m.parts[3])
				table.insert(moveCfs, face)
			end
			-- ring/dest refresh on selection or hover change
			local selected = Selection.isSelected(id)
			local wasSelected = prevSelected[id] == true
			if wasSelected ~= selected then
				prevSelected[id] = selected
				g.dirty = true
			end
			local showStatus = selected or id == hovered
			local m = g.marker
			if not g.ghost then
				m.statusLabel.Text = if showStatus then statusText(f) else ""
				m.bar.Visible = showStatus
				if showStatus then
					m.barFill.Size = UDim2.fromScale(math.clamp(f.strength / math.max(f.startStrength, 1), 0, 1), 1)
				end
			end
			updateOrders(g, f, selected)
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	labelClock += dt
	if labelClock >= LABEL_INTERVAL then
		labelClock = 0
		deconflictLabels(cam)
	end
end

-- Forces every group to re-place its parts (after hover changes etc).
function Figures.markDirty()
	for _, g in groups do
		g.dirty = true
	end
end

function Figures.clear()
	for _, g in groups do
		destroyGroup(g)
	end
	table.clear(groups)
	destroyParts(previews)
	table.clear(prevSelected)
	pendingKey = ""
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return Figures
