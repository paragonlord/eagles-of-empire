--!strict
-- Scriptable RTS camera: bounded pan, rotate, zoom, pitch; never clips into hills.
-- Height is measured above the terrain under the focus point.

local RunService = game:GetService("RunService") :: RunService
local UserInputService = game:GetService("UserInputService") :: UserInputService
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Grid = require(Shared.Grid)
local Settings = require(script.Parent.Settings)

local Camera = {}

local MIN_HEIGHT, MAX_HEIGHT = 120, 900
local MIN_PITCH, MAX_PITCH = math.rad(35), math.rad(65)
local DEFAULT_PITCH = math.rad(52)
local DEFAULT_HEIGHT = 420
local DEFAULT_YAW = math.pi / 2 -- look toward +z (north)
local PAN_SPEED = 1.1 -- studs per second per stud of height
local ROTATE_SPEED = 1.6
local ZOOM_STEP = 1.15
local DAMP = 10

-- target values (inputs move these) and smoothed values (what is rendered)
local target = { x = 800, z = 600, yaw = DEFAULT_YAW, pitch = DEFAULT_PITCH, height = DEFAULT_HEIGHT }
local cur = { x = 800, z = 600, yaw = DEFAULT_YAW, pitch = DEFAULT_PITCH, height = DEFAULT_HEIGHT }
local map: any = nil
local bounds = { x0 = 0, z0 = 0, x1 = 1600, z1 = 1200 }
local shakeAmount = 0
local connections: { RBXScriptConnection } = {}
local bound = false
local enabled = true
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

local function step(dt: number)
	readKeys(dt)
	local k = 1 - math.exp(-DAMP * dt)
	cur.x += (target.x - cur.x) * k
	cur.z += (target.z - cur.z) * k
	cur.height += (target.height - cur.height) * k
	cur.pitch += (target.pitch - cur.pitch) * k
	-- shortest-way yaw blend
	local dy = (target.yaw - cur.yaw + math.pi) % (2 * math.pi) - math.pi
	cur.yaw += dy * k

	local focusY = groundY(cur.x, cur.z)
	local dist = cur.height / math.tan(cur.pitch)
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
	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject, gp: boolean)
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
	target.yaw = DEFAULT_YAW
	target.pitch = DEFAULT_PITCH
	target.height = DEFAULT_HEIGHT
	Camera.focusOn(x, z, true)
	cur.yaw, cur.pitch, cur.height = target.yaw, target.pitch, target.height
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
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
end

return Camera
