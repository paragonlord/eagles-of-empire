--!strict
-- Unit card bar (bottom centre): one card per own formation in roster order, grouped by corps,
-- then greyed cards for reinforcements still on the road. Click selects, shift-click toggles,
-- double-click focuses the camera. Routing cards flash; destroyed or exited formations grey
-- out and collapse. Scrolls horizontally when the army is wider than the bar.

local TweenService = game:GetService("TweenService") :: TweenService
local UserInputService = game:GetService("UserInputService") :: UserInputService
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Generals = require(Shared.Generals)
local Kit = require(script.Parent.Kit)
local BattleState = require(script.Parent.Parent.BattleState)
local Selection = require(script.Parent.Parent.Selection)
local Input = require(script.Parent.Parent.Input)
local Camera = require(script.Parent.Parent.Camera)
local Factions = require(script.Parent.Parent.Factions)
local Ledger = require(script.Parent.Ledger)

local CardBar = {}

local FULL_W, COMPACT_W, CARD_H = 58, 46, 80
local COMPACT_ABOVE = 18 -- more cards than this and they narrow
local CARD_W = FULL_W
local ARROW_W = 18
local PAD = 5
local GAP = 3
CardBar.HEIGHT = 96
CardBar.SIDE_MARGIN = 276 -- clear of the command panel (left) and the minimap (right)

local AMBER = Color3.fromRGB(196, 140, 40)
local MORALE_DEFAULT: { [string]: number } = { steady = 100, shaken = 45, routing = 15, shattered = 0 }
local STATE_WORD: { [string]: string } = { idle = "Holding", moving = "Marching", reforming = "Reforming", firing = "Firing", charging = "Charging", melee = "In melee", retreating = "Retreating", routing = "Routing", rallying = "Rallying" }

type Card = {
	root: TextButton,
	stroke: UIStroke,
	name: TextLabel,
	count: TextLabel,
	strength: Frame,
	morale: Frame,
	icons: { [string]: Frame },
	reloadFill: Frame,
	dim: Frame, -- co-op: veils an ally's card
	view: any, -- last FormationView table seen (identity changes when the server resends it)
	seenAt: number,
	lastClick: number,
	routing: boolean,
	shattered: boolean,
}

local panel: Frame? = nil
local scroll: ScrollingFrame? = nil
local arrows: { TextButton } = {}
local cards: { [number]: Card } = {}
local extras: { Instance } = {} -- corps spacers and arriving cards, rebuilt on roster change
local arriving: { [number]: TextLabel } = {}
local rosterKey = ""
local conns: { RBXScriptConnection } = {}

-- ------------------------------------------------------------------ drawing helpers

local function rect(parent: Instance, w: number, h: number, x: number, y: number, rot: number, colour: Color3): Frame
	local f = Instance.new("Frame") :: Frame
	f.Size = UDim2.fromOffset(w, h)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(x, y)
	f.Rotation = rot
	f.BackgroundColor3 = colour
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function ring(parent: Instance, d: number, x: number, y: number, colour: Color3, thickness: number): Frame
	local f = rect(parent, d, d, x, y, 0, colour)
	f.BackgroundTransparency = 1
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = colour
	s.Thickness = thickness
	s.Parent = f
	return f
end

local function box(parent: Instance, d: number, x: number, y: number, colour: Color3): Frame
	local f = rect(parent, d, d, x, y, 0, colour)
	f.BackgroundTransparency = 1
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = colour
	s.Thickness = 1
	s.Parent = f
	return f
end

-- Class glyph centred in a CARD_W x 26 area.
local function glyph(parent: Frame, class: string)
	local cx, cy = CARD_W / 2, 13
	local ink = Kit.IVORY
	if class == "infantry" then -- crossed muskets
		rect(parent, 2, 26, cx, cy, 35, ink)
		rect(parent, 2, 26, cx, cy, -35, ink)
		rect(parent, 4, 7, cx - 6.5, cy + 9.5, 35, ink) -- butts
		rect(parent, 4, 7, cx + 6.5, cy + 9.5, -35, ink)
	elseif class == "cavalry" then -- sabre with crossguard
		local r = math.rad(30)
		rect(parent, 2, 24, cx, cy, 30, ink)
		rect(parent, 11, 2, cx - math.sin(r) * 7, cy + math.cos(r) * 7, 30, ink)
		rect(parent, 3, 5, cx - math.sin(r) * 10, cy + math.cos(r) * 10, 30, ink)
	elseif class == "artillery" then -- barrel on a wheel
		rect(parent, 24, 5, cx + 3, cy - 2, -15, ink)
		ring(parent, 12, cx - 3, cy + 5, ink, 2)
	elseif class == "hq" then -- eight-point star
		rect(parent, 14, 14, cx, cy, 0, Kit.GOLD)
		rect(parent, 14, 14, cx, cy, 45, Kit.GOLD)
		ring(parent, 5, cx, cy, Kit.INSET, 1.5)
	end
