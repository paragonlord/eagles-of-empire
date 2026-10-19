--!strict
-- Mouse and keyboard for the battlefield. Picking is done against formation footprints from
-- BattleState (never against cosmetic parts); the ground point comes from a terrain raycast.

local UserInputService = game:GetService("UserInputService") :: UserInputService
local RunService = game:GetService("RunService") :: RunService
local Players = game:GetService("Players") :: Players
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Vec = require(Shared.Vec)
local MapGen = require(Shared.MapGen)
local BattleState = require(script.Parent.BattleState)
local Selection = require(script.Parent.Selection)
local Camera = require(script.Parent.Camera)
local Net = require(script.Parent.Net)
local Figures = require(script.Parent.Figures)
local Signal = require(script.Parent.Signal)
local Terrain = require(script.Parent.World.Terrain)
local Settings = require(script.Parent.Settings)
local Touch = require(script.Parent.Touch)
local OrderWheel = require(script.Parent.UI.OrderWheel)

local Input = {}

Input.action = Signal.new() -- (name: string) for escape, dev, help
Input.orderSent = Signal.new() -- (kind) so the HUD can flash
Input.wheelPick = Signal.new() -- (key) from the touch order wheel; the HUD runs the command

type Vec = { x: number, z: number }

local DRAG_PX = 6
local PICK_PAD = 4

local mode = "off" -- off | battle | deploy
local connections: { RBXScriptConnection } = {}
local gui: ScreenGui? = nil
local box: Frame? = nil

local left: { down: boolean, sx: number, sy: number, ground: Vec?, dragging: boolean, formation: number? } = { down = false, sx = 0, sy = 0, ground = nil, dragging = false, formation = nil }
local right: { down: boolean, sx: number, sy: number, ground: Vec?, dragging: boolean, formation: number? } = { down = false, sx = 0, sy = 0, ground = nil, dragging = false, formation = nil }
local deployHeading: { [number]: number } = {}
local middleAt: Vector2? = nil -- middle-button press point: a click (not a rotate drag) pings
local armed: string? = nil -- "Charge": the next right-click charges instead of moving (touch: also Move / AttackMove)

-- Touch (docs/mobile-contract.md): one finger on the field at a time; a second cancels it.
type Finger = { obj: InputObject, t0: number, sx: number, sy: number, lx: number, ly: number, ground: Vec?, phase: string, formation: number?, kind: string?, action: string? }
local finger: Finger? = nil
local down: { [InputObject]: boolean } = {} -- touches that began on the field

-- ------------------------------------------------------------------ picking

local function mousePos(): Vector2
	return UserInputService:GetMouseLocation()
end

local function groundUnderMouse(): Vec?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	local m = mousePos()
	local ray = cam:ScreenPointToRay(m.X, m.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local list: { Instance } = { workspace.Terrain }
	local plane = Terrain.pickPlane()
	if plane then
		table.insert(list, plane)
	end
	params.FilterDescendantsInstances = list
	params.IgnoreWater = false
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 8000, params)
	if hit then
		return { x = hit.Position.X, z = hit.Position.Z }
	end
	return nil
end

-- Nearest formation whose footprint (padded) contains the ground point. Own first, then
-- visible enemies, then last-known ghosts.
local function pickAt(p: Vec): (number?, string?)
	local bestId: number? = nil
	local bestKind: string? = nil
	local bestScore = math.huge
	local function test(f: any, kind: string)
		local fx, fz = math.cos(f.heading), math.sin(f.heading)
		local dx, dz = p.x - f.x, p.z - f.z
		local along = dx * fx + dz * fz
		local across = -dx * fz + dz * fx
		local hd, hw = f.depth / 2 + PICK_PAD, f.width / 2 + PICK_PAD
		if math.abs(along) <= hd and math.abs(across) <= hw then
			local score = (along / hd) ^ 2 + (across / hw) ^ 2
			if score < bestScore then
				bestScore = score
				bestId = f.id
				bestKind = kind
			end
		end
	end
	for _, f in BattleState.formations do
		test(f, if f.faction ~= BattleState.viewerFaction then "enemy" elseif BattleState.canCommand(f.id) then "own" else "ally")
	end
	if bestId == nil then
		for _, lk in BattleState.lastKnown do
			test(lk, "ghost")
		end
	end
	return bestId, bestKind
