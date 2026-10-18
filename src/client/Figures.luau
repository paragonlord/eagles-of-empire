--!strict
-- Formation visuals: procedural figures (near LOD) or rank blocks (far LOD), nameplate
-- markers, selection rings, destination ghosts and route lines. Purely cosmetic: nothing here
-- is read for gameplay. Parts are anchored and moved with workspace:BulkMoveTo.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local BattleState = require(script.Parent.BattleState)
local Selection = require(script.Parent.Selection)
local Settings = require(script.Parent.Settings)
local Factions = require(script.Parent.Factions)
local Soldiers = require(script.Parent.World.Soldiers)
local Ground = require(script.Parent.Ground)
local Kit = require(script.Parent.UI.Kit)

local Figures = {}

local P = Config.Visual.Palette
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end
local CREAM = rgb(P.Cream)
local INK = rgb(P.Ink)
local SELECT = rgb(P.Select)
local HOSTILE = rgb(P.Hostile)

local NEAR_TIER_D = 150 -- camera distance within which the near tier may be built
local nearBand = NEAR_TIER_D -- the near-tier band in force: shrinks so the closest blocks fit the budget
local SNAP_DT = 0.1
local MAX_EXTRAP = 0.15
local LABEL_INTERVAL = 0.15

-- x/z: slot offset in the formation; sx/sz: routing scatter; ox/oz + vx/vz: personal flocking
-- offset and velocity; tx/tz: decaying slide from the previous layout; left/right: rank neighbours.
type Slot = { x: number, z: number, sx: number, sz: number, phase: number, ox: number, oz: number, vx: number, vz: number, tx: number, tz: number, left: number, right: number, face: number? }
type Marker = {
	parts: { BasePart },
	locals: { CFrame },
	plate: Part, -- invisible anchor for the billboard
	gui: BillboardGui,
	pxW: number, -- billboard size in screen pixels (for label deconfliction)
	pxH: number,
	frame: Frame, -- the ivory plate inside the billboard
	texts: { TextLabel }, -- name/corps lines (hidden in banner mode)
	curW: number, -- current on-screen plate width (px)
	curH: number,
	nameLabel: TextLabel,
	statusLabel: TextLabel,
	bar: Frame,
	barFill: Frame,
	stripe: Frame, -- co-op: the commanding officer's slot colour down the plate's left edge
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
	tier: string, -- near LOD detail: "near" (jointed figures, kit, spoked wheels) | "mid" (coat, breeches, shako, musket)
	dist: number, -- camera distance last frame
	parts: { BasePart },
	locals: { CFrame },
	slots: { Slot },
	partSlot: { number }, -- part index -> slot index (0 = formation-relative, no bob)
	anim: { number }, -- part index -> Soldiers anim code
	pivot: { number }, -- part index -> swing pivot height
	flagIdx: { number }, -- part indices of colours (anim 6), swayed every frame
	slotCf: { CFrame }, -- last placed slot frames (flags sway between full placements)
	look: Soldiers.Look?,
	nLine: number, -- slots 1..nLine are rank and file (specials follow)
	lastStrength: number,
	lossAcc: number, -- men lost not yet shown as a falling figure
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

local function cylinder(length: number, radius: number, color: Color3): BasePart
	local p = mk("Part", Vector3.new(length, radius * 2, radius * 2), color) :: Part
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Rendered ground (raycast cache; heightmap fallback before the world is ready).
local groundY = Ground.heightAt

-- Yaw so local +X points along a sim heading and local +Z is the formation's right.
local function frame(x: number, y: number, z: number, heading: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, -heading, 0)
end

-- Like frame(), but tilted to the slope under a d-deep, w-wide footprint, so blocks, rings and
-- destination markers lie on a hillside instead of floating level through it, then raised
-- until none of the footprint's four corners is under the ground.
local function groundFrame(x: number, z: number, lift: number, heading: number, w: number, d: number): CFrame
	local fx, fz = math.cos(heading), math.sin(heading)
	local rx, rz = -fz, fx
	local hd, hw = math.max(d / 2, 2), math.max(w / 2, 2)
	local slopeF = (groundY(x + fx * hd, z + fz * hd) - groundY(x - fx * hd, z - fz * hd)) / (2 * hd)
	local slopeR = (groundY(x + rx * hw, z + rz * hw) - groundY(x - rx * hw, z - rz * hw)) / (2 * hw)
	local fwd = Vector3.new(fx, slopeF, fz).Unit
	local up = Vector3.new(rx, slopeR, rz).Unit:Cross(fwd).Unit
	local cf = CFrame.fromMatrix(Vector3.new(x, groundY(x, z), z), fwd, up, fwd:Cross(up))
	local corners: { number } = {}
	local plane: { number } = {}
	local i = 0
	for _, dx in { -hd, hd } do
		for _, dz in { -hw, hw } do
			i += 1
			local c = cf * Vector3.new(dx, 0, dz)
			corners[i] = groundY(c.X, c.Z)
			plane[i] = c.Y
		end
	end
	return cf + Vector3.new(0, lift + Ground.lift(0, corners, plane), 0)
end

-- Half-footprints (forward, right) a figure's body covers, for the four-corner lift.
local FOOT: { [string]: { number } } = { infantry = { 0.35, 0.45 }, cavalry = { 1.6, 0.5 }, hq = { 1.6, 0.5 }, artillery = { 2.2, 1.6 } }

local function factionColour(faction: string, colourKey: string?): Color3
	return Factions.colour(faction, colourKey)
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

-- Infantry draws shoulder to shoulder: files every FILE_W studs across the real frontage, so a
-- line reads as a solid block of three ranks (Studio showed thin files with wide gaps). The
-- budget factor k widens the files and drops a line to two ranks instead of punching holes.
local FILE_W = 0.8

local function denseInfantry(shape: string, width: number, depth: number, k: number): { { x: number, z: number, face: number } }
	local out = {}
	local fw = FILE_W * math.sqrt(k)
	if shape == "square" then
		local side = math.max(width, depth)
		for ring = 0, (if k >= 2 then 0 else 1) do
			local half = side / 2 - 0.5 - ring * 1.1
			local n = math.max(2, math.floor(2 * half / fw))
			for i = 0, n - 1 do
				local u = -half + (i + 0.5) * 2 * half / n
				table.insert(out, { x = half, z = u, face = 0 }) -- front face looks forward
				table.insert(out, { x = -half, z = -u, face = math.pi })
				table.insert(out, { x = -u, z = half, face = math.pi / 2 })
				table.insert(out, { x = u, z = -half, face = -math.pi / 2 })
			end
		end
		return out
	end
	local shapeDef = (Config.Shapes :: any)[shape]
	local ranks = if shapeDef and shapeDef.ranks > 0 then shapeDef.ranks else 3
	if shape == "line" and k >= 2 then
		ranks = 2
	end
	ranks = math.max(1, math.min(ranks, math.floor(depth / 0.9)))
	local files = math.max(2, math.floor(width / fw))
	for r = 0, ranks - 1 do
		for f = 0, files - 1 do
			table.insert(out, { x = depth / 2 - (r + 0.5) * depth / ranks, z = (f + 0.5) * width / files - width / 2, face = 0 })
		end
	end
	return out
end

-- Figures the near LOD will draw for a formation (budget accounting).
local function visualCount(f: any): number
	if f.class == "infantry" then
		return #denseInfantry(f.shape, f.width, f.depth, 1)
	end
	return figureCount(f.class, f.strength)
end

local function linkRanks(slots: { Slot })
	-- rank neighbours: slots sharing x, ordered by z (O(n log n) once per layout)
	local order = {}
	for i = 1, #slots do
		order[i] = i
	end
	table.sort(order, function(a: number, b: number)
		local sa, sb = slots[a], slots[b]
		if math.abs(sa.x - sb.x) > 0.01 then
			return sa.x < sb.x
		end
		return sa.z < sb.z
	end)
	for j = 2, #order do
		local a, b = order[j - 1], order[j]
		if math.abs(slots[a].x - slots[b].x) <= 0.01 then
			slots[a].right = b
			slots[b].left = a
		end
	end
end

-- Returns local (x forward, z right) offsets for n figures in the formation footprint.
local function layoutSlots(class: string, shape: string, n: number, width: number, depth: number, k: number, seed: number): { Slot }
	if class == "infantry" then
		local rng = Random.new(seed)
		local slots: { Slot } = {}
		for _, c in denseInfantry(shape, width, depth, k) do
			table.insert(slots, {
				x = c.x, z = c.z, face = c.face,
				sx = (rng:NextNumber() - 0.5) * 6, sz = (rng:NextNumber() - 0.5) * 6,
				phase = rng:NextNumber() * math.pi * 2,
				ox = 0, oz = 0, vx = 0, vz = 0, tx = 0, tz = 0, left = 0, right = 0,
			})
		end
		linkRanks(slots)
		return slots
	end
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
				ox = 0, oz = 0, vx = 0, vz = 0, tx = 0, tz = 0, left = 0, right = 0,
			})
		end
	end
	linkRanks(slots)
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

