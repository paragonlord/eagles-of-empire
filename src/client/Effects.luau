--!strict
-- Pooled one-shot visual effects driven by snapshot events only: lingering volley smoke banks,
-- muzzle flashes, cannon plumes and shot strikes, charge dust, routing markers.

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
	vx: number,
	vz: number,
	alpha0: number,
}

-- Lingering smoke needs a deep pool; reduced effects halves it (and the puffs per event).
local BASE_POOL = { [1] = 120, [2] = 260, [3] = 420 }
local WIND_X, WIND_Z = 0.9, 0.35 -- studs/s drift, light breeze from the south-west

local folder: Folder? = nil
local free: { Part } = {}
local active: { Active } = {}
local capacity = 0
local density = 1
local rng = Random.new(1806)

local SMOKE = Color3.fromRGB(236, 234, 228)
local SMOKE_GREY = Color3.fromRGB(200, 198, 192)
local DUST = Color3.fromRGB(184, 166, 124)
local EARTH = Color3.fromRGB(110, 92, 64)
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
	density = 1
	if s.reducedEffects then
		capacity = capacity // 2
		density = 0.5
	end
end

local function count(n: number): number
	return math.max(1, math.round(n * density))
end

local function spawn(x: number, y: number, z: number, color: Color3, size0: number, size1: number, life: number, rise: number, alpha0: number, vx: number?, vz: number?)
	if not folder or #active >= capacity then
		return
	end
	local p = table.remove(free) or makePart()
	p.Color = color
	p.Size = Vector3.new(size0, size0, size0)
	p.Transparency = alpha0
	p.CFrame = CFrame.new(x, y, z)
	p.Parent = folder
	table.insert(active, { part = p, t0 = os.clock(), life = life, size0 = size0, size1 = size1, rise = rise, x = x, y = y, z = z, vx = vx or 0, vz = vz or 0, alpha0 = alpha0 })
end

local function puffs(x: number, z: number, n: number, spread: number, color: Color3, size: number, life: number, rise: number)
	local y = groundY(x, z) + 1.5
	for _ = 1, count(n) do
		local ox = (rng:NextNumber() - 0.5) * spread
		local oz = (rng:NextNumber() - 0.5) * spread
		spawn(x + ox, y + rng:NextNumber() * 1.5, z + oz, color, size * 0.6, size * (1.4 + rng:NextNumber() * 0.6), life, rise, 0.3, ox * 0.4, oz * 0.4)
	end
end

-- A bank of overlapping smoke along the firing front: flashes first, then smoke that swells,
-- drifts with the breeze and fades over ~6 s.
local function volley(ev: any)
	local f = BattleState.formations[ev.id or -1]
	if not f then
		if ev.x then
			puffs(ev.x, ev.z, 5, 14, SMOKE, 4, 5, 2)
		end
		return
	end
	local fx, fz = math.cos(f.heading), math.sin(f.heading)
	local rx, rz = -fz, fx
	local frontX = f.x + fx * (f.depth / 2 + 1.5)
	local frontZ = f.z + fz * (f.depth / 2 + 1.5)
	local n = count(math.clamp(math.floor(f.width / 3.5), 4, 22))
	for i = 1, n do
		local t = (i - 0.5) / n - 0.5 + (rng:NextNumber() - 0.5) / n
		local px = frontX + rx * f.width * t
		local pz = frontZ + rz * f.width * t
		local y = groundY(px, pz) + 1.9
		spawn(px, y, pz, FLASH, 0.9, 0.3, 0.1, 0, 0.05)
		-- muzzle puff thrown forward, then the bank behind it
		spawn(px + fx * 1.5, y + 0.3, pz + fz * 1.5, SMOKE, 1.6, 5 + rng:NextNumber() * 2, 6 + rng:NextNumber() * 1.5, 3, 0.25, fx * 1.2 + WIND_X, fz * 1.2 + WIND_Z)
		if rng:NextNumber() < 0.6 then
			spawn(px + fx * 3, y + 1.2, pz + fz * 3, SMOKE_GREY, 2.5, 6.5, 5.5, 4, 0.45, fx * 0.6 + WIND_X, fz * 0.6 + WIND_Z)
		end
	end
	Camera.shake(0.2)
