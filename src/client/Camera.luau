--!strict
-- Scriptable RTS camera: bounded pan, rotate, zoom, pitch; never clips into hills.
-- Height is measured above the terrain under the focus point.

local RunService = game:GetService("RunService") :: RunService
local UserInputService = game:GetService("UserInputService") :: UserInputService
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Grid = require(Shared.Grid)
local Settings = require(script.Parent.Settings)

local Camera = {}

local MIN_HEIGHT, MAX_HEIGHT = 55, 900 -- at the floor a soldier is ~30 px tall, so the uniforms read
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
local DAMP = 10

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
-- cinematic intro: sweeps from `from` to `to` over INTRO_SECONDS; any input skips it
type View = { x: number, z: number, yaw: number, pitch: number, height: number }
local intro: { t0: number, from: View, to: View }? = nil
local lastFrameHeight = DEFAULT_HEIGHT

local function groundY(x: number, z: number): number
	if map then
		return Grid.heightAt(map.grid, x, z)
	end
	return 0
end

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
	if fwd ~= 0 or side ~= 0 then
		local speed = PAN_SPEED * cur.height * dt
		-- forward on screen = look direction projected on the ground; right = +90° in sim space
		-- is the screen-left in Roblox (Y-up, right-handed), so screen-right is yaw - 90°.
		local fx, fz = math.cos(cur.yaw), math.sin(cur.yaw)
		local rx, rz = math.cos(cur.yaw - math.pi / 2), math.sin(cur.yaw - math.pi / 2)
		target.x += (fx * fwd + rx * side) * speed
		target.z += (fz * fwd + rz * side) * speed
	end
	if isDown(Enum.KeyCode.Q) then
		target.yaw += ROTATE_SPEED * dt
	end
	if isDown(Enum.KeyCode.E) then
		target.yaw -= ROTATE_SPEED * dt
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
	cur.height = a.height + (b.height - a.height) * e + math.sin(e * math.pi) * 120
	return true
end

local function step(dt: number)
	if not stepIntro() then
		readKeys(dt)
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
		if intro and (t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Gamepad1) then
			finishIntro()
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject, gp: boolean)
		if input.UserInputType == Enum.UserInputType.MouseWheel and intro then
			finishIntro()
			return
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
	target.yaw = defaultYaw
	target.pitch = DEFAULT_PITCH
	target.height = DEFAULT_HEIGHT
	Camera.focusOn(x, z, true)
	cur.yaw, cur.pitch, cur.height = target.yaw, target.pitch, target.height
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
	local from: View = { x = fx, z = fz, yaw = to.yaw - 2.4, pitch = math.rad(40), height = 700 }
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
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
end

return Camera
