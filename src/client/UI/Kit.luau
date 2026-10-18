--!strict
-- Native-GUI toolkit in the First Empire manner: dark walnut panels in a gold double frame with
-- corner rosettes, ivory Garamond capitals, gilt plaque buttons on blue lacquer (crimson for
-- primary actions), parchment only for documents: aged post, tea-stained at the edges with
-- foxing, a crease and now and then a coffee ring (Kit.paper). Every panel is Active so clicks
-- never reach the field. Screens build from these pieces, so restyling here restyles everything.

local Players = game:GetService("Players") :: Players
local UserInputService = game:GetService("UserInputService") :: UserInputService
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Factions = require(script.Parent.Parent.Factions)
local BattleState = require(script.Parent.Parent.BattleState)
local PaperLayout = require(script.Parent.PaperLayout)

local Kit = {}

local P = Config.Visual.Palette
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end
local function hex(h: number): Color3
	return Color3.fromRGB(bit32.rshift(h, 16) % 256, bit32.rshift(h, 8) % 256, h % 256)
end

-- Imperial palette
Kit.BLUE = hex(0x1E2A5A) -- imperial blue lacquer
Kit.BLUE_LIGHT = hex(0x2E3F7E)
Kit.CRIMSON = hex(0x8C1C1C)
Kit.CRIMSON_LIGHT = hex(0xA8302A)
Kit.GILT = hex(0xC9A24A)
Kit.GILT_DARK = hex(0x8A6A2A)
Kit.GILT_BRIGHT = hex(0xE6C46A)
Kit.IVORY = hex(0xEFE6CF) -- text on dark
Kit.WALNUT = hex(0x2A1E17) -- panel body, bottom
Kit.WALNUT_LIGHT = hex(0x3B2A1F) -- panel body, top
Kit.INSET = hex(0x14100D) -- wells, tracks, nested panels
Kit.PARCHMENT = hex(0xE6D7B4) -- documents only: mid tone of the aged sheet
Kit.PARCHMENT_LIGHT = hex(0xF1E7CB) -- warm ivory at the heart of the sheet
Kit.PARCHMENT_EDGE = hex(0xC8AB72) -- tea-stain ochre at the edges
Kit.PARCHMENT_STAIN = hex(0x8A6A3A) -- foxing, rings, the vignette (laid on at high transparency)
Kit.INK = hex(0x2F2116) -- iron-gall ink on parchment (10:1 on the mid tone)
Kit.INK_MUTED = hex(0x6B5640) -- 4.6:1 on the mid tone
Kit.STAMP = hex(0xA3362E) -- faded red of a dépôt stamp
-- A Creator Store paper texture: set to "rbxassetid://..." and Kit.paper lays it under the
-- gradients at low opacity. Empty, the procedural layers stand alone.
Kit.paperTextureId = "rbxassetid://4061980967" -- "old paper texture" (Matroscin2), free on the Creator Store
Kit.MUTED = hex(0xB3A285) -- secondary text on dark (resolves to INK_MUTED on parchment)
Kit.SLATE = hex(0x4A4B52) -- disabled lacquer

-- older names, kept for the screens that use them
Kit.CREAM = Kit.IVORY
Kit.GOLD = Kit.GILT
Kit.PANEL_DARK = Kit.INSET
Kit.SELECT = rgb(P.Select)
Kit.HOSTILE = hex(0xC8463A) -- reads on dark and on parchment
Kit.FRANCE = rgb(P.France)
Kit.PRUSSIA = rgb(P.Prussia)
Kit.MORALE = {
	steady = Color3.fromRGB(96, 140, 70),
	shaken = Color3.fromRGB(214, 168, 56),
	routing = Color3.fromRGB(184, 52, 40),
	shattered = Color3.fromRGB(70, 60, 54),
}

Kit.ITALIC = Font.new(Font.fromEnum(Enum.Font.Garamond).Family, Enum.FontWeight.Regular, Enum.FontStyle.Italic)
Kit.BOLD = Font.new(Font.fromEnum(Enum.Font.Garamond).Family, Enum.FontWeight.Bold)

-- Co-op player slots: 1 gold, 2 sky blue, 3 crimson, 4 ivory green.
Kit.SLOT = { Kit.GILT_BRIGHT, hex(0x6FA8DC), Kit.CRIMSON_LIGHT, hex(0xB8CFA0) }
function Kit.slotColour(slot: number?): Color3
	return Kit.SLOT[slot or 0] or Kit.MUTED
end

function Kit.factionColour(faction: string?): Color3
	if faction == nil or faction == "" then
		return Kit.MUTED
	end
	return Factions.colour(faction)
end

