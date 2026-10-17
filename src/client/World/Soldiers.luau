--!strict
-- Near-LOD figure builders: NTW-style silhouettes from plain parts (no meshes, no asset ids).
-- Builders call `add(part, localCFrame, anim, pivot)`; Figures parents, places and animates.
-- Local frame: +X forward, +Y up, +Z right; origin on the ground under the figure. ~3.2 studs tall.
--
-- anim codes: 0 static · 1/2 leg (opposite phases, swing about the hip at `pivot`)
--             3 musket chain (lc is an offset along the musket; pose by state)
--             4/5 horse leg (diagonal pairs, swing about the shoulder at `pivot`)

local Factions = require(script.Parent.Parent.Factions)

local Soldiers = {}

export type Add = (p: BasePart, cf: CFrame, anim: number, pivot: number) -> ()

local INK = Color3.fromRGB(32, 30, 28)
local SKIN = Color3.fromRGB(214, 180, 140)
local WHITE = Color3.fromRGB(236, 234, 226)
local WOOD = Color3.fromRGB(92, 64, 40)
local DARK_WOOD = Color3.fromRGB(64, 46, 32)
local STEEL = Color3.fromRGB(176, 180, 186)
local BRONZE = Color3.fromRGB(150, 112, 62)
local HORSES = { Color3.fromRGB(96, 66, 44), Color3.fromRGB(70, 48, 34), Color3.fromRGB(120, 90, 60), Color3.fromRGB(46, 38, 34) }
local FUR = Color3.fromRGB(52, 40, 32)
local RED = Color3.fromRGB(176, 40, 44)
local GOLD = Color3.fromRGB(205, 168, 62)

-- Up-close uniforms (far LOD keeps the palette cobalt vs charcoal): coat, collar/facings.
local COATS: { [string]: Color3 } = {
	france = Color3.fromRGB(34, 62, 156), -- cobalt
	prussia = Color3.fromRGB(30, 34, 54), -- dark blue-black
	britain = Color3.fromRGB(172, 34, 38),
	russia = Color3.fromRGB(42, 70, 44),
	austria = Color3.fromRGB(226, 222, 210),
}
local FACINGS: { [string]: Color3 } = {
	france = Color3.fromRGB(196, 36, 40), -- red collar (white lapels drawn separately)
	prussia = Color3.fromRGB(196, 36, 40), -- red collar
	britain = Color3.fromRGB(232, 222, 190),
	russia = Color3.fromRGB(196, 36, 40),
	austria = Color3.fromRGB(150, 40, 60),
}

-- Coat colour for a figure: a unit palette override (e.g. Saxony) keeps its own colour.
function Soldiers.coat(faction: string, override: string?, fallback: Color3): Color3
	if override then
		return fallback
	end
	return COATS[faction] or fallback
end

local TROUSERS: { [string]: Color3 } = {
	france = Color3.fromRGB(232, 228, 216), -- white breeches
	prussia = Color3.fromRGB(128, 128, 124), -- grey
	britain = Color3.fromRGB(98, 100, 108),
	russia = Color3.fromRGB(220, 218, 206),
	austria = Color3.fromRGB(224, 222, 214),
}

-- Musket poses: shouldered (slanted at the right shoulder) and levelled (firing / charging).
local SHOULDER = CFrame.new(0.02, 1.95, 0.4) * CFrame.Angles(0, 0, math.rad(8))
local LEVEL = CFrame.new(0.75, 1.85, 0.22) * CFrame.Angles(0, 0, math.rad(-90))

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

local function steel(p: BasePart): BasePart
	p.Material = Enum.Material.Metal
	return p
end

-- Pose for an animated part. swing in radians; armed = muskets levelled.
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
	end
	return lc
end

-- ------------------------------------------------------------------ headgear

local function headgear(add: Add, faction: string, y: number, detail: boolean)
	if faction == "britain" then
		add(mk(Vector3.new(0.4, 0.62, 0.4), INK), CFrame.new(0, y + 0.1, 0), 0, 0) -- stovepipe
		if detail then
			add(mk(Vector3.new(0.07, 0.24, 0.07), WHITE), CFrame.new(0.14, y + 0.5, 0), 0, 0)
		end
	elseif faction == "russia" then
		add(mk(Vector3.new(0.42, 0.44, 0.42), INK), CFrame.new(0, y, 0), 0, 0) -- kiwer
		add(mk(Vector3.new(0.56, 0.08, 0.56), INK), CFrame.new(0, y + 0.25, 0), 0, 0)
		if detail then
			add(mk(Vector3.new(0.05, 0.18, 0.2), GOLD), CFrame.new(0.22, y, 0), 0, 0)
		end
	else
		add(mk(Vector3.new(0.42, 0.48, 0.42), INK), CFrame.new(0, y + 0.02, 0), 0, 0) -- shako
		if detail then
			if faction == "france" then
				add(mk(Vector3.new(0.08, 0.32, 0.08), RED), CFrame.new(0.12, y + 0.42, 0), 0, 0) -- plume
			elseif faction == "austria" then
				add(ball(0.15, GOLD), CFrame.new(0.18, y + 0.26, 0), 0, 0)
			else
				add(ball(0.14, WHITE), CFrame.new(0.18, y + 0.26, 0), 0, 0) -- pompom
			end
		end
	end
