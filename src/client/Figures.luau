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
local Factions = require(script.Parent.Factions)
local Soldiers = require(script.Parent.World.Soldiers)

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

type Slot = { x: number, z: number, sx: number, sz: number, phase: number } -- local offset + scatter (routing spread)
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
	anim: { number }, -- part index -> Soldiers anim code
	pivot: { number }, -- part index -> swing pivot height
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
	return Factions.colour(faction, colourKey)
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

local function addPart(g: Group, p: BasePart, cf: CFrame, slot: number, anim: number?, pivot: number?)
	table.insert(g.parts, p)
	table.insert(g.locals, cf)
	table.insert(g.partSlot, slot)
	table.insert(g.anim, anim or 0)
	table.insert(g.pivot, pivot or 0)
	p.Parent = folder
end

-- Battalion extras: a mounted officer in front, colour-bearer and drummer at the front centre
-- (inside a square they stand in the middle). Never thinned.
local function specialSlots(f: any): { { x: number, z: number, role: string } }
	if f.shape == "square" then
		return { { x = 0, z = 0, role = "officer" }, { x = 0.6, z = -1.4, role = "colour" }, { x = 0.6, z = 1.4, role = "drummer" } }
	end
	local front = f.depth / 2
	return { { x = front + 3.6, z = 0, role = "officer" }, { x = front + 1.3, z = -0.6, role = "colour" }, { x = front + 1.3, z = 1.4, role = "drummer" } }
end

