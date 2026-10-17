--!strict
-- Pooled one-shot visual effects driven by snapshot events only. Smoke and dust are soft
-- translucent particles (built-in smoke texture, no asset ids) burst from a small round-robin
-- pool of emitter parts; flashes, earth spray and rout markers are short-lived pooled parts.

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

-- Part pool for short-lived effects; reduced effects halves it and the particles per event.
local BASE_POOL = { [1] = 40, [2] = 80, [3] = 140 } -- flashes, earth, rout markers only

-- Built-in client texture used by Roblox's own Smoke instance (rbxasset content, not an asset id).
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local WIND = Vector3.new(0.7, 0.35, 0.3) -- drift and a slow rise

type EmitterKind = "smoke" | "plume" | "dust"
local EMITTERS: { [EmitterKind]: number } = { smoke = 10, plume = 4, dust = 6 }
local emitters: { [EmitterKind]: { { part: Part, pe: ParticleEmitter } } } = { smoke = {}, plume = {}, dust = {} }
local cursor: { [EmitterKind]: number } = { smoke = 0, plume = 0, dust = 0 }
local qualityScale = 1

local folder: Folder? = nil
local free: { Part } = {}
local active: { Active } = {}
local capacity = 0
local density = 1
local rng = Random.new(1806)

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

local function makeEmitter(kind: EmitterKind, parent: Instance): { part: Part, pe: ParticleEmitter }
	local part = Instance.new("Part") :: Part
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(4, 1, 1)
	part.Parent = parent
	local pe = Instance.new("ParticleEmitter") :: ParticleEmitter
	pe.Texture = SMOKE_TEXTURE
	pe.Rate = 0
	pe.Enabled = true
	pe.LockedToPart = false
	pe.EmissionDirection = Enum.NormalId.Front
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-12, 12)
	pe.LightEmission = 0
	pe.LightInfluence = 1
	pe.Acceleration = WIND
	pe.Drag = 0.9
	if kind == "smoke" then
		pe.Lifetime = NumberRange.new(4.5, 7)
		pe.Speed = NumberRange.new(1, 3)
		pe.SpreadAngle = Vector2.new(25, 25)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(0.25, 4), NumberSequenceKeypoint.new(1, 7.5) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.3, 0.68), NumberSequenceKeypoint.new(1, 1) })
		pe.Color = ColorSequence.new(Color3.fromRGB(236, 234, 228), Color3.fromRGB(196, 194, 188))
	elseif kind == "plume" then
		pe.Lifetime = NumberRange.new(5.5, 8)
		pe.Speed = NumberRange.new(3, 7)
		pe.SpreadAngle = Vector2.new(18, 18)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(0.25, 6.5), NumberSequenceKeypoint.new(1, 11) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(0.3, 0.62), NumberSequenceKeypoint.new(1, 1) })
		pe.Color = ColorSequence.new(Color3.fromRGB(230, 228, 222), Color3.fromRGB(184, 182, 176))
	else
		pe.Lifetime = NumberRange.new(1.8, 3)
		pe.Speed = NumberRange.new(1, 4)
		pe.SpreadAngle = Vector2.new(60, 60)
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5.5) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		pe.Color = ColorSequence.new(Color3.fromRGB(176, 158, 116))
	end
	pe.Parent = part
	return { part = part, pe = pe }
end

-- Burst `n` particles from a box at `cf` (-Z = emission direction for smoke/plume).
local function emit(kind: EmitterKind, cf: CFrame, size: Vector3, n: number)
	local list = emitters[kind]
	if #list == 0 then
		return
	end
	local i = cursor[kind] % #list + 1
	cursor[kind] = i
	local e = list[i]
	e.part.Size = size
	e.part.CFrame = cf
	e.pe:Emit(math.max(1, math.round(n * density * qualityScale)))
end

function Effects.init()
	if folder then
		return
	end
	local f = Instance.new("Folder") :: Folder
	f.Name = "EoEEffects"
	f.Parent = workspace
	folder = f
	for kind, n in EMITTERS do
		for _ = 1, n do
			table.insert(emitters[kind], makeEmitter(kind, f))
		end
	end
	Effects.applySettings()
end

function Effects.applySettings()
	local s = Settings.get()
	capacity = BASE_POOL[math.clamp(s.quality, 1, 3)]
	qualityScale = ({ 0.6, 1, 1.4 })[math.clamp(s.quality, 1, 3)]
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