-- Battalion extras: a mounted officer in front, the colour (the Eagle for France) at the
-- centre of the front rank and a drummer on each flank; inside a square they all stand in the
-- middle. Never thinned.
local function specialSlots(f: any): { { x: number, z: number, role: string } }
	if f.shape == "square" then
		return { { x = 0, z = 0, role = "officer" }, { x = 0.6, z = -1.0, role = "colour" }, { x = -0.8, z = 1.4, role = "drummer" }, { x = -0.8, z = -1.6, role = "drummer" } }
	end
	local front = f.depth / 2
	local flank = f.width / 2 + 1.0
	return {
		{ x = front + 3.6, z = 0, role = "officer" },
		{ x = front + 0.9, z = 0, role = "colour" },
		{ x = front - 0.6, z = flank, role = "drummer" },
		{ x = front - 0.6, z = -flank, role = "drummer" },
	}
end

local function buildNear(g: Group, f: any)
	local n = figureCount(g.class, f.strength)
	g.slots = layoutSlots(g.class, f.shape, n, f.width, f.depth, thinK, g.id * 7919)
	local detail = Settings.get().quality >= 2 and g.tier == "near"
	local slotIndex = 0
	local function adder(): Soldiers.Add
		local si = slotIndex
		return function(p: BasePart, cf: CFrame, anim: number, pivot: number)
			addPart(g, p, cf, si, anim, pivot)
		end
	end
	local look = Soldiers.look(g.faction, f.colour, g.class, f.name)
	g.look = look
	local base = #g.slots
	g.nLine = base
	for i = 1, base do
		slotIndex = i
		local add = adder()
		if g.class == "infantry" then
			Soldiers.infantry(add, look, detail, "line", i)
		elseif g.class == "cavalry" then
			Soldiers.rider(add, look, detail, g.id + i)
		elseif g.class == "hq" then
			-- the general, then an aide in plain staff dress (the Emperor's grey is his alone)
			Soldiers.rider(add, if i == 1 then look else Soldiers.look(g.faction, f.colour, "hq", nil), detail, g.id + i)
		elseif g.class == "artillery" then
			Soldiers.gun(add, look, f.shape == "limbered" or f.limbered == true, detail, g.id + i)
		end
	end
	if g.class == "infantry" then
		local officer = Soldiers.look(g.faction, f.colour, "hq", nil)
		for _, s in specialSlots(f) do
			table.insert(g.slots, { x = s.x, z = s.z, sx = 0, sz = 0, phase = #g.slots * 1.7, ox = 0, oz = 0, vx = 0, vz = 0, tx = 0, tz = 0, left = 0, right = 0 })
			slotIndex = #g.slots
			local add = adder()
			if s.role == "officer" then
				Soldiers.rider(add, officer, detail, g.id)
			else
				Soldiers.infantry(add, look, detail, if s.role == "colour" then "colour" else "drummer", 0)
			end
		end
	end
	for i, a in g.anim do
		if a == 6 then
			table.insert(g.flagIdx, i)
		end
	end
end

-- ------------------------------------------------------------------ the fallen
-- Every 25 men lost (1 figure) by a near-LOD battalion or regiment, a figure from its ranks
-- tips over, settles on the ground and lies there for a while, then sinks away. Plain
-- low-detail builds; capped per quality level, oldest first.

type Body = { parts: { BasePart }, locals: { CFrame }, origin: CFrame, aboutX: boolean, fall: number, lift: number, t0: number }
local bodies: { Body } = {}
local bodyRng = Random.new(1815)
local FALL_T = 0.65
local BODY_LIFE = 50
local SINK_T = 4
local MAX_BODIES = { 24, 48, 80 }

local function removeBody(i: number)
	for _, p in bodies[i].parts do
		p:Destroy()
	end
	table.remove(bodies, i)
end

local function spawnBody(g: Group, now: number)
	local look = g.look
	local n = math.min(g.nLine, #g.slotCf)
	if not look or n == 0 then
		return
	end
	-- mostly from the front rank (where the fire lands)
	local si = bodyRng:NextInteger(1, n)
	for _ = 1, 3 do
		local c = bodyRng:NextInteger(1, n)
		if g.slots[c] and g.slots[si] and g.slots[c].x > g.slots[si].x then
			si = c
		end
	end
	local pos = g.slotCf[si].Position
	local heading = g.rh + (bodyRng:NextNumber() - 0.5) * 0.8
	local b: Body = { parts = {}, locals = {}, origin = CFrame.identity, aboutX = g.class == "cavalry", fall = 0, lift = 0, t0 = now + bodyRng:NextNumber() * 0.4 }
	local add = function(p: BasePart, cf: CFrame, anim: number, pivot: number)
		p.CastShadow = false
		p.Parent = folder
		table.insert(b.parts, p)
		table.insert(b.locals, if anim == 3 then Soldiers.partCFrame(anim, cf, pivot, 0, false) else cf)
	end
	local dir = if bodyRng:NextNumber() < 0.7 then 1 else -1 -- most fall back, away from the fire
	local len = 2.8
	if b.aboutX then
		Soldiers.rider(add, look, false, g.id + si)
		len, b.lift = 2.0, 0.35
	else
		Soldiers.infantry(add, look, false, "line", 0)
		b.lift = if dir > 0 then 0.42 else 0.24
	end
	-- the body lies on a frame tilted to the slope and lifted clear of it, so it conforms to
	-- the hillside instead of poking through it
	b.origin = if b.aboutX then groundFrame(pos.X, pos.Z, 0, heading, len * 2, 2) else groundFrame(pos.X, pos.Z, 0, heading, 1, len * 2)
	b.fall = dir * 1.52
	table.insert(bodies, b)
	local cap = MAX_BODIES[math.clamp(Settings.get().quality, 1, 3)]
	while #bodies > cap do
		removeBody(1)
	end
end

local function placeBodies(now: number, moveParts: { BasePart }, moveCfs: { CFrame })
	local i = 1
	while i <= #bodies do
		local b = bodies[i]
		local age = now - b.t0
		if age > BODY_LIFE + SINK_T then
			removeBody(i)
		else
			if age < FALL_T + 0.35 or age > BODY_LIFE or age < 0 then
				local k = 0
				if age >= FALL_T then
					k = 1 - 0.07 * math.sin(math.pi * math.min((age - FALL_T) / 0.35, 1)) -- small bounce
				elseif age > 0 then
					k = (age / FALL_T) ^ 2 -- topples faster as it goes
				end
				local a = b.fall * k
				local dy = b.lift * k - math.max(0, age - BODY_LIFE) / SINK_T * 1.2
				local cf = CFrame.new(0, dy, 0) * b.origin * (if b.aboutX then CFrame.Angles(a, 0, 0) else CFrame.Angles(0, 0, a))
				for j, p in b.parts do
					table.insert(moveParts, p)
					table.insert(moveCfs, cf * b.locals[j])
				end
			end
			i += 1
		end
	end
end

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.fromRGB(242, 240, 232)
local GUN = Color3.fromRGB(30, 28, 26)
local SLAB_H = 1.2

-- Reference look: French deep cobalt, Prussian near-black charcoal; ghosts desaturated.
local function slabColour(g: Group): Color3
	return g.colour:Lerp(BLACK, Factions.slabDarken(g.faction))
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
			part.Transparency = 0.62 -- a translucent sighting, not a unit
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

-- Dashed outline round a last-known footprint.
local function dashedOutline(g: Group, w: number, d: number)
	local hw, hd = w / 2 + 1.2, d / 2 + 1.2
	local function edge(ax: number, az: number, bx: number, bz: number)
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local n = math.max(1, math.floor(len / 3.2))
		local ang = math.atan2(bz - az, bx - ax)
		for i = 0, n - 1 do
			local t = (i + 0.5) / n
			local dash = mk("Part", Vector3.new(len / n * 0.55, 0.2, 0.35), g.colour:Lerp(Color3.new(1, 1, 1), 0.55))
			dash.CastShadow = false
			dash.Transparency = 0.2
			addPart(g, dash, CFrame.new(ax + (bx - ax) * t, 0.35, az + (bz - az) * t) * CFrame.Angles(0, -ang, 0), 0)
		end
	end
	edge(hd, -hw, hd, hw)
	edge(-hd, -hw, -hd, hw)
	edge(-hd, -hw, hd, -hw)
	edge(-hd, hw, hd, hw)
end

local function buildFar(g: Group, f: any)
	if g.ghost then
		dashedOutline(g, f.width, f.depth)
	end
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

-- Commander marker: a grey pole, a framed ivory name plate (screen-size BillboardGui, readable
-- at any zoom) and the faction flag beneath it. Last-known ghosts get a small "?" banner.
-- parts[1] is the pole (formation space); parts[2] the plate anchor; the rest (flag) are
-- camera-facing with locals relative to the plate centre.
local function buildMarker(g: Group, f: any): Marker
	local hq = g.class == "hq"
	local scale = if hq then 1.5 else 1
	local poleH = if g.ghost then 7 else 13 * scale
	local parts: { BasePart } = {}
	local locals: { CFrame } = {}
	local pole = cylinder(poleH, 0.1, POLE)
	pole.CastShadow = false
	table.insert(parts, pole)
	table.insert(locals, CFrame.new(0, poleH / 2, 0) * CFrame.Angles(0, 0, math.pi / 2))
	local anchor = mk("Part", Vector3.new(0.2, 0.2, 0.2), IVORY) :: Part
	anchor.Transparency = 1
	anchor.CastShadow = false
	table.insert(parts, anchor)
	table.insert(locals, CFrame.new())
	if not g.ghost then
		local s = 2.4 * scale
		Soldiers.flag(function(p: BasePart, cf: CFrame)
			p.CastShadow = false
			table.insert(parts, p)
			table.insert(locals, cf)
		end, g.faction, CFrame.new(0.2, -(s / 2 + 1.6), 0) * CFrame.Angles(0, math.pi, 0), s, s * 0.75)
	end
	for _, p in parts do
		p.Parent = folder
	end

	local pxW = if g.ghost then 56 elseif hq then 230 else 168
	local pxH = if g.ghost then 34 elseif hq then 58 else 44
	local gui = Instance.new("BillboardGui") :: BillboardGui
	gui.Size = UDim2.fromOffset(pxW, pxH + 16)
	gui.SizeOffset = Vector2.new(0, 0.1)
	gui.LightInfluence = 0
	gui.MaxDistance = 4000
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Adornee = anchor
	gui.Parent = anchor
	local plate = Instance.new("Frame") :: Frame
	plate.Size = UDim2.new(1, 0, 0, pxH)
	plate.BackgroundColor3 = if g.ghost then g.colour else IVORY
	plate.BackgroundTransparency = if g.ghost then 0.35 else 0.02
	plate.BorderSizePixel = 0
	plate.Parent = gui
	local stroke = Instance.new("UIStroke") :: UIStroke
	stroke.Color = if hq then GOLD else INK
	stroke.Thickness = if hq then 3 else 2
	stroke.Parent = plate
	local function text(sizeY: number, posY: number, value: string, font: EnumFont, colour: Color3, parent: Instance): TextLabel
		local l = Instance.new("TextLabel") :: TextLabel
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, -10, sizeY, 0)
		l.Position = UDim2.new(0, 5, posY, 0)
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = colour
		l.Text = value
		l.Parent = parent
		return l
	end
	local nameText = Kit.upper(tostring(f.name or ("#" .. g.id)))
	local corpsText = Kit.upper(tostring(f.corps or ""))
	if hq then
		-- "Napoléon — Imperial HQ" -> NAPOLÉON / IMPERIAL HQ
		local a, b = string.match(nameText, "^(.-)%s+[—%-]+%s+(.+)$")
		if a and b then
			nameText, corpsText = a, b
		end
	end
	local nameLabel: TextLabel
	local texts: { TextLabel } = {}
	if g.ghost then
		nameLabel = text(0.9, 0.05, "?", Enum.Font.Garamond, Color3.fromRGB(246, 241, 226), plate)
	else
		nameLabel = text(0.56, 0.06, nameText, Enum.Font.Garamond, INK, plate)
		local corps = text(0.32, 0.62, corpsText, Enum.Font.Garamond, INK, plate)
		corps.TextTransparency = 0.15
		texts = { nameLabel, corps }
	end
	-- status line under the plate (selected/hovered, or the age of a sighting)
	local statusLabel = text(0, 0, "", Enum.Font.GothamBold, IVORY, gui)
	statusLabel.Size = UDim2.new(1, 0, 0, 14)
	statusLabel.Position = UDim2.new(1, 0, 1, -14)
	statusLabel.AnchorPoint = Vector2.new(1, 0)
	statusLabel.TextStrokeTransparency = 0.3
	statusLabel.TextStrokeColor3 = INK
	local bar = Instance.new("Frame") :: Frame
	bar.Size = UDim2.new(1, -10, 0, 4)
	bar.Position = UDim2.new(0, 5, 1, -6)
	bar.BackgroundColor3 = INK
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = plate
	local fill = Instance.new("Frame") :: Frame
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = g.colour
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local stripe = Instance.new("Frame") :: Frame
	stripe.Size = UDim2.new(0, 5, 1, 0)
	stripe.BorderSizePixel = 0
	stripe.Visible = false
	stripe.Parent = plate
	return {
		parts = parts,
		locals = locals,
		plate = anchor,
		gui = gui,
		pxW = pxW,
		pxH = pxH,
		frame = plate,
		texts = texts,
		curW = pxW,
		curH = pxH,
		nameLabel = nameLabel,
		statusLabel = statusLabel,
		bar = bar,
		barFill = fill,
		stripe = stripe,
		height = poleH + 0.5,
		priority = if hq then 4 elseif g.ghost then 0 else 1,
	}
end

local function destroyParts(list: { BasePart })
	for _, p in list do
		p:Destroy()
	end
	table.clear(list)
end

local SLIDE_MAX = 4 -- studs; farther than this a figure pops instead of sliding

-- New slots slide in from the nearest old figure position (casualties close up over ~1 s).
local function carryOver(old: { { x: number, z: number } }, slots: { Slot })
	if #old == 0 then
		return
	end
	local used: { [number]: boolean } = {}
	for _, s in slots do
		local best, bd = 0, SLIDE_MAX * SLIDE_MAX
		for j, o in old do
			if not used[j] then
				local d = (o.x - s.x) ^ 2 + (o.z - s.z) ^ 2
				if d < bd then
					best, bd = j, d
				end
			end
		end
		if best > 0 then
			used[best] = true
			s.tx, s.tz = old[best].x - s.x, old[best].z - s.z
		end
	end
end

local function rebuildBody(g: Group, f: any)
	local old: { { x: number, z: number } } = {}
	if g.lod == "near" then
		for _, s in g.slots do
			table.insert(old, { x = s.x + s.ox + s.tx, z = s.z + s.oz + s.tz })
		end
	end
	destroyParts(g.parts)
	table.clear(g.locals)
	table.clear(g.partSlot)
	table.clear(g.anim)
	table.clear(g.pivot)
	table.clear(g.slots)
	table.clear(g.flagIdx)
	table.clear(g.slotCf)
	if g.lod == "near" and not g.ghost then
		buildNear(g, f)
		carryOver(old, g.slots)
	else
		buildFar(g, f)
	end
	g.dirty = true
end

local function layoutKeyOf(g: Group, f: any): string
	return string.format("%s|%d|%d|%d|%d|%s|%d", f.shape, math.round(f.width), math.round(f.depth), visualCount(f), thinK, if g.lod == "near" then g.tier else "far", Settings.get().quality)
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
		tier = "mid",
		dist = math.huge,
		parts = {},
		locals = {},
		slots = {},
		partSlot = {},
		anim = {},
		pivot = {},
		flagIdx = {},
		slotCf = {},
		look = nil,
		nLine = 0,
		lastStrength = f.strength or 0,
		lossAcc = 0,
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

-- The budget is spent in parts, not figures: MaxFigures × the ~12 parts a plain figure took
-- before the uniform pass, so the old ceiling holds whatever the detail tier builds.
local PARTS_PER_FIGURE = 12
-- Parts one figure costs per class and detail tier (measured from the Soldiers builders).
local FIGURE_COST: { [string]: { near: number, mid: number } } = {
	infantry = { near = 34, mid = 9 },
	cavalry = { near = 52, mid = 13 },
	hq = { near = 48, mid = 12 },
	artillery = { near = 140, mid = 30 },
}
local SPECIALS_COST = { near = 155, mid = 60 } -- officer, colour and two drummers per battalion

local function budget(): number
	local q = Settings.get().quality
	local figs = if q >= 3 then Config.Visual.MaxFiguresHigh elseif q == 2 then (Config.Visual.MaxFiguresHigh + Config.Visual.MaxFiguresLow) // 2 else Config.Visual.MaxFiguresLow
	return figs * PARTS_PER_FIGURE
end

local function groupCost(g: Group, f: any, near: boolean): number
	local c = FIGURE_COST[g.class] or FIGURE_COST.infantry
	return visualCount(f) * (if near then c.near else c.mid) + (if g.class == "infantry" then (if near then SPECIALS_COST.near else SPECIALS_COST.mid) else 0)
end

-- Spend the budget where the camera is: near-LOD blocks sorted by camera distance get the
-- near tier while their cost fits (blocks already near keep it a little longer), the rest
-- the mid tier; `nearBand` becomes the distance of the first block that did not fit. Returns
-- the parts the whole near LOD will cost at those tiers.
local function allocateTiers(list: { { g: Group, f: any } }): number
	table.sort(list, function(a: { g: Group, f: any }, b: { g: Group, f: any })
		return a.g.dist < b.g.dist
	end)
	local b = budget()
	local detail = Settings.get().quality >= 2
	local spent = 0
	nearBand = NEAR_TIER_D
	for _, e in list do
		local g = e.g
		local nearCost = groupCost(g, e.f, true)
		local cap = if g.tier == "near" then 0.9 else 0.75
		if detail and g.dist <= nearBand and spent + nearCost <= b * cap then
			spent += nearCost
		else
			nearBand = math.min(nearBand, g.dist)
			spent += groupCost(g, e.f, false)
		end
	end
	return spent
end

local function onSnapshot()
	if not folder then
		return
	end
	local now = os.clock()
	local seen: { [number]: boolean } = {}
	local nearList: { { g: Group, f: any } } = {}
	for id, f in BattleState.formations do
		seen[id] = true
		local near = groups[id]
		if near and near.lod == "near" then
			table.insert(nearList, { g = near, f = f }) -- the budget only spends parts on near-LOD blocks
		end
		local existing: Group? = groups[id]
		if existing and existing.ghost then
			destroyGroup(existing)
			groups[id] = nil
			existing = nil
		end
		local g: Group
		if existing then
			g = existing
			local str = f.strength or 0
			if str < g.lastStrength and g.lod == "near" and (g.class == "infantry" or g.class == "cavalry") then
				local per = Config.Visual.SoldiersPerFigure
				g.lossAcc += g.lastStrength - str
				local n = 0
				while g.lossAcc >= per and n < 4 do
					spawnBody(g, now)
					g.lossAcc -= per
					n += 1
				end
				g.lossAcc = math.min(g.lossAcc, per)
			end
			g.lastStrength = str
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
	local newK = math.max(1, math.ceil(allocateTiers(nearList) / budget()))
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
	local cf = groundFrame(x, z, 0.4, heading, w, d)
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

-- Plates scale with distance between a floor and their design size (so they never cover the
-- field at the deployment zoom). Far away, only HQs, the selection and the hovered unit keep a
-- full plate; the rest shrink to a small blank banner.
local PLATE_STUDS = 24 -- world width a plate represents before clamping
local PLATE_MIN_W = 84
local BANNER_W, BANNER_H = 34, 10
local FULL_PLATE_DEPTH = 560 -- camera depth beyond which ordinary plates become banners

local function sizePlate(m: Marker, w: number, h: number, banner: boolean)
	if math.abs(m.curW - w) < 2 and math.abs(m.curH - h) < 1 then
		return
	end
	m.curW, m.curH = w, h
	m.gui.Size = UDim2.fromOffset(w, h + 16)
	m.frame.Size = UDim2.new(1, 0, 0, h)
	for _, l in m.texts do
		l.Visible = not banner
	end
end

local function deconflictLabels(cam: Camera)
	local list: { { g: Group, x: number, y: number, w: number, h: number, pri: number } } = {}
	local hovered = Selection.hovered()
	local pxPerStudAt1 = cam.ViewportSize.Y / (2 * math.tan(math.rad(cam.FieldOfView) / 2))
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
			local w, h
			local banner = not g.ghost and pri < 2 and sp.Z > FULL_PLATE_DEPTH
			if banner then
				w, h = BANNER_W, BANNER_H
			else
				local scale = if m.priority >= 4 then 1.3 else 1
				w = math.clamp(PLATE_STUDS * scale * pxPerStudAt1 / sp.Z, math.min(PLATE_MIN_W, m.pxW), m.pxW)
				h = w * m.pxH / m.pxW
			end
			sizePlate(m, w, h, banner)
			table.insert(list, { g = g, x = sp.X, y = sp.Y - h / 2, w = w, h = h, pri = pri })
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

-- Per-figure life: spring back to the slot, damped per-figure noise (stagger while marching,
-- sway at rest), separation from rank neighbours only, decaying slide-in. Returns true if moved.
-- Colour sway (radians about the pole): streams a little off the pole and swings with the
-- breeze, harder on the march. Each battalion has its own phase.
local function flagSway(g: Group, now: number, moving: boolean): number
	local k = if moving then 1.5 else 1
	return 0.35 + k * (0.28 * math.sin(now * 1.3 + g.id * 1.7) + 0.1 * math.sin(now * 3.1 + g.id * 0.9))
end

local FLOCK_K, FLOCK_C, FLOCK_SEP = 7, 3.2, 14
local function stepFlock(g: Group, dt: number, moving: boolean, bound: number, now: number): boolean
	local slots = g.slots
	local amp = if moving then 3.0 else 0.5
	local decay = math.exp(-3.5 * dt)
	local any = false
	for _, s in slots do
		local ax = -FLOCK_K * s.ox - FLOCK_C * s.vx + amp * math.sin(now * 1.7 + s.phase * 3.1)
		local az = -FLOCK_K * s.oz - FLOCK_C * s.vz + amp * math.sin(now * 1.3 + s.phase * 5.3)
		for _, n in { s.left, s.right } do
			if n > 0 then
				local o = slots[n]
				local nominal = math.abs(s.z - o.z)
				local d = (s.z + s.oz) - (o.z + o.oz)
				local gap = math.abs(d)
				if gap < nominal * 0.8 then
					az += (if d >= 0 then 1 else -1) * (nominal * 0.8 - gap) * FLOCK_SEP
				end
			end
		end
		s.vx += ax * dt
		s.vz += az * dt
		s.ox += s.vx * dt
		s.oz += s.vz * dt
		local m = math.sqrt(s.ox * s.ox + s.oz * s.oz)
		if m > bound then
			s.ox, s.oz = s.ox / m * bound, s.oz / m * bound
			s.vx *= 0.5
			s.vz *= 0.5
		end
		if s.tx ~= 0 or s.tz ~= 0 then
			s.tx *= decay
			s.tz *= decay
			if math.abs(s.tx) + math.abs(s.tz) < 0.02 then
				s.tx, s.tz = 0, 0
			end
		end
		any = any or m > 0.01 or s.tx ~= 0 or s.tz ~= 0
	end
	return any
end

-- Debug: with the workspace attribute EoEClipCheck set (command bar:
-- workspace:SetAttribute("EoEClipCheck", true)), every second walk every live figure part and
-- count those whose lowest corner is below the rendered ground.
local clipClock = 0
local function clipCheck(dt: number)
	clipClock += dt
	if clipClock < 1 then
		return
	end
	clipClock = 0
	if not workspace:GetAttribute("EoEClipCheck") then
		return
	end
	local below, total = 0, 0
	local function check(p: BasePart)
		total += 1
		local cf, sz = p.CFrame, p.Size
		local half = math.abs(cf.XVector.Y) * sz.X / 2 + math.abs(cf.YVector.Y) * sz.Y / 2 + math.abs(cf.ZVector.Y) * sz.Z / 2
		if cf.Position.Y - half < groundY(cf.Position.X, cf.Position.Z) - 0.02 then
			below += 1
		end
	end
	for _, g in groups do
		if g.lod == "near" then
			for _, p in g.parts do
				check(p)
			end
		end
	end
	for _, b in bodies do
		for _, p in b.parts do
			check(p)
		end
	end
	local rays, ms = Ground.stats()
	print(string.format("[EoE clip] %d parts below ground of %d checked; ground rays last frame %d in %.2f ms", below, total, rays, ms))
end

function Figures.update(dt: number)
	if not folder then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	Ground.beginFrame()
	clipCheck(dt)
	local camPos = cam.CFrame.Position
	local now = os.clock()
	local flockOn = Settings.get().quality >= 2
	local moveParts: { BasePart } = {}
	local moveCfs: { CFrame } = {}
	local hovered = Selection.hovered()
	local coop = BattleState.coop()
	local deploying = BattleState.state == "deployment"
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
			g.dist = dist
			local wantLod = if g.ghost then "far" elseif g.lod == "near" then (if dist > farD * 1.1 then "far" else "near") else (if dist < farD then "near" else "far")
			if wantLod ~= g.lod then
				g.lod = wantLod
			end
			-- detail tier with the same hysteresis: the fine parts are only built where they are
			-- more than a pixel (within the band the budget allows)
			g.tier = if g.tier == "near" then (if dist > nearBand * 1.1 then "mid" else "near") else (if dist < nearBand then "near" else "mid")
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
			-- flocking layer: near LOD only, infantry/cavalry, quality 2+
			if flockOn and not g.ghost and g.lod == "near" and (g.class == "infantry" or g.class == "cavalry") then
				local bound = if f.shape == "line" and not animating then 0.6 else 1.2
				if stepFlock(g, math.min(dt, 0.05), animating and state ~= "routing", bound, now) then
					g.dirty = true
				end
			end
			if g.dirty then
				g.dirty = false
				local baseY = groundY(g.rx, g.rz)
				local cf = frame(g.rx, baseY, g.rz, g.rh) -- figures stand upright; slots sample their own ground
				local tilted = groundFrame(g.rx, g.rz, 0, g.rh, f.width, f.depth) -- blocks and rings follow the slope
				local routing = state == "routing"
				local charging = state == "charging"
				-- muskets come down for volleys and bayonet charges
				local armed = state == "firing" or (charging and g.class == "infantry")
				local pitched = g.class == "cavalry" or g.class == "artillery" or g.class == "hq"
				local foot = FOOT[g.class] or FOOT.infantry
				local amp = if routing or charging then 0.75 else 0.45
				local slotCf: { CFrame } = {}
				local swing: { number } = {}
				for si, s in g.slots do
					local sx, sz = s.x + s.ox + s.tx, s.z + s.oz + s.tz
					if routing then
						-- running back with a ragged spread
						sx += s.sx * 2.5
						sz += s.sz * 2.5
					end
					local wp = cf * Vector3.new(sx, 0, sz)
					local y = groundY(wp.X, wp.Z)
					local h = g.rh + (s.face or 0)
					if routing then
						h += math.pi + (s.phase - math.pi) * 0.35
					end
					local pitch = 0
					if pitched then
						-- horses and guns pitch with the slope under them; men stay upright
						local fx, fz = math.cos(h), math.sin(h)
						pitch = (groundY(wp.X + fx, wp.Z + fz) - groundY(wp.X - fx, wp.Z - fz)) / 2
					end
					-- every corner of the footprint clears the surface
					y += Ground.liftAt(wp.X, wp.Z, y, h, foot[1], foot[2], if pitched then pitch else nil)
					local sw = 0
					if animating then
						local ph = g.phase + s.phase
						sw = math.sin(ph) * amp
						y += math.abs(math.cos(ph)) * 0.12
					end
					swing[si] = sw
					local scf = frame(wp.X, y, wp.Z, h)
					if pitched then
						scf *= CFrame.Angles(0, 0, math.atan(pitch))
					end
					if charging then
						scf *= CFrame.Angles(0, 0, if g.class == "cavalry" then -0.1 else -0.22) -- lean into the charge
					end
					slotCf[si] = scf
				end
				g.slotCf = slotCf
				local sway = flagSway(g, now, animating)
				local anims, pivots, slots = g.anim, g.pivot, g.partSlot
				for i, p in g.parts do
					local slot = slots[i]
					local lc = g.locals[i]
					local base = tilted
					if slot > 0 then
						base = slotCf[slot]
						local a = anims[i]
						if a ~= 0 then
							lc = Soldiers.partCFrame(a, lc, pivots[i], if a == 6 then sway else swing[slot], armed and not routing)
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
					placeRing(moveParts, moveCfs, g.ring, tilted, f.width, f.depth)
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
				-- colours keep swaying while the battalion stands still
				if g.lod == "near" and #g.flagIdx > 0 then
					local sway = flagSway(g, now, false)
					for _, i in g.flagIdx do
						local scf = g.slotCf[g.partSlot[i]]
						if scf then
							table.insert(moveParts, g.parts[i])
							table.insert(moveCfs, scf * Soldiers.partCFrame(6, g.locals[i], 0, sway, false))
						end
					end
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
				-- co-op: allies' wings carry their officer's colour (every wing while deploying)
				local owner = if coop and g.faction == BattleState.viewerFaction then BattleState.player(BattleState.controllerOf(id)) else nil
				local ally = owner ~= nil and not BattleState.isMine(id)
				local striped = owner ~= nil and (deploying or ally)
				m.stripe.Visible = striped
				if striped then
					m.stripe.BackgroundColor3 = Kit.slotColour(owner.slot)
				end
				m.statusLabel.Text = if not showStatus then "" elseif ally then tostring(owner.name) .. " · " .. statusText(f) else statusText(f)
				m.bar.Visible = showStatus
				if showStatus then
					m.barFill.Size = UDim2.fromScale(math.clamp(f.strength / math.max(f.startStrength, 1), 0, 1), 1)
				end
			end
			updateOrders(g, f, selected)
		end
	end
	placeBodies(now, moveParts, moveCfs)
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
	table.clear(bodies) -- their parts go with the folder
	Ground.clear()
	destroyParts(previews)
	table.clear(prevSelected)
	pendingKey = ""
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return Figures
