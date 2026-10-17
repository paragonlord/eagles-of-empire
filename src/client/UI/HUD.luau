--!strict
-- Battle HUD, laid out after Napoleon: Total War. Top bar (name, clock / limit, pause and
-- speeds, weather), balance of power and objective banners under it, message ticker top-left,
-- selection inspector and command panel bottom-left, unit cards bottom-centre, framed minimap
-- bottom-right. Everything hugs the screen edges; the centre of the field stays clear.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Generals = require(Shared.Generals)
local Kit = require(script.Parent.Kit)
local Minimap = require(script.Parent.Minimap)
local CardBar = require(script.Parent.CardBar)
local Ledger = require(script.Parent.Ledger)
local BattleState = require(script.Parent.Parent.BattleState)
local Selection = require(script.Parent.Parent.Selection)
local Net = require(script.Parent.Parent.Net)
local Input = require(script.Parent.Parent.Input)
local Signal = require(script.Parent.Parent.Signal)

local HUD = {}

export type Callbacks = { settings: () -> (), help: () -> (), menu: () -> () }

local EDGE = 8
local CMD_W = 256
local BOTTOM_H = CardBar.HEIGHT

local gui: ScreenGui? = nil
local cb: Callbacks? = nil
local conns: { Signal.Connection } = {}
local weather: string? = nil

-- top bar
local clockLabel: TextLabel? = nil
local lagLabel: TextLabel? = nil
local weatherLabel: TextLabel? = nil
local speedButtons: { [number]: TextButton } = {}
local pauseButton: TextButton? = nil
local balanceOwn: Frame? = nil
local balanceText = ""
local objectiveStrip: Frame? = nil
local objectiveChips: { [string]: { frame: Frame, pennant: Frame, label: TextLabel, bar: Frame } } = {}

-- ticker
local tickerLines: { { label: TextLabel, t0: number, base: number } } = {}
local tickerFrame: Frame? = nil
local tickerOrder = 0
local TICKER_LIFE = 9

-- inspector
local inspector: Frame? = nil
local inspectorFields: { [string]: TextLabel } = {}
local inspectorBarFill: Frame? = nil
local inspectorTip: () -> string -- defined after updateInspector

-- command panel
local commandButtons: { [string]: TextButton } = {}
local rallyBar: Frame? = nil
local toast: TextLabel? = nil
local toastT0 = 0

local MORALE_WORD: { [string]: string } = { steady = "Steady", shaken = "Shaken", routing = "Routing", shattered = "Shattered" }
local STATE_WORD: { [string]: string } = { idle = "Holding", moving = "Marching", reforming = "Reforming", firing = "Firing", charging = "Charging", melee = "Melee", retreating = "Retreating", routing = "Routing", rallying = "Rallying", destroyed = "Destroyed", exited = "Exited" }

local GARAMOND_BOLD = Font.new(Font.fromEnum(Enum.Font.Garamond).Family, Enum.FontWeight.Bold)
local GARAMOND = Font.fromEnum(Enum.Font.Garamond)

local function selectedFormations(): { any }
	local out = {}
	for _, id in Selection.ids() do
		local f = BattleState.formations[id]
		if f then
			table.insert(out, f)
		end
	end
	return out
end

local function idsOfClass(forms: { any }, classes: { [string]: boolean }): { number }
	local ids = {}
	for _, f in forms do
		if classes[f.class] and f.state ~= "routing" then
			table.insert(ids, f.id)
		end
	end
	return ids
end

-- ------------------------------------------------------------------ top bar

