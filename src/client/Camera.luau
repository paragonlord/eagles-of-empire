--!strict
-- Scriptable RTS camera: bounded pan, rotate, zoom, pitch; never clips into hills.
-- Height is measured above the terrain under the focus point.

local RunService = game:GetService("RunService") :: RunService
local UserInputService = game:GetService("UserInputService") :: UserInputService
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Grid = require(Shared.Grid)
local Settings = require(script.Parent.Settings)

local Camera = {}

local MIN_HEIGHT, MAX_HEIGHT = 25, 900 -- at the floor a soldier fills ~60 px: down among the ranks
local MIN_PITCH, MAX_PITCH = math.rad(35), math.rad(65)
local DEFAULT_PITCH = math.rad(52)
-- NTW-style: the view tilts toward the horizon as it nears the ground (full tilt at MIN_HEIGHT,
-- none above TILT_FROM).
local TILT_MAX = math.rad(18)
local TILT_FROM = 520
local INTRO_SECONDS = 11
local DEFAULT_HEIGHT = 420
local DEFAULT_YAW = math.pi / 2 -- look toward +z (north)
local PAN_SPEED = 1.1 -- studs per second per stud of height
local ROTATE_SPEED = 1.6
local ZOOM_STEP = 1.15
local HEIGHT_SPEED = 1.1 -- X / Z: the height grows or shrinks by e^1.1 (3x) a second
local DAMP = 10
local EDGE_PX = 6 -- edge scrolling band at the window border

-- target values (inputs move these) and smoothed values (what is rendered)
local defaultYaw = DEFAULT_YAW -- per side: faces the enemy (Camera.setDefaultYaw)
local target = { x = 800, z = 600, yaw = DEFAULT_YAW, pitch = DEFAULT_PITCH, height = DEFAULT_HEIGHT }
local cur = { x = 800, z = 600, yaw = DEFAULT_YAW, pitch = DEFAULT_PITCH, height = DEFAULT_HEIGHT }
local map: any = nil
local bounds = { x0 = 0, z0 = 0, x1 = 1600, z1 = 1200 }
local shakeAmount = 0
local connections: { RBXScriptConnection } = {}
local bound = false
local enabled = true
local rotating = false -- middle-mouse drag in progress
local ROTATE_DRAG = 0.006 -- radians per pixel
local PAN_DRAG = 1.7 -- touch: studs per pixel per stud of height, over the viewport height
local pinch: { dist: number, ang: number, height: number }? = nil -- two-finger gesture in progress
-- cinematic intro: sweeps from `from` to `to` over INTRO_SECONDS; any input skips it
type View = { x: number, z: number, yaw: number, pitch: number, height: number }
local intro: { t0: number, from: View, to: View }? = nil
local lastFrameHeight = DEFAULT_HEIGHT
local follow: (() -> (number?, number?))? = nil -- the camera tracks a formation until the player pans
local drift = 0 -- the menu: radians a second the view turns about its focus, until the player moves it
local windowFocused = true

local function groundY(x: number, z: number): number
	if map then
		return Grid.heightAt(map.grid, x, z)
	end
	return 0
end

-- Screen-right on the ground for a camera looking along `yaw`: Roblox's right vector is
-- look x up, so looking along (cos, sin) it is (-sin, cos), a quarter turn the positive way.
function Camera.screenRight(yaw: number): (number, number)
	return math.cos(yaw + math.pi / 2), math.sin(yaw + math.pi / 2)
end

-- Total War's height keys.
Camera.HEIGHT_KEYS = { up = Enum.KeyCode.X, down = Enum.KeyCode.Z }

local function textBoxFocused(): boolean
	return (UserInputService:GetFocusedTextBox() :: TextBox?) ~= nil
end

-- The focus keeps a margin from the map edge that grows with height, so the frustum stays
-- over the terrain instead of showing sky past the edge.
local function clampTarget()
	target.height = math.clamp(target.height, MIN_HEIGHT, MAX_HEIGHT)
	target.pitch = math.clamp(target.pitch, MIN_PITCH, MAX_PITCH)
	local w, d = bounds.x1 - bounds.x0, bounds.z1 - bounds.z0
	local margin = math.clamp(target.height * 0.45, 40, math.min(w, d) * 0.3)
	target.x = math.clamp(target.x, bounds.x0 + margin, bounds.x1 - margin)
	target.z = math.clamp(target.z, bounds.z0 + margin, bounds.z1 - margin)
end