-- Flashes along the firing front, then a soft bank of smoke that swells, drifts and fades (~6 s).
local function volley(ev: any)
	local f = BattleState.formations[ev.id or -1]
	if not f then
		if ev.x then
			local y = groundY(ev.x, ev.z) + 2
			emit("smoke", CFrame.new(ev.x, y, ev.z), Vector3.new(12, 1, 2), 10)
		end
		return
	end
	local fwd = Vector3.new(math.cos(f.heading), 0, math.sin(f.heading))
	local rx, rz = -fwd.Z, fwd.X
	local cx = f.x + fwd.X * (f.depth / 2 + 1.5)
	local cz = f.z + fwd.Z * (f.depth / 2 + 1.5)
	local n = count(math.clamp(math.floor(f.width / 3), 3, 14))
	for i = 1, n do
		local t = (i - 0.5) / n - 0.5 + (rng:NextNumber() - 0.5) / n
		local px, pz = cx + rx * f.width * t, cz + rz * f.width * t
		spawn(px, groundY(px, pz) + 1.9, pz, FLASH, 0.8, 0.25, 0.09, 0, 0.1)
	end
	local y = groundY(cx, cz) + 2.2
	local origin = Vector3.new(cx, y, cz)
	emit("smoke", CFrame.lookAt(origin, origin + fwd), Vector3.new(f.width, 1.2, 1.5), math.clamp(f.width * 0.9, 8, 40))
	Camera.shake(0.2)
end

local function cannon(ev: any)
	if not ev.x then
		return
	end
	local y = groundY(ev.x, ev.z) + 1.6
	local dx, dz = 1, 0
	if ev.tx then
		local l = math.sqrt((ev.tx - ev.x) ^ 2 + (ev.tz - ev.z) ^ 2)
		if l > 1 then
			dx, dz = (ev.tx - ev.x) / l, (ev.tz - ev.z) / l
		end
	end
	spawn(ev.x + dx * 3.5, y, ev.z + dz * 3.5, FLASH, 2.2, 0.5, 0.12, 0, 0.1)
	local muzzle = Vector3.new(ev.x + dx * 4, y + 0.4, ev.z + dz * 4)
	emit("plume", CFrame.lookAt(muzzle, muzzle + Vector3.new(dx, 0.1, dz)), Vector3.new(2, 1.5, 1.5), 14)
	if ev.tx then
		-- round shot strikes: a short spray of earth and a dust puff
		local ty = groundY(ev.tx, ev.tz)
		for _ = 1, count(4) do
			spawn(ev.tx + (rng:NextNumber() - 0.5) * 3, ty + 0.5, ev.tz + (rng:NextNumber() - 0.5) * 3, EARTH, 0.8, 1.6, 0.8, 4, 0.1, dx * 3, dz * 3)
		end
		emit("dust", CFrame.new(ev.tx, ty + 0.5, ev.tz), Vector3.new(3, 1, 3), 6)
	end
	Camera.shake(1.2)
end

-- Dust thrown up behind a charging formation.
local function charge(ev: any)
	local f = BattleState.formations[ev.id or -1]
	if f then
		local bx = f.x - math.cos(f.heading) * f.depth / 2
		local bz = f.z - math.sin(f.heading) * f.depth / 2
		emit("dust", CFrame.new(bx, groundY(bx, bz) + 0.8, bz) * CFrame.Angles(0, -f.heading, 0), Vector3.new(4, 1, f.width), math.clamp(f.width * 0.5, 6, 20))
	elseif ev.x then
		emit("dust", CFrame.new(ev.x, groundY(ev.x, ev.z) + 0.8, ev.z), Vector3.new(20, 1, 20), 14)
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
			emit("dust", CFrame.new(ev.x, groundY(ev.x, ev.z) + 0.8, ev.z), Vector3.new(16, 1, 16), 8)
		end
	elseif kind == "charge" then
		charge(ev)
	elseif kind == "rout" then
		if ev.x then
			emit("dust", CFrame.new(ev.x, groundY(ev.x, ev.z) + 0.8, ev.z), Vector3.new(12, 1, 12), 5)
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
	for kind in EMITTERS do
		table.clear(emitters[kind])
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return Effects