local function buildTopBar(sg: ScreenGui)
	-- dark band: no frame, a crimson hairline over a gold lower rule
	local bar = Kit.panel(sg, { size = UDim2.new(1, 0, 0, 36), position = UDim2.new(0, 0, 0, 0), transparency = 0.04, plain = true })
	local bs = bar:FindFirstChildOfClass("UIStroke") :: UIStroke?
	if bs then
		bs.Enabled = false
	end
	for _, r in { { 2, -2, Kit.GILT }, { 1, -3, Kit.CRIMSON } } do
		local line = Instance.new("Frame") :: Frame
		line.Size = UDim2.new(1, 0, 0, r[1] :: number)
		line.Position = UDim2.new(0, 0, 1, r[2] :: number)
		line.BackgroundColor3 = r[3] :: Color3
		line.BorderSizePixel = 0
		line.Parent = bar
	end
	local sc = BattleState.scenario
	local name = Kit.title(bar, if sc then sc.name else "", { size = UDim2.new(0.5, -230, 1, 0), position = UDim2.new(0, 12, 0, 0), textSize = 20 })
	name.TextTruncate = Enum.TextTruncate.AtEnd

	-- centre: clock / limit, pause, speeds, weather
	local mid = Instance.new("Frame") :: Frame
	mid.Size = UDim2.fromOffset(0, 26)
	mid.AutomaticSize = Enum.AutomaticSize.X
	mid.Position = UDim2.new(0.5, 0, 0, 5)
	mid.AnchorPoint = Vector2.new(0.5, 0)
	mid.BackgroundTransparency = 1
	mid.Parent = bar
	local ml = Kit.list(mid, 6, true)
	ml.VerticalAlignment = Enum.VerticalAlignment.Center
	clockLabel = Kit.label(mid, "00:00", { size = UDim2.fromOffset(118, 26), textSize = 16, font = Enum.Font.GothamBold, align = Enum.TextXAlignment.Right })
	;(clockLabel :: TextLabel).LayoutOrder = 1
	local pb = Kit.button(mid, "II", function()
		if BattleState.state == "paused" then
			Net.control("resume")
		else
			Net.control("pause")
		end
	end, { size = UDim2.fromOffset(34, 26), order = 2, font = Enum.Font.GothamBlack, tooltip = "Pause / resume (Space)" })
	pauseButton = pb
	for i, s in { 1, 2, 4 } do
		local b = Kit.button(mid, "×" .. s, function()
			if BattleState.state == "paused" then
				Net.control("resume")
			end
			Net.control("speed", s)
		end, { size = UDim2.fromOffset(34, 26), order = 2 + i, tooltip = "Speed ×" .. s .. " (key " .. i .. ")" })
		speedButtons[s] = b
	end
	weatherLabel = Kit.title(mid, "", { size = UDim2.fromOffset(118, 26), textSize = 18 })
	;(weatherLabel :: TextLabel).LayoutOrder = 6
	lagLabel = Kit.label(mid, "", { size = UDim2.fromOffset(0, 26), textSize = 11, colour = Kit.HOSTILE })
	;(lagLabel :: TextLabel).AutomaticSize = Enum.AutomaticSize.X
	;(lagLabel :: TextLabel).LayoutOrder = 7

	local right = Instance.new("Frame") :: Frame
	right.Size = UDim2.fromOffset(220, 26)
	right.Position = UDim2.new(1, -EDGE, 0, 5)
	right.AnchorPoint = Vector2.new(1, 0)
	right.BackgroundTransparency = 1
	right.Parent = bar
	local l = Kit.list(right, 6, true)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	Kit.button(right, "Help", function()
		if cb then
			cb.help()
		end
	end, { size = UDim2.fromOffset(60, 26), order = 1 })
	Kit.button(right, "Settings", function()
		if cb then
			cb.settings()
		end
	end, { size = UDim2.fromOffset(80, 26), order = 2 })
	Kit.button(right, "Menu", function()
		if cb then
			cb.menu()
		end
	end, { size = UDim2.fromOffset(60, 26), order = 3, tooltip = "Leave the battle" })

	-- balance of power: own strength against the enemy strength we can see
	local bal = Kit.panel(sg, { size = UDim2.fromOffset(320, 12), position = UDim2.new(0.5, 0, 0, 42), anchor = Vector2.new(0.5, 0), transparency = 0, plain = true })
	local bg = bal:FindFirstChildOfClass("UIGradient")
	if bg then
		bg:Destroy()
	end
	bal.BackgroundColor3 = Kit.factionColour(BattleState.enemyFaction)
	local own = Instance.new("Frame") :: Frame
	own.Size = UDim2.fromScale(0.5, 1)
	own.BackgroundColor3 = Kit.BLUE_LIGHT
	own.BorderSizePixel = 0
	own.Parent = bal
	local tick = Instance.new("Frame") :: Frame
	tick.Size = UDim2.new(0, 2, 1, 4)
	tick.Position = UDim2.fromScale(0.5, 0.5)
	tick.AnchorPoint = Vector2.new(0.5, 0.5)
	tick.BackgroundColor3 = Kit.GOLD
	tick.BorderSizePixel = 0
	tick.Parent = bal
	Kit.hoverTip(bal, function(): string
		return balanceText
	end)
	balanceOwn = own

	local strip = Instance.new("Frame") :: Frame
	strip.Size = UDim2.new(0, 640, 0, 24)
	strip.Position = UDim2.new(0.5, 0, 0, 60)
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.BackgroundTransparency = 1
	strip.Parent = sg
	local sl = Kit.list(strip, 6, true)
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	objectiveStrip = strip
end

local function updateBalance()
	local own, enemy = 0, 0
	for _, f in BattleState.formations do
		if f.state ~= "destroyed" and f.state ~= "exited" then
			if f.faction == BattleState.viewerFaction then
				own += f.strength
			else
				enemy += f.strength
			end
		end
	end
	local o = balanceOwn
	if o then
		-- neutral grey until the first enemy formation is in sight
		local sighted = enemy > 0
		o.Size = UDim2.fromScale(if sighted then own / (own + enemy) else 1, 1)
		o.BackgroundColor3 = if sighted then Kit.BLUE_LIGHT else Kit.SLATE
	end
	balanceText = if enemy > 0
		then string.format("Balance of power\nYour army: %d men\nKnown enemy strength: %d men\n(only the enemy formations you can see)", own, enemy)
		else string.format("Balance of power\nYour army: %d men\nNo enemy sighted", own)