end

-- ------------------------------------------------------------------ flag

-- Flag in the local X-Y plane, hoist at x = 0, flying toward -X.
function Soldiers.flag(add: Add, faction: string, origin: CFrame, w: number, h: number)
	local design = Factions.flag(faction) :: any
	local c = origin * CFrame.new(-w / 2, 0, 0)
	local t = 0.08
	local stripes = design.stripes
	if stripes then
		-- horizontal bands, top to bottom (Prussia black-white-black); no mark
		local n = #stripes
		for i, col in stripes do
			add(mk(Vector3.new(w, h / n, 0.05), col), c * CFrame.new(0, h / 2 - (i - 0.5) * h / n, 0), 0, 0)
		end
		return
	end
	local bands = design.bands
	if bands then
		local n = #bands
		for i, col in bands do
			add(mk(Vector3.new(w / n, h, 0.05), col), origin * CFrame.new(-(i - 0.5) * w / n, 0, 0), 0, 0)
		end
	else
		add(mk(Vector3.new(w, h, 0.05), design.field or WHITE), c, 0, 0)
	end
	local mc: Color3 = design.markColour
	local diag = math.deg(math.atan2(h, w))
	if design.mark == "diamond" then
		add(mk(Vector3.new(h * 0.32, h * 0.32, t), mc), c * CFrame.Angles(0, 0, math.rad(45)), 0, 0)
	elseif design.mark == "x" then
		-- saltire corner to corner
		local len = math.sqrt(w * w + h * h)
		for _, a in { diag, -diag } do
			add(mk(Vector3.new(len, h * 0.16, t), mc), c * CFrame.Angles(0, 0, math.rad(a)), 0, 0)
		end
	elseif design.mark == "plus" then
		add(mk(Vector3.new(w, h * 0.16, t), mc), c, 0, 0)
		add(mk(Vector3.new(w * 0.12, h, t), mc), c, 0, 0)
	elseif design.mark == "double" then
		add(mk(Vector3.new(w, h * 0.1, t), mc), c * CFrame.new(0, h * 0.18, 0), 0, 0)
		add(mk(Vector3.new(w, h * 0.1, t), mc), c * CFrame.new(0, -h * 0.18, 0), 0, 0)
	elseif design.mark == "diagonal" then
		add(mk(Vector3.new(math.sqrt(w * w + h * h), h * 0.12, t), mc), c * CFrame.Angles(0, 0, math.rad(diag)), 0, 0)
	end
	local cross: Color3? = design.cross
	if cross then
		-- upright cross over the saltire (Union flag): a white edge under a red centre
		add(mk(Vector3.new(w, h * 0.26, t + 0.01), WHITE), c, 0, 0)
		add(mk(Vector3.new(w * 0.18, h, t + 0.01), WHITE), c, 0, 0)
		add(mk(Vector3.new(w, h * 0.15, t + 0.02), cross), c, 0, 0)
		add(mk(Vector3.new(w * 0.1, h, t + 0.02), cross), c, 0, 0)
	end
end

-- ------------------------------------------------------------------ infantry

export type InfantryRole = "line" | "colour" | "drummer"