-- The scenario's display name ("Russia & Austria") when the match gives one, else the faction's.
function Kit.factionName(faction: string?): string
	local sc = BattleState.scenario
	local names = if sc and type(sc.factionNames) == "table" then sc.factionNames else nil
	if names and faction and names[faction] then
		return tostring(names[faction])
	end
	return Factions.name(faction)
end

function Kit.screen(name: string, order: number, ignoreInset: boolean?): ScreenGui
	local sg = Instance.new("ScreenGui") :: ScreenGui
	sg.Name = name
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = ignoreInset == true
	sg.DisplayOrder = order
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	return sg
end

-- Capitals that are safe for UTF-8. Roblox's string.upper is byte-wise with Latin-1 rules: it
-- leaves é/è/à lowercase and turns the 0xE2 lead byte of "—", "’", "…" into 0xC2 ("�").
function Kit.upper(text: string): string
	if utf8.len(text) == nil then
		return text
	end
	local out = {}
	for _, cp in utf8.codes(text) do
		if (cp >= 97 and cp <= 122) or (cp >= 0xE0 and cp <= 0xFE and cp ~= 0xF7) then
			cp -= 32 -- a-z, à-þ
		elseif cp == 0x153 then
			cp = 0x152 -- œ
		elseif cp == 0xFF then
			cp = 0x178 -- ÿ
		end
		out[#out + 1] = utf8.char(cp)
	end
	return table.concat(out)
end

-- Capitals with wide tracking: "Eagles of Empire" -> "E A G L E S   O F   E M P I R E".
function Kit.spaced(text: string): string
	local out = {}
	for _, cp in utf8.codes(Kit.upper(text)) do
		local ch = utf8.char(cp)
		table.insert(out, if ch == " " then "  " else ch)
	end
	return table.concat(out, " ")
end

-- True when `inst` sits on a parchment document (text defaults to ink there).
local function onParchment(inst: Instance?): boolean
	local i = inst
	while i do
		if i:GetAttribute("parchment") == true then
			return true
		end
		if i:GetAttribute("parchment") == false then
			return false
		end
		i = i.Parent
	end
	return false
end

local function gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient") :: UIGradient
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end
Kit.gradient = gradient

local function frame(parent: Instance, size: UDim2, pos: UDim2, colour: Color3): Frame
	local f = Instance.new("Frame") :: Frame
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = colour
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

-- Gold rosette: a rotated square under a small disc.
function Kit.rosette(parent: Instance, pos: UDim2, size: number?): Frame
	local d = size or 9
	local holder = frame(parent, UDim2.fromOffset(d, d), pos, Kit.GILT)
	holder.Name = "Rosette"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Rotation = 45
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = Kit.GILT_DARK
	s.Parent = holder
	local disc = frame(holder, UDim2.fromOffset(math.max(3, d - 5), math.max(3, d - 5)), UDim2.fromScale(0.5, 0.5), Kit.GILT_BRIGHT)
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = disc
	return holder
end

-- Gold rule with a centred diamond; `width` in px (or the parent's width when nil). On parchment
-- it is drawn in ink as a thin double line with the diamond as its ornament.
function Kit.rule(parent: Instance, pos: UDim2, width: number?, anchorX: number?): Frame
	local doc = onParchment(parent)
	local colour = if doc then Kit.INK else Kit.GILT
	local r = frame(parent, if width then UDim2.fromOffset(width, 1) else UDim2.new(1, 0, 0, 1), pos, colour)
	r.Name = "Rule"
	r.AnchorPoint = Vector2.new(anchorX or 0, 0.5)
	if doc then
		r.BackgroundTransparency = 0.35
		local second = frame(r, UDim2.new(1, -16, 0, 1), UDim2.new(0.5, 0, 0, 3), colour)
		second.AnchorPoint = Vector2.new(0.5, 0)
		second.BackgroundTransparency = 0.55
	end
	local d = frame(r, UDim2.fromOffset(6, 6), UDim2.fromScale(0.5, 0.5), colour)
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Rotation = 45
	return r
end

-- Tricolour ribbon (blue, white, red), horizontal bands.
function Kit.tricolour(parent: Instance, size: UDim2, pos: UDim2, anchor: Vector2?): Frame
	local r = frame(parent, size, pos, Kit.IVORY)
	r.AnchorPoint = anchor or Vector2.new(0, 0)
	frame(r, UDim2.fromScale(1 / 3, 1), UDim2.new(), hex(0x22357A))
	frame(r, UDim2.fromScale(1 / 3, 1), UDim2.fromScale(2 / 3, 0), hex(0xA8262C))
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = Kit.GILT_DARK
	s.Parent = r
	return r
end

export type PanelProps = {
	size: UDim2,
	position: UDim2,
	anchor: Vector2?,
	transparency: number?,
	padding: number?,
	dark: boolean?, -- nested well: near-black inset with a dark-gold hairline
	plain: boolean?, -- single thin frame, no rosettes (chips, bars)
	parchment: boolean?, -- a document: briefing dispatch, report, history
	seed: number?, -- parchment: where its stains fall (default: from the parent's name and the size)
}

-- Inner hairline 4 px inside the outer gold stroke, with rosettes at the corners.
local function trim(f: Frame, pad: number, colour: Color3)
	local inner = Instance.new("Frame") :: Frame
	inner.Name = "Trim"
	inner.BackgroundTransparency = 1
	inner.Position = UDim2.fromOffset(4 - pad, 4 - pad)
	inner.Size = UDim2.new(1, 2 * pad - 8, 1, 2 * pad - 8)
	-- inside a Folder so a UIListLayout on the panel does not stack the trim as a row (it is
	-- sized to the panel, so on an auto-sized panel it pushed every row off screen)
	local deco = Instance.new("Folder")
	deco.Name = "Deco"
	deco.Parent = f
	inner.Parent = deco
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = colour
	s.Thickness = 1
	s.Parent = inner
	for _, c in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		Kit.rosette(inner, UDim2.fromScale(c.X, c.Y))
	end
end

local function round(f: GuiObject, radius: number?): UICorner
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(radius or 0.5, 0)
	c.Parent = f
	return c
end

local function hairline(f: GuiObject, colour: Color3, thickness: number, transparency: number): UIStroke
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = colour
	s.Thickness = thickness
	s.Transparency = transparency
	s.Parent = f
	return s
end

-- Aged post. The tone varies across the sheet: ochre creeps in from the edges along two
-- angles and darkens towards the foot; then foxing spots, a crease, a folded corner and on some
-- sheets a coffee ring, all placed by PaperLayout from `seed` so a panel looks the same each
-- time it opens. A deckled double edge rounds it off. Everything sits in a "Deco" Folder at
-- ZIndex 0 under the content; sizes are Scale-only so an auto-sized panel never grows for it.
-- About 15 instances (18 with a ring), fewer than the gilt trim it replaces.
function Kit.paper(f: Frame, pad: number, seed: number)
	local deco = Instance.new("Folder")
	deco.Name = "Deco"
	deco.Parent = f
	-- the padding is applied to the panel, so the sheet layers reach back out to its edge
	local full = UDim2.new(1, 2 * pad, 1, 2 * pad)
	local origin = UDim2.fromOffset(-pad, -pad)
	local function layer(name: string, size: UDim2, pos: UDim2, colour: Color3, transparency: number): Frame
		local l = frame(deco, size, pos, colour)
		l.Name = name
		l.ZIndex = 0
		l.BackgroundTransparency = transparency
		return l
	end
	if Kit.paperTextureId ~= "" then
		local img = Instance.new("ImageLabel") :: ImageLabel
		img.Name = "Texture"
		img.Size = full
		img.Position = origin
		img.BackgroundTransparency = 1
		img.Image = Kit.paperTextureId
		img.ImageTransparency = 0.3 -- at 0.6 the stain layers hide it (Studio)
		img.ScaleType = Enum.ScaleType.Crop
		img.ZIndex = 0
		img.Parent = deco
	end
	-- tea stain along two angles, clear at the heart; the second runs ochre into a darker
	-- vignette at its far end
	for i, rot in { 28, 117 } do
		local t = layer("Stain" .. i, full, origin, Kit.PARCHMENT_EDGE, 0)
		local g = Instance.new("UIGradient") :: UIGradient
		g.Rotation = rot
		if i == 2 then
			g.Color = ColorSequence.new(Kit.PARCHMENT_EDGE, Kit.PARCHMENT_STAIN)
		end
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(0.25, 0.88),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(0.78, 0.86),
			NumberSequenceKeypoint.new(1, 0.45),
		})
		g.Parent = t
	end
	local sheet = PaperLayout.sheet(seed)
	for i, m in sheet.blotches do
		round(layer("Fox" .. i, UDim2.fromScale(m.w, m.h), UDim2.fromScale(m.x, m.y), Kit.PARCHMENT_STAIN, m.alpha))
	end
	local ring = sheet.ring
	if ring then
		-- a thin darker ring round a soft fill
		local r = layer("Ring", UDim2.fromScale(ring.w, ring.h), UDim2.fromScale(ring.x, ring.y), Kit.PARCHMENT_STAIN, 0.9)
		round(r)
		hairline(r, Kit.PARCHMENT_STAIN, 2, ring.alpha)
	end
	-- a fold: a darker line with the light catching just below it
	local crease = layer("Crease", UDim2.new(1, 2 * pad, 0, 1), UDim2.new(0, -pad, sheet.crease.y, 0), Kit.PARCHMENT_STAIN, 0.72)
	crease.Rotation = sheet.crease.rotation
	local lit = frame(crease, UDim2.new(1, 0, 0, 1), UDim2.fromOffset(0, 1), Kit.PARCHMENT_LIGHT)
	lit.BackgroundTransparency = 0.45
	-- a dog-eared corner: a rotated square that just overruns the edge
	local cx, cy = (sheet.chip - 1) % 2, (sheet.chip - 1) // 2
	local chip = layer("Chip", UDim2.fromOffset(18, 18), UDim2.new(cx, if cx == 0 then -pad else pad, cy, if cy == 0 then -pad else pad), Kit.PARCHMENT_EDGE, 0.3)
	chip.AnchorPoint = Vector2.new(cx, cy)
	chip.Rotation = 45
	-- deckled edge: a second, offset hairline inside the outer stroke
	local deckle = layer("Deckle", UDim2.new(1, 2 * pad - 5, 1, 2 * pad - 5), UDim2.fromOffset(3 - pad, 2 - pad), Kit.PARCHMENT_STAIN, 1)
	hairline(deckle, Kit.PARCHMENT_STAIN, 1, 0.55)
end

-- A faded circular stamp ("DÉPÔT DE LA GUERRE"): two rings and the legend, the whole set a
-- little askew as if struck in haste. `d` is the diameter in px.
function Kit.stamp(parent: Instance, text: string, pos: UDim2, d: number, anchor: Vector2?): Frame
	local s = frame(parent, UDim2.fromOffset(d, d), pos, Kit.STAMP)
	s.Name = "Stamp"
	s.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	s.BackgroundTransparency = 0.93
	s.Rotation = -11
	round(s)
	hairline(s, Kit.STAMP, 3, 0.45)
	local inner = frame(s, UDim2.fromScale(0.84, 0.84), UDim2.fromScale(0.5, 0.5), Kit.STAMP)
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.BackgroundTransparency = 1
	round(inner)
	hairline(inner, Kit.STAMP, 1, 0.5)
	local l = Kit.label(s, Kit.upper(text), { size = UDim2.fromScale(0.8, 0.8), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), textSize = math.max(10, math.floor(d / 6.5)), font = Enum.Font.Garamond, colour = Kit.STAMP, align = Enum.TextXAlignment.Center, wrap = true })
	l.FontFace = Kit.BOLD
	l.TextTransparency = 0.4
	return s
