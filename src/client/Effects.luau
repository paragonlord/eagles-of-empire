--!strict
-- Pooled one-shot visual effects driven by snapshot events only (smoke, flashes, dust).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Grid = require(Shared.Grid)
local Settings = require(script.Parent.Settings)
local BattleState = require(script.Parent.BattleState)
local Camera = require(script.Parent.Camera)

local Effects = {}

type Active = {
	part: Part,
	t0: number,
	life: number,
	size0: number,
	size1: number,
	rise: number,
	x: number,
	y: number,
	z: number,
	alpha0: number,
}

local BASE_POOL = { [1] = 60, [2] = 140, [3] = 260 }
local folder: Folder? = nil
local free: { Part } = {}
local active: { Active } = {}
local capacity = 0
local rng = Random.new(1806)

local SMOKE = Color3.fromRGB(236, 232, 224)
local DUST = Color3.fromRGB(190, 170, 130)
local FLASH = Color3.fromRGB(255, 214, 120)
local ROUT = Color3.fromRGB(150, 60, 50)

local function groundY(x: number, z: number): number
	local m = BattleState.map
	return if m then Grid.heightAt(m.grid, x, z) else 0
end

local function makePart(): Part
	local p = Instance.new("Part") :: Part
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = Vector3.new(1, 1, 1)
	p.Transparency = 1
	return p
end

function Effects.init()
	if folder then
		return
	end
	local f = Instance.new("Folder") :: Folder
	f.Name = "EoEEffects"
	f.Parent = workspace
	folder = f
	Effects.applySettings()
end

function Effects.applySettings()
	local s = Settings.get()
	capacity = BASE_POOL[math.clamp(s.quality, 1, 3)]
	if s.reducedEffects then
		capacity = capacity // 2
	end
end

local function spawn(x: number, z: number, y: number, color: Color3, size0: number, size1: number, life: number, rise: number, alpha0: number)
	if not folder or #active >= capacity then
		return
	end
	local p = table.remove(free) or makePart()
	p.Color = color
	p.Size = Vector3.new(size0, size0, size0)
	p.Transparency = alpha0
	p.CFrame = CFrame.new(x, y, z)
	p.Parent = folder
	table.insert(active, { part = p, t0 = os.clock(), life = life, size0 = size0, size1 = size1, rise = rise, x = x, y = y, z = z, alpha0 = alpha0 })
end

local function puffs(x: number, z: number, n: number, spread: number, color: Color3, size: number, life: number)
	local y = groundY(x, z) + 2
	for _ = 1, n do
		local ox = (rng:NextNumber() - 0.5) * spread
		local oz = (rng:NextNumber() - 0.5) * spread
		spawn(x + ox, z + oz, y + rng:NextNumber() * 1.5, color, size * 0.6, size * (1.4 + rng:NextNumber() * 0.6), life, 2.5, 0.25)
	end
end

-- Musket smoke along the firing front of the formation (falls back to a point).
local function volley(ev: any)
	local f = BattleState.formations[ev.id or -1]
	if f then
		local fx, fz = math.cos(f.heading), math.sin(f.heading)
		local rx, rz = -fz, fx
		local frontX = f.x + fx * f.depth / 2
		local frontZ = f.z + fz * f.depth / 2
		local n = math.clamp(math.floor(f.width / 5), 3, 16)
		local y = groundY(f.x, f.z) + 2.2
		for i = 1, n do
			local t = (i - 0.5) / n - 0.5
			local px = frontX + rx * f.width * t + fx * 1.5
			local pz = frontZ + rz * f.width * t + fz * 1.5
			spawn(px, pz, y, FLASH, 0.8, 0.2, 0.12, 0, 0.1)
			spawn(px + fx * 2, pz + fz * 2, y + 0.5, SMOKE, 1.5, 4.5 + rng:NextNumber(), 1.5, 2.0, 0.3)
		end
	elseif ev.x then
		puffs(ev.x, ev.z, 4, 12, SMOKE, 3, 1.5)
	end
end

local function cannon(ev: any)
	if not ev.x then
		return
	end
	local y = groundY(ev.x, ev.z) + 2.5
	local dx, dz = 0, 0
	if ev.tx then
		local l = math.sqrt((ev.tx - ev.x) ^ 2 + (ev.tz - ev.z) ^ 2)
		if l > 1 then
			dx, dz = (ev.tx - ev.x) / l, (ev.tz - ev.z) / l
		end
	end
	spawn(ev.x + dx * 4, ev.z + dz * 4, y, FLASH, 2.5, 0.5, 0.15, 0, 0.05)
	for i = 1, 4 do
		spawn(ev.x + dx * (4 + i * 3), ev.z + dz * (4 + i * 3), y + 1, SMOKE, 2 + i, 7 + i, 2.2, 1.5, 0.25)
	end
	if ev.tx then
		puffs(ev.tx, ev.tz, 3, 10, DUST, 2.5, 1.0)
	end
	Camera.shake(1.2)
end

function Effects.onEvent(ev: any)
	if not folder then
		return
	end
	local kind = ev.kind
	if kind == "volley" then
		volley(ev)
	elseif kind == "cannon" then
		cannon(ev)
	elseif kind == "melee" then
		if ev.x then
			puffs(ev.x, ev.z, 5, 18, DUST, 3, 1.2)
		end
	elseif kind == "charge" then
		if ev.x then
			puffs(ev.x, ev.z, 8, 26, DUST, 3.5, 1.6)
		end
	elseif kind == "rout" then
		if ev.x then
			puffs(ev.x, ev.z, 3, 14, DUST, 2.5, 1.2)
			spawn(ev.x, ev.z, groundY(ev.x, ev.z) + 6, ROUT, 3, 1, 2.5, 6, 0.3)
		end
	end
end

function Effects.update(_dt: number)
	local now = os.clock()
	local i = 1
	while i <= #active do
		local a = active[i]
		local t = (now - a.t0) / a.life
		if t >= 1 then
			a.part.Parent = nil
			table.insert(free, a.part)
			active[i] = active[#active]
			active[#active] = nil
		else
			local s = a.size0 + (a.size1 - a.size0) * math.sqrt(t)
			a.part.Size = Vector3.new(s, s, s)
			a.part.Transparency = a.alpha0 + (1 - a.alpha0) * t * t
			a.part.CFrame = CFrame.new(a.x, a.y + a.rise * t, a.z)
			i += 1
		end
	end
end

function Effects.clear()
	for _, a in active do
		a.part:Destroy()
	end
	table.clear(active)
	for _, p in free do
		p:Destroy()
	end
	table.clear(free)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return Effects