end

local function objectiveTip(id: string): string
	for _, o in BattleState.objectives do
		if o.id == id then
			local owner = if o.owner then Kit.factionName(o.owner) else "Unclaimed"
			local t = string.format("%s\nHeld by: %s", o.name, owner)
			if o.contested then
				t ..= "\nContested"
			elseif o.capturing and (o.progress or 0) > 0 then
				t ..= string.format("\n%s capturing: %d%%", Kit.factionName(o.capturing), math.floor((o.progress or 0) * 100))
			end
			return t
		end
	end
	return ""
end

local function updateObjectives()
	local strip = objectiveStrip
	if not strip then
		return
	end
	for i, o in BattleState.objectives do
		local chip = objectiveChips[o.id]
		if not chip then
			local f = Kit.panel(strip, { size = UDim2.fromOffset(124, 24), position = UDim2.new(), transparency = 0.12, plain = true })
			f.LayoutOrder = i
			local pennant = Instance.new("Frame") :: Frame
			pennant.Size = UDim2.new(0, 7, 1, 0)
			pennant.BorderSizePixel = 0
			pennant.Parent = f
			local lbl = Kit.title(f, o.name, { size = UDim2.new(1, -14, 1, -3), position = UDim2.new(0, 11, 0, 0), textSize = 15, align = Enum.TextXAlignment.Center, caps = false })
			lbl.TextTruncate = Enum.TextTruncate.AtEnd
			local bar = Instance.new("Frame") :: Frame
			bar.Size = UDim2.new(0, 0, 0, 3)
			bar.Position = UDim2.new(0, 7, 1, -3)
			bar.BorderSizePixel = 0
			bar.Parent = f
			local oid = o.id
			Kit.hoverTip(f, function(): string
				return objectiveTip(oid)
			end)
			chip = { frame = f, pennant = pennant, label = lbl, bar = bar }
			objectiveChips[o.id] = chip
		end
		chip.pennant.BackgroundColor3 = if o.owner then Kit.factionColour(o.owner) else Kit.PANEL_DARK
		chip.label.TextColor3 = if o.contested then Kit.HOSTILE else Kit.IVORY
		chip.bar.BackgroundColor3 = Kit.factionColour(o.capturing or o.owner)
		chip.bar.Size = UDim2.new(math.clamp(o.progress or 0, 0, 1), -7, 0, 3)
	end
end

local function updateTopBar()
	if clockLabel then
		local limit = BattleState.timeLimit
		if limit <= 0 then
			local sc = BattleState.scenario
			limit = if sc and sc.timeLimit then sc.timeLimit else Config.Victory.TimeLimitSeconds
		end
		clockLabel.Text = Kit.formatClock(BattleState.clock) .. " / " .. Kit.formatClock(limit)
	end
	if weatherLabel then
		local w = (Config.Weather :: any)[weather or "clear"]
		weatherLabel.Text = if w then w.label else ""
	end
	if lagLabel then
		lagLabel.Text = if BattleState.simLag > 0.5 then string.format("lag %.1fs", BattleState.simLag) else ""
	end
	local paused = BattleState.state == "paused"
	for s, b in speedButtons do
		Kit.setActiveLook(b, not paused and BattleState.speed == s)
		Kit.setEnabled(b, BattleState.isCommander, "Only the commander sets the speed")
	end
	if pauseButton then
		pauseButton.Text = if paused then ">" else "II"
		Kit.setActiveLook(pauseButton, paused)
		Kit.setEnabled(pauseButton, BattleState.isCommander, "Only the commander may pause")
	end
	updateBalance()
end

-- ------------------------------------------------------------------ ticker

local function buildTicker(sg: ScreenGui)
	local f = Instance.new("Frame") :: Frame
	f.Size = UDim2.fromOffset(440, 96)
	f.Position = UDim2.new(0, 12, 0, 44)
	f.BackgroundTransparency = 1
	f.Parent = sg
	Kit.list(f, 3)
	tickerFrame = f
end