end

local function textBoxFocused(): boolean
	return (UserInputService:GetFocusedTextBox() :: TextBox?) ~= nil
end

local function clampToMap(p: Vec): Vec
	local m = BattleState.map
	local w = if m then m.width else Config.Map.Width
	local d = if m then m.depth else Config.Map.Depth
	return { x = math.clamp(p.x, 1, w - 1), z = math.clamp(p.z, 1, d - 1) }
end

local function selectedFormations(): { any }
	local out = {}
	for _, id in Selection.ids() do
		local f = BattleState.formations[id]
		if f then
			table.insert(out, f)
		end
	end
	return out
end

-- ------------------------------------------------------------------ orders

local function sendOrder(kind: string, ids: { number }, data: { [string]: any }): boolean
	if kind == "Charge" then
		armed = nil
		Input.action:Fire("disarm")
	end
	local requestId, reason = Net.send(kind, ids, data)
	if requestId then
		BattleState.addPending({
			requestId = requestId,
			kind = kind,
			ids = ids,
			pos = data.pos,
			heading = data.heading,
			frontage = data.frontage,
			issuedAt = os.clock(),
		})
		Input.orderSent:Fire(kind)
		return true
	end
	BattleState.orderRejected:Fire(reason or "Order refused")
	return false
end

-- Line placement along a right-drag: formations spread along the drag, facing its left side.
local function linePlacement(a: Vec, b: Vec): { { f: any, x: number, z: number, heading: number, frontage: number } }
	local forms = selectedFormations()
	if #forms == 0 then
		return {}
	end
	local d = Vec.sub(b, a)
	local len = Vec.len(d)
	local dir = Vec.normalize(d)
	local heading = Vec.heading({ x = dir.z, z = -dir.x }) -- right(f) == dir
	-- keep current left-to-right ordering along the drag so lines do not cross
	table.sort(forms, function(p, q)
		return Vec.dot({ x = p.x, z = p.z }, dir) < Vec.dot({ x = q.x, z = q.z }, dir)
	end)
	local out = {}
	local n = #forms
	for i, f in forms do
		local c = Vec.add(a, Vec.scale(dir, len * (i - 0.5) / n))
		table.insert(out, { f = f, x = c.x, z = c.z, heading = heading, frontage = len / n })
	end
	return out
end

local function previewLine(a: Vec, b: Vec)
	local list = {}
	for _, e in linePlacement(a, b) do
		table.insert(list, { x = e.x, z = e.z, heading = e.heading, width = math.max(e.frontage, 4), depth = e.f.depth })
	end
	Figures.setPreview(list)
end

-- Formations the player set to run (R or the Run button): every march they are given runs.
local runIds: { [number]: boolean } = {}
local lastClick: { id: number?, t: number } = { id = nil, t = -1 } -- double-click selects the type
local lastRight = { t = -1, x = 0, z = 0 } -- a second right-click on the same spot runs

local function issueLineMove(a: Vec, b: Vec, queue: boolean)
	for _, e in linePlacement(a, b) do
		local pos = clampToMap({ x = e.x, z = e.z })
		sendOrder("Move", { e.f.id }, { pos = pos, heading = e.heading, frontage = e.frontage, queue = queue, run = runIds[e.f.id] })
	end
end

-- Plain move keeps each formation's offset from the selection centroid. AttackMove goes to the
-- infantry and cavalry (they fight their way there); guns and staff simply march.
local function issueMove(target: Vec, queue: boolean, kind: string?)
	local forms = selectedFormations()
	if #forms == 0 then
		return
	end
	local now = os.clock()
	local double = now - lastRight.t < 0.4 and math.abs(target.x - lastRight.x) + math.abs(target.z - lastRight.z) < 40
	lastRight = { t = if double then -1 else now, x = target.x, z = target.z }
	local cx, cz = 0, 0
	for _, f in forms do
		cx += f.x
		cz += f.z
	end
	cx /= #forms
	cz /= #forms
	for _, f in forms do
		local pos = clampToMap({ x = target.x + (f.x - cx), z = target.z + (f.z - cz) })
		local k = if kind == "AttackMove" and (f.class == "infantry" or f.class == "cavalry") then "AttackMove" else "Move"
		sendOrder(k, { f.id }, { pos = pos, queue = queue, run = if double or runIds[f.id] then true else nil })
	end
