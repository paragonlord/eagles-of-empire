--!strict
-- Client-side props. The structure (trees, houses, bridges, walls, hedges, ground) is built
-- by the server from WorldGen and replicates under workspace.EoEWorld; this module adds the
-- detail tier for this client (hearth smoke, valley fog) from the same WorldGen, plus ground
-- labels, objective markers and the deployment zone outline. Quality changes hide or show
-- the "<group>Q2" folders locally; nothing is rebuilt.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local UserInputService = game:GetService("UserInputService") :: UserInputService
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Vec = require(Shared.Vec)
local WorldGen = require(Shared.WorldGen)
local WorldBuild = require(Shared.WorldBuild)
local Factions = require(script.Parent.Parent.Factions)
local WorldLighting = require(script.Parent.Lighting)

local Props = {}

local P = Config.Visual.Palette
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local folder: Folder? = nil
local zoneFolder: Folder? = nil
local labelParts: { { part: Part, size: number, len: number, text: TextLabel, float: TextLabel?, alpha: number } } = {}
-- Settings.placeNames: "ground" plates (default), "floating" billboards, "hover" (billboards
-- near the cursor only) or "off".
local labelMode = "ground"
local objectiveMarks: { [string]: { ring: { Part }, flag: Part } } = {}
local generation = 0
local currentMap: any = nil

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

-- Yaw so that local +X points along a sim heading (Roblox rotates +X toward -Z for +angle).
local function yaw(x: number, y: number, z: number, heading: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, -heading, 0)
end

local function groundY(x: number, z: number): number
	return Grid.heightAt(currentMap.grid, x, z)
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
	gui.Enabled = labelMode == "ground"
	table.insert(labelParts, { part = p, size = size, len = len, text = text, float = nil, alpha = 1 })
end

-- The floating form of a label: a small upright billboard over the place, built on demand.
local function floatLabel(l: { part: Part, size: number, len: number, text: TextLabel, float: TextLabel?, alpha: number }): TextLabel
	if l.float then
		return l.float
	end
	local bb = Instance.new("BillboardGui") :: BillboardGui
	bb.Name = "Float"
	bb.Adornee = l.part
	bb.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	bb.Size = UDim2.fromOffset(160, 22)
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false -- Studio: AlwaysOnTop billboards drew nothing at all (fog grade, Future)
	bb.Parent = l.part
	local t = l.text:Clone() :: TextLabel
	t.TextTransparency = 1
	t.TextStrokeTransparency = 1
	t.Parent = bb
	l.float = t
	return t
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

-- Builds this client's detail tier, labels and objective markers for a map. Yields. Returns
-- false when superseded by clear()/rebuild.
function Props.build(map: any, quality: number, onProgress: ((fraction: number) -> ())?): boolean
	Props.clear()
	generation += 1
	local myGen = generation
	currentMap = map
	local f = Instance.new("Folder") :: Folder
	f.Name = "EoEProps"
	f.Parent = workspace
	folder = f
	WorldLighting.setMap(map.id)
	local function alive(): boolean
		return generation == myGen
	end
	local terrain = WorldGen.terrain(map)
	local specs = WorldGen.props(map, terrain, { structure = false, yield = function()
		task.wait()
	end })
	if not alive() then
		return false
	end
	if not WorldBuild.spawn(specs, f, alive, onProgress) then
		return false
	end
	local fog = f:FindFirstChild("GroundFogQ2")
	if fog then
		-- each invisible anchor box gets an emitter of slow soft mist puffs drifting along the
		-- valley; Lighting sets the rate (on under the fog grade, fading to 0 as it lifts)
		for _, p in fog:GetDescendants() do
			if p:IsA("BasePart") then
				local pe = Instance.new("ParticleEmitter") :: ParticleEmitter
				pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
				pe.Color = ColorSequence.new(Color3.fromRGB(226, 224, 218))
				pe.LightEmission = 0
				pe.LightInfluence = 1
				pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 24) })
				-- 0.62/0.75: at 0.86/0.92 the puffs vanished into the fog grade (Studio, round 23)
				pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.62), NumberSequenceKeypoint.new(0.7, 0.75), NumberSequenceKeypoint.new(1, 1) })
				pe.Lifetime = NumberRange.new(12, 20)
				pe.Speed = NumberRange.new(0.3, 0.6)
				pe.EmissionDirection = Enum.NormalId.Right -- along the box's long side: the valley
				pe.SpreadAngle = Vector2.new(20, 6)
				pe.Rotation = NumberRange.new(0, 360)
				pe.RotSpeed = NumberRange.new(-2, 2)
				pe.Drag = 0
				pe.Rate = 0
				pe.Enabled = true
				pe.Parent = p
			end
		end
		WorldLighting.setGroundFog(fog :: Folder)
	end
	local villageNames: { [string]: boolean } = {}
	for _, v in map.villages do
		villageNames[v.name] = true
	end
	for _, l in map.labels do
		buildLabel(f, l, villageNames[l.text] == true)
	end
	for _, o in map.objectives do
		buildObjective(f, o)
	end
	Props.setQuality(quality)
	if onProgress then
		onProgress(1)
	end
	return alive()