local function buildNear(g: Group, f: any)
	local n = figureCount(g.class, f.strength)
	g.slots = layoutSlots(g.class, f.shape, n, f.width, f.depth, thinK, g.id * 7919)
	local detail = Settings.get().quality >= 2
	local slotIndex = 0
	local function adder(): Soldiers.Add
		local si = slotIndex
		return function(p: BasePart, cf: CFrame, anim: number, pivot: number)
			addPart(g, p, cf, si, anim, pivot)
		end
	end
	local base = #g.slots
	for i = 1, base do
		slotIndex = i
		local add = adder()
		if g.class == "infantry" then
			Soldiers.infantry(add, g.faction, g.colour, detail, "line")
		elseif g.class == "cavalry" then
			Soldiers.rider(add, g.faction, g.colour, Soldiers.riderKind(f.name), detail, g.id + i)
		elseif g.class == "hq" then
			Soldiers.rider(add, g.faction, g.colour, "officer", detail, g.id + i)
		elseif g.class == "artillery" then
			Soldiers.gun(add, g.faction, g.colour, f.shape == "limbered" or f.limbered == true, detail, g.id + i)
		end
	end
	if g.class == "infantry" then
		for _, s in specialSlots(f) do
			table.insert(g.slots, { x = s.x, z = s.z, sx = 0, sz = 0, phase = #g.slots * 1.7 })
			slotIndex = #g.slots
			local add = adder()
			if s.role == "officer" then
				Soldiers.rider(add, g.faction, g.colour, "officer", detail, g.id)
			else
				Soldiers.infantry(add, g.faction, g.colour, detail, if s.role == "colour" then "colour" else "drummer")
			end
		end
	end
end

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.fromRGB(242, 240, 232)
local GUN = Color3.fromRGB(30, 28, 26)
local SLAB_H = 1.2

-- Reference look: French deep cobalt, Prussian near-black charcoal; ghosts desaturated.
local function slabColour(g: Group): Color3
	local c = g.colour:Lerp(BLACK, Factions.slabDarken(g.faction))
	return if g.ghost then desaturate(c) else c
end

-- Flat slab: thin dark edge, body colour, slightly lighter top face.
local function slab(g: Group, cx: number, cz: number, sx: number, sz: number)
	local c = slabColour(g)
	local edge = mk("Part", Vector3.new(sx + 0.5, SLAB_H, sz + 0.5), c:Lerp(BLACK, 0.6))
	local body = mk("Part", Vector3.new(sx, SLAB_H + 0.1, sz), c)
	local top = mk("Part", Vector3.new(math.max(sx - 0.4, 0.5), 0.16, math.max(sz - 0.4, 0.5)), c:Lerp(Color3.new(1, 1, 1), 0.28))
	top.CastShadow = false
	for _, part in { edge, body, top } do
		if g.ghost then
			part.Transparency = 0.4
		end
	end
	addPart(g, edge, CFrame.new(cx, SLAB_H / 2, cz), 0)
	addPart(g, body, CFrame.new(cx, SLAB_H / 2 + 0.05, cz), 0)
	addPart(g, top, CFrame.new(cx, SLAB_H + 0.2, cz), 0)
end

-- White diagonal stripes on a slab top: French two parallel bands, Prussian a cross.
local function stripes(g: Group, sx: number, sz: number)
	local len = math.min(sx, sz) * 1.2
	local y = SLAB_H + 0.3
	local function stripe(ox: number, angle: number)
		local s = mk("Part", Vector3.new(len, 0.16, math.max(0.5, math.min(sx, sz) * 0.14)), WHITE)
		s.CastShadow = false
		if g.ghost then
			s.Transparency = 0.4
		end
		addPart(g, s, CFrame.new(ox, y, 0) * CFrame.Angles(0, angle, 0), 0)
	end
	if g.faction == "france" then
		stripe(-sx * 0.2, math.rad(45))
		stripe(sx * 0.2, math.rad(45))
	else
		stripe(0, math.rad(45))
		stripe(0, math.rad(-45))
	end
end

local function buildFar(g: Group, f: any)
	if g.class == "cavalry" then
		slab(g, 0, 0, f.depth, f.width)
		stripes(g, f.depth, f.width)
	elseif g.class == "artillery" then
		-- small dark gun silhouettes, no block
		local n = figureCount("artillery", f.strength)
		for i = 1, n do
			local z = (i - 0.5) / n * f.width - f.width / 2
			addPart(g, cylinder(5, 0.45, GUN), CFrame.new(0.5, 1.6, z), 0)
			for side = -1, 1, 2 do
				addPart(g, cylinder(0.5, 1.5, GUN), CFrame.new(-0.5, 1.5, z + side * 1.5) * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), 0)
			end
		end
	elseif g.class == "hq" then
		-- the marker alone stands for a headquarters
		return
	elseif f.shape == "square" then
		local tk = math.max(f.depth * 0.22, 2.5)
		slab(g, f.depth / 2 - tk / 2, 0, tk, f.width)
		slab(g, -f.depth / 2 + tk / 2, 0, tk, f.width)
		slab(g, 0, f.width / 2 - tk / 2, f.depth - 2 * tk, tk)
		slab(g, 0, -f.width / 2 + tk / 2, f.depth - 2 * tk, tk)
	else
		-- a cluster of 2–4 parallel slabs across the footprint depth
		local shapeDef = (Config.Shapes :: any)[f.shape]
		local ranks = math.clamp(if shapeDef and shapeDef.ranks > 0 then shapeDef.ranks else 3, 2, 4)
		ranks = math.max(1, math.min(ranks, figureCount(g.class, f.strength)))
		local rankSp = f.depth / ranks
		for r = 0, ranks - 1 do
			slab(g, f.depth / 2 - (r + 0.5) * rankSp, 0, rankSp * 0.6, f.width)
		end
	end
end

local POLE = Color3.fromRGB(150, 150, 150)
local IVORY = Color3.fromRGB(246, 241, 226)
local GOLD = Color3.fromRGB(205, 168, 62)

-- Marker: pole (formation space), then camera-facing parts whose locals are offsets from the
-- plate centre: frame, plate, square flag. parts[1] is always the pole.
local function buildMarker(g: Group, f: any): Marker
	local hq = g.class == "hq"
	local scale = if hq then 1.5 else 1
	local poleH = 13 * scale
	local plateW = if hq then 12 else 8
	local plateH = if hq then 4.2 else 2.8
	local parts: { BasePart } = {}
	local locals: { CFrame } = {}
	local function face(p: BasePart, cf: CFrame)
		p.CastShadow = false
		table.insert(parts, p)
		table.insert(locals, cf)
	end
	local pole = cylinder(poleH, 0.1, POLE)
	pole.CastShadow = false
	table.insert(parts, pole)
	table.insert(locals, CFrame.new(0, poleH / 2, 0) * CFrame.Angles(0, 0, math.pi / 2))
	local framePart = mk("Part", Vector3.new(plateW + 0.4, plateH + 0.4, 0.2), if hq then GOLD else INK)
	face(framePart, CFrame.new(0, 0, 0.12))
	local plate = mk("Part", Vector3.new(plateW, plateH, 0.3), IVORY) :: Part
	face(plate, CFrame.new())
	-- square flag below the plate, beside the pole; design per faction
	local s = 2.4 * scale
	local fx = s / 2 + 0.2
	local fy = -(plateH / 2 + s / 2 + 0.3)
	local flag = Factions.flag(g.faction)
	if flag.bands then
		local n = #flag.bands
		for i, c in flag.bands do
			face(mk("Part", Vector3.new(s / n, s, 0.12), c), CFrame.new(fx + (i - (n + 1) / 2) * s / n, fy, 0))
		end
	else
		face(mk("Part", Vector3.new(s, s, 0.12), flag.field or g.colour), CFrame.new(fx, fy, 0))
	end
	local mc = flag.markColour
	local markCf = CFrame.new(fx, fy, -0.08)
	if flag.mark == "diamond" then
		face(mk("Part", Vector3.new(0.55 * scale, 0.55 * scale, 0.14), mc), markCf * CFrame.Angles(0, 0, math.rad(45)))
	elseif flag.mark == "x" then
		for _, a in { 45, -45 } do
			face(mk("Part", Vector3.new(s * 1.3, 0.22, 0.14), mc), markCf * CFrame.Angles(0, 0, math.rad(a)))
		end
	elseif flag.mark == "plus" then
		face(mk("Part", Vector3.new(s, 0.3, 0.14), mc), markCf)
		face(mk("Part", Vector3.new(0.3, s, 0.14), mc), markCf)
	elseif flag.mark == "double" then
		face(mk("Part", Vector3.new(s, 0.24, 0.14), mc), markCf * CFrame.new(0, s * 0.18, 0))
		face(mk("Part", Vector3.new(s, 0.24, 0.14), mc), markCf * CFrame.new(0, -s * 0.18, 0))
	elseif flag.mark == "diagonal" then
		face(mk("Part", Vector3.new(s * 1.3, 0.22, 0.14), mc), markCf * CFrame.Angles(0, 0, math.rad(45)))
	end
	for _, p in parts do
		if g.ghost then
			p.Transparency = 0.35
		end
		p.Parent = folder
	end

	local gui = Instance.new("SurfaceGui") :: SurfaceGui
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(plateW * 60, plateH * 60)
	gui.LightInfluence = 0
	gui.Parent = plate
	local function line(sizeY: number, posY: number, text: string, font: EnumFont): TextLabel
		local l = Instance.new("TextLabel") :: TextLabel
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, -16, sizeY, 0)
		l.Position = UDim2.new(0, 8, posY, 0)
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = INK
		l.Text = text
		l.Parent = gui
		return l
	end
	local nameText = string.upper(tostring(f.name or ("#" .. g.id)))
	local corpsText = string.upper(tostring(f.corps or ""))
	if hq then
		-- "Napoléon — Imperial HQ" -> NAPOLÉON / IMPERIAL HQ
		local a, b = string.match(nameText, "^(.-)%s+[—%-]+%s+(.+)$")
		if a and b then
			nameText, corpsText = a, b
		end
	end
	local nameLabel = line(if hq then 0.5 else 0.46, 0.04, nameText, Enum.Font.Garamond)
	line(if hq then 0.22 else 0.26, if hq then 0.54 else 0.48, corpsText, Enum.Font.Garamond)
	local statusLabel = line(0.22, if hq then 0.76 else 0.74, "", Enum.Font.Gotham)
	local bar = Instance.new("Frame") :: Frame
	bar.Size = UDim2.new(1, -16, 0, 6)
	bar.Position = UDim2.new(0, 8, 1, -8)
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
	table.clear(g.anim)
	table.clear(g.pivot)
	table.clear(g.slots)
	if g.lod == "near" and not g.ghost then
		buildNear(g, f)
	else
		buildFar(g, f)
	end
	g.dirty = true