end

local function issueEngage(targetId: number, queue: boolean)
	local ids = {}
	for _, f in selectedFormations() do
		if f.class ~= "hq" then
			table.insert(ids, f.id)
		end
	end
	if #ids > 0 then
		sendOrder("Engage", ids, { targetId = targetId, queue = queue })
	end
end

-- ------------------------------------------------------------------ deployment drags

local function deployPos(id: number, p: Vec): Vec
	local m = BattleState.map
	if m then
		local zone = m.deployZones[BattleState.viewerFaction]
		if zone then
			return { x = math.clamp(p.x, zone.x0 + 2, zone.x1 - 2), z = math.clamp(p.z, zone.z0 + 2, zone.z1 - 2) }
		end
	end
	return clampToMap(p)
end

local function deployPreview(id: number, p: Vec?, heading: number?)
	local f = BattleState.formations[id]
	if not f then
		Figures.setPreview(nil)
		return
	end
	local pos = if p then deployPos(id, p) else { x = f.x, z = f.z }
	Figures.setPreview({ { x = pos.x, z = pos.z, heading = heading or deployHeading[id] or f.heading, width = f.width, depth = f.depth } })
end

local function sendDeploy(id: number, p: Vec, heading: number)
	local f = BattleState.formations[id]
	if not f then
		return
	end
	local pos = deployPos(id, p)
	local m = BattleState.map
	if m and not MapGen.inZone(m, BattleState.viewerFaction, pos) then
		BattleState.orderRejected:Fire("Outside your deployment zone")
		return
	end
	sendOrder("Deploy", { id }, { pos = pos, heading = heading })
end

-- ------------------------------------------------------------------ box select

local function ensureGui()
	if gui then
		return
	end
	local player = Players.LocalPlayer :: Player
	local sg = Instance.new("ScreenGui") :: ScreenGui
	sg.Name = "EoEInput"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true -- box coordinates come from GetMouseLocation (inset included)
	sg.DisplayOrder = 5
	sg.Parent = player:WaitForChild("PlayerGui")
	local b = Instance.new("Frame") :: Frame
	b.BackgroundColor3 = Color3.fromRGB(240, 226, 180)
	b.BackgroundTransparency = 0.8
	b.BorderSizePixel = 1
	b.BorderColor3 = Color3.fromRGB(240, 226, 180)
	b.Visible = false
	b.Parent = sg
	gui = sg
	box = b
end

local function showBox(x0: number, y0: number, x1: number, y1: number)
	if box then
		box.Visible = true
		box.Position = UDim2.fromOffset(math.min(x0, x1), math.min(y0, y1))
		box.Size = UDim2.fromOffset(math.abs(x1 - x0), math.abs(y1 - y0))
	end
end

local function hideBox()
	if box then
		box.Visible = false
	end
end

local function boxSelect(x0: number, y0: number, x1: number, y1: number, additive: boolean)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local minX, maxX = math.min(x0, x1), math.max(x0, x1)
	local minY, maxY = math.min(y0, y1), math.max(y0, y1)
	local ids = {}
	for id, f in BattleState.formations do
		if f.faction == BattleState.viewerFaction then
			local sp, on = cam:WorldToScreenPoint(Vector3.new(f.x, Camera.groundHeight(f.x, f.z), f.z))
			if on and sp.X >= minX and sp.X <= maxX and sp.Y >= minY and sp.Y <= maxY then
				table.insert(ids, id)
			end
		end
	end
	if additive then
		Selection.add(ids)
	else
		Selection.set(ids)
	end
end

-- ------------------------------------------------------------------ handlers