end

function Kit.panel(parent: Instance, props: PanelProps): Frame
	local f = Instance.new("Frame") :: Frame
	f.Size = props.size
	f.Position = props.position
	f.AnchorPoint = props.anchor or Vector2.new(0, 0)
	f.BackgroundTransparency = props.transparency or 0.04
	f.BorderSizePixel = 0
	f.Active = true
	f.Parent = parent
	local stroke = Instance.new("UIStroke") :: UIStroke
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	if props.parchment then
		f:SetAttribute("parchment", true)
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		-- the base sheet already shifts from ivory to the mid tone; Kit.paper ages it
		local g = gradient(f, Kit.PARCHMENT_LIGHT, Kit.PARCHMENT, 75)
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Kit.PARCHMENT_LIGHT),
			ColorSequenceKeypoint.new(0.5, Kit.PARCHMENT),
			ColorSequenceKeypoint.new(1, Kit.PARCHMENT:Lerp(Kit.PARCHMENT_EDGE, 0.5)),
		})
		stroke.Color = Kit.PARCHMENT_STAIN
		stroke.Thickness = 2
		stroke.Transparency = 0.2
		Kit.paper(f, props.padding or 0, props.seed or PaperLayout.seed(parent.Name .. tostring(props.size)))
	elseif props.dark then
		f:SetAttribute("parchment", false)
		f.BackgroundColor3 = Kit.INSET
		stroke.Color = Kit.GILT_DARK
		stroke.Thickness = 1
	else
		f:SetAttribute("parchment", false)
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		gradient(f, Kit.WALNUT_LIGHT, Kit.WALNUT)
		stroke.Color = Kit.GILT
		stroke.Thickness = if props.plain then 1 else 2
		if not props.plain then
			trim(f, props.padding or 0, Kit.GILT_DARK)
		end
	end
	stroke.Parent = f
	if props.padding then
		local pad = Instance.new("UIPadding") :: UIPadding
		pad.PaddingTop = UDim.new(0, props.padding)
		pad.PaddingBottom = UDim.new(0, props.padding)
		pad.PaddingLeft = UDim.new(0, props.padding)
		pad.PaddingRight = UDim.new(0, props.padding)
		pad.Parent = f
	end
	return f