end

-- Shows the parts for `quality` and hides the rest locally: every "<group>Q2" folder of the
-- server's world and of this client's detail tier is quality 2 and up.
function Props.setQuality(quality: number)
	local hide = quality < 2
	for _, rootName in { "EoEWorld", "EoEProps" } do
		local root = workspace:FindFirstChild(rootName)
		if root then
			for _, g in root:GetChildren() do
				if string.sub(g.Name, -2) == "Q2" then
					for _, p in g:GetDescendants() do
						if p:IsA("BasePart") then
							(p :: BasePart).LocalTransparencyModifier = if hide then 1 else 0
						end
					end
				end
			end
		end
	end
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

function Props.setLabelMode(mode: string)
	labelMode = mode
	for _, l in labelParts do
		local gui = l.part:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui?
		if gui then
			gui.Enabled = mode == "ground"
		end
		if l.float then
			l.float.TextTransparency = 1
			l.float.TextStrokeTransparency = 1
		end
	end
end

-- Where the cursor's ray meets the plane at height `y`, or nil when it points at the sky.
local function cursorOnPlane(y: number): (number?, number?)
	local cam = workspace.CurrentCamera
	if not cam then
		return nil, nil
	end
	local m = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	if ray.Direction.Y >= -1e-3 then
		return nil, nil
	end
	local t = (y - ray.Origin.Y) / ray.Direction.Y
	return ray.Origin.X + ray.Direction.X * t, ray.Origin.Z + ray.Direction.Z * t
end

local HOVER_RADIUS = 70 -- studs around the cursor within which hover names show
local NEAR_FADE = 160 -- camera this close to a floating name: it fades so as not to shout

-- Ground labels grow with camera height so they stay readable from any zoom. Floating and hover
-- names are billboards that scale with height and fade in and out over a few frames.
local lastLabelK = -1
function Props.updateLabels(cameraHeight: number)
	local k = math.clamp(cameraHeight / 420, 0.7, LABEL_MAX_K)
	if labelMode == "ground" or labelMode == "off" then
		if math.abs(k - lastLabelK) < 0.05 then
			return
		end
		lastLabelK = k
		for _, l in labelParts do
			l.part.Size = Vector3.new(l.size * k, 0.2, l.len * k)
		end
		return
	end
	lastLabelK = -1
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local cx, cz = nil, nil
	if labelMode == "hover" and #labelParts > 0 then
		cx, cz = cursorOnPlane(labelParts[1].part.Position.Y)
	end
	for _, l in labelParts do
		local t = floatLabel(l)
		local bb = t.Parent :: BillboardGui
		local scale = math.clamp(cameraHeight / 420, 0.8, 1.8) * (l.size / 20)
		bb.Size = UDim2.fromOffset(math.floor(l.len / l.size * 22 * scale), math.floor(22 * scale))
		-- higher off the ground as the camera climbs so ridges and unit plates do not clip the name
		bb.StudsOffsetWorldSpace = Vector3.new(0, 6 + cameraHeight * 0.04, 0)
		local pos = l.part.Position
		local target = 1
		if labelMode == "floating" then
			local near = (camPos - pos).Magnitude
			target = if near < NEAR_FADE then 0.8 else 0.15
		elseif cx and cz then
			local dx, dz = pos.X - cx, pos.Z - cz
			target = if dx * dx + dz * dz < HOVER_RADIUS * HOVER_RADIUS then 0.1 else 1
		end
		l.alpha += (target - l.alpha) * 0.15
		t.TextTransparency = l.alpha
		t.TextStrokeTransparency = 0.5 + 0.5 * l.alpha
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