end

local function iconSlot(parent: Instance, name: string, order: number): Frame
	local f = Instance.new("Frame") :: Frame
	f.Name = name
	f.Size = UDim2.fromOffset(10, 10)
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.Visible = false
	f.Parent = parent
	return f
end

-- Short form of a formation name for a 58 px card (the tooltip carries the full name).
local ABBREV = {
	{ " — .*$", "" },
	{ " à cheval", "" },
	{ " de ", " " },
	{ "Batterie", "Bty" },
	{ "Battery", "Bty" },
	{ "Battalion", "Bn" },
	{ "Bataillon", "Bn" },
	{ "Regiment", "Rgt" },
	{ "Chasseurs", "Chass." },
	{ "Grenadiers?", "Gren." },
	{ "Cuirassiers", "Cuir." },
	{ "Dragoons", "Drag." },
	{ "Dragoner", "Drag." },
	{ "Husaren", "Huss." },
	{ "Hussars", "Huss." },
	{ "Infanterie", "Inf." },
}
local function abbreviate(name: string): string
	local s = name
	for _, a in ABBREV do
		s = string.gsub(s, a[1], a[2])
	end
	return s
end

local function tipFor(id: number): string
	local f = BattleState.formations[id]
	if not f then
		return ""
	end
	local lines = {
		tostring(f.name or ("#" .. id)),
		tostring(f.corps or ""),
		string.format("%d / %d men · %s", f.strength, f.startStrength, string.upper(string.sub(f.moraleBand, 1, 1)) .. string.sub(f.moraleBand, 2)),
		STATE_WORD[f.state] or f.state,
	}
	if f.status and f.status ~= "" then
		lines[4] ..= " · " .. f.status
	end
	-- generals' traits and abilities acting on it now (the gilt star on the card)
	local tags = (f :: any).tags -- not in BattleState.Formation yet
	if type(tags) == "string" then
		for tag in string.gmatch(tags, "[^,]+") do
			local name, text = Generals.tagInfo(tag)
			if name then
				table.insert(lines, "★ " .. name .. ": " .. tostring(text))
			end
		end
	end
	local ally = BattleState.allyOf(id)
	if ally then
		table.insert(lines, "Commanded by " .. tostring(ally.name))
	end
	return table.concat(lines, "\n")
end

-- ------------------------------------------------------------------ cards