end

export type TextProps = {
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	font: EnumFont?,
	colour: Color3?,
	align: EnumTextXAlignment?,
	wrap: boolean?,
	rich: boolean?,
	caps: boolean?, -- titles: false keeps mixed case (long names in tight spots)
	spaced: boolean?, -- titles: wide-tracked capitals
	rule: boolean?, -- titles: gold rule with a diamond underneath
}

function Kit.label(parent: Instance, text: string, props: TextProps?): TextLabel
	local p: TextProps = props or {}
	local doc = onParchment(parent)
	local colour: Color3 = p.colour or (if doc then Kit.INK else Kit.IVORY)
	if doc and colour == Kit.MUTED then
		colour = Kit.INK_MUTED
	end
	local l = Instance.new("TextLabel") :: TextLabel
	l.Size = p.size or UDim2.new(1, 0, 0, 20)
	l.Position = p.position or UDim2.new(0, 0, 0, 0)
	l.AnchorPoint = p.anchor or Vector2.new(0, 0)
	l.BackgroundTransparency = 1
	-- SourceSans sets small: one point up keeps the old Gotham sizes readable
	l.Font = p.font or Enum.Font.SourceSans
	l.TextSize = (p.textSize or 14) + (if p.font == nil then 1 else 0)
	l.TextColor3 = colour
	l.TextXAlignment = p.align or Enum.TextXAlignment.Left
	l.TextWrapped = p.wrap == true
	l.RichText = p.rich == true
	l.Text = text
	l.Parent = parent
	return l
