--!strict
-- Minimap: terrain classes painted as run-length Frames (2 px per 16 studs), formation dots,
-- objectives, camera frustum, click to pan. North (+z) is up.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Kit = require(script.Parent.Kit)
local BattleState = require(script.Parent.Parent.BattleState)
local Camera = require(script.Parent.Parent.Camera)

local Minimap = {}

local P = Config.Visual.Palette
local IDS = Config.TerrainIds
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local CLASS_COLOUR: { [number]: Color3 } = {
	[IDS.open] = rgb(P.TerrainGrass),
	[IDS.road] = rgb(P.Road),
	[IDS.woods] = rgb(P.TreeCrown),
	[IDS.village] = rgb(P.Roof),
	[IDS.water] = rgb(P.Water),
	[IDS.ford] = rgb(P.Water):Lerp(rgb(P.Road), 0.4),
	[IDS.bridge] = rgb(P.Road),
	[IDS.steep] = rgb(P.TerrainSlope),
	[IDS.cliff] = Color3.fromRGB(96, 84, 70),
}

local SAMPLE = 16 -- studs per painted cell
local PX = 2 -- pixels per painted cell

local root: Frame? = nil
local terrainLayer: Frame? = nil
local dotLayer: Frame? = nil
local dots: { Frame } = {}
local objectiveDots: { [string]: Frame } = {}
local frustum: { Frame } = {}
local connection: RBXScriptConnection? = nil
local mapW, mapD = 1600, 1200

local function toPixel(x: number, z: number): (number, number)
	local w = (root :: Frame).AbsoluteSize.X
	local h = (root :: Frame).AbsoluteSize.Y
	return x / mapW * w, (1 - z / mapD) * h
end

local function dot(parent: Instance, size: number): Frame
	local d = Instance.new("Frame") :: Frame
	d.Size = UDim2.fromOffset(size, size)
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.BorderSizePixel = 0
	d.Parent = parent
	return d
end

function Minimap.create(parent: Instance, size: UDim2, position: UDim2, anchor: Vector2)
	Minimap.destroy()
	local r = Instance.new("TextButton") :: TextButton
	r.Size = size
	r.Position = position
	r.AnchorPoint = anchor
	r.BackgroundColor3 = Kit.INK
	r.BorderSizePixel = 0
	r.Text = ""
	r.AutoButtonColor = false
	r.ClipsDescendants = true
	r.Active = true
	r.Parent = parent
	local stroke = Instance.new("UIStroke") :: UIStroke
	stroke.Color = Kit.CREAM
	stroke.Thickness = 1
	stroke.Parent = r
	local tl = Instance.new("Frame") :: Frame
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Parent = r
	local dl = Instance.new("Frame") :: Frame
	dl.Size = UDim2.fromScale(1, 1)
	dl.BackgroundTransparency = 1
	dl.ZIndex = 3
	dl.Parent = r
	for i = 1, 4 do
		local l = Instance.new("Frame") :: Frame
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.BackgroundColor3 = Kit.CREAM
		l.BackgroundTransparency = 0.2
		l.BorderSizePixel = 0
		l.ZIndex = 4
		l.Parent = dl
		frustum[i] = l
	end
	connection = r.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local lx = (input.Position.X - r.AbsolutePosition.X) / math.max(r.AbsoluteSize.X, 1)
			local ly = (input.Position.Y - r.AbsolutePosition.Y) / math.max(r.AbsoluteSize.Y, 1)
			Camera.focusOn(lx * mapW, (1 - ly) * mapD)
		end
	end)
	root = r :: any
	terrainLayer = tl
	dotLayer = dl
end