-- Edge scrolling from the pointer (mx, my) in a view vw x vh pixels: (side, forward), each -1, 0
-- or 1. A pointer outside the view pans nothing: Roblox reports (-1, -1) once the mouse leaves
-- the window, which read as the top-left corner sent the camera off to the map's edge.
function Camera.edgeScroll(mx: number, my: number, vw: number, vh: number): (number, number)
	if mx < 0 or my < 0 or mx > vw or my > vh then
		return 0, 0
	end
	local side = if mx <= EDGE_PX then -1 elseif mx >= vw - EDGE_PX then 1 else 0
	local fwd = if my <= EDGE_PX then 1 elseif my >= vh - EDGE_PX then -1 else 0
	return side, fwd
end

local function readKeys(dt: number)
	if not enabled or textBoxFocused() then
		return
	end
	local isDown = function(k: EnumKeyCode): boolean
		return UserInputService:IsKeyDown(k)
	end
	local fwd = 0
	local side = 0
	if isDown(Enum.KeyCode.W) or isDown(Enum.KeyCode.Up) then
		fwd += 1
	end
	if isDown(Enum.KeyCode.S) or isDown(Enum.KeyCode.Down) then
		fwd -= 1
	end
	if isDown(Enum.KeyCode.D) or isDown(Enum.KeyCode.Right) then
		side += 1
	end
	if isDown(Enum.KeyCode.A) or isDown(Enum.KeyCode.Left) then
		side -= 1
	end
	-- edge scrolling (desktop only, never while the window is out of focus or the menu's view
	-- turns: a pointer resting on the screen's edge would carry the backdrop away)
	if Settings.get().edgeScroll and windowFocused and drift == 0 and not Settings.touch() then
		local cam = workspace.CurrentCamera
		if cam then
			local m, v = UserInputService:GetMouseLocation(), cam.ViewportSize
			local es, ef = Camera.edgeScroll(m.X, m.Y, v.X, v.Y)
			side += es
			fwd += ef
		end
	end
	if fwd ~= 0 or side ~= 0 then
		follow = nil -- panning takes the camera back
		local speed = PAN_SPEED * cur.height * dt
		-- forward on screen = look direction projected on the ground
		local fx, fz = math.cos(cur.yaw), math.sin(cur.yaw)
		local rx, rz = Camera.screenRight(cur.yaw)
		target.x += (fx * fwd + rx * side) * speed
		target.z += (fz * fwd + rz * side) * speed
	end
	if isDown(Enum.KeyCode.Q) then
		target.yaw += ROTATE_SPEED * dt
	end
	if isDown(Enum.KeyCode.E) then
		target.yaw -= ROTATE_SPEED * dt
	end
	if isDown(Camera.HEIGHT_KEYS.up) then
		target.height *= math.exp(HEIGHT_SPEED * dt)
	end
	if isDown(Camera.HEIGHT_KEYS.down) then
		target.height /= math.exp(HEIGHT_SPEED * dt)
	end
	if isDown(Enum.KeyCode.PageUp) then
		target.pitch += 0.8 * dt
	end
	if isDown(Enum.KeyCode.PageDown) then
		target.pitch -= 0.8 * dt
	end
	clampTarget()
end

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function finishIntro()
	local i = intro
	if not i then
		return
	end
	intro = nil
	target.x, target.z, target.yaw, target.pitch, target.height = i.to.x, i.to.z, i.to.yaw, i.to.pitch, i.to.height
	cur.x, cur.z, cur.yaw, cur.pitch, cur.height = i.to.x, i.to.z, i.to.yaw, i.to.pitch, i.to.height
end

local function stepIntro(): boolean
	local i = intro
	if not i then
		return false
	end
	local t = (os.clock() - i.t0) / INTRO_SECONDS
	if t >= 1 then
		finishIntro()
		return false
	end
	local e = smoothstep(t)
	local a, b = i.from, i.to
	cur.x = a.x + (b.x - a.x) * e
	cur.z = a.z + (b.z - a.z) * e
	cur.yaw = a.yaw + (b.yaw - a.yaw) * e
	cur.pitch = a.pitch + (b.pitch - a.pitch) * e
	-- rise a little mid-sweep, then settle onto the default view
	cur.height = a.height + (b.height - a.height) * e + math.sin(e * math.pi) * 60
	return true
end

local function step(dt: number)
	if not stepIntro() then
		readKeys(dt)
		target.yaw += drift * dt
		local track = follow
		if track then
			local x, z = track()
			if x and z then
				target.x, target.z = x, z
				clampTarget()
			else
				follow = nil -- the formation is gone
			end
		end
		local k = 1 - math.exp(-DAMP * dt)
		cur.x += (target.x - cur.x) * k
		cur.z += (target.z - cur.z) * k
		cur.height += (target.height - cur.height) * k
		cur.pitch += (target.pitch - cur.pitch) * k
		-- shortest-way yaw blend
		local dy = (target.yaw - cur.yaw + math.pi) % (2 * math.pi) - math.pi
		cur.yaw += dy * k
	end

	local focusY = groundY(cur.x, cur.z)
	local tilt = TILT_MAX * math.clamp((TILT_FROM - cur.height) / (TILT_FROM - MIN_HEIGHT), 0, 1)
	local pitch = cur.pitch - tilt
	local dist = cur.height / math.tan(pitch)
	local camX = cur.x - math.cos(cur.yaw) * dist
	local camZ = cur.z - math.sin(cur.yaw) * dist
	local camY = focusY + cur.height
	-- never clip into hills: the camera and the line to the focus stay above the terrain
	camY = math.max(camY, groundY(camX, camZ) + 14)
	for i = 1, 4 do
		local t = i / 5
		local sx, sz = camX + (cur.x - camX) * t, camZ + (cur.z - camZ) * t
		local lineY = camY + (focusY - camY) * t
		local need = groundY(sx, sz) + 8
		if lineY < need then
			camY += (need - lineY) / (1 - t)
		end
	end
	lastFrameHeight = camY - focusY
	local pos = Vector3.new(camX, camY, camZ)
	if shakeAmount > 0.01 then
		local s = if Settings.get().reducedShake then shakeAmount * 0.3 else shakeAmount
		pos += Vector3.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, (math.random() - 0.5) * s)
		shakeAmount *= math.exp(-6 * dt)
	end
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(pos, Vector3.new(cur.x, focusY, cur.z))
	end