end

function Kit.title(parent: Instance, text: string, props: TextProps?): TextLabel
	local p: TextProps = props or {}
	p.font = Enum.Font.Garamond
	p.textSize = p.textSize or 26
	local t = if p.spaced then Kit.spaced(text) elseif p.caps == false then text else Kit.upper(text)
	local l = Kit.label(parent, t, p)
	if p.rule then
		local centred = p.align == Enum.TextXAlignment.Center
		Kit.rule(l, UDim2.new(if centred then 0.5 else 0, 0, 1, 3), 140, if centred then 0.5 else 0)
	end
	return l
end

-- Vertical list container. Children lay out top to bottom.
function Kit.list(parent: Instance, gap: number, horizontal: boolean?): UIListLayout
	local l = Instance.new("UIListLayout") :: UIListLayout
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Parent = parent
	return l
end

-- Wax seal: crimson disc with a darker rim and an "N".
function Kit.seal(parent: Instance, pos: UDim2, d: number, anchor: Vector2?): Frame
	local s = frame(parent, UDim2.fromOffset(d, d), pos, Kit.CRIMSON)
	s.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = s
	gradient(s, Kit.CRIMSON_LIGHT, hex(0x5E1010), 45)
	local st = Instance.new("UIStroke") :: UIStroke
	st.Color = hex(0x5E1010)
	st.Thickness = 3
	st.Parent = s
	local n = Kit.label(s, "N", { size = UDim2.fromScale(1, 1), textSize = math.floor(d * 0.6), font = Enum.Font.Garamond, colour = hex(0xD9A0A0), align = Enum.TextXAlignment.Center })
	n.FontFace = Kit.BOLD
	return s
end