-- Paints terrain classes once per map. Yields every few rows.
function Minimap.paint(map: any)
	local tl = terrainLayer
	if not tl then
		return
	end
	tl:ClearAllChildren()
	table.clear(objectiveDots)
	mapW, mapD = map.width, map.depth
	local g = map.grid
	local cols = math.floor(map.width / SAMPLE)
	local rows = math.floor(map.depth / SAMPLE)
	local w, h = cols * PX, rows * PX
	for r = 0, rows - 1 do
		local z = (rows - 1 - r + 0.5) * SAMPLE -- top row is north
		local runStart = 0
		local runCls = Grid.classAt(g, 0.5 * SAMPLE, z)
		local function flush(endCol: number)
			local f = Instance.new("Frame") :: Frame
			f.BorderSizePixel = 0
			f.BackgroundColor3 = CLASS_COLOUR[runCls] or Kit.MUTED
			f.Position = UDim2.new(runStart * PX / w, 0, r * PX / h, 0)
			f.Size = UDim2.new((endCol - runStart) * PX / w, 0, PX / h, 0)
			f.Parent = tl
		end
		for c = 1, cols - 1 do
			local cls = Grid.classAt(g, (c + 0.5) * SAMPLE, z)
			if cls ~= runCls then
				flush(c)
				runStart = c
				runCls = cls
			end
		end
		flush(cols)
		if r % 12 == 11 then
			task.wait()
		end
	end
	for _, o in map.objectives do
		local d = dot(dotLayer :: Frame, 7)
		d.BackgroundColor3 = Kit.CREAM
		local px, py = toPixel(o.pos.x, o.pos.z)
		d.Position = UDim2.fromOffset(px, py)
		d.ZIndex = 5
		local c = Instance.new("UICorner") :: UICorner
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = d
		objectiveDots[o.id] = d
	end
end

local function line(f: Frame, x0: number, y0: number, x1: number, y1: number)
	local dx, dy = x1 - x0, y1 - y0
	local len = math.sqrt(dx * dx + dy * dy)
	f.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
	f.Size = UDim2.fromOffset(len, 1)
	f.Rotation = math.deg(math.atan2(dy, dx))
end

-- Ground points under the four viewport corners, projected to the focus plane.
local function frustumCorners(): { { number } }?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	local vp = cam.ViewportSize
	local fx, fz = Camera.getFocus()
	local planeY = Camera.groundHeight(fx, fz)
	local out = {}
	for _, c in { { 0, 0 }, { vp.X, 0 }, { vp.X, vp.Y }, { 0, vp.Y } } do
		local ray = cam:ViewportPointToRay(c[1], c[2])
		local dir = ray.Direction
		local t
		if dir.Y < -0.02 then
			t = (planeY - ray.Origin.Y) / dir.Y
		else
			t = 3000 -- horizon: clamp far away
		end
		t = math.min(t, 3000)
		local p = ray.Origin + dir * t
		table.insert(out, { p.X, p.Z })
	end
	return out
end

function Minimap.update()
	local r = root
	local dl = dotLayer
	if not r or not dl then
		return
	end
	-- formation dots (pooled)
	local i = 0
	local function place(x: number, z: number, colour: Color3, alpha: number, size: number)
		i += 1
		local d = dots[i]
		if not d then
			d = dot(dl, size)
			dots[i] = d
		end
		d.Size = UDim2.fromOffset(size, size)
		d.BackgroundColor3 = colour
		d.BackgroundTransparency = alpha
		local px, py = toPixel(x, z)
		d.Position = UDim2.fromOffset(px, py)
		d.Visible = true
	end
	for _, f in BattleState.formations do
		place(f.x, f.z, Kit.factionColour(f.faction), 0, if f.class == "hq" then 6 else 4)
	end
	for _, lk in BattleState.lastKnown do
		place(lk.x, lk.z, Kit.factionColour(lk.faction):Lerp(Kit.MUTED, 0.6), 0.3, 4)
	end
	-- co-op pings: a pulsing blip in the sender's slot colour for 6 s
	local now = os.clock()
	for _, pg in BattleState.pings do
		local age = now - pg.t0
		if age < 6 then
			place(pg.x, pg.z, Kit.slotColour(pg.slot), age / 8, 7 + 3 * math.sin(age * 8))
		end
	end
	for j = i + 1, #dots do
		dots[j].Visible = false
	end
	for _, o in BattleState.objectives do
		local d = objectiveDots[o.id]
		if d then
			d.BackgroundColor3 = if o.contested then Kit.HOSTILE else Kit.factionColour(o.owner)
			if not o.owner and not o.contested then
				d.BackgroundColor3 = Kit.CREAM
			end
		end
	end
	local corners = frustumCorners()
	if corners then
		for k = 1, 4 do
			local a = corners[k]
			local b = corners[k % 4 + 1]
			local ax, ay = toPixel(a[1], a[2])
			local bx, by = toPixel(b[1], b[2])
			line(frustum[k], ax, ay, bx, by)
		end
	end
end

function Minimap.destroy()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if root then
		root:Destroy()
		root = nil
	end
	terrainLayer = nil
	dotLayer = nil
	table.clear(dots)
	table.clear(objectiveDots)
	table.clear(frustum)
end

return Minimap