end

function Camera.init()
	if bound then
		return
	end
	bound = true
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = 55
	end
	RunService:BindToRenderStep("EoECamera", Enum.RenderPriority.Camera.Value, step)
	if RunService:IsStudio() then
		-- Shot rig (docs/qa.md): workspace attribute EoECamera = "x,z,height,yawDeg,pitchDeg" jumps
		-- the view there, so before/after screenshots share one camera.
		table.insert(connections, workspace:GetAttributeChangedSignal("EoECamera"):Connect(function()
			local v = string.split(tostring(workspace:GetAttribute("EoECamera") or ""), ",")
			local x, z, h, yaw, pitch = tonumber(v[1]), tonumber(v[2]), tonumber(v[3]), tonumber(v[4]), tonumber(v[5])
			if x and z and h and yaw and pitch then
				finishIntro()
				follow = nil
				target.x, target.z, target.height, target.yaw, target.pitch = x, z, h, math.rad(yaw), math.rad(pitch)
				clampTarget()
				cur.x, cur.z, cur.height, cur.yaw, cur.pitch = target.x, target.z, target.height, target.yaw, target.pitch
			end
		end))
	end
	table.insert(connections, UserInputService.WindowFocused:Connect(function()
		windowFocused = true
	end))
	table.insert(connections, UserInputService.WindowFocusReleased:Connect(function()
		windowFocused = false
	end))
	-- Middle-mouse drag rotates (yaw) and tilts (pitch), Total War style.
	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton3 and not gp and enabled then
			rotating = true
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton3 then
			rotating = false
		end
	end))
	table.insert(connections, UserInputService.WindowFocusReleased:Connect(function()
		rotating = false
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject)
		if rotating and enabled and not intro and input.UserInputType == Enum.UserInputType.MouseMovement then
			target.yaw -= input.Delta.X * ROTATE_DRAG
			target.pitch += input.Delta.Y * ROTATE_DRAG
			clampTarget()
		end
	end))
	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Gamepad1 then
			drift = 0 -- a menu click leaves the view turning; taking the camera stops it
		end
		if intro and (t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Gamepad1) then
			finishIntro()
		end
	end))
	-- Touch: two fingers pinch to zoom (height) and twist to rotate (yaw), measured from the
	-- finger positions so the units Roblox reports do not matter.
	table.insert(connections, UserInputService.TouchPinch:Connect(function(touches: { Vector2 }, _scale: number, _velocity: number, state: EnumUserInputState, gp: boolean)
		if not enabled or not Settings.touch() or #touches < 2 then
			return
		end
		local a, b = touches[1], touches[2]
		local d = math.max((b - a).Magnitude, 1)
		local ang = math.atan2(b.Y - a.Y, b.X - a.X)
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			pinch = nil
		elseif pinch == nil then
			if not gp then
				finishIntro()
				pinch = { dist = d, ang = ang, height = target.height }
			end
		else
			local g = pinch :: { dist: number, ang: number, height: number }
			target.height = g.height * g.dist / d
			target.yaw -= (ang - g.ang + math.pi) % (2 * math.pi) - math.pi
			g.ang = ang
			clampTarget()
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject, gp: boolean)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			drift = 0
			if intro then
				finishIntro()
				return
			end
		end
		if gp or not enabled or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		if input.Position.Z > 0 then
			target.height /= ZOOM_STEP
		elseif input.Position.Z < 0 then
			target.height *= ZOOM_STEP
		end
		clampTarget()
	end))