end

local function cannon(ev: any)
	if not ev.x then
		return
	end
	local y = groundY(ev.x, ev.z) + 1.6
	local dx, dz = 0, 0
	if ev.tx then
		local l = math.sqrt((ev.tx - ev.x) ^ 2 + (ev.tz - ev.z) ^ 2)
		if l > 1 then
			dx, dz = (ev.tx - ev.x) / l, (ev.tz - ev.z) / l
		end
	end
	spawn(ev.x + dx * 3.5, y, ev.z + dz * 3.5, FLASH, 2.5, 0.6, 0.14, 0, 0.05)
	-- a thick plume rolling out of the muzzle
	for i = 1, count(6) do
		local d = 3 + i * 2.2
		spawn(ev.x + dx * d, y + 0.5 + i * 0.3, ev.z + dz * d, if i % 2 == 0 then SMOKE_GREY else SMOKE, 2.5 + i * 0.6, 8 + i * 1.2, 6.5, 4, 0.2, dx * 1.5 + WIND_X, dz * 1.5 + WIND_Z)
	end
	if ev.tx then
		-- round shot strikes: a spray of earth and a dust puff
		local ty = groundY(ev.tx, ev.tz)
		for _ = 1, count(4) do
			spawn(ev.tx + (rng:NextNumber() - 0.5) * 3, ty + 0.5, ev.tz + (rng:NextNumber() - 0.5) * 3, EARTH, 1.2, 2.5, 0.9, 4, 0.1, dx * 3, dz * 3)
		end
		puffs(ev.tx, ev.tz, 3, 6, DUST, 3, 2.2, 1.5)
	end
	Camera.shake(1.2)
end

-- Dust thrown up behind a charging formation.
local function charge(ev: any)
	local f = BattleState.formations[ev.id or -1]
	if f then
		local fx, fz = math.cos(f.heading), math.sin(f.heading)
		local rx, rz = -fz, fx
		local n = count(10)
		for i = 1, n do
			local t = (i - 0.5) / n - 0.5
			local px = f.x - fx * f.depth / 2 + rx * f.width * t
			local pz = f.z - fz * f.depth / 2 + rz * f.width * t
			spawn(px, groundY(px, pz) + 1, pz, DUST, 2, 6, 3, 2, 0.35, -fx * 2 + WIND_X, -fz * 2 + WIND_Z)
		end
	elseif ev.x then
		puffs(ev.x, ev.z, 8, 26, DUST, 3.5, 2.5, 2)
	end
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
			puffs(ev.x, ev.z, 5, 18, DUST, 3, 1.6, 1.5)
		end
	elseif kind == "charge" then
		charge(ev)
	elseif kind == "rout" then
		if ev.x then
			puffs(ev.x, ev.z, 3, 14, DUST, 2.5, 1.4, 1)
			spawn(ev.x, groundY(ev.x, ev.z) + 6, ev.z, ROUT, 3, 1, 2.5, 6, 0.3)
		end
	end
end

function Effects.update(_dt: number)
	local now = os.clock()
	local i = 1
	while i <= #active do
		local a = active[i]
		local age = now - a.t0
		local t = age / a.life
		if t >= 1 then
			a.part.Parent = nil
			table.insert(free, a.part)
			active[i] = active[#active]
			active[#active] = nil
		else
			local s = a.size0 + (a.size1 - a.size0) * math.sqrt(t)
			a.part.Size = Vector3.new(s, s * 0.85, s)
			-- hold density for the first third, then thin out
			local fade = math.clamp((t - 0.3) / 0.7, 0, 1)
			a.part.Transparency = a.alpha0 + (1 - a.alpha0) * fade * fade
			a.part.CFrame = CFrame.new(a.x + a.vx * age, a.y + a.rise * t, a.z + a.vz * age)
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