local function newCard(f: any): Card
	local s = scroll :: ScrollingFrame
	local id = f.id
	local b = Instance.new("TextButton") :: TextButton
	b.Name = "Card" .. id
	b.Size = UDim2.fromOffset(CARD_W, CARD_H)
	b.BackgroundColor3 = Kit.WALNUT_LIGHT
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Text = ""
	b.ClipsDescendants = true
	b.Active = true
	b.Parent = s
	local stroke = Instance.new("UIStroke") :: UIStroke
	stroke.Color = Kit.GILT_DARK
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	local header = Instance.new("Frame") :: Frame
	header.Size = UDim2.new(1, 0, 0, 6)
	header.BackgroundColor3 = Factions.colour(f.faction, f.colour)
	header.BorderSizePixel = 0
	header.Parent = b
	-- enamel: a bright glaze over the top half, a gilt edge beneath
	local glaze = Instance.new("UIGradient") :: UIGradient
	glaze.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	glaze.Rotation = 90
	glaze.Parent = header
	local edge = Instance.new("Frame") :: Frame
	edge.Size = UDim2.new(1, 0, 0, 1)
	edge.Position = UDim2.fromOffset(0, 6)
	edge.BackgroundColor3 = Kit.GILT_DARK
	edge.BorderSizePixel = 0
	edge.Parent = b
	local g = Instance.new("Frame") :: Frame
	g.Size = UDim2.fromOffset(CARD_W, 26)
	g.Position = UDim2.fromOffset(0, 7)
	g.BackgroundTransparency = 1
	g.Parent = b
	glyph(g, f.class)
	local name = Kit.label(b, abbreviate(tostring(f.name or id)), { size = UDim2.new(1, -6, 0, 12), position = UDim2.fromOffset(3, 34), textSize = 10, align = Enum.TextXAlignment.Center })
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local count = Kit.label(b, "", { size = UDim2.new(0.6, 0, 0, 10), position = UDim2.fromOffset(4, 47), textSize = 9, font = Enum.Font.GothamBold })
	Kit.label(b, string.rep("›", math.clamp(f.experience or 0, 0, 3)), { size = UDim2.new(0.4, -4, 0, 10), position = UDim2.new(0.6, 0, 0, 47), textSize = 10, font = Enum.Font.GothamBold, colour = Kit.GOLD, align = Enum.TextXAlignment.Right })
	local strength = Kit.bar(b, UDim2.new(1, -8, 0, 4), UDim2.fromOffset(4, 58), Factions.colour(f.faction, f.colour))
	local morale = Kit.bar(b, UDim2.new(1, -8, 0, 4), UDim2.fromOffset(4, 64), Kit.MORALE.steady)

	-- status icons, left to right; hidden ones take no room
	local row = Instance.new("Frame") :: Frame
	row.Size = UDim2.new(1, -8, 0, 10)
	row.Position = UDim2.fromOffset(4, 69)
	row.BackgroundTransparency = 1
	row.Parent = b
	Kit.list(row, 2, true)
	local icons: { [string]: Frame } = {}
	local reload = iconSlot(row, "reload", 1) -- cartridge box filling as the volley reloads
	box(reload, 8, 5, 5, Kit.IVORY)
	local reloadFill = Instance.new("Frame") :: Frame
	reloadFill.AnchorPoint = Vector2.new(0, 1)
	reloadFill.Position = UDim2.fromOffset(2, 8)
	reloadFill.Size = UDim2.fromOffset(6, 0)
	reloadFill.BackgroundColor3 = AMBER
	reloadFill.BorderSizePixel = 0
	reloadFill.Parent = reload
	icons.reload = reload
	local noAmmo = iconSlot(row, "noAmmo", 2) -- struck-through box
	box(noAmmo, 8, 5, 5, Kit.HOSTILE)
	rect(noAmmo, 2, 11, 5, 5, 45, Kit.HOSTILE)
	icons.noAmmo = noAmmo
	local square = iconSlot(row, "square", 3) -- hollow square
	box(square, 8, 5, 5, Kit.IVORY)
	box(square, 4, 5, 5, Kit.IVORY)
	icons.square = square
	local limbered = iconSlot(row, "limbered", 4) -- wheel and trail
	ring(limbered, 7, 4, 5, Kit.IVORY, 1.5)
	rect(limbered, 5, 2, 8, 6, 20, Kit.IVORY)
	icons.limbered = limbered
	local holdFire = iconSlot(row, "holdFire", 5) -- red cross
	rect(holdFire, 2, 11, 5, 5, 45, Kit.HOSTILE)
	rect(holdFire, 2, 11, 5, 5, -45, Kit.HOSTILE)
	icons.holdFire = holdFire
	local general = iconSlot(row, "general", 6) -- gilt diamond: a general's trait or ability applies
	rect(general, 6, 6, 5, 5, 45, Kit.GILT_BRIGHT)
	icons.general = general
	local dim = Instance.new("Frame") :: Frame
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Kit.INSET
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.ZIndex = 4
	dim.Visible = false
	dim.Parent = b

	local card: Card = {
		root = b,
		stroke = stroke,
		name = name,
		count = count,
		strength = strength,
		morale = morale,
		icons = icons,
		reloadFill = reloadFill,
		dim = dim,
		view = nil,
		seenAt = 0,
		lastClick = 0,
		routing = false,
		shattered = false,
	}
	b.Activated:Connect(function()
		local now = os.clock()
		if now - card.lastClick < 0.35 then
			local cur = BattleState.formations[id]
			if cur then
				Camera.focusOn(cur.x, cur.z)
			end
		elseif Input.mode() ~= "off" and BattleState.canCommand(id) then
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
				Selection.toggle(id)
			else
				Selection.set({ id })
			end
		end
		card.lastClick = now
	end)
	Kit.hoverTip(b, function(): string
		return tipFor(id)
	end)
	return card
end

-- Seconds of reload left, run forward locally: the server only resends a formation when
-- something else about it changes.
local function reloadLeft(c: Card, f: any): number
	if c.view ~= f then
		c.view = f
		c.seenAt = os.clock()
	end
	local r = f.reload or 0
	if r <= 0 then
		return 0
	end
	local elapsed = if BattleState.state == "running" then (os.clock() - c.seenAt) * BattleState.speed else 0
	return r - elapsed