function Soldiers.infantry(add: Add, faction: string, coat: Color3, detail: boolean, role: InfantryRole)
	local legs = TROUSERS[faction] or Color3.fromRGB(150, 148, 140)
	add(mk(Vector3.new(0.3, 1.1, 0.26), legs), CFrame.new(0, 0.55, -0.16), 1, 1.1)
	add(mk(Vector3.new(0.3, 1.1, 0.26), legs), CFrame.new(0, 0.55, 0.16), 2, 1.1)
	add(mk(Vector3.new(0.42, 1.05, 0.66), coat), CFrame.new(0, 1.6, 0), 0, 0)
	add(mk(Vector3.new(0.46, 0.14, 0.62), FACINGS[faction] or coat), CFrame.new(0, 2.1, 0), 0, 0) -- collar
	if detail and faction == "france" then
		add(mk(Vector3.new(0.04, 0.6, 0.34), WHITE), CFrame.new(0.22, 1.78, 0), 0, 0) -- white lapels
	end
	if detail then
		-- white cross-belts over the coat front
		add(mk(Vector3.new(0.05, 1.15, 0.09), WHITE), CFrame.new(0.22, 1.6, 0) * CFrame.Angles(0.6, 0, 0), 0, 0)
		add(mk(Vector3.new(0.05, 1.15, 0.09), WHITE), CFrame.new(0.22, 1.6, 0) * CFrame.Angles(-0.6, 0, 0), 0, 0)
	end
	add(ball(0.46, SKIN), CFrame.new(0, 2.38, 0), 0, 0)
	headgear(add, faction, 2.82, detail)
	if role == "line" then
		add(mk(Vector3.new(0.08, 1.7, 0.08), WOOD), CFrame.new(), 3, 0)
		if detail then
			add(steel(mk(Vector3.new(0.04, 0.4, 0.04), STEEL)), CFrame.new(0, 1.03, 0), 3, 0)
		end
	elseif role == "colour" then
		add(mk(Vector3.new(0.07, 4.2, 0.07), DARK_WOOD), CFrame.new(0.05, 2.1, 0.35), 0, 0)
		add(ball(0.16, GOLD), CFrame.new(0.05, 4.25, 0.35), 0, 0)
		Soldiers.flag(add, faction, CFrame.new(0.02, 3.55, 0.35), 1.5, 1.1)
	elseif role == "drummer" then
		add(cyl(0.42, 0.3, WHITE), CFrame.new(0.32, 1.25, 0.12) * CFrame.Angles(0, 0, math.pi / 2), 0, 0)
		add(cyl(0.44, 0.31, coat), CFrame.new(0.32, 1.25, 0.12) * CFrame.Angles(0, 0, math.pi / 2), 0, 0)
	end
end

-- ------------------------------------------------------------------ cavalry

export type RiderKind = "cuirassier" | "hussar" | "trooper" | "officer"

function Soldiers.riderKind(name: string?): RiderKind
	local n = string.lower(name or "")
	if string.find(n, "cuirass", 1, true) or string.find(n, "kürass", 1, true) or string.find(n, "kurass", 1, true) then
		return "cuirassier"
	elseif string.find(n, "hussar", 1, true) or string.find(n, "husar", 1, true) then
		return "hussar"
	end
	return "trooper"
end