end

function Camera.setMap(m: any)
	map = m
	if m then
		bounds = { x0 = 0, z0 = 0, x1 = m.width, z1 = m.depth }
	end
	clampTarget()
end

function Camera.setEnabled(on: boolean)
	enabled = on
end

-- Touch: a finger dragged (dx, dy) pixels carries the ground with it.
function Camera.panPixels(dx: number, dy: number)
	if not enabled then
		return
	end
	finishIntro()
	local cam = workspace.CurrentCamera
	local k = cur.height * PAN_DRAG / (if cam then math.max(cam.ViewportSize.Y, 1) else 720)
	local fx, fz = math.cos(cur.yaw), math.sin(cur.yaw)
	local rx, rz = Camera.screenRight(cur.yaw)
	target.x += (fx * dy - rx * dx) * k
	target.z += (fz * dy - rz * dx) * k
	clampTarget()
end

-- Track a moving point (a formation) until the player pans, or stop with nil.
function Camera.follow(getPos: (() -> (number?, number?))?)
	follow = getPos
end

function Camera.following(): boolean
	return follow ~= nil
end

function Camera.focusOn(x: number, z: number, snap: boolean?)
	target.x, target.z = x, z
	clampTarget()
	if snap then
		cur.x, cur.z = target.x, target.z
	end
end

-- Default angle: high oblique, look north from the south at 52°, 420 studs up.
function Camera.reset(x: number, z: number)
	intro = nil
	drift = 0
	target.yaw = defaultYaw
	target.pitch = DEFAULT_PITCH
	target.height = DEFAULT_HEIGHT
	Camera.focusOn(x, z, true)
	cur.yaw, cur.pitch, cur.height = target.yaw, target.pitch, target.height
end

-- The menu: low over the field (call after Camera.reset, before playIntro), turning slowly
-- about it once the sweep lands, until the player takes the camera.
function Camera.menuView()
	target.height, target.pitch = 140, MIN_PITCH
	cur.height, cur.pitch = target.height, target.pitch
	drift = 0.02
end

-- The yaw Camera.reset returns to; nil restores north. Each side looks toward its enemy.
function Camera.setDefaultYaw(yaw: number?)
	defaultYaw = yaw or DEFAULT_YAW
end

-- Sweeps in from high over the far side of the field, turning onto the current default view
-- (call after Camera.reset). Skipped by any key, click or wheel.
function Camera.playIntro()
	if not map then
		return
	end
	local to: View = { x = target.x, z = target.z, yaw = target.yaw, pitch = target.pitch, height = target.height }
	local cx, cz = map.width / 2, map.depth / 2
	-- start across the map centre from the destination, looking back toward it
	local fx = math.clamp(cx + (cx - to.x) * 0.6, map.width * 0.2, map.width * 0.8)
	local fz = math.clamp(cz + (cz - to.z) * 0.6, map.depth * 0.2, map.depth * 0.8)
	-- from the default height, not 700 up: from there the whole field sank into the haze and the
	-- map's edge showed, the first thing seen of every battle
	local from: View = { x = fx, z = fz, yaw = to.yaw - 2.4, pitch = math.rad(38), height = DEFAULT_HEIGHT }
	intro = { t0 = os.clock(), from = from, to = to }
	cur.x, cur.z, cur.yaw, cur.pitch, cur.height = from.x, from.z, from.yaw, from.pitch, from.height
end

function Camera.introPlaying(): boolean
	return intro ~= nil
end

function Camera.getFocus(): (number, number)
	return cur.x, cur.z
end

function Camera.getYaw(): number
	return cur.yaw
end

function Camera.height(): number
	return lastFrameHeight
end

function Camera.groundHeight(x: number, z: number): number
	return groundY(x, z)
end

function Camera.shake(amount: number)
	shakeAmount = math.max(shakeAmount, amount)
end

function Camera.destroy()
	if not bound then
		return
	end
	bound = false
	RunService:UnbindFromRenderStep("EoECamera")
	intro = nil
	rotating = false
	pinch = nil
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
end

return Camera
