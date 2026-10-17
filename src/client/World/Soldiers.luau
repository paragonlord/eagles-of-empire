--!strict
-- Near-LOD figure builders: NTW-style silhouettes from plain parts (no meshes, no asset ids).
-- Builders call `add(part, localCFrame, anim, pivot)`; Figures parents, places and animates.
-- Local frame: +X forward, +Y up, +Z right; origin on the ground under the figure. ~3.2 studs tall.
--
-- anim codes: 0 static · 1/2 leg (opposite phases, swing about the hip at `pivot`)
--             3 musket chain (lc is an offset along the musket; pose by state)
--             4/5 horse leg (diagonal pairs, swing about the shoulder at `pivot`)
--             6 colour (flag): swings about the colour pole by the per-frame sway angle
--
-- `Soldiers.look` turns a formation (faction, palette override, class, name) into a uniform:
-- coat, facings, legwear, headgear and kit, so a French grenadier, a Prussian musketeer, an
-- Austrian in white and a Highlander read apart at a glance.

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

-- Pose for an animated part. swing in radians (anim 6: the flag's sway angle); armed = muskets levelled.
function Soldiers.partCFrame(anim: number, lc: CFrame, pivot: number, swing: number, armed: boolean): CFrame
	if anim == 1 or anim == 2 or anim == 4 or anim == 5 then
		if swing == 0 then
			return lc
		end
		local a = if anim == 1 or anim == 4 then swing else -swing
		local p = lc.Position
		return CFrame.new(p.X, pivot, p.Z) * CFrame.Angles(0, 0, a) * CFrame.new(0, p.Y - pivot, 0)
	elseif anim == 3 then
		return (if armed then LEVEL else SHOULDER) * lc
	elseif anim == 6 then
		return CFrame.new(POLE) * CFrame.Angles(0, swing, 0) * CFrame.new(-POLE) * lc
	end
	return lc
end

-- ------------------------------------------------------------------ headgear

-- French fusilier company pompons (1806 regulation colours), picked per figure.
local POMPONS = { rgb(40, 120, 60), rgb(120, 170, 214), rgb(220, 130, 40), rgb(120, 60, 140) }

-- `at`: top of the head, facing +X.
local function headgear(add: Add, L: Look, at: CFrame, detail: boolean, seed: number)
	local h = L.head
	local c = L.headColour
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

-- ------------------------------------------------------------------ infantry

export type InfantryRole = "line" | "colour" | "drummer"

-- Legs, coat with facings, belts, knapsack, head and headgear. `seed` varies company pompons.
function Soldiers.infantry(add: Add, L: Look, detail: boolean, role: InfantryRole, seed: number?)
	local s = seed or 0
	if detail and L.gaiters then
		-- breeches above, black gaiters below the knee; both swing about the hip
		for i, z in { -0.16, 0.16 } do
			add(mk(Vector3.new(0.3, 0.56, 0.26), L.legs), CFrame.new(0, 0.82, z), i, 1.1)
			add(mk(Vector3.new(0.31, 0.56, 0.27), L.gaiters :: Color3), CFrame.new(0, 0.28, z), i, 1.1)
		end
	else
		add(mk(Vector3.new(0.3, 1.1, 0.26), L.legs), CFrame.new(0, 0.55, -0.16), 1, 1.1)
		add(mk(Vector3.new(0.3, 1.1, 0.26), L.legs), CFrame.new(0, 0.55, 0.16), 2, 1.1)
	end
	add(mk(Vector3.new(0.42, 1.05, 0.66), L.coat), CFrame.new(0, 1.6, 0), 0, 0)
	add(mk(Vector3.new(0.46, 0.14, 0.62), L.facing), CFrame.new(0, 2.1, 0), 0, 0) -- collar
	add(mk(Vector3.new(0.26, 0.5, 0.48), L.pack), CFrame.new(-0.33, 1.72, 0), 0, 0) -- knapsack
	if detail then
		local lapels = L.lapels
		if lapels and lapels ~= L.coat then
			add(mk(Vector3.new(0.04, 0.6, 0.34), lapels), CFrame.new(0.22, 1.78, 0), 0, 0)
		end
		-- cross-belts over the coat front
		add(mk(Vector3.new(0.05, 1.15, 0.09), L.belts), CFrame.new(0.22, 1.6, 0) * CFrame.Angles(0.6, 0, 0), 0, 0)
		add(mk(Vector3.new(0.05, 1.15, 0.09), L.belts), CFrame.new(0.22, 1.6, 0) * CFrame.Angles(-0.6, 0, 0), 0, 0)
		add(cyl(0.5, 0.1, GREATCOAT), CFrame.new(-0.3, 2.04, 0) * CFrame.Angles(0, math.pi / 2, 0), 0, 0) -- rolled greatcoat
		local ep = L.epaulettes
		if ep then
			add(mk(Vector3.new(0.18, 0.09, 0.16), ep), CFrame.new(0, 2.12, -0.33), 0, 0)
			add(mk(Vector3.new(0.18, 0.09, 0.16), ep), CFrame.new(0, 2.12, 0.33), 0, 0)
		end
	end
	add(ball(0.46, SKIN), CFrame.new(0, 2.38, 0), 0, 0)
	headgear(add, L, CFrame.new(0, 2.58, 0), detail, s)
	if role == "line" then
		add(mk(Vector3.new(0.08, 1.7, 0.08), WOOD), CFrame.new(), 3, 0)
		if detail then
			add(metal(mk(Vector3.new(0.04, 0.4, 0.04), STEEL)), CFrame.new(0, 1.03, 0), 3, 0)
		end
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
function Soldiers.horse(add: Add, origin: CFrame, seed: number, cloth: Color3?, hide: Color3?)
	local coat = hide or HORSES[seed % #HORSES + 1]
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

function Soldiers.rider(add: Add, L: Look, detail: boolean, seed: number)
	Soldiers.horse(add, CFrame.new(), seed, if detail then (if L.pelisse then L.pelisse else L.coat) else nil, L.horse)
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
	if detail and L.epaulettes then
		add(mk(Vector3.new(0.18, 0.09, 0.7), L.epaulettes), CFrame.new(-0.05, 3.08, 0), 0, 0)
	end
	headgear(add, L, CFrame.new(-0.05, 3.5, 0), detail, seed)
	local pennon = L.pennon
	if pennon then
		-- lance carried upright at the right stirrup, pennon at the tip
		add(mk(Vector3.new(0.06, 5.2, 0.06), DARK_WOOD), CFrame.new(0.1, 3.6, 0.42) * CFrame.Angles(0, 0, math.rad(-6)), 0, 0)
		if detail then
			add(fabric(mk(Vector3.new(0.5, 0.14, 0.03), pennon[1])), CFrame.new(-0.05, 6.0, 0.42), 0, 0)
			add(fabric(mk(Vector3.new(0.5, 0.14, 0.03), pennon[2])), CFrame.new(-0.05, 5.86, 0.42), 0, 0)
		end
	elseif detail and L.kind ~= "officer" and L.kind ~= "emperor" then
		-- sabre at the shoulder
		add(metal(mk(Vector3.new(0.05, 1.1, 0.05), STEEL)), CFrame.new(0.15, 3.15, 0.36) * CFrame.Angles(0, 0, math.rad(20)), 0, 0)
	end
end

-- ------------------------------------------------------------------ artillery

local function gunner(add: Add, L: Look, at: CFrame, detail: boolean, rammer: boolean)
	add(mk(Vector3.new(0.3, 1.1, 0.5), L.legs), at * CFrame.new(0, 0.55, 0), 0, 0)
	add(mk(Vector3.new(0.42, 1.05, 0.62), L.coat), at * CFrame.new(0, 1.6, 0), 0, 0)
	add(ball(0.44, SKIN), at * CFrame.new(0, 2.36, 0), 0, 0)
	headgear(add, L, at * CFrame.new(0, 2.56, 0), false, 0)
	if detail and rammer then
		add(mk(Vector3.new(0.07, 2.6, 0.07), WOOD), at * CFrame.new(0.3, 1.5, 0) * CFrame.Angles(0, 0, math.rad(-20)), 0, 0)
	end
end

-- Painted wheel with an iron tyre; axis along local Z.
local function wheel(add: Add, at: CFrame, r: number, paint: Color3)
	local rot = CFrame.Angles(0, math.pi / 2, 0)
	add(cyl(0.16, r, IRON), at * rot, 0, 0)
	add(cyl(0.22, r * 0.84, paint), at * rot, 0, 0)
end

-- One gun on a two-wheeled carriage with trail, crew of 4; limbered: hooked to a limber
-- with a two-horse team, crew walking alongside. Carriage paint follows the nation.
function Soldiers.gun(add: Add, L: Look, limbered: boolean, detail: boolean, seed: number)
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
		if detail then
			add(mk(Vector3.new(2.6, 0.12, 0.12), paint), CFrame.new(2.6, 0.95, 0), 0, 0) -- pole
		end
		Soldiers.horse(add, CFrame.new(3.6, 0, -0.55), seed, nil, nil)
		Soldiers.horse(add, CFrame.new(3.6, 0, 0.55), seed + 1, nil, nil)
		for _, p in { { 0.2, -1.6 }, { 0.2, 1.6 }, { -1.8, -1.5 }, { -1.8, 1.5 } } do
			gunner(add, L, CFrame.new(p[1], 0, p[2]), detail, false)
		end
	else
		for i, p in { { -1.7, -1.1 }, { -1.7, 1.1 }, { 0.3, -1.45 }, { 0.3, 1.45 } } do
			gunner(add, L, CFrame.new(p[1], 0, p[2]), detail, i == 3)
		end
	end
end

return Soldiers