end

local function reloadTime(f: any): number
	if f.class == "artillery" then
		local gun = Config.Units.artillery.gun
		return if f.ammoMode == "canister" then gun.canister.reload else gun.roundShot.reload
	end
	local m = Config.Units.infantry.musket
	return if m then m.reload else 15
end

local function paint(c: Card, f: any)
	Kit.setBar(c.strength, f.strength / math.max(f.startStrength, 1))
	c.count.Text = tostring(math.floor(f.strength))
	Kit.setBar(c.morale, (f.morale or MORALE_DEFAULT[f.moraleBand] or 50) / 100)
	c.morale.BackgroundColor3 = (Kit.MORALE :: { [string]: Color3 })[f.moraleBand] or Kit.MUTED
	local left = reloadLeft(c, f)
	local shoots = f.class == "infantry" or f.class == "artillery"
	c.icons.reload.Visible = shoots and left > 0
	c.reloadFill.Size = UDim2.fromOffset(6, math.floor(6 * math.clamp(1 - left / reloadTime(f), 0, 1)))
	c.icons.noAmmo.Visible = shoots and f.ammo ~= nil and f.ammo <= 0
	c.icons.square.Visible = f.shape == "square"
	c.icons.limbered.Visible = f.class == "artillery" and (f.limbered == true or f.shape == "limbered")
	c.icons.holdFire.Visible = shoots and f.fireAtWill == false
	c.icons.general.Visible = type(f.tags) == "string" and f.tags ~= ""
	c.routing = f.state == "routing" or f.moraleBand == "routing"
	c.shattered = f.moraleBand == "shattered"
	c.dim.Visible = BattleState.allyOf(f.id) ~= nil
	local sel = Selection.isSelected(f.id)
	c.stroke.Color = if sel then Kit.GILT_BRIGHT else Kit.GILT_DARK
	c.stroke.Thickness = if sel then 2 else 1
	c.stroke.Transparency = if sel then 0 else 0.4
	if not c.routing then
		c.root.BackgroundColor3 = if c.shattered then Kit.SLATE elseif sel then Kit.BLUE_LIGHT else Kit.WALNUT_LIGHT
	end
end

-- Grey the card out, then fold it away.
local function retire(c: Card)
	local cover = Instance.new("Frame") :: Frame
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Kit.INSET
	cover.BackgroundTransparency = 0.3
	cover.BorderSizePixel = 0
	cover.ZIndex = 5
	cover.Parent = c.root
	c.root.Active = false
	local tw = TweenService:Create(c.root, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), { Size = UDim2.fromOffset(0, CARD_H) })
	tw.Completed:Connect(function()
		c.root:Destroy()
	end)
	tw:Play()
end

local function spacer(order: number)
	local s = Instance.new("Frame") :: Frame
	s.Size = UDim2.fromOffset(5, CARD_H)
	s.BackgroundTransparency = 1
	s.LayoutOrder = order
	s.Parent = scroll
	local rule = Instance.new("Frame") :: Frame
	rule.Size = UDim2.new(0, 1, 0.7, 0)
	rule.Position = UDim2.fromScale(0.5, 0.15)
	rule.BackgroundColor3 = Kit.GOLD
	rule.BorderSizePixel = 0
	rule.Parent = s
	table.insert(extras, s)
end

local function arrivingCard(r: any, order: number)
	local f = Instance.new("Frame") :: Frame
	f.Size = UDim2.fromOffset(CARD_W, CARD_H)
	f.BackgroundColor3 = Kit.PANEL_DARK
	f.BackgroundTransparency = 0.3
	f.BorderSizePixel = 0
	f.Active = true
	f.LayoutOrder = order
	f.Parent = scroll
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = Kit.MUTED
	s.Thickness = 1
	s.Parent = f
	local header = Instance.new("Frame") :: Frame
	header.Size = UDim2.new(1, 0, 0, 5)
	header.BackgroundColor3 = Kit.MUTED
	header.BorderSizePixel = 0
	header.Parent = f
	Kit.label(f, "on the road", { size = UDim2.new(1, 0, 0, 12), position = UDim2.fromOffset(0, 10), textSize = 9, colour = Kit.MUTED, align = Enum.TextXAlignment.Center })
	local eta = Kit.label(f, "", { size = UDim2.new(1, 0, 0, 14), position = UDim2.fromOffset(0, 22), textSize = 12, font = Enum.Font.GothamBold, colour = Kit.MUTED, align = Enum.TextXAlignment.Center })
	local n = Kit.label(f, abbreviate(tostring(r.name)), { size = UDim2.new(1, -6, 0, 24), position = UDim2.fromOffset(3, 40), textSize = 10, wrap = true, colour = Kit.MUTED, align = Enum.TextXAlignment.Center })
	n.TextTruncate = Enum.TextTruncate.AtEnd
	local rname, rcorps = tostring(r.name), tostring(r.corps or "")
	Kit.hoverTip(f, function(): string
		return rname .. "\n" .. rcorps .. "\nReinforcement, not yet on the field"
	end)
	arriving[r.id] = eta
	table.insert(extras, f)