-- A flag from Factions.flag: vertical bands or a plain field, with a simple mark.
-- `poleRight` puts the staff on the right so two flags can face each other.
function Kit.flag(parent: Instance, faction: string, size: Vector2, pos: UDim2, poleRight: boolean?): Frame
	local fl = Factions.flag(faction)
	local holder = Instance.new("Frame") :: Frame
	holder.Size = UDim2.fromOffset(size.X + 4, size.Y + 10)
	holder.Position = pos
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	-- Inline on a button or label (left-hand flag): reserve its width in the text padding so
	-- the text can never run under it, and let long names shrink or wrap to fit.
	if (parent:IsA("TextButton") or parent:IsA("TextLabel")) and not poleRight and pos.X.Scale == 0 then
		local t = parent :: any
		local pad = (parent:FindFirstChild("Lift") or parent:FindFirstChildOfClass("UIPadding")) :: UIPadding?
		if not pad then
			local np = Instance.new("UIPadding") :: UIPadding
			np.Parent = parent
			pad = np
		end
		local old = (pad :: UIPadding).PaddingLeft.Offset
		local reserve = pos.X.Offset + size.X + 4 + 6
		;(pad :: UIPadding).PaddingLeft = UDim.new(0, reserve)
		holder.Position = UDim2.new(0, pos.X.Offset - (reserve - old), pos.Y.Scale, pos.Y.Offset)
		local cap = Instance.new("UITextSizeConstraint") :: UITextSizeConstraint
		cap.MaxTextSize = t.TextSize
		cap.MinTextSize = 9
		cap.Parent = parent
		t.TextWrapped = true
		t.TextScaled = true
	end
	local pole = frame(holder, UDim2.new(0, 2, 1, 0), UDim2.fromScale(if poleRight then 1 else 0, 0), Kit.GILT)
	pole.AnchorPoint = Vector2.new(if poleRight then 1 else 0, 0)
	local cloth = frame(holder, UDim2.fromOffset(size.X, size.Y), UDim2.fromOffset(if poleRight then 0 else 4, 1), fl.field or Kit.IVORY)
	local bands = fl.bands
	if bands then
		for i, c in bands do
			frame(cloth, UDim2.fromScale(1 / #bands, 1), UDim2.fromScale((i - 1) / #bands, 0), c)
		end
	end
	local stripes = fl.stripes
	if stripes then
		for i, c in stripes do
			frame(cloth, UDim2.fromScale(1, 1 / #stripes), UDim2.fromScale(0, (i - 1) / #stripes), c)
		end
	end
	local m, mc = (if stripes then nil else fl.mark), fl.markColour
	local cx, cy = size.X / 2, size.Y / 2
	local function bar(w: number, h: number, rot: number)
		local b = frame(cloth, UDim2.fromOffset(w, h), UDim2.fromOffset(cx, cy), mc)
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Rotation = rot
	end
	local diag = size.Y * 1.15 -- rotated children are not clipped, so marks stay inside
	if m == "diamond" then
		bar(size.Y * 0.4, size.Y * 0.4, 45)
	elseif m == "x" then
		-- saltire corner to corner (a hair short: rotated children are not clipped)
		local a = math.deg(math.atan2(size.Y, size.X))
		local len = math.sqrt(size.X * size.X + size.Y * size.Y) - 3
		bar(len, 4, a)
		bar(len, 4, -a)
	elseif m == "plus" then
		bar(size.X, 3, 0)
		bar(3, size.Y, 0)
	elseif m == "double" then
		bar(size.X, 2, 0)
		local b = frame(cloth, UDim2.fromOffset(size.X, 2), UDim2.fromOffset(0, cy + 4), mc)
		b.AnchorPoint = Vector2.new(0, 0.5)
	elseif m == "diagonal" then
		bar(diag, 3, -45)
	end
	local cross = fl.cross
	if cross then
		-- white edging under the red cross, as on the Union flag
		local ew = frame(cloth, UDim2.new(1, 0, 0, 6), UDim2.new(0, 0, 0.5, -3), Kit.IVORY)
		ew.ZIndex = 2
		local eh = frame(cloth, UDim2.new(0, 6, 1, 0), UDim2.new(0.5, -3, 0, 0), Kit.IVORY)
		eh.ZIndex = 2
		local rw = frame(cloth, UDim2.new(1, 0, 0, 3), UDim2.new(0, 0, 0.5, -1), cross)
		rw.ZIndex = 3
		local rh = frame(cloth, UDim2.new(0, 3, 1, 0), UDim2.new(0.5, -1, 0, 0), cross)
		rh.ZIndex = 3
	end
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = Kit.INSET
	s.Transparency = 0.3
	s.Parent = cloth
	return holder
end

-- ------------------------------------------------------------------ tooltip (one per screen)

local tooltip: TextLabel? = nil

local function ensureTooltip()
	if tooltip and tooltip.Parent then
		return
	end
	local sg = Kit.screen("EoETooltip", 50, true)
	local t = Kit.label(sg, "", { size = UDim2.fromOffset(240, 36), textSize = 15, wrap = true, align = Enum.TextXAlignment.Center, colour = Kit.IVORY })
	t.BackgroundTransparency = 0.04
	t.BackgroundColor3 = Kit.INSET
	t.Visible = false
	t.ZIndex = 100
	t.AutomaticSize = Enum.AutomaticSize.Y
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = Kit.GILT
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = t
	local pad = Instance.new("UIPadding") :: UIPadding
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = t
	tooltip = t
end

local function showTooltip(text: string)
	ensureTooltip()
	local t = tooltip :: TextLabel
	t.Text = text
	local m = UserInputService:GetMouseLocation()
	local cam = workspace.CurrentCamera
	local maxX = if cam then cam.ViewportSize.X - 248 else m.X + 14
	-- grows upward from just above the cursor and stays on screen at the right edge
	t.AnchorPoint = Vector2.new(0, 1)
	t.Position = UDim2.fromOffset(math.min(m.X + 14, maxX), math.max(m.Y - 10, 40))
	t.Visible = true
end

local function hideTooltip()
	if tooltip then
		tooltip.Visible = false
	end
end

-- ------------------------------------------------------------------ buttons

export type ButtonProps = {
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	font: EnumFont?,
	tooltip: string?,
	primary: boolean?, -- crimson plaque (Fight, Start Battle)
	flat: boolean?, -- text-only gilt entry that underlines on hover (main menu)
	caps: boolean?, -- false keeps the caller's case
	order: number?,
}

-- One look function for every state combination, driven by attributes.
local function restyle(b: TextButton)
	local disabled = b:GetAttribute("disabled") == true
	local active = b:GetAttribute("active") == true
	local hover = b:GetAttribute("hover") == true and not disabled
	local pressed = b:GetAttribute("pressed") == true and not disabled
	local primary = b:GetAttribute("primary") == true
	local stroke = b:FindFirstChild("Gilt") :: UIStroke?
	local pad = b:FindFirstChild("Lift") :: UIPadding?
	local grad = b:FindFirstChild("Lacquer") :: UIGradient?
	if pad then
		pad.PaddingBottom = UDim.new(0, if hover and not pressed then 2 else 0)
	end
	if b:GetAttribute("flat") == true then
		local u = b:FindFirstChild("Underline") :: Frame?
		if u then
			u.Visible = hover or active
		end
		b.TextColor3 = if disabled then Kit.SLATE elseif hover then Kit.GILT_BRIGHT else Kit.GILT
		return
	end
	local body = if disabled then Kit.SLATE elseif active then Kit.GILT_DARK elseif primary then Kit.CRIMSON else Kit.BLUE
	if pressed then
		body = body:Lerp(Color3.new(0, 0, 0), 0.35)
	elseif hover then
		body = body:Lerp(Color3.new(1, 1, 1), 0.1)
	end
	b.BackgroundColor3 = body
	b.TextColor3 = Kit.IVORY
	b.TextTransparency = if disabled then 0.5 else 0
	if grad then
		grad.Enabled = not pressed
	end
	if stroke then
		stroke.Color = if disabled then Kit.GILT_DARK elseif hover or active then Kit.GILT_BRIGHT else Kit.GILT
		stroke.Transparency = if disabled then 0.5 else 0
	end
end

function Kit.button(parent: Instance, text: string, onClick: () -> (), props: ButtonProps?): TextButton
	local p: ButtonProps = props or {}
	local size = p.textSize or 14
	local b = Instance.new("TextButton") :: TextButton
	b.Size = p.size or UDim2.new(0, 110, 0, 30)
	b.Position = p.position or UDim2.new(0, 0, 0, 0)
	b.AnchorPoint = p.anchor or Vector2.new(0, 0)
	b.Font = p.font or (if size >= 15 then Enum.Font.Garamond else Enum.Font.SourceSansSemibold)
	b.TextSize = if b.Font == Enum.Font.Garamond then size + 2 else size
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.LayoutOrder = p.order or 0
	b.Active = true
	b.Parent = parent
	local caps = p.caps ~= false
	b.Text = if caps then Kit.upper(text) else text
	if caps then
		b:GetPropertyChangedSignal("Text"):Connect(function()
			local up = Kit.upper(b.Text)
			if up ~= b.Text then
				b.Text = up
			end
		end)
	end
	local lift = Instance.new("UIPadding") :: UIPadding
	lift.Name = "Lift"
	lift.PaddingLeft = UDim.new(0, 3)
	lift.PaddingRight = UDim.new(0, 3)
	lift.Parent = b
	if p.flat then
		b.BackgroundTransparency = 1
		local u = Instance.new("Frame") :: Frame
		u.Name = "Underline"
		u.AnchorPoint = Vector2.new(0, 1)
		u.Position = UDim2.fromScale(0, 1)
		u.Size = UDim2.new(1, 0, 0, 1)
		u.BackgroundColor3 = Kit.GILT
		u.BorderSizePixel = 0
		u.Visible = false
		u.Parent = b
		b:SetAttribute("flat", true)
	else
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient") :: UIGradient
		g.Name = "Lacquer"
		-- top highlight fading into the lacquer
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(205, 205, 205)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 160, 160)),
		})
		g.Rotation = 90
		g.Parent = b
		local s = Instance.new("UIStroke") :: UIStroke
		s.Name = "Gilt"
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Thickness = 1
		s.Parent = b
	end
	b:SetAttribute("primary", p.primary == true)
	b:SetAttribute("reason", "")
	b:SetAttribute("tip", p.tooltip or "")
	b.Activated:Connect(function()
		if b:GetAttribute("disabled") == true then
			return
		end
		onClick()
	end)
	b.MouseEnter:Connect(function()
		b:SetAttribute("hover", true)
		restyle(b)
		local reason = b:GetAttribute("reason")
		local tip = b:GetAttribute("tip")
		if type(reason) == "string" and reason ~= "" then
			showTooltip(reason)
		elseif type(tip) == "string" and tip ~= "" then
			showTooltip(tip)
		end
	end)
	b.MouseLeave:Connect(function()
		b:SetAttribute("hover", false)
		b:SetAttribute("pressed", false)
		restyle(b)
		hideTooltip()
	end)
	b.MouseButton1Down:Connect(function()
		b:SetAttribute("pressed", true)
		restyle(b)
	end)
	b.MouseButton1Up:Connect(function()
		b:SetAttribute("pressed", false)
		restyle(b)
	end)
	restyle(b)
	return b
