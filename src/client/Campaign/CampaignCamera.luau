--!strict
-- Board camera: orbit (middle drag), pan (WASD / arrows), zoom (wheel), clamped to the board
-- and smoothed. Runs after the battlefield camera in the render step, so it owns the view
-- while the campaign is open; the battlefield camera is told to ignore its keys meanwhile.

local RunService = game:GetService("RunService") :: RunService
local UserInputService = game:GetService("UserInputService") :: UserInputService
local MainCamera = require(script.Parent.Parent.Camera)
local WorldLighting = require(script.Parent.Parent.World.Lighting)

local CampaignCamera = {}

local MIN_H, MAX_H = 60, 720
local MIN_PITCH, MAX_PITCH = math.rad(38), math.rad(80)
local PAN = 1.1 -- studs per second per stud of height
local DAMP = 9
local DRAG = 0.006

type View = { x: number, z: number, yaw: number, pitch: number, height: number }
local target: View = { x = 0, z = 0, yaw = -math.pi / 2, pitch = math.rad(56), height = 320 }
local cur: View = table.clone(target)
local bounds = { x0 = 0, z0 = 0, x1 = 1, z1 = 1, y = 0 }
local conns: { RBXScriptConnection } = {}
local running = false
local rotating = false
local clouds: Clouds? = nil

local function clamp()
	target.height = math.clamp(target.height, MIN_H, MAX_H)
	target.pitch = math.clamp(target.pitch, MIN_PITCH, MAX_PITCH)
	target.x = math.clamp(target.x, bounds.x0, bounds.x1)
	target.z = math.clamp(target.z, bounds.z0, bounds.z1)
end

local function keys(dt: number)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	local function down(a: EnumKeyCode, b: EnumKeyCode): number
		return if UserInputService:IsKeyDown(a) or UserInputService:IsKeyDown(b) then 1 else 0
	end
	local fwd = down(Enum.KeyCode.W, Enum.KeyCode.Up) - down(Enum.KeyCode.S, Enum.KeyCode.Down)
	local side = down(Enum.KeyCode.D, Enum.KeyCode.Right) - down(Enum.KeyCode.A, Enum.KeyCode.Left)
	-- X up, Z down, as on the battlefield (MainCamera.HEIGHT_KEYS)
	local rise = down(MainCamera.HEIGHT_KEYS.up, MainCamera.HEIGHT_KEYS.up) - down(MainCamera.HEIGHT_KEYS.down, MainCamera.HEIGHT_KEYS.down)
	if rise ~= 0 then
		target.height *= math.exp(1.1 * rise * dt)
		clamp()
	end
	if fwd ~= 0 or side ~= 0 then
		local lx, lz = math.cos(cur.yaw), math.sin(cur.yaw)
		local speed = PAN * cur.height * dt
		-- screen-right of a camera looking along (lx, lz) is (-lz, lx) in Roblox world space
		target.x += (lx * fwd - lz * side) * speed
		target.z += (lz * fwd + lx * side) * speed
		clamp()
	end
end

local function step(dt: number)
	keys(dt)
	local k = 1 - math.exp(-DAMP * dt)
	cur.x += (target.x - cur.x) * k
	cur.z += (target.z - cur.z) * k
	cur.height += (target.height - cur.height) * k
	cur.pitch += (target.pitch - cur.pitch) * k
	cur.yaw += ((target.yaw - cur.yaw + math.pi) % (2 * math.pi) - math.pi) * k
	local dist = cur.height / math.tan(cur.pitch)
	local focus = Vector3.new(cur.x, bounds.y, cur.z)
	local pos = focus + Vector3.new(-math.cos(cur.yaw) * dist, cur.height, -math.sin(cur.yaw) * dist)
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(pos, focus)
	end
end

-- Takes the view over a board spanning x0..x1, z0..z1 (world) at height y, focused on (fx, fz).
function CampaignCamera.start(x0: number, z0: number, x1: number, z1: number, y: number, fx: number, fz: number)
	bounds = { x0 = x0, z0 = z0, x1 = x1, z1 = z1, y = y }
	CampaignCamera.focusOn(fx, fz, true)
	if running then
		return
	end
	running = true
	MainCamera.setEnabled(false)
	WorldLighting.setBoard(true)
	-- the battlefield cloud layer would sit between the table and a high camera
	clouds = workspace.Terrain:FindFirstChildOfClass("Clouds") :: Clouds?
	if clouds then
		clouds.Enabled = false
	end
	RunService:BindToRenderStep("EoEGrandCamera", Enum.RenderPriority.Camera.Value + 1, step)
	table.insert(conns, UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton3 and not gp then
			rotating = true
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton3 then
			rotating = false
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input: InputObject, gp: boolean)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement and rotating then
			target.yaw += input.Delta.X * DRAG
			target.pitch += input.Delta.Y * DRAG
			clamp()
		elseif t == Enum.UserInputType.MouseWheel and not gp then
			target.height *= if input.Position.Z > 0 then 1 / 1.15 else 1.15
			clamp()
		end
	end))
end

function CampaignCamera.focusOn(x: number, z: number, snap: boolean?)
	target.x, target.z = x, z
	clamp()
	if snap then
		cur = table.clone(target)
	end
end

function CampaignCamera.height(): number
	return cur.height
end

function CampaignCamera.stop()
	if not running then
		return
	end
	running = false
	rotating = false
	RunService:UnbindFromRenderStep("EoEGrandCamera")
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	if clouds then
		clouds.Enabled = true
		clouds = nil
	end
	WorldLighting.setBoard(false)
end

return CampaignCamera
