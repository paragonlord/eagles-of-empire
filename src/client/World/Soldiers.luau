--!strict
-- Near-LOD figure builders: NTW-style silhouettes from plain parts (no meshes, no asset ids).
-- Builders call `add(part, localCFrame, anim, pivot)`; Figures parents, places and animates.
-- Local frame: +X forward, +Y up, +Z right; origin on the ground under the figure. ~3.2 studs tall.
--
-- anim codes: 0 static · 1/2 leg (opposite phases, swing about the hip at `pivot`)
--             3 musket chain (lc is an offset along the musket; pose by state)
--             4/5 horse leg (diagonal pairs, swing about the shoulder at `pivot`)
--             6 colour (flag): swings about the colour pole by the per-frame sway angle
--             7/8 shin (follows thigh 1/2, bends at the knee) · 9/10 horse cannon (follows 4/5)
--             11 gun crew: steps clear of the gun while the battery fires (pivot = side, ±1)
--             12/13 left/right arm: hangs or holds the shouldered musket; reaches forward when levelled
--
-- Detail tiers: `detail` false builds the mid tier (coat, breeches, headgear, musket: ~9 parts a
-- man); true builds the near tier for the low camera (jointed limbs, shako peak and scales,
-- bayonet, cartridge box, spoked wheels, horses with neck, mane, tail and shabraque).
--
-- `Soldiers.look` turns a formation (faction, palette override, class, name) into a uniform:
-- coat, facings, legwear, headgear and kit, so a French grenadier, a Prussian musketeer, an
-- Austrian in white and a Highlander read apart at a glance.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Assets = require(Shared.Assets)
local Factions = require(script.Parent.Parent.Factions)

local Soldiers = {}

export type Add = (p: BasePart, cf: CFrame, anim: number, pivot: number) -> ()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local INK = rgb(32, 30, 28)
local SKIN = rgb(214, 180, 140)
local WHITE = rgb(236, 234, 226)
local BREECHES = rgb(230, 226, 214)
local WOOD = rgb(92, 64, 40)
local DARK_WOOD = rgb(64, 46, 32)
local IRON = rgb(44, 42, 40)
local STEEL = rgb(176, 180, 186)
local BRASS = rgb(196, 154, 70)
local BRONZE = rgb(150, 112, 62)
local FUR = rgb(30, 25, 22)
local HIDE = rgb(118, 82, 52)
local GREATCOAT = rgb(176, 168, 150)
local RED = rgb(186, 34, 40)
local GOLD = rgb(205, 168, 62)
local GREEN = rgb(36, 90, 54)
local GREY_COAT = rgb(140, 140, 134)
local HORSES = { rgb(96, 66, 44), rgb(70, 48, 34), rgb(120, 90, 60), rgb(46, 38, 34) }
local GREY_HORSE = rgb(196, 192, 184)
local BLACK_HORSE = rgb(34, 30, 28)