end

-- Hover text for any GUI object; the text is computed when the pointer arrives.
function Kit.hoverTip(obj: GuiObject, text: () -> string)
	obj.MouseEnter:Connect(function()
		local t = text()
		if t ~= "" then
			showTooltip(t)
		end
	end)
	obj.MouseLeave:Connect(hideTooltip)
end

-- Disabled buttons stay visible (desaturated) and explain themselves on hover.
function Kit.setEnabled(b: TextButton, enabled: boolean, reason: string?)
	b:SetAttribute("disabled", not enabled)
	b:SetAttribute("reason", if enabled then "" else (reason or ""))
	restyle(b)
end

-- Toggles and selectors: the chosen one turns gilt.
function Kit.setActiveLook(b: TextButton, active: boolean)
	b:SetAttribute("active", active)
	restyle(b)
end

-- ------------------------------------------------------------------ slider

function Kit.slider(parent: Instance, labelText: string, value: number, onChange: (v: number) -> ()): Frame
	local row = Instance.new("Frame") :: Frame
	row.Size = UDim2.new(1, 0, 0, 36)
	row.BackgroundTransparency = 1
	row.Parent = parent
	local l = Kit.label(row, labelText, { size = UDim2.new(1, 0, 0, 16) })
	local valueLabel = Kit.label(row, "", { size = UDim2.new(0, 48, 0, 16), position = UDim2.new(1, -48, 0, 0), align = Enum.TextXAlignment.Right })
	local track = Instance.new("TextButton") :: TextButton
	track.Size = UDim2.new(1, 0, 0, 12)
	track.Position = UDim2.new(0, 0, 0, 20)
	track.BackgroundColor3 = Kit.INSET
	track.BorderSizePixel = 0
	track.Text = ""
	local ts = Instance.new("UIStroke") :: UIStroke
	ts.Color = Kit.GILT_DARK
	ts.Parent = track
	track.AutoButtonColor = false
	track.Parent = row
	local fill = Instance.new("Frame") :: Frame
	fill.BackgroundColor3 = Kit.GILT
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(value, 0, 1, 0)
	fill.Parent = track
	local dragging = false
	local function apply(px: number)
		local v = math.clamp((px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		fill.Size = UDim2.new(v, 0, 1, 0)
		valueLabel.Text = string.format("%d%%", math.round(v * 100))
		onChange(v)
	end
	valueLabel.Text = string.format("%d%%", math.round(value * 100))
	track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			apply(input.Position.X)
		end
	end)
	track.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	local c1 = UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			apply(input.Position.X)
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	row.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
	end)
	l.Name = "Label"
	return row