local function shift(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function ctrl(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end

local function alt(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
end

local function cancelDrags()
	left.down = false
	left.dragging = false
	left.formation = nil
	right.down = false
	right.dragging = false
	right.formation = nil
	hideBox()
	Figures.setPreview(nil)
	finger = nil
	table.clear(down)
	OrderWheel.hide()
end

-- Co-op ping: G look, Shift+G attack, Ctrl+G defend (middle click: look). Inert solo.
local function ping(): boolean
	if not BattleState.coop() then
		return false
	end
	local g = groundUnderMouse()
	if g then
		local kind = if shift() then "attack" elseif ctrl() then "defend" else "look"
		Net.control("ping", { x = g.x, z = g.z, kind = kind })
	end
	return true
end

local function onLeftDown()
	if UserInputService:IsKeyDown(Enum.KeyCode.G) and ping() then
		return
	end
	local m = mousePos()
	left.down = true
	left.dragging = false
	left.sx, left.sy = m.X, m.Y
	left.ground = groundUnderMouse()
	left.formation = nil
	if mode == "deploy" and left.ground then
		local id, kind = pickAt(left.ground)
		if id and kind == "own" then
			left.formation = id
			Selection.set({ id })
		end
	end
end

local function onLeftUp()
	if not left.down then
		return
	end
	left.down = false
	local m = mousePos()
	if left.dragging then
		left.dragging = false
		if left.formation then
			local g = groundUnderMouse()
			local f = BattleState.formations[left.formation]
			if g and f then
				sendDeploy(left.formation, g, deployHeading[left.formation] or f.heading)
			end
			Figures.setPreview(nil)
		else
			hideBox()
			boxSelect(left.sx, left.sy, m.X, m.Y, shift())
		end
		left.formation = nil
		return
	end
	left.formation = nil
	local g = groundUnderMouse()
	if not g then
		return
	end
	local id, kind = pickAt(g)
	if id and kind == "own" then
		local now = os.clock()
		if lastClick.id == id and now - lastClick.t < 0.4 then
			-- double-click: every formation of ours of the same type
			local f = BattleState.formations[id]
			local same = {}
			for oid, o in BattleState.formations do
				if BattleState.canCommand(oid) and f and (o.type or o.class) == (f.type or f.class) and o.state ~= "routing" and o.state ~= "destroyed" and o.state ~= "exited" then
					table.insert(same, oid)
				end
			end
			table.sort(same)
			Selection.set(same)
			lastClick = { id = nil, t = -1 }
			return
		end
		lastClick = { id = id, t = now }
		Selection.inspect(nil)
		if shift() then
			Selection.toggle(id)
		else
			Selection.set({ id })
		end
	elseif id and kind == "enemy" then
		Selection.inspect(id) -- read-only look at a visible enemy; our selection stays
	elseif not shift() then
		Selection.inspect(nil)
		Selection.clear()
	end
end

local function onRightDown()
	local m = mousePos()
	right.down = true
	right.dragging = false
	right.sx, right.sy = m.X, m.Y
	right.ground = groundUnderMouse()
	right.formation = nil
	if mode == "deploy" and right.ground then
		local id, kind = pickAt(right.ground)
		if id and kind == "own" then
			right.formation = id
		end
	end
end

local function onRightUp()
	if not right.down then
		return
	end
	right.down = false
	local g = groundUnderMouse()
	if right.dragging then
		right.dragging = false
		Figures.setPreview(nil)
		if mode == "deploy" then
			if right.formation and g and right.ground then
				local f = BattleState.formations[right.formation]
				if f then
					local h = Vec.heading(Vec.sub(g, right.ground))
					deployHeading[right.formation] = h
					sendDeploy(right.formation, { x = f.x, z = f.z }, h)
				end
			end
		elseif right.ground and g then
			issueLineMove(right.ground, g, shift())
		end
		right.formation = nil
		return
	end
	right.formation = nil
	if mode ~= "battle" or not g then
		return
	end
	if Selection.count() == 0 then
		return
	end
	local id, kind = pickAt(g)
	if armed == "Charge" then
		local ids = {}
		for _, f in selectedFormations() do
			if f.class == "infantry" or f.class == "cavalry" then
				table.insert(ids, f.id)
			end
		end
		if #ids > 0 then
			if id and (kind == "enemy" or kind == "ghost") then
				sendOrder("Charge", ids, { targetId = id, queue = shift() })
			else
				sendOrder("Charge", ids, { pos = clampToMap(g), queue = shift() })
			end
		end
		armed = nil
		Input.action:Fire("disarm")
	elseif armed == "AttackMove" then
		issueMove(g, shift(), "AttackMove")
		armed = nil
		Input.action:Fire("disarm")
	elseif armed == "Garrison" then
		-- the village or farm nearest the click; the first selected battalion goes in
		local best, bestD = nil, 80
		local map = BattleState.map
		for _, sp in (if map then map.strongpoints else nil) or {} do
			local d = Vec.dist(g, sp.pos)
			if d < bestD then
				best, bestD = sp, d
			end
		end
		local f: any = nil
		for _, o in selectedFormations() do
			if not f and o.class == "infantry" and not o.garrison and BattleState.canCommand(o.id) then
				f = o
			end
		end
		if best and f then
			sendOrder("Garrison", { f.id }, { strongpoint = best.id, queue = shift(), run = runIds[f.id] })
		end
		armed = nil
		Input.action:Fire("disarm")
	elseif alt() then
		-- turn in place to face the clicked point
		for _, f in selectedFormations() do
			if BattleState.canCommand(f.id) then
				sendOrder("Face", { f.id }, { heading = Vec.heading(Vec.sub(g, { x = f.x, z = f.z })), queue = shift() })
			end
		end
	elseif id and (kind == "enemy" or kind == "ghost") then
		issueEngage(id, shift())
	elseif kind == "own" and id and Selection.count() == 1 and Selection.isSelected(id) then
		-- right-clicking the only selected formation: no-op
		return
	else
		issueMove(g, shift())
	end
end

local function onMouseMove()
	local m = mousePos()
	if left.down and not left.dragging then
		if math.abs(m.X - left.sx) > DRAG_PX or math.abs(m.Y - left.sy) > DRAG_PX then
			left.dragging = true
		end
	end
	if left.dragging then
		if left.formation then
			deployPreview(left.formation, groundUnderMouse(), nil)
		else
			showBox(left.sx, left.sy, m.X, m.Y)
		end
	end
	if right.down and not right.dragging then
		if math.abs(m.X - right.sx) > DRAG_PX or math.abs(m.Y - right.sy) > DRAG_PX then
			right.dragging = true
		end
	end
	if right.dragging and right.ground then
		local g = groundUnderMouse()
		if g then
			if mode == "deploy" then
				if right.formation then
					deployPreview(right.formation, nil, Vec.heading(Vec.sub(g, right.ground)))
				end
			elseif Vec.dist(g, right.ground) > 8 then
				previewLine(right.ground, g)
			end
		end
	end
	-- hover
	if not left.dragging and not right.dragging then
		local g = groundUnderMouse()
		local id = if g then (pickAt(g)) else nil
		Selection.setHovered(id)
	end
end

local function focusSelection()
	local forms = selectedFormations()
	if #forms == 0 then
		return
	end
	local cx, cz = 0, 0
	for _, f in forms do
		cx += f.x
		cz += f.z
	end
	Camera.focusOn(cx / #forms, cz / #forms)
end

local GROUP_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine }
-- One key per command panel order (HUD runs them through Input.wheelPick, like the touch wheel).
local ORDER_KEYS: { [EnumItem]: string } = {
	[Enum.KeyCode.L] = "line",
	[Enum.KeyCode.C] = "column",
	[Enum.KeyCode.B] = "square",
	[Enum.KeyCode.K] = "skirmish",
	[Enum.KeyCode.Y] = "wedge",
	[Enum.KeyCode.T] = "fire",
	[Enum.KeyCode.Z] = "charge",
	[Enum.KeyCode.R] = "run",
	[Enum.KeyCode.M] = "attack",
	[Enum.KeyCode.H] = "hold",
	[Enum.KeyCode.Backspace] = "stop",
	[Enum.KeyCode.X] = "retreat",
	[Enum.KeyCode.U] = "limber",
	[Enum.KeyCode.I] = "ammo",
	[Enum.KeyCode.P] = "rally",
	[Enum.KeyCode.O] = "occupy",
}
local SPEEDS = { 1, 2, 4 }
local lastGroup = { n = 0, t = -1 }

local function stepSpeed(dir: number): number
	local i = table.find(SPEEDS, BattleState.speed) or 1
	return SPEEDS[math.clamp(i + dir, 1, #SPEEDS)]
end

local function onKey(input: InputObject)
	local k = input.KeyCode
	local state = BattleState.state
	if k == Enum.KeyCode.Escape then
		if armed then
			armed = nil
			Input.action:Fire("disarm")
		else
			Selection.inspect(nil)
			Selection.clear()
		end
		Input.action:Fire("escape")
	elseif k == Enum.KeyCode.F9 then
		Input.action:Fire("dev")
	elseif k == Enum.KeyCode.F1 then
		Input.action:Fire("help")
	elseif k == Enum.KeyCode.Space then
		if state == "running" then
			Net.control("pause")
		elseif state == "paused" then
			Net.control("resume")
		end
	elseif k == Enum.KeyCode.Equals or k == Enum.KeyCode.Plus or k == Enum.KeyCode.KeypadPlus then
		Net.control("speed", stepSpeed(1))
	elseif k == Enum.KeyCode.Minus or k == Enum.KeyCode.KeypadMinus then
		Net.control("speed", stepSpeed(-1))
	elseif k == Enum.KeyCode.A and ctrl() then
		local all = {}
		for id, f in BattleState.formations do
			if BattleState.canCommand(id) and f.state ~= "routing" and f.state ~= "destroyed" and f.state ~= "exited" then
				table.insert(all, id)
			end
		end
		table.sort(all)
		Selection.set(all)
	elseif ORDER_KEYS[k] and (state == "running" or state == "paused") then
		Input.wheelPick:Fire(ORDER_KEYS[k])
	elseif k == Enum.KeyCode.F then
		focusSelection()
	elseif k == Enum.KeyCode.V then
		-- follow the first selected formation (again: stop)
		local id = Selection.first()
		if Camera.following() or not id then
			Camera.follow(nil)
		else
			Camera.follow(function(): (number?, number?)
				local f = BattleState.formations[id]
				if f and f.state ~= "destroyed" and f.state ~= "exited" then
					return f.x, f.z
				end
				return nil, nil
			end)
		end

	elseif k == Enum.KeyCode.Home then
		local c = BattleState.armyCentre()
		Camera.focusOn(c.x, c.z)
	else
		for n, code in GROUP_KEYS do
			if k == code then
				if ctrl() then
					Selection.assignGroup(n)
				else
					local now = os.clock()
					Selection.recallGroup(n)
					if lastGroup.n == n and now - lastGroup.t < 0.4 then
						focusSelection() -- a double tap centres the camera on the group
					end
					lastGroup = { n = n, t = now }
				end
			end
		end
	end
end

-- ------------------------------------------------------------------ touch

local function cancelFinger()
	finger = nil
	OrderWheel.hide()
	Figures.setPreview(nil)
end

local function armedOrder(g: Vec, id: number?, kind: string?)
	local what = armed
	armed = nil
	Input.action:Fire("disarm")
	if what == "Charge" then
		local ids = {}
		for _, f in selectedFormations() do
			if f.class == "infantry" or f.class == "cavalry" then
				table.insert(ids, f.id)
			end
		end
		if #ids > 0 then
			if id and (kind == "enemy" or kind == "ghost") then
				sendOrder("Charge", ids, { targetId = id, queue = false })
			else
				sendOrder("Charge", ids, { pos = clampToMap(g), queue = false })
			end
		end
	elseif what == "AttackMove" then
		local ids = {}
		for _, f in selectedFormations() do
			if f.class == "infantry" or f.class == "cavalry" then
				table.insert(ids, f.id)
			end
		end
		if #ids > 0 then
			sendOrder("AttackMove", ids, { pos = clampToMap(g), queue = false })
		end
	elseif what == "Move" then
		if id and (kind == "enemy" or kind == "ghost") then
			issueEngage(id, false)
		else
			issueMove(g, false)
		end
	end
end

local function onTap(fg: Finger)
	local g = groundUnderMouse() or fg.ground
	if not g then
		return
	end
	local id, kind = pickAt(g)
	if mode == "deploy" then
		if id and kind == "own" then
			Selection.set({ id })
		else
			Selection.clear()
		end
		return
	end
	if armed and Selection.count() > 0 and not (kind == "own" and id) then
		armedOrder(g, id, kind)
	elseif id and kind == "own" then
		Selection.toggle(id)
	elseif id and (kind == "enemy" or kind == "ghost") then
		if Selection.count() > 0 then
			issueEngage(id, false)
		end
	else
		Selection.clear()
		if armed then
			armed = nil
			Input.action:Fire("disarm")
		end
	end
end

local function openWheel(fg: Finger)
	fg.action = "wheel"
	OrderWheel.show(fg.lx, fg.ly, function(key: string)
		if key == "move" then
			armed = "Move"
		elseif key == "attackmove" then
			armed = "AttackMove"
		else
			Input.wheelPick:Fire(key)
		end
	end)
end

-- The finger stayed HOLD_S: wheel on an own unit, a move anchor on the ground, else a ping.
local function onHold(fg: Finger)
	local id, kind = fg.formation, fg.kind
	if mode == "battle" and id and kind == "own" then
		if not Selection.isSelected(id) then
			Selection.set({ id })
		end
		openWheel(fg)
	elseif mode == "deploy" and id and kind == "own" then
		fg.action = "facing"
	elseif Selection.count() > 0 and mode == "battle" then
		fg.action = "line"
	elseif Selection.count() == 0 then
		fg.action = "ping"
		ping()
	end
end

local function advanceFinger(fg: Finger, x: number, y: number)
	local dist = math.max(math.abs(x - fg.sx), math.abs(y - fg.sy))
	local phase = Touch.phase(fg.phase, os.clock() - fg.t0, dist)
	if phase ~= fg.phase then
		fg.phase = phase
		if phase == "hold" then
			onHold(fg)
		end
	end
end

local function onTouchBegan(input: InputObject)
	if next(down) ~= nil then
		down[input] = true
		cancelFinger() -- a second finger: pinch / twist belong to the camera
		return
	end
	down[input] = true
	local p = input.Position
	local g = groundUnderMouse()
	local id, kind = nil, nil
	if g then
		id, kind = pickAt(g)
	end
	finger = { obj = input, t0 = os.clock(), sx = p.X, sy = p.Y, lx = p.X, ly = p.Y, ground = g, phase = "pending", formation = id, kind = kind, action = nil }
end

local function onTouchChanged(input: InputObject)
	local fg = finger
	if not fg or fg.obj ~= input then
		return
	end
	local p = input.Position
	advanceFinger(fg, p.X, p.Y)
	local g = groundUnderMouse()
	if fg.phase == "drag" then
		if mode == "deploy" and fg.formation and fg.kind == "own" then
			deployPreview(fg.formation, g, nil)
		else
			Camera.panPixels(p.X - fg.lx, p.Y - fg.ly)
		end
	elseif fg.phase == "holdDrag" then
		if fg.action == "wheel" then
			OrderWheel.hover(p.X, p.Y)
		elseif fg.action == "line" and fg.ground and g then
			if Vec.dist(g, fg.ground) > 8 then
				previewLine(fg.ground, g)
			end
		elseif fg.action == "facing" and fg.formation and fg.ground and g then
			deployPreview(fg.formation, nil, Vec.heading(Vec.sub(g, fg.ground)))
		end
	end
	fg.lx, fg.ly = p.X, p.Y
end

local function onTouchEnded(input: InputObject)
	down[input] = nil
	local fg = finger
	if not fg or fg.obj ~= input then
		return
	end
	finger = nil
	local p = input.Position
	advanceFinger(fg, p.X, p.Y)
	local result = Touch.release(fg.phase)
	local g = groundUnderMouse()
	Figures.setPreview(nil)
	if result == "tap" then
		onTap(fg)
	elseif result == "drag" then
		if mode == "deploy" and fg.formation and fg.kind == "own" and g then
			local f = BattleState.formations[fg.formation]
			if f then
				sendDeploy(fg.formation, g, deployHeading[fg.formation] or f.heading)
			end
		end
	elseif fg.action == "wheel" then
		OrderWheel.release(p.X, p.Y)
	elseif fg.action == "line" and fg.ground and g then
		if result == "holdDrag" and Vec.dist(g, fg.ground) > 8 then
			issueLineMove(fg.ground, g, false)
		else
			issueMove(g, false)
		end
	elseif fg.action == "facing" and result == "holdDrag" and fg.formation and fg.ground and g then
		local f = BattleState.formations[fg.formation]
		if f then
			local h = Vec.heading(Vec.sub(g, fg.ground))
			deployHeading[fg.formation] = h
			sendDeploy(fg.formation, { x = f.x, z = f.z }, h)
		end
	end
end

-- ------------------------------------------------------------------ public

function Input.init()
	if #connections > 0 then
		return
	end
	ensureGui()
	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if mode == "off" then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if gp or textBoxFocused() then
				return
			end
			onKey(input)
			return
		end
		if gp then
			return -- the GUI consumed it: never a battlefield order
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			if Settings.touch() then
				onTouchBegan(input)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			onLeftDown()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			onRightDown()
		elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
			middleAt = mousePos()
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input: InputObject, _gp: boolean)
		if mode == "off" then
			return
		end
		-- releases are handled even when over the GUI so drags always finish
		if input.UserInputType == Enum.UserInputType.Touch then
			onTouchEnded(input)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			onLeftUp()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			onRightUp()
		elseif input.UserInputType == Enum.UserInputType.MouseButton3 and middleAt then
			local m, a = mousePos(), middleAt :: Vector2
			middleAt = nil
			if math.abs(m.X - a.X) <= DRAG_PX and math.abs(m.Y - a.Y) <= DRAG_PX then
				ping()
			end
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject, _gp: boolean)
		if mode == "off" then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			onMouseMove()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			onTouchChanged(input)
		end
	end))
	-- a still finger has no events: the hold is timed here
	table.insert(connections, RunService.Heartbeat:Connect(function()
		local fg = finger
		if fg and fg.phase == "pending" then
			advanceFinger(fg, fg.lx, fg.ly)
		end
	end))
	table.insert(connections, UserInputService.WindowFocusReleased:Connect(cancelDrags))
end

-- "off" | "battle" | "deploy"
function Input.setMode(m: string)
	if m == mode then
		return
	end
	cancelDrags()
	mode = m
	Camera.setEnabled(m ~= "off")
	if m == "off" then
		Selection.setHovered(nil)
	end
	if m ~= "deploy" then
		table.clear(deployHeading)
	end
end

function Input.mode(): string
	return mode
end

-- Arms a two-step order (Charge): the next right-click supplies the target or position.
function Input.arm(kind: string?)
	armed = kind
end

function Input.armed(): string?
	return armed
end

function Input.sendOrder(kind: string, ids: { number }, data: { [string]: any }): boolean
	return sendOrder(kind, ids, data)
end

-- Run / walk for the selection: its current marches and every later one.
function Input.toggleRun()
	local ids, anyRunning = {}, false
	for _, f in selectedFormations() do
		if f.class ~= "artillery" and BattleState.canCommand(f.id) then
			anyRunning = anyRunning or runIds[f.id] == true or f.running == true
			table.insert(ids, f.id)
		end
	end
	for _, id in ids do
		runIds[id] = if anyRunning then nil else true
	end
	if #ids > 0 then
		sendOrder("Run", ids, { run = not anyRunning })
	end
end

function Input.isRunning(id: number): boolean
	return runIds[id] == true
end

function Input.destroy()
	cancelDrags()
	mode = "off"
	armed = nil
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	if gui then
		gui:Destroy()
		gui = nil
		box = nil
	end
	OrderWheel.destroy()
	table.clear(deployHeading)
	table.clear(runIds)
end

return Input