-- Head shapes: shako · bearskin · mitre · stovepipe · kiwer · kaskett · crested · bonnet ·
-- helmet (cuirassier/dragoon, with mane) · busby · czapka · bicorne
export type Look = {
	nation: string,
	kind: string,
	coat: Color3,
	facing: Color3,
	lapels: Color3?, -- plastron on the chest (French white, Prussian red)
	legs: Color3,
	gaiters: Color3?, -- black gaiters below the knee
	belts: Color3,
	pack: Color3,
	head: string,
	headColour: Color3, -- helmet metal, bearskin fur, shako felt
	plume: Color3?, -- tall plume (grenadiers, light infantry); pompons otherwise
	plate: Color3?, -- shako plate
	epaulettes: Color3?,
	cuirass: Color3?,
	pelisse: Color3?,
	pennon: { Color3 }?, -- lancers: top, bottom
	horse: Color3?, -- fixed horse colour (Scots Greys, the Emperor's grey)
	carriage: Color3, -- gun and limber paint
}

type Nation = {
	coat: Color3,
	facing: Color3,
	lapels: Color3?,
	legs: Color3,
	gaiters: Color3?,
	head: string,
	plate: Color3?,
	pack: Color3?,
	artCoat: Color3, -- artillery coat (Austrian brown, British blue)
	artHead: string,
	carriage: Color3,
	cav: Color3, -- default horse-soldier coat
}

local NATIONS: { [string]: Nation } = {
	france = { coat = rgb(32, 58, 150), facing = RED, lapels = WHITE, legs = BREECHES, gaiters = INK, head = "shako", artCoat = rgb(30, 44, 110), artHead = "shako", carriage = rgb(88, 96, 56), cav = rgb(32, 50, 128) },
	prussia = { coat = rgb(20, 24, 42), facing = RED, lapels = RED, legs = rgb(124, 124, 120), head = "shako", artCoat = rgb(20, 24, 42), artHead = "shako", carriage = rgb(92, 106, 120), cav = rgb(226, 222, 210) },
	austria = { coat = rgb(230, 226, 214), facing = rgb(170, 36, 54), legs = BREECHES, gaiters = INK, head = "kaskett", artCoat = rgb(112, 80, 50), artHead = "bicorne", carriage = rgb(194, 156, 66), cav = rgb(226, 222, 210) },
	russia = { coat = rgb(32, 56, 36), facing = RED, legs = BREECHES, gaiters = INK, head = "kiwer", plate = GOLD, artCoat = rgb(32, 56, 36), artHead = "kiwer", carriage = rgb(62, 90, 56), cav = rgb(226, 222, 210) },
	britain = { coat = rgb(178, 30, 34), facing = rgb(226, 204, 150), legs = rgb(86, 88, 96), head = "stovepipe", plate = BRASS, pack = rgb(30, 30, 32), artCoat = rgb(28, 34, 72), artHead = "stovepipe", carriage = rgb(130, 144, 150), cav = rgb(178, 30, 34) },
	saxony = { coat = rgb(232, 228, 216), facing = RED, lapels = RED, legs = BREECHES, gaiters = INK, head = "shako", artCoat = rgb(70, 82, 64), artHead = "shako", carriage = rgb(92, 106, 120), cav = rgb(226, 222, 210) },
	netherlands = { coat = rgb(30, 42, 98), facing = WHITE, legs = rgb(104, 106, 112), head = "shako", artCoat = rgb(30, 42, 98), artHead = "shako", carriage = rgb(120, 112, 88), cav = rgb(30, 42, 98) },
	bavaria = { coat = rgb(86, 122, 196), facing = RED, legs = BREECHES, gaiters = INK, head = "crested", artCoat = rgb(40, 40, 46), artHead = "crested", carriage = rgb(92, 106, 120), cav = rgb(36, 82, 50) },
}

-- French hussar regiments by number: dolman, pelisse.
local FR_HUSSARS: { [number]: { Color3 } } = {
	[1] = { rgb(120, 170, 214), rgb(120, 170, 214) },
	[2] = { rgb(112, 72, 44), rgb(112, 72, 44) },
	[3] = { rgb(150, 152, 156), rgb(150, 152, 156) },
	[4] = { rgb(30, 44, 110), RED },
	[5] = { rgb(120, 170, 214), WHITE },
	[6] = { RED, rgb(30, 44, 110) },
	[7] = { GREEN, GREEN },
	[8] = { GREEN, GREEN },
	[9] = { RED, rgb(120, 170, 214) },
	[10] = { rgb(120, 170, 214), rgb(120, 170, 214) },
}

local function has(n: string, ...: string): boolean
	for _, k in { ... } do
		if string.find(n, k, 1, true) then
			return true
		end
	end
	return false
end

-- Uniform for a formation. `override` is the unit's palette key ("Austria" in a Russian army).
function Soldiers.look(faction: string, override: string?, class: string, name: string?): Look
	local nation = if override then string.lower(override) else faction
	local N = NATIONS[nation] or NATIONS[faction] or NATIONS.france
	local n = string.lower(name or "")
	local L: Look = {
		nation = nation,
		kind = "line",
		coat = N.coat,
		facing = N.facing,
		lapels = N.lapels,
		legs = N.legs,
		gaiters = N.gaiters,
		belts = WHITE,
		pack = N.pack or HIDE,
		head = N.head,
		headColour = INK,
		plume = nil,
		plate = N.plate,
		epaulettes = nil,
		cuirass = nil,
		pelisse = nil,
		pennon = nil,
		horse = nil,
		carriage = N.carriage,
	}
	if class == "infantry" then
		if has(n, "highland", "black watch") then
			L.kind, L.legs, L.gaiters, L.head = "highland", rgb(30, 46, 38), nil, "bonnet"
		elseif has(n, "rifles") then
			L.kind, L.coat, L.facing, L.legs, L.belts, L.lapels = "rifles", rgb(30, 52, 36), INK, rgb(30, 52, 36), INK, nil
		elseif has(n, "jäger", "jager", "jaeger", "füsilier", "fusilier-bataillon") then
			L.kind, L.coat, L.lapels = "jaeger", rgb(34, 64, 42), nil
		elseif has(n, "light") then
			L.kind, L.epaulettes = "light", if nation == "britain" then nil else GREEN
		elseif has(n, "légère", "legere", "léger") then
			L.kind, L.lapels, L.legs, L.epaulettes, L.plume = "light", L.coat, L.coat, GREEN, GREEN
		elseif nation == "france" and has(n, "garde") then
			L.kind, L.head, L.headColour, L.epaulettes, L.plume = "guard", "bearskin", FUR, RED, RED
		elseif has(n, "grenad") or (nation == "russia" and has(n, "guards")) then
			L.kind, L.epaulettes, L.plume = "grenadier", RED, RED
			if nation == "austria" then
				L.head, L.headColour = "bearskin", FUR
			elseif nation == "prussia" or nation == "russia" then
				L.head, L.headColour = "mitre", BRASS
			end
		end
	elseif class == "cavalry" then
		L.kind, L.coat, L.head, L.legs = "trooper", N.cav, "shako", if nation == "france" then BREECHES else L.legs
		if has(n, "carabin") then
			L.kind, L.coat, L.head, L.headColour, L.cuirass, L.plume = "carabinier", rgb(234, 232, 224), "helmet", BRASS, BRASS, RED
		elseif has(n, "cuirass", "kürass", "kurass", "garde du corps", "gensd", "chevalier", "guard horse") then
			L.kind, L.head, L.headColour, L.cuirass = "cuirassier", "helmet", STEEL, STEEL
			if nation ~= "france" then
				L.coat = rgb(230, 226, 214)
			end
		elseif has(n, "life guards") then
			L.kind, L.head, L.headColour = "lifeguard", "helmet", STEEL
		elseif has(n, "greys") then
			L.kind, L.head, L.headColour, L.horse = "greys", "bearskin", FUR, GREY_HORSE
		elseif has(n, "grenadiers à cheval", "grenadiers a cheval") then
			L.kind, L.coat, L.head, L.headColour, L.horse, L.epaulettes = "guardgren", rgb(30, 44, 110), "bearskin", FUR, BLACK_HORSE, RED
		elseif has(n, "dragon", "dragoner", "dragoon") then
			L.kind, L.head, L.headColour = "dragoon", "helmet", BRASS
			L.coat = if nation == "france" then GREEN elseif nation == "prussia" then rgb(118, 158, 206) elseif nation == "britain" then rgb(178, 30, 34) else L.coat
			if has(n, "light dragoon") then
				L.kind, L.coat, L.head, L.headColour = "trooper", rgb(30, 40, 92), "shako", INK
			end
		elseif has(n, "hussar", "husar", "hussard") then
			L.kind, L.head, L.headColour = "hussar", if nation == "prussia" then "shako" else "busby", FUR
			local num = tonumber(string.match(n, "^(%d+)"))
			local fr = if nation == "france" and num then FR_HUSSARS[num] else nil
			if fr then
				L.coat, L.pelisse = fr[1], fr[2]
			elseif has(n, "blücher", "blucher") then
				L.coat, L.pelisse = RED, rgb(28, 34, 70)
			elseif has(n, "pavlograd") then
				L.coat, L.pelisse = GREEN, GREEN
			elseif has(n, "elisabethgrad") then
				L.coat, L.pelisse = rgb(150, 152, 156), rgb(150, 152, 156)
			elseif nation == "austria" then
				L.coat, L.pelisse = rgb(120, 170, 214), rgb(30, 44, 110)
			elseif nation == "prussia" then
				L.coat, L.pelisse = rgb(30, 30, 34), rgb(30, 30, 34)
			else
				L.coat, L.pelisse = rgb(30, 44, 110), rgb(30, 44, 110)
			end
		elseif has(n, "lancier", "lancer", "uhlan", "ulan") then
			L.kind, L.head, L.headColour = "lancer", "czapka", INK
			L.coat = if nation == "france" then GREEN else rgb(30, 44, 110)
			L.pennon = if nation == "france" then { RED, WHITE } else { WHITE, RED }
		elseif has(n, "chasseurs à cheval", "chasseurs a cheval") then
			L.kind, L.coat = "chasseur", GREEN
		elseif has(n, "chevauleger", "chevau-léger") then
			L.kind, L.coat, L.head = "chevauleger", rgb(40, 74, 50), "crested"
		end
	elseif class == "hq" then
		L.kind, L.head, L.plume = "officer", "bicorne", WHITE
		if has(n, "napol") then
			L.kind, L.coat, L.horse, L.plume = "emperor", GREY_COAT, GREY_HORSE, nil
		end
	elseif class == "artillery" then
		L.kind, L.coat, L.head, L.lapels = "gunner", N.artCoat, N.artHead, nil
	end
	return L
end

-- Musket poses: shouldered (slanted at the right shoulder) and levelled (firing / charging).
local SHOULDER = CFrame.new(0.02, 1.95, 0.4) * CFrame.Angles(0, 0, math.rad(8))
local LEVEL = CFrame.new(0.75, 1.85, 0.22) * CFrame.Angles(0, 0, math.rad(-90))
-- The colour pole's foot in the bearer's frame; flag parts swing about its vertical axis.
local POLE = Vector3.new(0.05, 0, 0.35)
-- Arm frames at the shoulder (near tier). Rest: the left arm hangs, the right holds the butt
-- of the shouldered musket; levelled: both reach forward along the piece.
local ARM_L_REST = CFrame.new(0.02, 2.08, -0.44) * CFrame.Angles(0, 0, math.rad(8))
local ARM_R_REST = CFrame.new(0.02, 2.08, 0.44) * CFrame.Angles(0, 0, math.rad(-6))
local ARM_L_LEVEL = CFrame.new(0.02, 2.08, -0.4) * CFrame.Angles(0, math.rad(-20), math.rad(78))
local ARM_R_LEVEL = CFrame.new(0.02, 2.08, 0.4) * CFrame.Angles(0, 0, math.rad(62))
-- Reloading: the musket stands upright in front, butt on the ground, the left hand on the barrel
-- and the right working the ramrod; the last part of the cycle it is levelled and fired.
local RAM = CFrame.new(0.55, 0.9, 0.12) * CFrame.Angles(0, 0, math.rad(6)) -- the middle of the musket; its butt is on the ground
local ARM_L_RAM = CFrame.new(0.02, 2.08, -0.4) * CFrame.Angles(0, math.rad(-10), math.rad(38))
local RAMMING = 0.75 -- share of the reload cycle spent loading
local THRUST = 0.35 -- studs a bayonet thrust drives forward

local function mk(size: Vector3, color: Color3, className: string?): BasePart
	local p = Instance.new(className or "Part") :: BasePart
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function ball(d: number, color: Color3): BasePart
	local p = mk(Vector3.new(d, d, d), color) :: Part
	p.Shape = Enum.PartType.Ball
	return p
end

-- Cylinder whose axis is local X (Roblox default); callers rotate as needed.
local function cyl(length: number, radius: number, color: Color3): BasePart
	local p = mk(Vector3.new(length, radius * 2, radius * 2), color) :: Part
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function metal(p: BasePart): BasePart
	p.Material = Enum.Material.Metal
	return p
end

local function fabric(p: BasePart): BasePart
	p.Material = Enum.Material.Fabric
	return p
end

-- A Creator Store mesh in an Assets slot, as one Part carrying a SpecialMesh, or nil when
-- the slot is empty (the procedural build is used instead). `size` is the figure's extent in
-- studs; the slot's scale/offset are set by the Studio session for that mesh.
local function meshed(key: string, size: Vector3, colour: Color3): BasePart?
	local slot = Assets.get(key)
	if not slot then
		return nil
	end
	local p = mk(size, colour)
	p.Transparency = 1 -- the Part is only the carrier; the mesh draws
	local m = Instance.new("SpecialMesh") :: SpecialMesh
	m.MeshType = Enum.MeshType.FileMesh
	m.MeshId = slot.mesh
	m.TextureId = slot.texture
	m.Scale = Vector3.new(slot.scale[1], slot.scale[2], slot.scale[3])
	m.Offset = Vector3.new(slot.offset[1], slot.offset[2], slot.offset[3])
	if slot.texture == "" then
		m.VertexColor = Vector3.new(colour.R, colour.G, colour.B)
	end
	m.Parent = p
	return p
end

-- ------------------------------------------------------------------ generated kits

-- A kit piece as a part carrying its mesh, cloned from one template per piece.
local templates: { [Assets.Piece]: BasePart } = {}
local function piece(p: Assets.Piece): BasePart
	local t = templates[p]
	if not t then
		local part = mk(Vector3.new(p.size[1], p.size[2], p.size[3]), Color3.new(1, 1, 1))
		local m = Instance.new("SpecialMesh") :: SpecialMesh
		m.MeshType = Enum.MeshType.FileMesh
		m.MeshId = p.mesh
		m.TextureId = p.texture
		m.Scale = Vector3.new(p.scale[1], p.scale[2], p.scale[3])
		m.Parent = part
		templates[p] = part
		t = part
	end
	return (t :: BasePart):Clone() :: BasePart
end

local function at(p: Assets.Piece): CFrame
	local c = p.cf
	return CFrame.new(c[1], c[2], c[3]) * CFrame.Angles(c[4], c[5], c[6])
end

-- The kit figure's shoulders stand this much above the part-built one's: arm and musket poses
-- turn about the kit's own shoulder (partCFrame's `pivot` for anims 3, 12, 13).
local KIT_LIFT = 0.42
-- The kit musket is longer than the part-built one; it is held this far toward the muzzle from
-- its middle, so the butt sits at the hip shouldered and in the shoulder levelled.
local KIT_GRIP = 0.72