end

local function relayout(forms: { any })
	local want = if #forms + #BattleState.reinforcements > COMPACT_ABOVE then COMPACT_W else FULL_W
	if want ~= CARD_W then
		-- every card is drawn for one width: rebuild them all
		CARD_W = want
		for _, c in cards do
			c.root:Destroy()
		end
		table.clear(cards)
	end
	for _, e in extras do
		e:Destroy()
	end
	table.clear(extras)
	table.clear(arriving)
	-- corps in order of their first formation, formations by id inside a corps
	local corpsRank: { [string]: number } = {}
	for _, f in forms do -- forms is id-sorted
		local k = tostring(f.corps)
		if corpsRank[k] == nil then
			local n = 0
			for _ in corpsRank do
				n += 1
			end
			corpsRank[k] = n
		end
	end
	local present: { [number]: boolean } = {}
	local spaced: { [number]: boolean } = {}
	for _, f in forms do
		present[f.id] = true
		local rank = corpsRank[tostring(f.corps)]
		local c = cards[f.id]
		if not c then
			c = newCard(f)
			cards[f.id] = c
		end
		-- co-op: your wing first, allies' cards after it
		local wing = if BattleState.isMine(f.id) then 0 else 500000000
		c.root.LayoutOrder = wing + rank * 100000 + f.id * 2
		local key = wing + rank * 100000
		if key > 0 and not spaced[key] then
			spaced[key] = true
			spacer(key)
		end
	end
	for id, c in cards do
		if not present[id] then
			cards[id] = nil
			retire(c)
		end
	end
	local base = 1000000000
	if #BattleState.reinforcements > 0 and #forms > 0 then
		spacer(base)
	end
	for i, r in BattleState.reinforcements do
		arrivingCard(r, base + i)
	end
end

local function step(): number
	return CARD_W + GAP
end

local function refreshArrows()
	local s = scroll
	if not s or #arrows < 2 then
		return
	end
	local maxX = math.max(0, s.AbsoluteCanvasSize.X - s.AbsoluteWindowSize.X)
	Kit.setEnabled(arrows[1], s.CanvasPosition.X > 1, "Start of the line")
	Kit.setEnabled(arrows[2], s.CanvasPosition.X < maxX - 1, "End of the line")
end

-- Size the bar to its cards; when they overflow, show gilt arrows at both ends and trim the
-- window to a whole number of cards so none is drawn half-cut at the edge.
local function fitWidth()
	local p, s = panel, scroll
	if not p or not s then
		return
	end
	local layout = s:FindFirstChildOfClass("UIListLayout") :: UIListLayout?
	local sg = p.Parent :: ScreenGui
	local k = Kit.scale() -- absolute sizes carry the touch UIScale; offsets do not
	local content = if layout then layout.AbsoluteContentSize.X / k else 0
	-- touch: the bar starts at the left edge and stops short of the command panel on the right
	local avail = math.max(if Kit.touch() then sg.AbsoluteSize.X / k - 8 - 272 else sg.AbsoluteSize.X / k - 2 * CardBar.SIDE_MARGIN, CARD_W + 2 * PAD)
	local overflow = content + 2 * PAD > avail
	for _, a in arrows do
		a.Visible = overflow
	end
	if overflow then
		local window = math.max(step(), math.floor((avail - 2 * PAD - 2 * (ARROW_W + 4) + GAP) / step()) * step() - GAP)
		s.Position = UDim2.fromOffset(ARROW_W + 4, 0)
		s.Size = UDim2.new(0, window, 1, 0)
		p.Size = UDim2.fromOffset(window + 2 * PAD + 2 * (ARROW_W + 4), CardBar.HEIGHT)
	else
		s.Position = UDim2.new()
		s.Size = UDim2.fromScale(1, 1)
		p.Size = UDim2.fromOffset(content + 2 * PAD, CardBar.HEIGHT)
	end
	p.Visible = content > 0
	refreshArrows()
