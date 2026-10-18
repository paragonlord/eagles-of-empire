--!strict
-- Pooled one-shot visual effects driven by snapshot events (plus a cavalry dust trail read from
-- formation state). Smoke and dust are soft translucent particles (built-in smoke texture, no
-- asset ids) burst from a small round-robin pool of emitter parts; flashes, earth spray and rout
-- markers are short-lived pooled parts. Deaths are drawn by Figures (falling figures).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Settings = require(script.Parent.Settings)
local BattleState = require(script.Parent.BattleState)
local Camera = require(script.Parent.Camera)
local Ground = require(script.Parent.Ground)

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
-- Prevailing breeze: powder smoke drifts this way at ~1.3 studs/s and rises slowly. Drag sets
-- the drift speed (terminal velocity = acceleration / drag), so each kind scales by its drag.
local WIND_DIR = Vector3.new(0.85, 0, 0.52).Unit
local DRIFT = 1.3
local function wind(drag: number, rise: number): Vector3
	return WIND_DIR * DRIFT * drag + Vector3.new(0, rise, 0)
end

-- smoke: musket volley bank · plume: cannon smoke ball · haze: long-lived battle smoke that
-- builds up over a sustained firefight · dust: hooves, feet, routs · spurt: earth thrown up by
-- roundshot grazes and canister
type EmitterKind = "smoke" | "plume" | "haze" | "dust" | "spurt"
local EMITTERS: { [EmitterKind]: number } = { smoke = 10, plume = 4, haze = 3, dust = 6, spurt = 6 }
local emitters: { [EmitterKind]: { { part: Part, pe: ParticleEmitter } } } = { smoke = {}, plume = {}, haze = {}, dust = {}, spurt = {} }
local cursor: { [EmitterKind]: number } = { smoke = 0, plume = 0, haze = 0, dust = 0, spurt = 0 }
local qualityScale = 1

local folder: Folder? = nil
local free: { Part } = {}
local active: { Active } = {}
local queue: { { at: number, fn: () -> () } } = {} -- delayed bursts (rippled volleys, shot flight)
local heat: { [number]: { h: number, t: number } } = {} -- recent volleys per formation
local dustClock = 0
local capacity = 0
local density = 1
local rng = Random.new(1806)

local EARTH = Color3.fromRGB(110, 92, 64)
local FLASH = Color3.fromRGB(255, 214, 120)
local BLAST = Color3.fromRGB(255, 150, 60)
local ROUT = Color3.fromRGB(150, 60, 50)

local groundY = Ground.heightAt -- rendered ground (raycast cache), never the heightmap alone

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

local function seq(points: { { number } }): NumberSequence
	local kps = {}
	for _, pt in points do
		table.insert(kps, NumberSequenceKeypoint.new(pt[1], pt[2]))
	end
	return NumberSequence.new(kps)
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
	pe.RotSpeed = NumberRange.new(-10, 10)
	pe.LightEmission = 0
	pe.LightInfluence = 1
	if kind == "smoke" then
		-- billows a few studs forward off the muzzles, then hangs and drifts downwind
		pe.Drag = 1.4
		pe.Acceleration = wind(1.4, 0.25)
		pe.Lifetime = NumberRange.new(9, 14)
		pe.Speed = NumberRange.new(3, 8)
		pe.SpreadAngle = Vector2.new(22, 8)
		pe.Size = seq({ { 0, 1.4 }, { 0.15, 4.5 }, { 1, 10 } })
		pe.Transparency = seq({ { 0, 0.3 }, { 0.2, 0.45 }, { 0.7, 0.76 }, { 1, 1 } })
		pe.Color = ColorSequence.new(Color3.fromRGB(240, 238, 232), Color3.fromRGB(196, 194, 188))
	elseif kind == "plume" then
		pe.Drag = 1.8
		pe.Acceleration = wind(1.8, 0.35)
		pe.Lifetime = NumberRange.new(11, 17)
		pe.Speed = NumberRange.new(10, 20)
		pe.SpreadAngle = Vector2.new(14, 10)
		pe.Size = seq({ { 0, 2.5 }, { 0.12, 7 }, { 1, 16 } })
		pe.Transparency = seq({ { 0, 0.12 }, { 0.25, 0.4 }, { 0.75, 0.76 }, { 1, 1 } })
		pe.Color = ColorSequence.new(Color3.fromRGB(236, 234, 228), Color3.fromRGB(186, 184, 178))
	elseif kind == "haze" then
		pe.Drag = 0.6
		pe.Acceleration = wind(0.6, 0.06)
		pe.Lifetime = NumberRange.new(30, 45)
		pe.Speed = NumberRange.new(0.3, 1.2)
		pe.SpreadAngle = Vector2.new(70, 70)
		pe.EmissionDirection = Enum.NormalId.Top
		pe.RotSpeed = NumberRange.new(-3, 3)
		pe.Size = seq({ { 0, 9 }, { 1, 24 } })
		pe.Transparency = seq({ { 0, 1 }, { 0.15, 0.8 }, { 0.6, 0.83 }, { 1, 1 } })
		pe.Color = ColorSequence.new(Color3.fromRGB(226, 226, 222))
	elseif kind == "spurt" then
		pe.Drag = 1
		pe.Acceleration = Vector3.new(0, -14, 0)
		pe.Lifetime = NumberRange.new(0.8, 1.4)
		pe.Speed = NumberRange.new(6, 11)
		pe.SpreadAngle = Vector2.new(22, 22)
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Size = seq({ { 0, 0.8 }, { 1, 3.2 } })
		pe.Transparency = seq({ { 0, 0.3 }, { 1, 1 } })
		pe.Color = ColorSequence.new(Color3.fromRGB(150, 128, 92))
	else
		pe.Drag = 0.9
		pe.Acceleration = wind(0.9, 0.3)
		pe.Lifetime = NumberRange.new(1.8, 3.2)
		pe.Speed = NumberRange.new(1, 4)
		pe.SpreadAngle = Vector2.new(60, 60)
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Size = seq({ { 0, 1.5 }, { 1, 6 } })
		pe.Transparency = seq({ { 0, 0.55 }, { 1, 1 } })
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