-- Horse alone (also used for limber teams). `seed` picks a coat colour.
function Soldiers.horse(add: Add, origin: CFrame, seed: number, cloth: Color3?)
	local hide = HORSES[seed % #HORSES + 1]
	add(mk(Vector3.new(2.0, 0.85, 0.75), hide), origin * CFrame.new(0, 1.55, 0), 0, 0)
	add(mk(Vector3.new(0.45, 0.95, 0.4), hide), origin * CFrame.new(0.95, 2.1, 0) * CFrame.Angles(0, 0, math.rad(-35)), 0, 0)
	add(mk(Vector3.new(0.75, 0.36, 0.34), hide), origin * CFrame.new(1.38, 2.5, 0) * CFrame.Angles(0, 0, math.rad(-25)), 0, 0)
	add(mk(Vector3.new(0.5, 0.12, 0.12), INK), origin * CFrame.new(-1.05, 1.6, 0) * CFrame.Angles(0, 0, math.rad(60)), 0, 0) -- tail
	for _, l in { { 0.75, -0.25, 4 }, { 0.75, 0.25, 5 }, { -0.75, -0.25, 5 }, { -0.75, 0.25, 4 } } do
		add(mk(Vector3.new(0.18, 1.15, 0.18), hide), origin * CFrame.new(l[1], 0.58, l[2]), l[3], 1.15)
	end
	if cloth then
		add(mk(Vector3.new(0.95, 0.1, 0.98), cloth), origin * CFrame.new(-0.1, 2.0, 0), 0, 0)
	end
end

function Soldiers.rider(add: Add, faction: string, coat: Color3, kind: RiderKind, detail: boolean, seed: number)
	Soldiers.horse(add, CFrame.new(), seed, if detail then coat else nil)
	local legs = TROUSERS[faction] or Color3.fromRGB(150, 148, 140)
	add(mk(Vector3.new(0.35, 0.6, 0.9), legs), CFrame.new(-0.05, 2.0, 0), 0, 0)
	add(mk(Vector3.new(0.4, 0.85, 0.58), coat), CFrame.new(-0.05, 2.65, 0), 0, 0)
	add(ball(0.42, SKIN), CFrame.new(-0.05, 3.3, 0), 0, 0)
	if kind == "cuirassier" then
		add(steel(mk(Vector3.new(0.46, 0.55, 0.62), STEEL)), CFrame.new(-0.03, 2.78, 0), 0, 0)
		add(steel(ball(0.48, STEEL)), CFrame.new(-0.05, 3.4, 0), 0, 0)
		if detail then
			add(mk(Vector3.new(0.6, 0.14, 0.1), INK), CFrame.new(-0.12, 3.66, 0), 0, 0) -- crest
		end
	elseif kind == "hussar" then
		add(mk(Vector3.new(0.42, 0.48, 0.42), FUR), CFrame.new(-0.05, 3.7, 0), 0, 0) -- busby
		if detail then
			add(mk(Vector3.new(0.1, 0.3, 0.12), RED), CFrame.new(-0.24, 3.62, 0.14), 0, 0)
		end
	elseif kind == "officer" then
		add(mk(Vector3.new(0.32, 0.28, 0.95), INK), CFrame.new(-0.05, 3.58, 0), 0, 0) -- bicorne
		if detail then
			add(mk(Vector3.new(0.05, 0.2, 0.2), WHITE), CFrame.new(0.12, 3.62, 0.2), 0, 0)
		end
	else
		add(mk(Vector3.new(0.4, 0.45, 0.4), INK), CFrame.new(-0.05, 3.7, 0), 0, 0)
	end
	if detail and kind ~= "officer" then
		-- sabre at the shoulder
		add(steel(mk(Vector3.new(0.05, 1.1, 0.05), STEEL)), CFrame.new(0.15, 3.15, 0.36) * CFrame.Angles(0, 0, math.rad(20)), 0, 0)
	end
end

-- ------------------------------------------------------------------ artillery

local function gunner(add: Add, faction: string, coat: Color3, at: CFrame)
	local legs = TROUSERS[faction] or Color3.fromRGB(150, 148, 140)
	add(mk(Vector3.new(0.3, 1.1, 0.5), legs), at * CFrame.new(0, 0.55, 0), 0, 0)
	add(mk(Vector3.new(0.42, 1.05, 0.62), coat), at * CFrame.new(0, 1.6, 0), 0, 0)
	add(ball(0.44, SKIN), at * CFrame.new(0, 2.36, 0), 0, 0)
	add(mk(Vector3.new(0.4, 0.4, 0.4), INK), at * CFrame.new(0, 2.76, 0), 0, 0)
end

-- One gun on a two-wheeled carriage with trail, crew of 4; limbered: hooked to a limber
-- with a two-horse team, crew walking alongside.
function Soldiers.gun(add: Add, faction: string, coat: Color3, limbered: boolean, detail: boolean, seed: number)
	local g = if limbered then CFrame.new(-1.4, 0, 0) * CFrame.Angles(0, math.pi, 0) else CFrame.new()
	for side = -1, 1, 2 do
		add(cyl(0.22, 0.75, DARK_WOOD), g * CFrame.new(0, 0.75, side * 0.7) * CFrame.Angles(0, math.pi / 2, 0), 0, 0)
	end
	add(mk(Vector3.new(0.15, 0.15, 1.3), DARK_WOOD), g * CFrame.new(0, 0.75, 0), 0, 0)
	add(mk(Vector3.new(1.95, 0.22, 0.32), WOOD), g * CFrame.new(-0.95, 0.43, 0) * CFrame.Angles(0, 0, math.rad(19)), 0, 0)
	add(steel(cyl(2.3, 0.17, if faction == "france" then BRONZE else Color3.fromRGB(70, 70, 66))), g * CFrame.new(0.45, 1.05, 0) * CFrame.Angles(0, 0, math.rad(4)), 0, 0)
	if limbered then
		for side = -1, 1, 2 do
			add(cyl(0.2, 0.65, DARK_WOOD), CFrame.new(1.0, 0.65, side * 0.65) * CFrame.Angles(0, math.pi / 2, 0), 0, 0)
		end
		add(mk(Vector3.new(1.0, 0.55, 1.0), WOOD), CFrame.new(1.0, 1.2, 0), 0, 0)
		if detail then
			add(mk(Vector3.new(2.6, 0.12, 0.12), DARK_WOOD), CFrame.new(2.6, 0.95, 0), 0, 0)
		end
		Soldiers.horse(add, CFrame.new(3.6, 0, -0.55), seed, nil)
		Soldiers.horse(add, CFrame.new(3.6, 0, 0.55), seed + 1, nil)
		for _, p in { { 0.2, -1.6 }, { 0.2, 1.6 }, { -1.8, -1.5 }, { -1.8, 1.5 } } do
			gunner(add, faction, coat, CFrame.new(p[1], 0, p[2]))
		end
	else
		for _, p in { { -1.7, -1.1 }, { -1.7, 1.1 }, { 0.3, -1.45 }, { 0.3, 1.45 } } do
			gunner(add, faction, coat, CFrame.new(p[1], 0, p[2]))
		end
	end
end

return Soldiers