end

-- ------------------------------------------------------------------ API

function CardBar.create(sg: ScreenGui)
	CardBar.destroy()
	local p = Kit.panel(sg, { size = UDim2.fromOffset(200, CardBar.HEIGHT), position = UDim2.new(0.5, 0, 1, -8), anchor = Vector2.new(0.5, 1), padding = PAD, transparency = 0.12 })
	p.Name = "CardBar"
	if Kit.touch() then
		p.Position = UDim2.new(0, 8, 1, -8)
		p.AnchorPoint = Vector2.new(0, 1)
	end
	local s = Instance.new("ScrollingFrame") :: ScrollingFrame
	s.Size = UDim2.fromScale(1, 1)
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollingDirection = Enum.ScrollingDirection.X
	s.AutomaticCanvasSize = Enum.AutomaticSize.X
	s.CanvasSize = UDim2.new()
	s.ScrollBarThickness = 6
	s.ScrollBarImageColor3 = Kit.GILT
	s.ScrollBarImageTransparency = 0
	s.Active = true
	s.Parent = p
	local layout = Kit.list(s, GAP, true)
	panel = p
	scroll = s
	-- page by whole cards
	for i, dir in { -1, 1 } do
		local b = Kit.button(p, if dir < 0 then "‹" else "›", function()
			local page = math.max(step(), math.floor(s.AbsoluteWindowSize.X / step()) * step())
			local maxX = math.max(0, s.AbsoluteCanvasSize.X - s.AbsoluteWindowSize.X)
			local x = math.clamp(s.CanvasPosition.X + dir * page, 0, maxX)
			s.CanvasPosition = Vector2.new(math.round(x / step()) * step(), 0)
		end, { size = UDim2.new(0, ARROW_W, 1, 0), position = UDim2.fromScale(if dir < 0 then 0 else 1, 0), anchor = Vector2.new(if dir < 0 then 0 else 1, 0), textSize = 22, font = Enum.Font.Garamond, tooltip = if dir < 0 then "Earlier formations" else "More formations" })
		b.Visible = false
		arrows[i] = b
	end
	table.insert(conns, s:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshArrows))
	table.insert(conns, layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitWidth))
	table.insert(conns, sg:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWidth))
	-- the wheel scrolls the cards sideways instead of zooming the camera
	table.insert(conns, s.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			s.CanvasPosition = Vector2.new(math.max(0, s.CanvasPosition.X - input.Position.Z * 80), 0)
		end
	end))
	rosterKey = ""
	fitWidth()
end

function CardBar.update()
	if not scroll then
		return
	end
	local forms = BattleState.ownFormations()
	local ids = {}
	for _, f in forms do
		table.insert(ids, if BattleState.isMine(f.id) then f.id else -f.id - 0.5) -- wing changes relayout
	end
	for _, r in BattleState.reinforcements do
		table.insert(ids, -r.id)
	end
	Ledger.observe(forms)
	local key = table.concat(ids, ",")
	if key ~= rosterKey then
		rosterKey = key
		relayout(forms)
	end
	for _, f in forms do
		local c = cards[f.id]
		if c then
			paint(c, f)
		end
	end
	for _, r in BattleState.reinforcements do
		local l = arriving[r.id]
		if l then
			l.Text = Kit.formatClock(r.eta or 0)
		end
	end
end

-- Per frame: routing cards pulse red, reload boxes keep filling between snapshots.
function CardBar.animate()
	local pulse = (math.sin(os.clock() * 8) + 1) / 2
	for id, c in cards do
		if c.routing then
			c.root.BackgroundColor3 = Kit.WALNUT_LIGHT:Lerp(Kit.MORALE.routing, 0.25 + 0.6 * pulse)
		end
		if c.icons.reload.Visible then
			local f = BattleState.formations[id]
			if f then
				local left = reloadLeft(c, f)
				c.reloadFill.Size = UDim2.fromOffset(6, math.floor(6 * math.clamp(1 - left / reloadTime(f), 0, 1)))
				if left <= 0 then
					c.icons.reload.Visible = false
				end
			end
		end
	end
end

function CardBar.destroy()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	if panel then
		panel:Destroy()
	end
	panel = nil
	scroll = nil
	table.clear(arrows)
	CARD_W = FULL_W
	table.clear(cards)
	table.clear(extras)
	table.clear(arriving)
	rosterKey = ""
end

return CardBar