-- Run `fn` after `delay` seconds (processed in Effects.update).
local function later(delay: number, fn: () -> ())
	if delay <= 0 then
		fn()
	else
		table.insert(queue, { at = os.clock() + delay, fn = fn })
	end
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
	p.Material = if color == FLASH or color == BLAST then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Size = Vector3.new(size0, size0, size0)
	p.Transparency = alpha0
	p.CFrame = CFrame.new(x, y, z)
	p.Parent = folder
	table.insert(active, { part = p, t0 = os.clock(), life = life, size0 = size0, size1 = size1, rise = rise, x = x, y = y, z = z, vx = vx or 0, vz = vz or 0, alpha0 = alpha0 })
end

-- Earth thrown up where a ball grazes or canister strikes.
local function strike(x: number, z: number, n: number, dx: number, dz: number)
	local y = groundY(x, z)
	emit("spurt", CFrame.new(x, y + 0.3, z), Vector3.new(1.5, 0.5, 1.5), n)
	emit("dust", CFrame.new(x, y + 0.5, z), Vector3.new(2.5, 1, 2.5), math.max(1, n // 2))
	spawn(x, y + 0.5, z, EARTH, 0.7, 1.4, 0.7, 3, 0.1, dx * 4, dz * 4)
end

-- A volley ripples down the rank from one flank to the other: a muzzle flash per file and a
-- bank of white powder smoke that billows forward, hangs over the line and drifts downwind.
-- Each volley also feeds the battle haze, and a battalion that keeps firing thickens its own
-- cloud, so a sustained firefight disappears into smoke.
local function volley(ev: any)
	local f = BattleState.formations[ev.id or -1]
	if not f then
		if ev.x then
			local y = groundY(ev.x, ev.z) + 2
			emit("smoke", CFrame.new(ev.x, y, ev.z), Vector3.new(12, 1, 2), 10)
		end
		return
	end
	local now = os.clock()
	local hs = heat[ev.id]
	local h = if hs then hs.h * math.exp(-(now - hs.t) / 30) + 1 else 1
	heat[ev.id] = { h = h, t = now }
	local thick = 1 + math.min(h - 1, 6) * 0.15
	local fwd = Vector3.new(math.cos(f.heading), 0, math.sin(f.heading))
	local rx, rz = -fwd.Z, fwd.X
	local cx = f.x + fwd.X * (f.depth / 2 + 1.5)
	local cz = f.z + fwd.Z * (f.depth / 2 + 1.5)
	local dur = 0.3 + f.width / 120
	local flip = rng:NextNumber() < 0.5
	local function delayAt(t: number): number -- t in [0, 1] across the front
		return (if flip then 1 - t else t) * dur + rng:NextNumber() * 0.05
	end
	local n = count(math.clamp(math.floor(f.width / 1.6), 4, 28))
	for i = 1, n do
		local t = (i - 0.5) / n
		local u = t - 0.5 + (rng:NextNumber() - 0.5) / n
		local px, pz = cx + rx * f.width * u, cz + rz * f.width * u
		later(delayAt(t), function()
			spawn(px, groundY(px, pz) + 1.9, pz, FLASH, 0.9, 0.25, 0.09, 0, 0.05)
		end)
	end
	local k = math.clamp(math.round(f.width / 5), 2, 10)
	local per = math.max(2, math.clamp(f.width * 0.9, 8, 40) * thick / k)
	for j = 1, k do
		local t = (j - 0.5) / k
		local u = t - 0.5
		local origin = Vector3.new(cx + rx * f.width * u, 0, cz + rz * f.width * u)
		origin = Vector3.new(origin.X, groundY(origin.X, origin.Z) + 2.2, origin.Z)
		later(delayAt(t) + 0.03, function()
			emit("smoke", CFrame.lookAt(origin, origin + fwd), Vector3.new(f.width / k, 1.2, 1.2), per)
		end)
	end
	local hx, hz = cx + fwd.X * 5, cz + fwd.Z * 5
	emit("haze", CFrame.new(hx, groundY(hx, hz) + 3, hz) * CFrame.Angles(0, -f.heading, 0), Vector3.new(6, 1, f.width), 1 + thick)
	Camera.shake(0.2)
end

-- Gun fire: a flash and a fireball at the muzzle, a big ball of smoke rolling out ahead of the
-- battery, then the shot: a roundshot grazes short and bounces through the target, each graze
-- kicking up earth; canister sprays a cone of spurts in front of the guns.
local function cannon(ev: any)
	if not ev.x then
		return
	end
	local y = groundY(ev.x, ev.z) + 1.6
	local dx, dz = 1, 0
	local dist = 0
	if ev.tx then
		dist = math.sqrt((ev.tx - ev.x) ^ 2 + (ev.tz - ev.z) ^ 2)
		if dist > 1 then
			dx, dz = (ev.tx - ev.x) / dist, (ev.tz - ev.z) / dist
		end
	end
	spawn(ev.x + dx * 3.5, y, ev.z + dz * 3.5, FLASH, 3.2, 0.6, 0.12, 0, 0.05)
	spawn(ev.x + dx * 5, y + 0.3, ev.z + dz * 5, BLAST, 1.6, 4, 0.22, 0.4, 0.3, dx * 12, dz * 12)
	local muzzle = Vector3.new(ev.x + dx * 4, y + 0.4, ev.z + dz * 4)
	emit("plume", CFrame.lookAt(muzzle, muzzle + Vector3.new(dx, 0.08, dz)), Vector3.new(2, 1.5, 1.5), 18)
	emit("dust", CFrame.new(ev.x, y - 1.2, ev.z), Vector3.new(4, 1, 4), 3) -- blast-scoured ground
	emit("haze", CFrame.new(muzzle + Vector3.new(dx * 8, 1.5, dz * 8)), Vector3.new(6, 1, 6), 1)
	if ev.tx and dist > 1 then
		local px, pz = -dz, dx
		if ev.text == "canister" then
			for _ = 1, count(12) do
				local r = dist * (0.45 + rng:NextNumber() * 0.65)
				local side = (rng:NextNumber() - 0.5) * 0.45 * r
				local x, z = ev.x + dx * r + px * side, ev.z + dz * r + pz * side
				later(r / 350, function()
					strike(x, z, 2, dx, dz)
				end)
			end
		else
			local jitter = (rng:NextNumber() - 0.5) * 4
			for i, frac in { 0.72, 0.88, 1.0, 1.14 } do
				local r = dist * frac
				local x, z = ev.x + dx * r + px * jitter, ev.z + dz * r + pz * jitter
				later(r / 280, function()
					strike(x, z, if i == 1 then 5 else 3, dx, dz)
				end)
			end
		end
	end
	Camera.shake(1.2)
end

-- Dust thrown up behind a charging formation.
local function chargeDust(f: any, n: number)
	local bx = f.x - math.cos(f.heading) * f.depth / 2
	local bz = f.z - math.sin(f.heading) * f.depth / 2
	emit("dust", CFrame.new(bx, groundY(bx, bz) + 0.8, bz) * CFrame.Angles(0, -f.heading, 0), Vector3.new(4, 1, f.width), n)
end

local function charge(ev: any)
	local f = BattleState.formations[ev.id or -1]
	if f then
		chargeDust(f, math.clamp(f.width * 0.5, 6, 20))
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

function Effects.update(dt: number)
	local now = os.clock()
	local q = 1
	while q <= #queue do
		local e = queue[q]
		if now >= e.at then
			queue[q] = queue[#queue]
			queue[#queue] = nil
			e.fn()
		else
			q += 1
		end
	end
	-- galloping horse kicks up a trail of dust for as long as the charge (or the flight) lasts
	dustClock += dt
	if folder and dustClock >= 0.3 then
		dustClock = 0
		for _, f in BattleState.formations do
			if f.class == "cavalry" and (f.state == "charging" or f.state == "routing") then
				chargeDust(f, math.clamp(f.width * 0.3, 3, 10))
			end
		end
	end
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

-- Co-op ping: a banner pole in the sender's slot colour, struck after 6 s.
function Effects.ping(x: number, z: number, colour: Color3)
	local f = folder
	if not f then
		return
	end
	local y = groundY(x, z)
	local pole = makePart()
	pole.Shape = Enum.PartType.Block
	pole.Transparency = 0
	pole.Color = Color3.fromRGB(70, 60, 50)
	pole.Size = Vector3.new(0.4, 18, 0.4)
	pole.CFrame = CFrame.new(x, y + 9, z)
	pole.Parent = f
	local banner = makePart()
	banner.Shape = Enum.PartType.Block
	banner.Transparency = 0
	banner.Material = Enum.Material.Fabric
	banner.Color = colour
	banner.Size = Vector3.new(0.15, 4, 6)
	banner.CFrame = CFrame.new(x, y + 16, z + 3.2)
	banner.Parent = f
	task.delay(6, function()
		pole:Destroy()
		banner:Destroy()
	end)
end

function Effects.clear()
	for _, a in active do
		a.part:Destroy()
	end
	table.clear(active)
	table.clear(queue)
	table.clear(heat)
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