end

local function layoutKeyOf(g: Group, f: any): string
	return string.format("%s|%d|%d|%d|%d|%d|%d", f.shape, math.round(f.width), math.round(f.depth), figureCount(g.class, f.strength), thinK, if g.lod == "near" then 1 else 0, Settings.get().quality)
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
		anim = {},
		pivot = {},
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

			local state = f.state
			local animating = not g.ghost and g.lod == "near" and (state == "moving" or state == "charging" or state == "routing" or state == "retreating" or state == "melee")
			if animating then
				g.phase += dt * (if state == "charging" or state == "routing" then 9 else 5.5)
				g.dirty = true
			end
			if g.dirty then
				g.dirty = false
				local baseY = groundY(g.rx, g.rz)
				local cf = frame(g.rx, baseY, g.rz, g.rh)
				local routing = state == "routing"
				local charging = state == "charging"
				-- muskets come down for volleys and bayonet charges
				local armed = state == "firing" or (charging and g.class == "infantry")
				local amp = if routing or charging then 0.75 else 0.45
				local slotCf: { CFrame } = {}
				local swing: { number } = {}
				for si, s in g.slots do
					local sx, sz = s.x, s.z
					if routing then
						-- running back with a ragged spread
						sx += s.sx * 2.5
						sz += s.sz * 2.5
					end
					local wp = cf * Vector3.new(sx, 0, sz)
					local y = groundY(wp.X, wp.Z)
					local sw = 0
					if animating then
						local ph = g.phase + s.phase
						sw = math.sin(ph) * amp
						y += math.abs(math.cos(ph)) * 0.12
					end
					swing[si] = sw
					local h = g.rh
					if routing then
						h += math.pi + (s.phase - math.pi) * 0.35
					end
					local scf = frame(wp.X, y, wp.Z, h)
					if charging then
						scf *= CFrame.Angles(0, 0, if g.class == "cavalry" then -0.1 else -0.22) -- lean into the charge
					end
					slotCf[si] = scf
				end
				local anims, pivots, slots = g.anim, g.pivot, g.partSlot
				for i, p in g.parts do
					local slot = slots[i]
					local lc = g.locals[i]
					local base = cf
					if slot > 0 then
						base = slotCf[slot]
						local a = anims[i]
						if a ~= 0 then
							lc = Soldiers.partCFrame(a, lc, pivots[i], swing[slot], armed and not routing)
						end
					end
					table.insert(moveParts, p)
					table.insert(moveCfs, base * lc)
				end
				-- marker: pole in formation space, plate and flag turned to the camera
				local m = g.marker
				local markerBase = CFrame.new(g.rx, baseY, g.rz)
				local plateY = baseY + m.height
				local face = CFrame.lookAt(Vector3.new(g.rx, plateY, g.rz), Vector3.new(camPos.X, plateY, camPos.Z))
				for i, p in m.parts do
					table.insert(moveParts, p)
					table.insert(moveCfs, if i == 1 then markerBase * m.locals[1] else face * m.locals[i])
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
				for i = 2, #m.parts do
					table.insert(moveParts, m.parts[i])
					table.insert(moveCfs, face * m.locals[i])
				end
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