end

function Kit.toggle(parent: Instance, labelText: string, value: boolean, onChange: (v: boolean) -> ()): TextButton
	local b: TextButton
	local function text(v: boolean): string
		return (if v then "[x] " else "[ ] ") .. labelText
	end
	b = Kit.button(parent, text(value), function()
		value = not value
		b.Text = text(value)
		onChange(value)
	end, { size = UDim2.new(1, 0, 0, 28), caps = false })
	b.TextXAlignment = Enum.TextXAlignment.Left
	return b
end

-- Horizontal bar: dark track with a fill sized by `frac` (0..1). Returns the fill.
function Kit.bar(parent: Instance, size: UDim2, position: UDim2, colour: Color3): Frame
	local track = Instance.new("Frame") :: Frame
	track.Size = size
	track.Position = position
	track.BackgroundColor3 = Kit.INSET
	track.BackgroundTransparency = 0.2
	track.BorderSizePixel = 0
	track.Parent = parent
	local fill = Instance.new("Frame") :: Frame
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = colour
	fill.BorderSizePixel = 0
	fill.Parent = track
	return fill
end

function Kit.setBar(fill: Frame, frac: number)
	fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
end

function Kit.formatClock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", s // 60, s % 60)
end

function Kit.hideTooltip()
	hideTooltip()
end

return Kit