-- Pose for an animated part. swing in radians (anim 6: the flag's sway angle); armed = muskets
-- levelled. act = "reload" (firing infantry) or "thrust" (infantry in melee), at t in [0, 1) of
-- each man's own cycle, moves the musket and arms (3, 12, 13).
function Soldiers.partCFrame(anim: number, lc: CFrame, pivot: number, swing: number, armed: boolean, act: string?, t: number?): CFrame
	if pivot ~= 0 and (anim == 3 or anim == 12 or anim == 13) then
		-- a kit's musket stands on its butt while ramming, so only the hands are lifted then
		local grounded = anim == 3 and act == "reload" and (t or 0) < RAMMING
		return CFrame.new(0, if grounded then 0 else pivot, 0) * Soldiers.partCFrame(anim, lc, 0, swing, armed, act, t)
	end
	local phase = t or 0
	if act == "reload" and phase < RAMMING then
		if anim == 3 then
			return RAM * lc
		elseif anim == 12 then
			return ARM_L_RAM * lc
		elseif anim == 13 then
			local stroke = 0.5 + 0.5 * math.sin(phase * math.pi * 2 * 4) -- four strokes of the ramrod
			return CFrame.new(0.02, 2.08, 0.4) * CFrame.Angles(0, 0, math.rad(15 + 45 * stroke)) * lc
		end
	elseif act == "thrust" and (anim == 3 or anim == 12 or anim == 13) then
		local drive = CFrame.new(THRUST * math.max(0, math.sin(phase * math.pi * 2)), 0, 0)
		local held = if anim == 3 then LEVEL elseif anim == 12 then ARM_L_LEVEL else ARM_R_LEVEL
		return drive * held * lc
	end
	if anim == 1 or anim == 2 or anim == 4 or anim == 5 then
		if swing == 0 then
			return lc
		end
		local a = if anim == 1 or anim == 4 then swing else -swing
		local p = lc.Position
		return CFrame.new(p.X, pivot, p.Z) * CFrame.Angles(0, 0, a) * CFrame.new(0, p.Y - pivot, 0) * lc.Rotation
	elseif anim == 3 then
		return (if armed then LEVEL else SHOULDER) * lc
	elseif anim == 6 then
		return CFrame.new(POLE) * CFrame.Angles(0, swing, 0) * CFrame.new(-POLE) * lc
	elseif anim == 7 or anim == 8 or anim == 9 or anim == 10 then
		-- lower leg: hip/shoulder swing, then the knee bends as the leg comes forward
		local a = if anim == 7 or anim == 9 then swing else -swing
		local kneeY = pivot * 0.5
		local p = lc.Position
		local bend = 0.9 * math.max(0, -a)
		return CFrame.new(p.X, pivot, p.Z) * CFrame.Angles(0, 0, a) * CFrame.new(0, kneeY - pivot, 0) * CFrame.Angles(0, 0, bend) * CFrame.new(0, p.Y - kneeY, 0)
	elseif anim == 11 then
		return if armed then CFrame.new(-0.5, 0, pivot * 0.7) * lc else lc
	elseif anim == 12 then
		return (if armed then ARM_L_LEVEL else ARM_L_REST) * lc
	elseif anim == 13 then
		return (if armed then ARM_R_LEVEL else ARM_R_REST) * lc
	end
	return lc
end

-- ------------------------------------------------------------------ headgear

-- French fusilier company pompons (1806 regulation colours), picked per figure.
local POMPONS = { rgb(40, 120, 60), rgb(120, 170, 214), rgb(220, 130, 40), rgb(120, 60, 140) }

-- `at`: top of the head, facing +X.
local HEAD_MESH: { [string]: string } = { shako = "shako", bearskin = "bearskin", helmet = "helmet" }

local function headgear(add: Add, L: Look, at: CFrame, detail: boolean, seed: number)
	local h = L.head
	local c = L.headColour
	local hm = meshed(HEAD_MESH[h] or "", Vector3.new(0.5, 0.6, 0.5), L.headColour)
	if hm then
		add(hm, at * CFrame.new(0, 0.28, 0), 0, 0)
		return
	end
	local function put(p: BasePart, x: number, y: number, z: number, rot: CFrame?)
		add(p, at * CFrame.new(x, y, z) * (rot or CFrame.identity), 0, 0)
	end
	local function plumeOr(side: number, topY: number)
		if not detail then
			return
		end
		if L.plume then
			put(mk(Vector3.new(0.08, 0.32, 0.08), L.plume), 0.12, topY + 0.14, side, nil)
		elseif L.nation == "france" and L.kind == "line" then
			put(ball(0.15, POMPONS[seed // 6 % #POMPONS + 1]), 0.16, topY + 0.04, 0, nil)
		else
			put(ball(0.14, WHITE), 0.16, topY + 0.04, 0, nil)
		end
	end
	if h == "bearskin" or h == "bonnet" then
		put(mk(Vector3.new(0.5, 0.74, 0.48), FUR), 0, 0.33, 0, nil)
		if detail then
			put(mk(Vector3.new(0.08, 0.38, 0.08), L.plume or WHITE), 0.02, 0.62, if h == "bonnet" then 0.24 else -0.24, nil)
		end
	elseif h == "mitre" then
		put(mk(Vector3.new(0.36, 0.5, 0.4), RED), -0.04, 0.22, 0, nil)
		put(metal(mk(Vector3.new(0.06, 0.62, 0.42), c)), 0.18, 0.28, 0, nil)
	elseif h == "stovepipe" then
		put(mk(Vector3.new(0.4, 0.62, 0.4), INK), 0, 0.28, 0, nil)
		if detail then
			put(metal(mk(Vector3.new(0.04, 0.2, 0.18), L.plate or BRASS)), 0.21, 0.32, 0, nil)
			put(ball(0.14, WHITE), 0.14, 0.64, 0, nil)
		end
	elseif h == "kiwer" then
		put(mk(Vector3.new(0.42, 0.44, 0.42), INK), 0, 0.2, 0, nil)
		put(mk(Vector3.new(0.56, 0.08, 0.56), INK), 0, 0.44, 0, nil)
		if detail then
			put(metal(mk(Vector3.new(0.05, 0.18, 0.2), L.plate or GOLD)), 0.22, 0.2, 0, nil)
		end
	elseif h == "kaskett" then
		put(mk(Vector3.new(0.44, 0.36, 0.44), INK), -0.02, 0.17, 0, nil)
		put(mk(Vector3.new(0.06, 0.52, 0.44), INK), 0.2, 0.3, 0, nil) -- tall front plate
		if detail then
			put(metal(mk(Vector3.new(0.02, 0.12, 0.3), BRASS)), 0.24, 0.5, 0, nil)
		end
	elseif h == "crested" then
		put(mk(Vector3.new(0.44, 0.34, 0.44), INK), 0, 0.16, 0, nil)
		put(mk(Vector3.new(0.52, 0.22, 0.16), FUR), -0.02, 0.4, 0, nil)
	elseif h == "helmet" then
		put(metal(ball(0.5, c)), 0, 0.08, 0, nil)
		put(metal(mk(Vector3.new(0.56, 0.16, 0.08), if c == STEEL then BRASS else c)), -0.02, 0.36, 0, nil)
		if detail then
			put(mk(Vector3.new(0.08, 0.62, 0.12), if L.kind == "carabinier" then RED else FUR), -0.3, 0.02, 0, CFrame.Angles(0, 0, math.rad(-12))) -- mane
		end
	elseif h == "busby" then
		put(mk(Vector3.new(0.44, 0.5, 0.44), FUR), 0, 0.23, 0, nil)
		if detail then
			put(mk(Vector3.new(0.12, 0.34, 0.1), L.pelisse or RED), -0.18, 0.3, 0.2, CFrame.Angles(math.rad(25), 0, 0)) -- bag
		end
	elseif h == "czapka" then
		put(mk(Vector3.new(0.38, 0.3, 0.38), INK), 0, 0.14, 0, nil)
		put(mk(Vector3.new(0.48, 0.12, 0.48), L.facing), 0, 0.34, 0, CFrame.Angles(0, math.rad(45), 0))
	elseif h == "bicorne" then
		put(mk(Vector3.new(0.32, 0.3, 0.98), INK), 0, 0.14, 0, nil)
		if detail and L.plume then
			put(mk(Vector3.new(0.3, 0.08, 0.6), L.plume), 0, 0.31, 0, nil)
		end
	else -- shako
		put(mk(Vector3.new(0.42, 0.48, 0.42), INK), 0, 0.22, 0, nil)
		plumeOr(0, 0.46)
	end
end

-- ------------------------------------------------------------------ flag

-- Flag in the local X-Y plane, hoist at x = 0, flying toward -X. `anim` tags every part
-- (6 makes the colour-bearer's flag sway about the pole).
function Soldiers.flag(add: Add, faction: string, origin: CFrame, w: number, h: number, anim: number?)
	local design = Factions.flag(faction) :: any
	local an = anim or 0
	local function put(p: BasePart, cf: CFrame)
		add(fabric(p), cf, an, 0)
	end
	local c = origin * CFrame.new(-w / 2, 0, 0)
	local t = 0.08
	local stripes = design.stripes
	if stripes then
		-- horizontal bands, top to bottom (Prussia black-white-black); no mark
		local n = #stripes
		for i, col in stripes do
			put(mk(Vector3.new(w, h / n, 0.05), col), c * CFrame.new(0, h / 2 - (i - 0.5) * h / n, 0))
		end
		return
	end
	local bands = design.bands
	if bands then
		local n = #bands
		for i, col in bands do
			put(mk(Vector3.new(w / n, h, 0.05), col), origin * CFrame.new(-(i - 0.5) * w / n, 0, 0))
		end
	else
		put(mk(Vector3.new(w, h, 0.05), design.field or WHITE), c)
	end
	local mc: Color3 = design.markColour
	local diag = math.deg(math.atan2(h, w))
	if design.mark == "diamond" then
		put(mk(Vector3.new(h * 0.32, h * 0.32, t), mc), c * CFrame.Angles(0, 0, math.rad(45)))
	elseif design.mark == "x" then
		-- saltire corner to corner
		local len = math.sqrt(w * w + h * h)
		for _, a in { diag, -diag } do
			put(mk(Vector3.new(len, h * 0.16, t), mc), c * CFrame.Angles(0, 0, math.rad(a)))
		end
	elseif design.mark == "plus" then
		put(mk(Vector3.new(w, h * 0.16, t), mc), c)
		put(mk(Vector3.new(w * 0.12, h, t), mc), c)
	elseif design.mark == "double" then
		put(mk(Vector3.new(w, h * 0.1, t), mc), c * CFrame.new(0, h * 0.18, 0))
		put(mk(Vector3.new(w, h * 0.1, t), mc), c * CFrame.new(0, -h * 0.18, 0))
	elseif design.mark == "diagonal" then
		put(mk(Vector3.new(math.sqrt(w * w + h * h), h * 0.12, t), mc), c * CFrame.Angles(0, 0, math.rad(diag)))
	end
	local cross: Color3? = design.cross
	if cross then
		-- upright cross over the saltire (Union flag): a white edge under a red centre
		put(mk(Vector3.new(w, h * 0.26, t + 0.01), WHITE), c)
		put(mk(Vector3.new(w * 0.18, h, t + 0.01), WHITE), c)
		put(mk(Vector3.new(w, h * 0.15, t + 0.02), cross), c)
		put(mk(Vector3.new(w * 0.1, h, t + 0.02), cross), c)
	end
end

-- ------------------------------------------------------------------ near tier

local function wedge(size: Vector3, color: Color3): BasePart
	return mk(size, color, "WedgePart")
end

-- Near-tier headgear: shako with peak, chin scales and plate; helmets with comb and mane;
-- bearskins with cords and plume. `at`: top of the head, facing +X.
local function headgearNear(add: Add, L: Look, at: CFrame, seed: number)
	local h = L.head
	local hm = meshed(HEAD_MESH[h] or "", Vector3.new(0.5, 0.6, 0.5), L.headColour)
	if hm then
		add(hm, at * CFrame.new(0, 0.28, 0), 0, 0)
		return
	end
	local function put(p: BasePart, x: number, y: number, z: number, rot: CFrame?)
		add(p, at * CFrame.new(x, y, z) * (rot or CFrame.identity), 0, 0)
	end
	local function peakAndScales(y: number, w: number)
		put(mk(Vector3.new(0.24, 0.03, w * 0.9), INK), 0.3, y, 0, CFrame.Angles(0, 0, math.rad(-14))) -- peak
		put(metal(mk(Vector3.new(w + 0.04, 0.05, w + 0.04), BRASS)), 0, y + 0.03, 0, nil) -- chin scales / band
	end
	if h == "bearskin" or h == "bonnet" then
		put(mk(Vector3.new(0.5, 0.78, 0.5), FUR), 0, 0.35, 0, nil)
		put(mk(Vector3.new(0.06, 0.16, 0.5), L.facing), 0.24, 0.5, 0, nil) -- front patch / band
		put(mk(Vector3.new(0.08, 0.44, 0.08), L.plume or WHITE), 0.02, 0.7, if h == "bonnet" then 0.25 else -0.25, nil)
		if h == "bearskin" then
			put(mk(Vector3.new(0.5, 0.03, 0.03), WHITE), 0, 0.2, 0, CFrame.Angles(math.rad(-25), 0, 0)) -- cords
		end
	elseif h == "mitre" then
		put(mk(Vector3.new(0.34, 0.54, 0.4), RED), -0.04, 0.24, 0, nil)
		put(metal(mk(Vector3.new(0.06, 0.66, 0.42), BRASS)), 0.18, 0.3, 0, nil)
		put(ball(0.12, WHITE), -0.04, 0.54, 0, nil)
	elseif h == "stovepipe" then
		put(mk(Vector3.new(0.4, 0.64, 0.4), INK), 0, 0.29, 0, nil)
		peakAndScales(0, 0.4)
		put(metal(mk(Vector3.new(0.04, 0.22, 0.18), L.plate or BRASS)), 0.21, 0.32, 0, nil)
		put(mk(Vector3.new(0.08, 0.22, 0.08), WHITE), 0.1, 0.68, 0, nil) -- tuft
	elseif h == "kiwer" then
		put(mk(Vector3.new(0.42, 0.46, 0.42), INK), 0, 0.21, 0, nil)
		put(mk(Vector3.new(0.58, 0.08, 0.58), INK), 0, 0.46, 0, nil)
		peakAndScales(0, 0.42)
		put(metal(mk(Vector3.new(0.05, 0.2, 0.22), L.plate or GOLD)), 0.22, 0.2, 0, nil)
		put(ball(0.14, L.plume or WHITE), 0.16, 0.56, 0, nil)
	elseif h == "kaskett" then
		put(mk(Vector3.new(0.44, 0.36, 0.44), INK), -0.02, 0.17, 0, nil)
		put(mk(Vector3.new(0.06, 0.56, 0.44), INK), 0.2, 0.32, 0, nil)
		put(metal(mk(Vector3.new(0.02, 0.14, 0.3), BRASS)), 0.24, 0.52, 0, nil)
		put(mk(Vector3.new(0.3, 0.03, 0.44), INK), 0.3, 0.0, 0, CFrame.Angles(0, 0, math.rad(-12)))
	elseif h == "crested" then
		put(mk(Vector3.new(0.44, 0.34, 0.44), INK), 0, 0.16, 0, nil)
		put(mk(Vector3.new(0.56, 0.26, 0.14), FUR), -0.02, 0.44, 0, nil)
		peakAndScales(0, 0.44)
	elseif h == "helmet" then
		local c = L.headColour
		put(metal(ball(0.52, c)), 0, 0.08, 0, nil)
		put(metal(mk(Vector3.new(0.3, 0.03, 0.4), c)), 0.3, -0.02, 0, CFrame.Angles(0, 0, math.rad(-14))) -- peak
		put(metal(mk(Vector3.new(0.58, 0.2, 0.08), if c == STEEL then BRASS else c)), -0.02, 0.36, 0, nil) -- comb
		put(mk(Vector3.new(0.1, 0.72, 0.12), if L.kind == "carabinier" then RED else FUR), -0.34, 0.0, 0, CFrame.Angles(0, 0, math.rad(-14))) -- mane
		put(metal(mk(Vector3.new(0.46, 0.04, 0.5), BRASS)), 0, -0.1, 0, nil) -- chin scales
		if L.plume then
			put(mk(Vector3.new(0.08, 0.5, 0.08), L.plume), 0.1, 0.52, -0.18, nil)
		end
	elseif h == "busby" then
		put(mk(Vector3.new(0.46, 0.52, 0.46), FUR), 0, 0.24, 0, nil)
		put(mk(Vector3.new(0.14, 0.4, 0.12), L.pelisse or RED), -0.2, 0.3, 0.22, CFrame.Angles(math.rad(28), 0, 0)) -- bag
		put(mk(Vector3.new(0.08, 0.46, 0.08), L.plume or WHITE), 0.12, 0.66, 0, nil)
		put(metal(mk(Vector3.new(0.48, 0.03, 0.03), BRASS)), 0, 0.02, 0, nil) -- chin chain
	elseif h == "czapka" then
		put(mk(Vector3.new(0.38, 0.3, 0.38), INK), 0, 0.14, 0, nil)
		put(mk(Vector3.new(0.5, 0.14, 0.5), L.facing), 0, 0.36, 0, CFrame.Angles(0, math.rad(45), 0))
		peakAndScales(0, 0.38)
		put(mk(Vector3.new(0.08, 0.4, 0.08), WHITE), 0.08, 0.6, -0.18, nil)
	elseif h == "bicorne" then
		put(mk(Vector3.new(0.3, 0.32, 1.0), INK), 0, 0.15, 0, nil)
		put(mk(Vector3.new(0.34, 0.18, 0.22), INK), 0, 0.18, 0, nil)
		put(mk(Vector3.new(0.32, 0.08, 0.64), L.plume or INK), 0, 0.34, 0, nil)
		put(metal(mk(Vector3.new(0.03, 0.14, 0.14), GOLD)), 0.16, 0.2, 0.05, nil) -- cockade
	else -- shako
		put(mk(Vector3.new(0.42, 0.5, 0.44), INK), 0, 0.23, 0, nil)
		peakAndScales(0, 0.42)
		put(metal(mk(Vector3.new(0.03, 0.2, 0.18), L.plate or BRASS)), 0.22, 0.26, 0, nil) -- plate
		put(mk(Vector3.new(0.44, 0.03, 0.03), WHITE), 0, 0.42, 0, CFrame.Angles(math.rad(-20), 0, 0)) -- cords
		if L.plume then
			put(mk(Vector3.new(0.08, 0.44, 0.08), L.plume), 0.12, 0.66, 0, nil)
		elseif L.nation == "france" and L.kind == "line" then
			put(ball(0.15, POMPONS[seed // 6 % #POMPONS + 1]), 0.16, 0.54, 0, nil)
		else
			put(ball(0.14, WHITE), 0.16, 0.54, 0, nil)
		end
	end
end

-- Jointed legs: thigh (anim 1/2) and shin + shoe (anim 7/8) per side, hip at 1.1.
local function legsNear(add: Add, L: Look)
	for i, z in { -0.16, 0.16 } do
		add(mk(Vector3.new(0.3, 0.52, 0.27), L.legs), CFrame.new(0, 0.84, z), i, 1.1)
		add(mk(Vector3.new(0.26, 0.5, 0.24), L.gaiters or L.legs), CFrame.new(0.01, 0.31, z), i + 6, 1.1)
		add(mk(Vector3.new(0.4, 0.1, 0.24), INK), CFrame.new(0.07, 0.05, z), i + 6, 1.1)
	end
end

-- Arms with bent elbows: upper arm, forearm (cuff colour) and hand, posed by anim 12/13.
local function armsNear(add: Add, L: Look)
	-- left: hangs, forearm a little forward (rest), reaches along the musket (levelled)
	add(mk(Vector3.new(0.2, 0.5, 0.2), L.coat), CFrame.new(0, -0.27, 0), 12, 0)
	add(mk(Vector3.new(0.18, 0.46, 0.18), L.facing), CFrame.new(0.12, -0.7, 0) * CFrame.Angles(0, 0, math.rad(-28)), 12, 0)
	add(ball(0.17, SKIN), CFrame.new(0.26, -0.9, 0), 12, 0)
	-- right: elbow bent to hold the butt at the hip (rest), trigger hand forward (levelled)
	add(mk(Vector3.new(0.2, 0.5, 0.2), L.coat), CFrame.new(0, -0.27, 0), 13, 0)
	add(mk(Vector3.new(0.18, 0.46, 0.18), L.facing), CFrame.new(0.2, -0.6, 0) * CFrame.Angles(0, 0, math.rad(-70)), 13, 0)
	add(ball(0.17, SKIN), CFrame.new(0.42, -0.62, 0), 13, 0)
end

-- Musket with lock, barrel and bayonet, all on the musket chain (anim 3).
local function musketNear(add: Add)
	add(mk(Vector3.new(0.09, 1.7, 0.09), WOOD), CFrame.new(), 3, 0)
	add(metal(mk(Vector3.new(0.05, 1.2, 0.05), STEEL)), CFrame.new(0.03, 0.4, 0), 3, 0)
	add(metal(mk(Vector3.new(0.03, 0.5, 0.03), STEEL)), CFrame.new(0.04, 1.1, 0), 3, 0) -- bayonet
	add(metal(mk(Vector3.new(0.06, 0.14, 0.04), BRASS)), CFrame.new(0, -0.3, 0.05), 3, 0) -- lock
end

local function infantryNear(add: Add, L: Look, role: InfantryRole, seed: number)
	legsNear(add, L)
	-- torso: chest wider at the shoulders, waist, coat tails behind
	add(mk(Vector3.new(0.46, 0.62, 0.74), L.coat), CFrame.new(0, 1.84, 0), 0, 0)
	add(mk(Vector3.new(0.4, 0.46, 0.6), L.coat), CFrame.new(0, 1.32, 0), 0, 0)
	add(wedge(Vector3.new(0.3, 0.6, 0.52), L.coat), CFrame.new(-0.28, 1.0, 0) * CFrame.Angles(0, math.pi, 0), 0, 0) -- tails
	add(mk(Vector3.new(0.04, 0.2, 0.5), L.facing), CFrame.new(-0.4, 0.78, 0), 0, 0) -- turnbacks
	add(mk(Vector3.new(0.48, 0.14, 0.64), L.facing), CFrame.new(0, 2.14, 0), 0, 0) -- collar
	local lapels = L.lapels
	if lapels and lapels ~= L.coat then
		add(mk(Vector3.new(0.04, 0.58, 0.38), lapels), CFrame.new(0.25, 1.86, 0), 0, 0)
	end
	local ep = L.epaulettes
	if ep then
		add(mk(Vector3.new(0.22, 0.09, 0.2), ep), CFrame.new(0, 2.17, -0.36), 0, 0)
		add(mk(Vector3.new(0.22, 0.09, 0.2), ep), CFrame.new(0, 2.17, 0.36), 0, 0)
	end
	-- cross-belts, cartridge box on the right hip, knapsack with the rolled greatcoat
	add(mk(Vector3.new(0.05, 1.2, 0.1), L.belts), CFrame.new(0.25, 1.62, 0) * CFrame.Angles(0.6, 0, 0), 0, 0)
	add(mk(Vector3.new(0.05, 1.2, 0.1), L.belts), CFrame.new(0.25, 1.62, 0) * CFrame.Angles(-0.6, 0, 0), 0, 0)
	add(mk(Vector3.new(0.22, 0.24, 0.32), INK), CFrame.new(-0.22, 1.2, 0.36), 0, 0) -- cartridge box
	add(mk(Vector3.new(0.28, 0.5, 0.5), L.pack), CFrame.new(-0.36, 1.78, 0), 0, 0)
	add(cyl(0.54, 0.11, GREATCOAT), CFrame.new(-0.36, 2.1, 0) * CFrame.Angles(0, math.pi / 2, 0), 0, 0)
	if L.kind == "grenadier" or L.kind == "guard" then
		add(metal(mk(Vector3.new(0.04, 0.7, 0.05), STEEL)), CFrame.new(-0.15, 1.0, -0.34) * CFrame.Angles(0, 0, math.rad(-18)), 0, 0) -- sabre-briquet
	end
	armsNear(add, L)
	add(mk(Vector3.new(0.18, 0.16, 0.18), SKIN), CFrame.new(0, 2.22, 0), 0, 0) -- neck
	add(ball(0.46, SKIN), CFrame.new(0, 2.44, 0), 0, 0)
	headgearNear(add, L, CFrame.new(0, 2.64, 0), seed)
	if role == "line" then
		musketNear(add)
	elseif role == "colour" then
		add(mk(Vector3.new(0.07, 4.4, 0.07), DARK_WOOD), CFrame.new(POLE.X, 2.2, POLE.Z), 0, 0)
		if L.nation == "france" then
			add(metal(mk(Vector3.new(0.14, 0.12, 0.12), GOLD)), CFrame.new(POLE.X, 4.45, POLE.Z), 0, 0)
			add(metal(mk(Vector3.new(0.16, 0.2, 0.12), GOLD)), CFrame.new(POLE.X + 0.02, 4.6, POLE.Z), 0, 0)
			add(metal(mk(Vector3.new(0.06, 0.14, 0.5), GOLD)), CFrame.new(POLE.X - 0.02, 4.68, POLE.Z) * CFrame.Angles(math.rad(-8), 0, 0), 0, 0)
			add(metal(mk(Vector3.new(0.1, 0.1, 0.06), GOLD)), CFrame.new(POLE.X + 0.1, 4.72, POLE.Z), 0, 0) -- head
		else
			add(metal(mk(Vector3.new(0.1, 0.3, 0.1), GOLD)), CFrame.new(POLE.X, 4.5, POLE.Z) * CFrame.Angles(0, math.rad(45), 0), 0, 0)
		end
		Soldiers.flag(add, L.nation, CFrame.new(POLE.X - 0.03, 3.65, POLE.Z), 1.7, 1.25, 6)
	elseif role == "drummer" then
		local at = CFrame.new(0.34, 1.22, 0.14) * CFrame.Angles(0, 0, math.pi / 2)
		add(cyl(0.44, 0.31, if L.nation == "france" then BRASS else WHITE), at, 0, 0)
		add(cyl(0.48, 0.27, L.facing), at, 0, 0)
		add(mk(Vector3.new(0.3, 0.03, 0.03), WOOD), CFrame.new(0.5, 1.5, 0.3) * CFrame.Angles(0, 0, math.rad(-30)), 0, 0) -- sticks
		add(mk(Vector3.new(0.3, 0.03, 0.03), WOOD), CFrame.new(0.5, 1.5, 0.0) * CFrame.Angles(0, 0, math.rad(-40)), 0, 0)
	end
end

-- Near-tier horse: barrel, chest and rump, arched neck with mane, head with ears and bridle,
-- jointed legs (anim 4/5 upper, 9/10 cannon + hoof), tail, saddle and shabraque in `cloth`.
local function horseNear(add: Add, origin: CFrame, seed: number, cloth: Color3?, hide: Color3?)
	local coat = hide or HORSES[seed % #HORSES + 1]
	local function put(p: BasePart, cf: CFrame, anim: number?, pivot: number?)
		add(p, origin * cf, anim or 0, pivot or 0)
	end
	put(mk(Vector3.new(1.5, 0.86, 0.74), coat), CFrame.new(0, 1.6, 0))
	put(ball(0.82, coat), CFrame.new(0.82, 1.66, 0))
	put(ball(0.8, coat), CFrame.new(-0.8, 1.62, 0))
	put(mk(Vector3.new(0.44, 1.0, 0.36), coat), CFrame.new(1.12, 2.2, 0) * CFrame.Angles(0, 0, math.rad(-38))) -- neck
	put(mk(Vector3.new(0.08, 0.9, 0.1), INK), CFrame.new(0.98, 2.4, 0) * CFrame.Angles(0, 0, math.rad(-38))) -- mane
	put(mk(Vector3.new(0.66, 0.32, 0.3), coat), CFrame.new(1.58, 2.58, 0) * CFrame.Angles(0, 0, math.rad(-22))) -- head
	put(mk(Vector3.new(0.3, 0.26, 0.26), coat), CFrame.new(1.85, 2.46, 0) * CFrame.Angles(0, 0, math.rad(-22))) -- muzzle
	put(mk(Vector3.new(0.08, 0.18, 0.06), coat), CFrame.new(1.34, 2.84, -0.1))
	put(mk(Vector3.new(0.08, 0.18, 0.06), coat), CFrame.new(1.34, 2.84, 0.1))
	put(mk(Vector3.new(0.34, 0.04, 0.34), INK), CFrame.new(1.7, 2.52, 0) * CFrame.Angles(0, 0, math.rad(68))) -- noseband
	put(mk(Vector3.new(0.9, 0.03, 0.03), INK), CFrame.new(0.9, 2.4, 0.2) * CFrame.Angles(0, 0, math.rad(-10))) -- rein
	put(mk(Vector3.new(0.4, 0.14, 0.14), INK), CFrame.new(-1.2, 1.7, 0) * CFrame.Angles(0, 0, math.rad(50))) -- dock
	put(mk(Vector3.new(0.7, 0.12, 0.12), INK), CFrame.new(-1.42, 1.1, 0) * CFrame.Angles(0, 0, math.rad(75))) -- tail
	for _, l in { { 0.72, -0.26, 4 }, { 0.72, 0.26, 5 }, { -0.72, -0.26, 5 }, { -0.72, 0.26, 4 } } do
		put(mk(Vector3.new(0.22, 0.62, 0.2), coat), CFrame.new(l[1], 0.86, l[2]), l[3], 1.15)
		put(mk(Vector3.new(0.14, 0.5, 0.14), coat), CFrame.new(l[1], 0.33, l[2]), l[3] + 5, 1.15)
		put(mk(Vector3.new(0.2, 0.1, 0.18), INK), CFrame.new(l[1] + 0.02, 0.05, l[2]), l[3] + 5, 1.15)
	end
	if cloth then
		put(fabric(mk(Vector3.new(1.1, 0.08, 1.0), cloth)), CFrame.new(-0.12, 2.02, 0))
		put(fabric(wedge(Vector3.new(0.4, 0.08, 1.0), cloth)), CFrame.new(-0.87, 2.02, 0) * CFrame.Angles(0, math.pi, 0)) -- pointed rear corner
		put(mk(Vector3.new(0.64, 0.18, 0.56), DARK_WOOD), CFrame.new(-0.05, 2.12, 0)) -- saddle
		put(mk(Vector3.new(0.05, 0.42, 0.04), STEEL), CFrame.new(0.05, 1.5, 0.5)) -- stirrup leather
		put(mk(Vector3.new(0.05, 0.42, 0.04), STEEL), CFrame.new(0.05, 1.5, -0.5))
	end
end

local function riderNear(add: Add, L: Look, seed: number)
	horseNear(add, CFrame.new(), seed, L.pelisse or L.coat, L.horse)
	-- legs bent at the knee down the horse's flanks
	for _, z in { -0.44, 0.44 } do
		add(mk(Vector3.new(0.6, 0.24, 0.22), L.legs), CFrame.new(0.2, 2.05, z) * CFrame.Angles(0, 0, math.rad(-15)), 0, 0)
		add(mk(Vector3.new(0.2, 0.5, 0.2), L.legs), CFrame.new(0.38, 1.7, z), 0, 0)
		add(mk(Vector3.new(0.32, 0.1, 0.2), INK), CFrame.new(0.42, 1.44, z), 0, 0)
	end
	add(mk(Vector3.new(0.42, 0.86, 0.6), L.coat), CFrame.new(-0.05, 2.66, 0), 0, 0)
	add(mk(Vector3.new(0.46, 0.14, 0.62), L.facing), CFrame.new(-0.05, 3.1, 0), 0, 0) -- collar
	local cuirass = L.cuirass
	if cuirass then
		add(metal(mk(Vector3.new(0.5, 0.6, 0.66), cuirass)), CFrame.new(-0.03, 2.8, 0), 0, 0)
	elseif L.kind == "hussar" then
		add(mk(Vector3.new(0.04, 0.5, 0.5), BRASS), CFrame.new(0.17, 2.72, 0), 0, 0) -- dolman braid
	end
	local pelisse = L.pelisse
	if pelisse then
		add(mk(Vector3.new(0.46, 0.64, 0.2), pelisse), CFrame.new(-0.08, 2.74, -0.38) * CFrame.Angles(math.rad(-10), 0, 0), 0, 0)
		add(mk(Vector3.new(0.48, 0.1, 0.22), FUR), CFrame.new(-0.08, 3.06, -0.38), 0, 0) -- fur collar
	end
	if L.epaulettes then
		add(mk(Vector3.new(0.18, 0.09, 0.7), L.epaulettes), CFrame.new(-0.05, 3.12, 0), 0, 0)
	end
	-- arms: left holds the reins, right the sabre or lance
	add(mk(Vector3.new(0.2, 0.46, 0.2), L.coat), CFrame.new(-0.05, 2.74, -0.42) * CFrame.Angles(0, 0, math.rad(15)), 0, 0)
	add(mk(Vector3.new(0.5, 0.18, 0.18), L.coat), CFrame.new(0.3, 2.5, -0.42) * CFrame.Angles(0, 0, math.rad(-10)), 0, 0)
	add(mk(Vector3.new(0.2, 0.46, 0.2), L.coat), CFrame.new(-0.05, 2.74, 0.42) * CFrame.Angles(0, 0, math.rad(-10)), 0, 0)
	add(mk(Vector3.new(0.4, 0.18, 0.18), L.coat), CFrame.new(0.2, 2.5, 0.44) * CFrame.Angles(0, 0, math.rad(-30)), 0, 0)
	add(ball(0.42, SKIN), CFrame.new(-0.05, 3.3, 0), 0, 0)
	headgearNear(add, L, CFrame.new(-0.05, 3.5, 0), seed)
	local pennon = L.pennon
	if pennon then
		add(mk(Vector3.new(0.06, 5.2, 0.06), DARK_WOOD), CFrame.new(0.1, 3.6, 0.46) * CFrame.Angles(0, 0, math.rad(-6)), 0, 0)
		add(fabric(wedge(Vector3.new(0.03, 0.16, 0.6), pennon[1])), CFrame.new(-0.2, 6.02, 0.46) * CFrame.Angles(0, math.rad(90), 0), 0, 0)
		add(fabric(wedge(Vector3.new(0.03, 0.16, 0.6), pennon[2])), CFrame.new(-0.2, 5.86, 0.46) * CFrame.Angles(math.pi, math.rad(90), 0), 0, 0)
	elseif L.kind ~= "officer" and L.kind ~= "emperor" then
		add(metal(mk(Vector3.new(0.04, 1.1, 0.05), STEEL)), CFrame.new(0.4, 2.9, 0.5) * CFrame.Angles(0, 0, math.rad(35)), 0, 0) -- drawn sabre
		add(metal(mk(Vector3.new(0.12, 0.08, 0.12), BRASS)), CFrame.new(0.42, 2.5, 0.5), 0, 0) -- hilt
		add(metal(mk(Vector3.new(0.04, 1.1, 0.05), INK)), CFrame.new(-0.3, 1.9, 0.5) * CFrame.Angles(0, 0, math.rad(-60)), 0, 0) -- scabbard
	else
		add(mk(Vector3.new(0.6, 0.04, 0.04), WHITE), CFrame.new(0.3, 2.95, 0.3), 0, 0) -- pointing the way
	end
end

-- Spoked wheel: hub, 8 spokes and an 8-segment rim with iron tyre; axis along local Z.
local function wheelNear(add: Add, at: CFrame, r: number, paint: Color3)
	add(cyl(0.26, 0.16, paint), at * CFrame.Angles(0, math.pi / 2, 0), 0, 0)
	for i = 0, 7 do
		local a = i * math.pi / 4
		local rot = at * CFrame.Angles(0, 0, a)
		add(mk(Vector3.new(0.06, r - 0.12, 0.08), paint), rot * CFrame.new(0, r / 2, 0), 0, 0)
		local seg = 2 * r * math.sin(math.pi / 8) + 0.02
		add(mk(Vector3.new(seg, 0.1, 0.14), IRON), rot * CFrame.Angles(0, 0, math.pi / 8) * CFrame.new(0, r - 0.05, 0), 0, 0)
	end
end

-- Barrel with muzzle swell, reinforce ring, trunnions and cascabel; axis along local X.
local function barrelNear(add: Add, at: CFrame, len: number)
	add(metal(cyl(len, 0.16, BRONZE)), at, 0, 0)
	add(metal(cyl(0.26, 0.2, BRONZE)), at * CFrame.new(len / 2 - 0.13, 0, 0), 0, 0) -- muzzle swell
	add(metal(cyl(0.16, 0.2, BRONZE)), at * CFrame.new(-0.1, 0, 0), 0, 0) -- reinforce
	add(metal(cyl(0.8, 0.07, BRONZE)), at * CFrame.new(-0.05, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), 0, 0) -- trunnions
	add(metal(ball(0.2, BRONZE)), at * CFrame.new(-len / 2 - 0.08, 0, 0), 0, 0) -- cascabel
end

-- Crew at their stations: rammer at the muzzle, gun-layer crouched at the breech, ventsman,
-- loader with the next round. Every part is on anim 11, so they step clear when the gun fires.
local function gunnerNear(add: Add, L: Look, at: CFrame, side: number, job: string)
	local function put(p: BasePart, cf: CFrame)
		add(p, at * cf, 11, side)
	end
	local crouch = job == "layer"
	local lean = if crouch then math.rad(28) else 0
	for _, z in { -0.16, 0.16 } do
		put(mk(Vector3.new(0.3, 0.52, 0.27), L.legs), CFrame.new(0, 0.84, z) * CFrame.Angles(0, 0, if crouch then math.rad(-25) else 0))
		put(mk(Vector3.new(0.26, 0.5, 0.24), L.gaiters or L.legs), CFrame.new(0, 0.3, z))
	end
	local torso = CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, -lean)
	put(mk(Vector3.new(0.42, 1.0, 0.64), L.coat), torso)
	put(mk(Vector3.new(0.46, 0.14, 0.62), L.facing), torso * CFrame.new(0, 0.5, 0))
	put(mk(Vector3.new(0.05, 1.1, 0.1), WHITE), torso * CFrame.new(0.22, 0, 0) * CFrame.Angles(0.6, 0, 0))
	put(ball(0.44, SKIN), torso * CFrame.new(0, 0.78, 0))
	local top = torso * CFrame.new(0, 0.98, 0)
	put(mk(Vector3.new(0.42, 0.48, 0.42), INK), top * CFrame.new(0, 0.22, 0))
	put(mk(Vector3.new(0.24, 0.03, 0.38), INK), top * CFrame.new(0.3, 0, 0) * CFrame.Angles(0, 0, math.rad(-14)))
	put(ball(0.14, RED), top * CFrame.new(0.16, 0.52, 0))
	-- arms forward on the tool
	put(mk(Vector3.new(0.5, 0.18, 0.18), L.coat), torso * CFrame.new(0.3, 0.2, -0.4) * CFrame.Angles(0, 0, math.rad(-20)))
	put(mk(Vector3.new(0.5, 0.18, 0.18), L.coat), torso * CFrame.new(0.3, 0.2, 0.4) * CFrame.Angles(0, 0, math.rad(-20)))
	if job == "rammer" then
		put(mk(Vector3.new(2.4, 0.07, 0.07), WOOD), CFrame.new(0.9, 1.7, 0) * CFrame.Angles(0, math.rad(-side * 60), math.rad(-8)))
		put(cyl(0.2, 0.12, GREATCOAT), CFrame.new(2.0, 1.6, -side * 1.9) * CFrame.Angles(0, math.rad(-side * 60), 0)) -- sponge head
	elseif job == "loader" then
		put(metal(ball(0.26, IRON)), torso * CFrame.new(0.5, 0.2, 0)) -- the round
	elseif job == "vent" then
		put(mk(Vector3.new(0.9, 0.05, 0.05), WOOD), torso * CFrame.new(0.5, 0.4, 0) * CFrame.Angles(0, 0, math.rad(40))) -- linstock
	end
end

local function gunNear(add: Add, L: Look, limbered: boolean, seed: number)
	local paint = L.carriage
	local g = if limbered then CFrame.new(-1.4, 0, 0) * CFrame.Angles(0, math.pi, 0) else CFrame.new()
	for side = -1, 1, 2 do
		wheelNear(add, g * CFrame.new(0, 0.75, side * 0.72), 0.75, paint)
	end
	add(mk(Vector3.new(0.16, 0.16, 1.4), paint), g * CFrame.new(0, 0.75, 0), 0, 0) -- axle
	for side = -1, 1, 2 do
		add(wedge(Vector3.new(0.14, 0.5, 2.0), paint), g * CFrame.new(-0.6, 0.9, side * 0.3) * CFrame.Angles(0, math.pi / 2, 0), 0, 0) -- cheeks
	end
	add(mk(Vector3.new(2.0, 0.22, 0.34), paint), g * CFrame.new(-1.1, 0.42, 0) * CFrame.Angles(0, 0, math.rad(17)), 0, 0) -- trail
	add(metal(mk(Vector3.new(0.3, 0.1, 0.9), IRON)), g * CFrame.new(0.05, 1.1, 0), 0, 0) -- capsquares
	add(wedge(Vector3.new(0.3, 0.2, 0.3), WOOD), g * CFrame.new(-0.55, 0.98, 0), 0, 0) -- elevating quoin
	barrelNear(add, g * CFrame.new(0.4, 1.12, 0) * CFrame.Angles(0, 0, math.rad(4)), 2.3)
	if limbered then
		for side = -1, 1, 2 do
			wheelNear(add, CFrame.new(1.0, 0.65, side * 0.68), 0.65, paint)
		end
		add(mk(Vector3.new(0.16, 0.16, 1.3), paint), CFrame.new(1.0, 0.65, 0), 0, 0)
		add(mk(Vector3.new(1.0, 0.55, 1.0), paint), CFrame.new(1.0, 1.2, 0), 0, 0) -- ammunition chest
		add(mk(Vector3.new(1.0, 0.06, 1.04), INK), CFrame.new(1.0, 1.5, 0), 0, 0) -- lid
		add(mk(Vector3.new(2.6, 0.12, 0.12), paint), CFrame.new(2.6, 0.95, 0), 0, 0) -- pole
		horseNear(add, CFrame.new(3.6, 0, -0.55), seed, nil, nil)
		horseNear(add, CFrame.new(3.6, 0, 0.55), seed + 1, nil, nil)
		add(mk(Vector3.new(0.05, 0.05, 1.3), INK), CFrame.new(3.4, 1.9, 0), 0, 0) -- traces
		for _, p in { { 0.2, -1.6 }, { 0.2, 1.6 }, { -1.8, -1.5 }, { -1.8, 1.5 } } do
			gunnerNear(add, L, CFrame.new(p[1], 0, p[2]), if p[2] > 0 then 1 else -1, "walk")
		end
	else
		gunnerNear(add, L, CFrame.new(1.2, 0, -1.3) * CFrame.Angles(0, math.rad(90), 0), -1, "rammer")
		gunnerNear(add, L, CFrame.new(-2.4, 0, 0.5), 1, "layer")
		gunnerNear(add, L, CFrame.new(-0.9, 0, 1.3) * CFrame.Angles(0, math.rad(-90), 0), 1, "vent")
		gunnerNear(add, L, CFrame.new(0.4, 0, -1.6) * CFrame.Angles(0, math.rad(90), 0), -1, "loader")
	end
end

-- ------------------------------------------------------------------ infantry

export type InfantryRole = "line" | "colour" | "drummer"

-- Where each kit piece goes on the part-built rig: legs swing from the hip (1/2), arms (12/13)
-- and musket (3) pose about the kit's shoulder, so at rest every piece stands as generated.
export type KitEntry = { key: string, lc: CFrame, anim: number, pivot: number }
function Soldiers.kitLayout(kit: Assets.Kit): { KitEntry }
	local hip = kit.legL.cf[2] + kit.legL.size[2] / 2 - 0.1
	local lift = CFrame.new(0, KIT_LIFT, 0)
	return {
		{ key = "torso", lc = at(kit.torso), anim = 0, pivot = 0 },
		{ key = "head", lc = at(kit.head), anim = 0, pivot = 0 },
		{ key = "legL", lc = at(kit.legL), anim = 1, pivot = hip },
		{ key = "legR", lc = at(kit.legR), anim = 2, pivot = hip },
		{ key = "armL", lc = (lift * ARM_L_REST):Inverse() * at(kit.armL), anim = 12, pivot = KIT_LIFT },
		{ key = "armR", lc = (lift * ARM_R_REST):Inverse() * at(kit.armR), anim = 13, pivot = KIT_LIFT },
		{ key = "headgear", lc = at(kit.headgear), anim = 0, pivot = 0 },
		{ key = "musket", lc = CFrame.new(0, KIT_GRIP, 0) * at(kit.musket).Rotation, anim = 3, pivot = KIT_LIFT },
	}
end

-- The nation's generated kit. It wears a shako; other headgear is the part-built one on the
-- kit's head. Colour bearers and drummers carry their pole or drum instead of the musket.
-- Headgear on a kit's head: a generated hat for this kind when there is one, else the kit's
-- own (it wears the nation's line headgear), else the part-built one.
local function kitHeadgear(add: Add, kit: Assets.Kit, L: Look, seed: number): boolean
	local hat = Assets.kit("head_" .. L.head)
	local g = kit.headgear.cf
	if hat then
		local bottom = g[2] - kit.headgear.size[2] / 2 + 0.02
		add(piece(hat.headgear), CFrame.new(g[1], bottom + hat.headgear.size[2] / 2, g[3]) * at(hat.headgear).Rotation, 0, 0)
		return true
	end
	local N = NATIONS[L.nation]
	if N and L.head == N.head then
		return false -- the kit's own
	end
	local h = kit.head.cf
	headgear(add, L, CFrame.new(h[1], h[2] + kit.head.size[2] / 2 - 0.03, h[3]), false, seed)
	return true
end

local function infantryKit(add: Add, kit: Assets.Kit, L: Look, role: InfantryRole, seed: number)
	for _, e in Soldiers.kitLayout(kit) do
		if e.key == "headgear" and kitHeadgear(add, kit, L, seed) then
			continue
		elseif e.key ~= "musket" or role == "line" then
			add(piece(kit[e.key]), e.lc, e.anim, e.pivot)
		end
	end
	if role == "colour" then
		add(mk(Vector3.new(0.07, 4.4, 0.07), DARK_WOOD), CFrame.new(POLE.X, 2.2 + KIT_LIFT, POLE.Z), 0, 0)
		Soldiers.flag(add, L.nation, CFrame.new(POLE.X - 0.03, 3.65 + KIT_LIFT, POLE.Z), 1.7, 1.25, 6)
	elseif role == "drummer" then
		local drum = CFrame.new(0.38, 1.45, 0.14) * CFrame.Angles(0, 0, math.pi / 2)
		add(cyl(0.44, 0.31, if L.nation == "france" then BRASS else WHITE), drum, 0, 0)
		add(cyl(0.46, 0.27, L.facing), drum, 0, 0) -- hoops
	end
end

-- Legs, coat with facings, belts, knapsack, head and headgear. `seed` varies company pompons.
function Soldiers.infantry(add: Add, L: Look, detail: boolean, role: InfantryRole, seed: number?)
	local s = seed or 0
	local kit = Assets.kit("infantry_" .. L.nation)
	if kit and L.kind ~= "gunner" then
		infantryKit(add, kit, L, role, s)
		return
	end
	local mesh = meshed("soldierInfantry", Vector3.new(0.9, 3.2, 0.9), L.coat)
	if mesh then
		add(mesh, CFrame.new(0, 1.6, 0), 0, 0)
		if role == "colour" then
			add(mk(Vector3.new(0.07, 4.4, 0.07), DARK_WOOD), CFrame.new(POLE.X, 2.2, POLE.Z), 0, 0)
			Soldiers.flag(add, L.nation, CFrame.new(POLE.X - 0.03, 3.65, POLE.Z), 1.7, 1.25, 6)
		end
		return
	end
	if detail then
		infantryNear(add, L, role, s)
		return
	end
	add(mk(Vector3.new(0.3, 1.1, 0.26), L.legs), CFrame.new(0, 0.55, -0.16), 1, 1.1)
	add(mk(Vector3.new(0.3, 1.1, 0.26), L.legs), CFrame.new(0, 0.55, 0.16), 2, 1.1)
	add(mk(Vector3.new(0.42, 1.05, 0.66), L.coat), CFrame.new(0, 1.6, 0), 0, 0)
	add(mk(Vector3.new(0.46, 0.14, 0.62), L.facing), CFrame.new(0, 2.1, 0), 0, 0) -- collar
	add(mk(Vector3.new(0.26, 0.5, 0.48), L.pack), CFrame.new(-0.33, 1.72, 0), 0, 0) -- knapsack
	local lapels = L.lapels
	if lapels and lapels ~= L.coat then
		add(mk(Vector3.new(0.04, 0.6, 0.34), lapels), CFrame.new(0.22, 1.78, 0), 0, 0)
	end
	local ep = L.epaulettes
	if ep then
		add(mk(Vector3.new(0.18, 0.09, 0.16), ep), CFrame.new(0, 2.12, -0.33), 0, 0)
		add(mk(Vector3.new(0.18, 0.09, 0.16), ep), CFrame.new(0, 2.12, 0.33), 0, 0)
	end
	add(ball(0.46, SKIN), CFrame.new(0, 2.38, 0), 0, 0)
	headgear(add, L, CFrame.new(0, 2.58, 0), false, s)
	if role == "line" then
		add(mk(Vector3.new(0.08, 1.7, 0.08), WOOD), CFrame.new(), 3, 0)
	elseif role == "colour" then
		add(mk(Vector3.new(0.07, 4.4, 0.07), DARK_WOOD), CFrame.new(POLE.X, 2.2, POLE.Z), 0, 0)
		if L.nation == "france" then
			-- the Eagle: gilt bird with spread wings on a plinth
			add(metal(mk(Vector3.new(0.14, 0.12, 0.12), GOLD)), CFrame.new(POLE.X, 4.45, POLE.Z), 0, 0)
			add(metal(mk(Vector3.new(0.16, 0.2, 0.12), GOLD)), CFrame.new(POLE.X + 0.02, 4.6, POLE.Z), 0, 0)
			add(metal(mk(Vector3.new(0.06, 0.14, 0.5), GOLD)), CFrame.new(POLE.X - 0.02, 4.68, POLE.Z) * CFrame.Angles(math.rad(-8), 0, 0), 0, 0)
		else
			add(metal(mk(Vector3.new(0.1, 0.3, 0.1), GOLD)), CFrame.new(POLE.X, 4.5, POLE.Z) * CFrame.Angles(0, math.rad(45), 0), 0, 0)
		end
		Soldiers.flag(add, L.nation, CFrame.new(POLE.X - 0.03, 3.65, POLE.Z), 1.7, 1.25, 6)
	elseif role == "drummer" then
		add(cyl(0.44, 0.31, if L.nation == "france" then BRASS else WHITE), CFrame.new(0.32, 1.25, 0.12) * CFrame.Angles(0, 0, math.pi / 2), 0, 0)
		add(cyl(0.46, 0.27, L.facing), CFrame.new(0.32, 1.25, 0.12) * CFrame.Angles(0, 0, math.pi / 2), 0, 0) -- hoops
	end
end

-- ------------------------------------------------------------------ cavalry

-- Horse alone (also used for limber teams). `seed` picks a coat colour unless `hide` is given.
-- A kit horse: body with saddle, neck and head, and four legs swinging in diagonal pairs from
-- the shoulder (4/5), as the part-built horse's do.
local function horseKit(add: Add, kit: Assets.Kit, origin: CFrame)
	local shoulder = kit.legFL.cf[2] + kit.legFL.size[2] / 2 - 0.1
	add(piece(kit.body), origin * at(kit.body), 0, 0)
	add(piece(kit.neck), origin * at(kit.neck), 0, 0)
	local legs: { [string]: number } = { legFL = 4, legFR = 5, legBL = 5, legBR = 4 }
	for key, anim in legs do
		add(piece(kit[key]), origin * at(kit[key]), anim, shoulder)
	end
end

-- Horse alone (limber teams, gun teams): the French kit's bay when there is one.
function Soldiers.horse(add: Add, origin: CFrame, seed: number, cloth: Color3?, hide: Color3?)
	local kit = Assets.kit("cavalry_france")
	if kit then
		horseKit(add, kit, origin)
		return
	end
	local coat = hide or HORSES[seed % #HORSES + 1]
	local mesh = meshed("horse", Vector3.new(3.4, 3.0, 0.9), coat)
	if mesh then
		add(mesh, origin * CFrame.new(0, 1.5, 0), 0, 0)
		return
	end
	add(mk(Vector3.new(2.0, 0.85, 0.75), coat), origin * CFrame.new(0, 1.55, 0), 0, 0)
	add(mk(Vector3.new(0.45, 0.95, 0.4), coat), origin * CFrame.new(0.95, 2.1, 0) * CFrame.Angles(0, 0, math.rad(-35)), 0, 0)
	add(mk(Vector3.new(0.75, 0.36, 0.34), coat), origin * CFrame.new(1.38, 2.5, 0) * CFrame.Angles(0, 0, math.rad(-25)), 0, 0)
	add(mk(Vector3.new(0.5, 0.12, 0.12), INK), origin * CFrame.new(-1.05, 1.6, 0) * CFrame.Angles(0, 0, math.rad(60)), 0, 0) -- tail
	for _, l in { { 0.75, -0.25, 4 }, { 0.75, 0.25, 5 }, { -0.75, -0.25, 5 }, { -0.75, 0.25, 4 } } do
		add(mk(Vector3.new(0.18, 1.15, 0.18), coat), origin * CFrame.new(l[1], 0.58, l[2]), l[3], 1.15)
	end
	if cloth then
		add(fabric(mk(Vector3.new(0.95, 0.1, 0.98), cloth)), origin * CFrame.new(-0.1, 2.0, 0), 0, 0)
	end
end

-- Where a kit rider's head is, for a hat in place of the kit's helmet (officers' bicornes).
local RIDER_HEAD = Vector3.new(0.12, 3.42, 0)

-- The nation's horse-soldier kit: horse, rider, and the rider's helmet with his sabre. Officers
-- and generals wear their hat instead; lancers carry the part-built lance and pennon.
local function cavalryKit(add: Add, kit: Assets.Kit, L: Look)
	horseKit(add, kit, CFrame.identity)
	add(piece(kit.rider), at(kit.rider), 0, 0)
	local hat = if L.head == "bicorne" then Assets.kit("head_bicorne") else nil
	if hat then
		add(piece(hat.headgear), CFrame.new(RIDER_HEAD + Vector3.new(0, hat.headgear.size[2] / 2, 0)) * at(hat.headgear).Rotation, 0, 0)
	else
		add(piece(kit.riderHead), at(kit.riderHead), 0, 0)
	end
	local pennon = L.pennon
	if pennon then
		add(mk(Vector3.new(0.06, 5.2, 0.06), DARK_WOOD), CFrame.new(0.3, 3.6, 0.42) * CFrame.Angles(0, 0, math.rad(-6)), 0, 0)
		add(fabric(mk(Vector3.new(0.5, 0.14, 0.03), pennon[1])), CFrame.new(0.15, 6.0, 0.42), 0, 0)
	end
end

function Soldiers.rider(add: Add, L: Look, detail: boolean, seed: number)
	local kit = (if L.kind == "emperor" then Assets.kit("cavalry_emperor") else nil) or Assets.kit("cavalry_" .. L.nation)
	if kit then
		cavalryKit(add, kit, L)
		return
	end
	local mesh = meshed("soldierCavalry", Vector3.new(3.6, 4.0, 1.0), L.coat)
	if mesh then
		add(mesh, CFrame.new(0, 2.0, 0), 0, 0)
		return
	end
	if detail then
		riderNear(add, L, seed)
		return
	end
	Soldiers.horse(add, CFrame.new(), seed, nil, L.horse)
	add(mk(Vector3.new(0.35, 0.6, 0.9), L.legs), CFrame.new(-0.05, 2.0, 0), 0, 0)
	add(mk(Vector3.new(0.4, 0.85, 0.58), L.coat), CFrame.new(-0.05, 2.65, 0), 0, 0)
	add(ball(0.42, SKIN), CFrame.new(-0.05, 3.3, 0), 0, 0)
	local cuirass = L.cuirass
	if cuirass then
		add(metal(mk(Vector3.new(0.48, 0.56, 0.64), cuirass)), CFrame.new(-0.03, 2.78, 0), 0, 0)
	end
	local pelisse = L.pelisse
	if pelisse then
		-- slung from the left shoulder, fur-trimmed
		add(mk(Vector3.new(0.46, 0.62, 0.2), pelisse), CFrame.new(-0.08, 2.72, -0.36) * CFrame.Angles(math.rad(-10), 0, 0), 0, 0)
	end
	headgear(add, L, CFrame.new(-0.05, 3.5, 0), false, seed)
	local pennon = L.pennon
	if pennon then
		-- lance carried upright at the right stirrup, pennon at the tip
		add(mk(Vector3.new(0.06, 5.2, 0.06), DARK_WOOD), CFrame.new(0.1, 3.6, 0.42) * CFrame.Angles(0, 0, math.rad(-6)), 0, 0)
		add(fabric(mk(Vector3.new(0.5, 0.14, 0.03), pennon[1])), CFrame.new(-0.05, 6.0, 0.42), 0, 0)
	end
end

-- ------------------------------------------------------------------ artillery

local function gunner(add: Add, L: Look, at: CFrame)
	add(mk(Vector3.new(0.3, 1.1, 0.5), L.legs), at * CFrame.new(0, 0.55, 0), 0, 0)
	add(mk(Vector3.new(0.42, 1.05, 0.62), L.coat), at * CFrame.new(0, 1.6, 0), 0, 0)
	add(ball(0.44, SKIN), at * CFrame.new(0, 2.36, 0), 0, 0)
	headgear(add, L, at * CFrame.new(0, 2.56, 0), false, 0)
end

-- Painted wheel with an iron tyre; axis along local Z.
local function wheel(add: Add, at: CFrame, r: number, paint: Color3)
	local rot = CFrame.Angles(0, math.pi / 2, 0)
	add(cyl(0.16, r, IRON), at * rot, 0, 0)
	add(cyl(0.22, r * 0.84, paint), at * rot, 0, 0)
end

-- One gun on a two-wheeled carriage with trail, crew of 4; limbered: hooked to a limber
-- with a two-horse team, crew walking alongside. Carriage paint follows the nation.
-- Gun kits by carriage paint: French olive, Austrian ochre, the blue-grey of Britain and the
-- German states.
local GUN_KIT: { [string]: string } = { austria = "gun_austria", britain = "gun_britain", prussia = "gun_britain", saxony = "gun_britain", bavaria = "gun_britain" }

-- A gunner from the nation's infantry kit, at rest without a musket; the whole man steps clear
-- of the gun as it fires (anim 11, `side` = ±1).
local function gunnerKit(add: Add, kit: Assets.Kit, foot: CFrame, side: number)
	for _, key in { "torso", "head", "headgear", "armL", "armR", "legL", "legR" } do
		add(piece(kit[key]), foot * at(kit[key]), 11, side)
	end
end

local function gunKit(add: Add, kit: Assets.Kit, L: Look, limbered: boolean, seed: number)
	local g = if limbered then CFrame.new(-1.4, 0, 0) * CFrame.Angles(0, math.pi, 0) else CFrame.new()
	for _, key in { "barrel", "carriage", "wheelL", "wheelR" } do
		add(piece(kit[key]), g * at(kit[key]), 0, 0)
	end
	if limbered then
		local limber = Assets.kit("limber_france")
		if limber then
			add(piece(limber.limber), at(limber.limber), 0, 0)
		else
			for side = -1, 1, 2 do
				wheel(add, CFrame.new(1.0, 0.65, side * 0.65), 0.65, L.carriage)
			end
			add(mk(Vector3.new(1.0, 0.55, 1.0), L.carriage), CFrame.new(1.0, 1.2, 0), 0, 0) -- ammunition chest
			add(mk(Vector3.new(2.6, 0.12, 0.12), L.carriage), CFrame.new(2.6, 0.95, 0), 0, 0) -- pole
		end
		Soldiers.horse(add, CFrame.new(3.6, 0, -0.55), seed, nil, nil)
		Soldiers.horse(add, CFrame.new(3.6, 0, 0.55), seed + 1, nil, nil)
	end
	local crew = Assets.kit("infantry_" .. L.nation)
	local spots = if limbered then { { 0.2, -1.6 }, { 0.2, 1.6 }, { -1.8, -1.5 }, { -1.8, 1.5 } } else { { -1.7, -1.1 }, { -1.7, 1.1 }, { 0.3, -1.45 }, { 0.3, 1.45 } }
	for _, p in spots do
		local foot = CFrame.new(p[1], 0, p[2])
		if crew then
			gunnerKit(add, crew, foot, if p[2] < 0 then -1 else 1)
		else
			gunner(add, L, foot)
		end
	end
end

function Soldiers.gun(add: Add, L: Look, limbered: boolean, detail: boolean, seed: number)
	local kit = Assets.kit(GUN_KIT[L.nation] or "gun_france")
	if kit then
		gunKit(add, kit, L, limbered, seed)
		return
	end
	local gunMesh = meshed("gun", Vector3.new(4.4, 2.2, 2.6), L.carriage)
	if gunMesh then
		local g = if limbered then CFrame.new(-1.4, 0, 0) * CFrame.Angles(0, math.pi, 0) else CFrame.new()
		add(gunMesh, g * CFrame.new(-0.4, 1.1, 0), 0, 0)
		if limbered then
			local lim = meshed("limber", Vector3.new(2.6, 2.0, 2.4), L.carriage)
			if lim then
				add(lim, CFrame.new(1.4, 1.0, 0), 0, 0)
			end
			Soldiers.horse(add, CFrame.new(3.6, 0, -0.55), seed, nil, nil)
			Soldiers.horse(add, CFrame.new(3.6, 0, 0.55), seed + 1, nil, nil)
		end
		for _, p in { { 0.2, -1.6 }, { 0.2, 1.6 }, { -1.8, -1.5 }, { -1.8, 1.5 } } do
			gunner(add, L, CFrame.new(p[1], 0, p[2]))
		end
		return
	end
	if detail then
		gunNear(add, L, limbered, seed)
		return
	end
	local paint = L.carriage
	local g = if limbered then CFrame.new(-1.4, 0, 0) * CFrame.Angles(0, math.pi, 0) else CFrame.new()
	for side = -1, 1, 2 do
		wheel(add, g * CFrame.new(0, 0.75, side * 0.7), 0.75, paint)
	end
	add(mk(Vector3.new(0.15, 0.15, 1.3), paint), g * CFrame.new(0, 0.75, 0), 0, 0)
	add(mk(Vector3.new(1.95, 0.22, 0.32), paint), g * CFrame.new(-0.95, 0.43, 0) * CFrame.Angles(0, 0, math.rad(19)), 0, 0)
	add(metal(cyl(2.3, 0.17, BRONZE)), g * CFrame.new(0.45, 1.05, 0) * CFrame.Angles(0, 0, math.rad(4)), 0, 0)
	if limbered then
		for side = -1, 1, 2 do
			wheel(add, CFrame.new(1.0, 0.65, side * 0.65), 0.65, paint)
		end
		add(mk(Vector3.new(1.0, 0.55, 1.0), paint), CFrame.new(1.0, 1.2, 0), 0, 0) -- ammunition chest
		add(mk(Vector3.new(2.6, 0.12, 0.12), paint), CFrame.new(2.6, 0.95, 0), 0, 0) -- pole
		Soldiers.horse(add, CFrame.new(3.6, 0, -0.55), seed, nil, nil)
		Soldiers.horse(add, CFrame.new(3.6, 0, 0.55), seed + 1, nil, nil)
		for _, p in { { 0.2, -1.6 }, { 0.2, 1.6 }, { -1.8, -1.5 }, { -1.8, 1.5 } } do
			gunner(add, L, CFrame.new(p[1], 0, p[2]))
		end
	else
		for _, p in { { -1.7, -1.1 }, { -1.7, 1.1 }, { 0.3, -1.45 }, { 0.3, 1.45 } } do
			gunner(add, L, CFrame.new(p[1], 0, p[2]))
		end
	end
end

return Soldiers