local function escape(s: string): string
	return (string.gsub(string.gsub(string.gsub(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- Up to four lines, newest at the bottom, fading out. `bold` for routs and captures.
-- `ribbon` paints the line on a solid band (crimson for routs and losses) in ivory.
function HUD.message(text: string, colour: Color3?, bold: boolean?, ribbon: Color3?)
	local f = tickerFrame
	if not f then
		return
	end
	if #tickerLines >= 4 then
		local old = table.remove(tickerLines, 1)
		if old then
			old.label:Destroy()
		end
	end
	local l = Kit.label(f, escape(text), { size = UDim2.fromOffset(0, 20), textSize = 17, colour = if ribbon then Kit.IVORY else (colour or Kit.CREAM), rich = true })
	l.FontFace = if bold then GARAMOND_BOLD else GARAMOND
	l.AutomaticSize = Enum.AutomaticSize.X
	l.BackgroundColor3 = ribbon or Kit.INSET
	local base = if ribbon then 0.08 else 0.45
	l.BackgroundTransparency = base
	l.TextStrokeTransparency = 0.5
	l.TextStrokeColor3 = Kit.INK
	local pad = Instance.new("UIPadding") :: UIPadding
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = l
	if bold then
		local edge = Instance.new("Frame") :: Frame
		edge.Size = UDim2.new(0, 2, 1, 0)
		edge.Position = UDim2.fromOffset(-8, 0)
		edge.BackgroundColor3 = Kit.GOLD
		edge.BorderSizePixel = 0
		edge.Parent = l
	end
	tickerOrder += 1
	l.LayoutOrder = tickerOrder
	table.insert(tickerLines, { label = l, t0 = os.clock(), base = base })
end

local function updateTicker()
	local now = os.clock()
	local i = 1
	while i <= #tickerLines do
		local e = tickerLines[i]
		local age = now - e.t0
		if age > TICKER_LIFE then
			e.label:Destroy()
			table.remove(tickerLines, i)
		else
			local fade = math.clamp((age - TICKER_LIFE + 3) / 3, 0, 1)
			e.label.TextTransparency = fade
			e.label.TextStrokeTransparency = 0.5 + 0.5 * fade
			e.label.BackgroundTransparency = e.base + (1 - e.base) * fade
			i += 1
		end
	end
	if toast and now - toastT0 > 3 then
		toast.Visible = false
	end
end

-- ------------------------------------------------------------------ inspector

local INSPECTOR_FIELDS = { "corps", "class", "strength", "morale", "fatigue", "ammo", "shape", "status" }

local function buildInspector(sg: ScreenGui)
	local p = Kit.panel(sg, { size = UDim2.fromOffset(CMD_W, 190), position = UDim2.new(0, EDGE, 1, -EDGE - BOTTOM_H - 6), anchor = Vector2.new(0, 1), transparency = 0.1, padding = 10 })
	inspectorFields.name = Kit.title(p, "", { size = UDim2.new(1, -40, 0, 26), textSize = 21, caps = false })
	inspectorFields.name.TextTruncate = Enum.TextTruncate.AtEnd
	inspectorFields.exp = Kit.label(p, "", { size = UDim2.new(0, 40, 0, 26), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0), textSize = 16, font = Enum.Font.GothamBold, align = Enum.TextXAlignment.Right, colour = Kit.GOLD })
	inspectorBarFill = Kit.bar(p, UDim2.new(1, 0, 0, 6), UDim2.new(0, 0, 0, 30), Kit.FRANCE)
	local y = 40
	local names = { corps = "Corps", class = "Class", strength = "Strength", morale = "Morale", fatigue = "Fatigue", ammo = "Ammunition", shape = "Shape", status = "Status" }
	for i, key in INSPECTOR_FIELDS do
		local col = (i - 1) % 2
		local rowY = y + ((i - 1) // 2) * 32
		local k = Kit.label(p, names[key], { size = UDim2.new(0.5, -4, 0, 12), position = UDim2.new(col * 0.5, 0, 0, rowY), textSize = 10, colour = Kit.MUTED })
		k.Name = key .. "Key"
		inspectorFields[key] = Kit.label(p, "—", { size = UDim2.new(0.5, -4, 0, 18), position = UDim2.new(col * 0.5, 0, 0, rowY + 12), textSize = 12, font = Enum.Font.GothamBold })
		inspectorFields[key].TextTruncate = Enum.TextTruncate.AtEnd
	end
	p.Visible = false
	inspector = p
	Kit.hoverTip(p, function(): string
		return inspectorTip()
	end)
end

local function updateInspector()
	local p = inspector
	if not p then
		return
	end
	local forms = selectedFormations()
	if #forms == 0 then
		p.Visible = false
		return
	end
	p.Visible = true
	local f = forms[1]
	local F = inspectorFields
	F.name.Text = if #forms > 1 then string.format("%s  (+%d)", tostring(f.name or f.id), #forms - 1) else tostring(f.name or f.id)
	F.exp.Text = string.rep("›", math.clamp(f.experience or 0, 0, 3))
	F.corps.Text = tostring(f.corps or "—")
	F.class.Text = string.upper(string.sub(f.class, 1, 1)) .. string.sub(f.class, 2)
	F.strength.Text = string.format("%d / %d", f.strength, f.startStrength)
	if inspectorBarFill then
		Kit.setBar(inspectorBarFill, f.strength / math.max(f.startStrength, 1))
		inspectorBarFill.BackgroundColor3 = Kit.factionColour(f.faction)
	end
	F.morale.Text = string.format("%s%s", MORALE_WORD[f.moraleBand] or f.moraleBand, if f.morale then string.format(" (%d)", math.floor(f.morale)) else "")
	F.morale.TextColor3 = if f.moraleBand == "steady" then Kit.IVORY else Kit.HOSTILE
	F.fatigue.Text = if f.fatigue then (if f.fatigue < 30 then "Fresh" elseif f.fatigue < 70 then "Tired" else "Exhausted") .. string.format(" (%d)", math.floor(f.fatigue)) else "—"
	if f.class == "artillery" then
		F.ammo.Text = string.format("%s rounds · %s", if f.ammo then tostring(math.floor(f.ammo)) else "?", tostring(f.ammoMode or "auto"))
	elseif f.class == "infantry" then
		F.ammo.Text = if f.ammo then tostring(math.floor(f.ammo)) else "—"
	else
		F.ammo.Text = "—"
	end
	F.shape.Text = string.upper(string.sub(f.shape, 1, 1)) .. string.sub(f.shape, 2) .. (if f.fireAtWill == false then " · hold fire" else "")
	local status = STATE_WORD[f.state] or f.state
	if f.status and f.status ~= "" then
		status ..= " · " .. f.status
	elseif f.reload and f.reload > 0 then
		status ..= " · reloading"
	end
	F.status.Text = status
	-- the HQ's general: his traits replace the (empty) ammunition field; hover for the details
	local ammoKey = p:FindFirstChild("ammoKey") :: TextLabel?
	local g = if f.class == "hq" and f.general then Generals.byId[f.general] else nil
	if ammoKey then
		ammoKey.Text = if g then g.rank .. " " .. Generals.displayName(g, f.name) else "Ammunition"
	end
	if g then
		local names = {}
		for _, tr in g.traits do
			table.insert(names, tr.name)
		end
		F.ammo.Text = if #names > 0 then table.concat(names, " · ") else "No traits"
	end
end

-- Inspector hover: every trait / ability modifier on the first selected formation, in full.
inspectorTip = function(): string
	local f = selectedFormations()[1]
	if not f then
		return ""
	end
	local lines = {}
	local g = if f.class == "hq" and f.general then Generals.byId[f.general] else nil
	if g then
		for _, tr in g.traits do
			table.insert(lines, Generals.describe(tr))
		end
		table.insert(lines, g.ability.name .. ": " .. g.ability.text)
	end
	if type(f.tags) == "string" and f.tags ~= "" then
		table.insert(lines, "Now affecting this formation:")
		for id in string.gmatch(f.tags, "[^,]+") do
			local name, text = Generals.tagInfo(id)
			if name then
				table.insert(lines, "• " .. name .. ": " .. tostring(text))
			end
		end
	end
	return table.concat(lines, "\n")
end

-- ------------------------------------------------------------------ command panel

type CommandDef = { key: string, text: string, tip: string }
-- Grid order, four to a row: formations, then stance and orders, then guns and the staff.
local COMMANDS: { CommandDef } = {
	{ key = "line", text = "Line", tip = "Three ranks: full fire, slow (infantry/cavalry)" },
	{ key = "column", text = "Column", tip = "Deep column: fast, strong in the charge, weak to fire" },
	{ key = "square", text = "Square", tip = "Hollow box against cavalry; artillery loves it" },
	{ key = "wedge", text = "Wedge", tip = "Cavalry charge formation" },
	{ key = "fire", text = "Fire at will", tip = "Toggle: fire at any target in range" },
	{ key = "charge", text = "Charge", tip = "Then right-click a target or a point" },
	{ key = "hold", text = "Hold", tip = "Stand and hold position" },
	{ key = "stop", text = "Halt", tip = "Cancel orders and halt" },
	{ key = "retreat", text = "Retreat", tip = "Fall back toward your edge" },
	{ key = "limber", text = "Limber", tip = "Guns: limber to move, unlimber to fire" },
	{ key = "ammo", text = "Auto", tip = "Ammunition, click to cycle: auto / round shot (long) / canister (short)" },
	{ key = "rally", text = "Rally", tip = "HQ: rally routing formations within 100 studs" },
}

local AMMO_CYCLE = { auto = "roundShot", roundShot = "canister", canister = "auto" }

local function runCommand(key: string)
	local forms = selectedFormations()
	if key == "line" or key == "column" or key == "square" then
		local ids = idsOfClass(forms, { infantry = true, cavalry = key == "line" })
		if #ids > 0 then
			Input.sendOrder("Shape", ids, { shape = key })
		end
	elseif key == "wedge" then
		local ids = idsOfClass(forms, { cavalry = true })
		if #ids > 0 then
			Input.sendOrder("Shape", ids, { shape = "wedge" })
		end
	elseif key == "fire" then
		local ids = idsOfClass(forms, { infantry = true, artillery = true })
		if #ids > 0 then
			local first = BattleState.formations[ids[1]]
			Input.sendOrder("Stance", ids, { fireAtWill = not (first and first.fireAtWill ~= false) })
		end
	elseif key == "charge" then
		Input.arm(if Input.armed() == "Charge" then nil else "Charge")
		HUD.refreshCommands()
	elseif key == "hold" or key == "stop" or key == "retreat" then
		local ids = idsOfClass(forms, { infantry = true, cavalry = true, artillery = true, hq = true })
		if #ids > 0 then
			Input.sendOrder(if key == "hold" then "Hold" elseif key == "stop" then "Stop" else "Retreat", ids, {})
		end
	elseif key == "limber" then
		local ids = idsOfClass(forms, { artillery = true })
		if #ids > 0 then
			local first = BattleState.formations[ids[1]]
			Input.sendOrder("Limber", ids, { limbered = not (first and first.limbered == true) })
		end
	elseif key == "ammo" then
		local ids = idsOfClass(forms, { artillery = true })
		if #ids > 0 then
			local first = BattleState.formations[ids[1]]
			local cur = if first and first.ammoMode then first.ammoMode else "auto"
			Input.sendOrder("Ammo", ids, { ammo = AMMO_CYCLE[cur] or "auto" })
		end
	elseif key == "rally" then
		local ids = idsOfClass(forms, { hq = true })
		if #ids > 0 then
			Input.sendOrder("Rally", ids, {})
		end
	end
end

local function buildCommandPanel(sg: ScreenGui)
	local p = Kit.panel(sg, { size = UDim2.fromOffset(CMD_W, BOTTOM_H), position = UDim2.new(0, EDGE, 1, -EDGE), anchor = Vector2.new(0, 1), transparency = 0.1, padding = 9 })
	local grid = Instance.new("Frame") :: Frame
	grid.Size = UDim2.fromScale(1, 1)
	grid.BackgroundTransparency = 1
	grid.Parent = p
	local g = Instance.new("UIGridLayout") :: UIGridLayout
	g.CellSize = UDim2.fromOffset(math.floor((CMD_W - 18 - 9) / 4), 24)
	g.CellPadding = UDim2.fromOffset(3, 3)
	g.FillDirectionMaxCells = 4
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = grid
	for i, c in COMMANDS do
		local key = c.key
		local b = Kit.button(grid, c.text, function()
			runCommand(key)
		end, { order = i, textSize = 11, tooltip = c.tip })
		b.TextScaled = true
		local tc = Instance.new("UITextSizeConstraint") :: UITextSizeConstraint
		tc.MaxTextSize = 11
		tc.Parent = b
		commandButtons[c.key] = b
	end
	-- rally cooldown: a gold bar along the bottom of the button that shrinks to nothing
	local rb = commandButtons.rally
	local bar = Instance.new("Frame") :: Frame
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, -3, 1, 0)
	bar.Size = UDim2.new(0, 0, 0, 3)
	bar.BackgroundColor3 = Kit.GOLD
	bar.BorderSizePixel = 0
	bar.Parent = rb
	rallyBar = bar

	toast = Kit.label(sg, "", { size = UDim2.fromOffset(500, 24), position = UDim2.new(0.5, 0, 1, -EDGE - BOTTOM_H - 10), anchor = Vector2.new(0.5, 1), textSize = 13, align = Enum.TextXAlignment.Center, colour = Kit.CREAM })
	toast.TextStrokeTransparency = 0.3
	toast.TextStrokeColor3 = Kit.INK
	toast.Visible = false
end

-- ------------------------------------------------------------------ general's ability
-- One large button above the inspector while an own HQ with a general is selected: ability
-- and general's name, the exact effect on hover, and a dark sweep that drains as it recharges.

local abilityButton: TextButton? = nil
local abilitySweep: Frame? = nil
local abilityHQ: any = nil

local function selectedHQ(): any
	for _, f in selectedFormations() do
		if f.class == "hq" and f.general and Generals.byId[f.general] and f.faction == BattleState.viewerFaction then
			return f
		end
	end
	return nil
end

-- Seconds until ready, run forward between snapshots.
local function abilityLeft(f: any): number
	local now = BattleState.clock
	if BattleState.state == "running" then
		now += (os.clock() - BattleState.lastSnapshotAt) * BattleState.speed
	end
	return math.max(0, (f.abilityReadyAt or 0) - now)
end

local function buildAbility(sg: ScreenGui)
	local b = Kit.button(sg, "", function()
		local f = abilityHQ
		local g = if f then Generals.byId[f.general] else nil
		if f and g then
			Input.sendOrder("Ability", { f.id }, { abilityId = g.ability.id })
		end
	end, { size = UDim2.fromOffset(CMD_W, 46), position = UDim2.new(0, EDGE, 1, -EDGE - BOTTOM_H - 6 - 190 - 6), anchor = Vector2.new(0, 1), textSize = 17, caps = false, primary = true })
	b.RichText = true
	b.Visible = false
	b.ClipsDescendants = true
	local sweep = Instance.new("Frame") :: Frame
	sweep.Name = "Sweep"
	sweep.Size = UDim2.fromScale(0, 1)
	sweep.BackgroundColor3 = Kit.INSET
	sweep.BackgroundTransparency = 0.35
	sweep.BorderSizePixel = 0
	sweep.ZIndex = b.ZIndex + 1
	sweep.Parent = b
	abilityButton = b
	abilitySweep = sweep
end

-- Selection / snapshot refresh: which HQ, its text, enabled state and tooltip.
local function refreshAbility()
	local b = abilityButton
	if not b then
		return
	end
	local f = selectedHQ()
	abilityHQ = f
	b.Visible = f ~= nil
	if not f then
		return
	end
	local g = Generals.byId[f.general]
	local ab = g.ability
	b.Text = string.format("%s\n<font size=\"12\">%s %s</font>", ab.name, g.rank, Generals.displayName(g, f.name))
	b:SetAttribute("tip", ab.name .. ": " .. ab.text)
	local left = abilityLeft(f)
	local commander = BattleState.isCommander and (BattleState.state == "running" or BattleState.state == "paused")
	if not commander then
		Kit.setEnabled(b, false, if BattleState.isCommander then "Not during this phase" else "Spectators cannot give orders")
	elseif f.state == "routing" or f.state == "rallying" then
		Kit.setEnabled(b, false, "The staff is in flight")
	elseif left > 0 then
		Kit.setEnabled(b, false, string.format("Recharging (%ds)\n%s: %s", math.ceil(left), ab.name, ab.text))
	else
		Kit.setEnabled(b, true)
	end
end

-- Every frame: the sweep covers the share of the cooldown still to run.
local function animateAbility()
	local f, sweep = abilityHQ, abilitySweep
	if not f or not sweep then
		return
	end
	local g = Generals.byId[f.general]
	local left = abilityLeft(f)
	sweep.Size = UDim2.fromScale(if g then math.clamp(left / g.ability.cooldown, 0, 1) else 0, 1)
	if left <= 0 and abilityButton and abilityButton:GetAttribute("disabled") == true and BattleState.isCommander and BattleState.state == "running" then
		refreshAbility()
	end
end

-- Which classes each command needs (any one of them, not routing).
local COMMAND_CLASSES: { [string]: { string } } = {
	line = { "infantry", "cavalry" },
	column = { "infantry" },
	square = { "infantry" },
	wedge = { "cavalry" },
	fire = { "infantry", "artillery" },
	charge = { "infantry", "cavalry" },
	limber = { "artillery" },
	ammo = { "artillery" },
	rally = { "hq" },
}
local ANY_CLASS = { "infantry", "cavalry", "artillery", "hq" }

local function firstOfClass(forms: { any }, class: string): any
	for _, f in forms do
		if f.class == class then
			return f
		end
	end
	return nil
end

-- Button text / active look that depends on the selection; may veto with a reason.
local function decorateCommand(key: string, b: TextButton, forms: { any }): string?
	if key == "fire" then
		local f: any = forms[1]
		b.Text = if f and f.fireAtWill == false then "Hold fire" else "Fire at will"
		Kit.setActiveLook(b, f ~= nil and f.fireAtWill ~= false)
	elseif key == "charge" then
		local armed = Input.armed() == "Charge"
		Kit.setActiveLook(b, armed)
		b.Text = if armed then "Charge…" else "Charge"
	elseif key == "limber" then
		local art = firstOfClass(forms, "artillery")
		b.Text = if art and art.limbered == true then "Unlimber" else "Limber"
	elseif key == "ammo" then
		local art = firstOfClass(forms, "artillery")
		local mode = if art and art.ammoMode then art.ammoMode else "auto"
		b.Text = if mode == "roundShot" then "Shot" elseif mode == "canister" then "Canister" else "Auto"
	elseif key == "rally" then
		local cd = 0
		for _, f in forms do
			if f.class == "hq" and f.rallyCd and f.rallyCd > cd then
				cd = f.rallyCd
			end
		end
		if rallyBar then
			local frac = math.clamp(cd / Config.Units.hq.rally.cooldown, 0, 1)
			rallyBar.Size = UDim2.new(frac, math.round(6 * frac), 0, 3)
		end
		if cd > 0 then
			return string.format("Recharging (%ds)", math.ceil(cd))
		end
	end
	return nil
end

function HUD.refreshCommands()
	local forms = selectedFormations()
	local commander = BattleState.isCommander and (BattleState.state == "running" or BattleState.state == "paused")
	local has: { [string]: boolean } = {}
	local allRouting = #forms > 0
	for _, f in forms do
		if f.state ~= "routing" and f.moraleBand ~= "shattered" then
			has[f.class] = true
			allRouting = false
		end
	end
	local function why(classes: { string }): (boolean, string?)
		if not commander then
			return false, if BattleState.isCommander then "Not during this phase" else "Spectators cannot give orders"
		end
		if #forms == 0 then
			return false, "Select a formation"
		end
		if allRouting then
			return false, "Routing formations take no orders"
		end
		for _, c in classes do
			if has[c] then
				return true, nil
			end
		end
		return false, "Needs " .. table.concat(classes, " or ")
	end
	for key, b in commandButtons do
		local ok, reason = why(COMMAND_CLASSES[key] or ANY_CLASS)
		local veto = decorateCommand(key, b, forms)
		if ok and veto then
			ok, reason = false, veto
		end
		Kit.setEnabled(b, ok, reason)
	end
end

function HUD.toast(text: string)
	if toast then
		toast.Text = text
		toast.Visible = true
		toastT0 = os.clock()
	end
end

-- ------------------------------------------------------------------ lifecycle

local function buildMinimap(sg: ScreenGui)
	local m = BattleState.map
	local w = 200
	local h = if m then math.round(w * m.depth / m.width) else 150
	local frame = Kit.panel(sg, { size = UDim2.fromOffset(w + 12, h + 12), position = UDim2.new(1, -EDGE, 1, -EDGE), anchor = Vector2.new(1, 1), transparency = 0.05, padding = 6 })
	frame.Name = "MinimapFrame"
	Minimap.create(frame, UDim2.fromScale(1, 1), UDim2.new(), Vector2.new(0, 0))
	local n = Kit.title(frame, "N", { size = UDim2.fromOffset(14, 14), position = UDim2.new(0.5, 0, 0, -6), anchor = Vector2.new(0.5, 0.5), textSize = 14, align = Enum.TextXAlignment.Center })
	n.BackgroundTransparency = 0
	n.BackgroundColor3 = Kit.INSET
	n.TextColor3 = Kit.GILT
	n.ZIndex = 10
	if m then
		task.spawn(Minimap.paint, m)
	end
end

local function refreshAll()
	updateTopBar()
	updateObjectives()
	CardBar.update()
	updateInspector()
	HUD.refreshCommands()
	refreshAbility()
end

function HUD.show(callbacks: Callbacks)
	HUD.destroy()
	cb = callbacks
	weather = if BattleState.scenario then BattleState.scenario.weather else nil
	local sg = Kit.screen("EoEHUD", 10)
	buildTopBar(sg)
	buildTicker(sg)
	buildInspector(sg)
	buildCommandPanel(sg)
	buildAbility(sg)
	CardBar.create(sg)
	buildMinimap(sg)
	gui = sg
	table.insert(conns, BattleState.updated:Connect(function(snap: any)
		if type(snap) == "table" and type(snap.weather) == "string" then
			weather = snap.weather
		end
		refreshAll()
	end))
	table.insert(conns, Selection.changed:Connect(function()
		CardBar.update()
		updateInspector()
		HUD.refreshCommands()
		refreshAbility()
	end))
	table.insert(conns, BattleState.orderRejected:Connect(function(reason: string)
		HUD.toast(reason)
	end))
	table.insert(conns, Input.action:Connect(function(name: string)
		if name == "disarm" then
			HUD.refreshCommands()
		end
	end))
	refreshAll()
end

function HUD.onEvent(ev: any)
	Ledger.onEvent(ev)
	local f = if ev.id then BattleState.formations[ev.id] else nil
	local name = if f and f.name then f.name else (if ev.id then "#" .. tostring(ev.id) else nil)
	local ours = ev.faction == BattleState.viewerFaction
	local kind = ev.kind
	if kind == "message" and ev.text then
		HUD.message(ev.text)
	elseif kind == "rout" and name then
		HUD.message(name .. " is routing!", Kit.GILT_BRIGHT, true, if ours then Kit.CRIMSON else nil)
	elseif kind == "rally" and name then
		HUD.message(name .. " has rallied.")
	elseif kind == "capture" then
		local names = if BattleState.scenario and BattleState.scenario.factionNames then BattleState.scenario.factionNames else {}
		local who = if ev.faction then (names[ev.faction] or Kit.factionName(ev.faction)) else "Someone"
		HUD.message(string.format("%s captured %s", who, ev.text or "an objective"), if ours then Kit.GILT_BRIGHT else Kit.HOSTILE, true)
	elseif kind == "destroyed" and (ev.text or name) then
		-- the formation has already left the snapshot: the event text carries its name
		HUD.message(if ev.text then tostring(ev.text) .. "." else tostring(name) .. " is destroyed.", nil, true, if ours then Kit.CRIMSON else Kit.INSET)
	elseif kind == "charge" and name then
		HUD.message(name .. " charges!")
	elseif kind == "ability" and ev.text then
		HUD.message(tostring(ev.text), if ours then Kit.GILT_BRIGHT else Kit.HOSTILE, true)
	end
end

function HUD.update(_dt: number)
	if not gui then
		return
	end
	updateTicker()
	CardBar.animate()
	animateAbility()
	Minimap.update()
end

function HUD.destroy()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	Minimap.destroy()
	CardBar.destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
	cb = nil
	clockLabel = nil
	lagLabel = nil
	weatherLabel = nil
	pauseButton = nil
	balanceOwn = nil
	objectiveStrip = nil
	tickerFrame = nil
	inspector = nil
	inspectorBarFill = nil
	rallyBar = nil
	abilityButton = nil
	abilitySweep = nil
	abilityHQ = nil
	toast = nil
	table.clear(speedButtons)
	table.clear(objectiveChips)
	table.clear(tickerLines)
	table.clear(inspectorFields)
	table.clear(commandButtons)
end

return HUD
