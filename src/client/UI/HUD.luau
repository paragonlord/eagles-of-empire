--!strict
-- Battle HUD: top bar (clock, speed, pause), objective strip, event ticker, roster, inspector,
-- command bar and minimap. Thin frame around the field; the centre stays clear.

local Kit = require(script.Parent.Kit)
local Minimap = require(script.Parent.Minimap)
local BattleState = require(script.Parent.Parent.BattleState)
local Selection = require(script.Parent.Parent.Selection)
local Net = require(script.Parent.Parent.Net)
local Input = require(script.Parent.Parent.Input)
local Camera = require(script.Parent.Parent.Camera)
local Signal = require(script.Parent.Parent.Signal)

local HUD = {}

export type Callbacks = { settings: () -> (), help: () -> (), menu: () -> () }

local gui: ScreenGui? = nil
local cb: Callbacks? = nil
local conns: { Signal.Connection } = {}

-- top bar
local clockLabel: TextLabel? = nil
local lagLabel: TextLabel? = nil
local speedButtons: { [number]: TextButton } = {}
local pauseButton: TextButton? = nil
local objectiveStrip: Frame? = nil
local objectiveChips: { [string]: { frame: Frame, label: TextLabel, bar: Frame } } = {}

-- ticker
local tickerLines: { { label: TextLabel, t0: number } } = {}
local tickerFrame: Frame? = nil
local TICKER_LIFE = 9

-- roster
local rosterScroll: ScrollingFrame? = nil
local rosterKey = ""
local rosterRows: { [number]: { frame: TextButton, name: TextLabel, state: TextLabel, bar: Frame, lastClick: number } } = {}

-- inspector
local inspector: Frame? = nil
local inspectorFields: { [string]: TextLabel } = {}
local inspectorBarFill: Frame? = nil

-- command bar
local commandButtons: { [string]: TextButton } = {}
local toast: TextLabel? = nil
local toastT0 = 0

local MORALE_WORD: { [string]: string } = { steady = "Steady", shaken = "Shaken", routing = "Routing", shattered = "Shattered" }
local STATE_WORD: { [string]: string } = { idle = "Holding", moving = "Marching", reforming = "Reforming", firing = "Firing", charging = "Charging", melee = "Melee", retreating = "Retreating", routing = "Routing", rallying = "Rallying", destroyed = "Destroyed", exited = "Exited" }

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
	local bar = Kit.panel(sg, { size = UDim2.new(1, 0, 0, 36), position = UDim2.new(0, 0, 0, 0), transparency = 0.08 })
	local sc = BattleState.scenario
	Kit.title(bar, if sc then sc.name else "", { size = UDim2.new(0, 360, 1, 0), position = UDim2.new(0, 12, 0, 0), textSize = 20 })
	clockLabel = Kit.label(bar, "00:00", { size = UDim2.new(0, 90, 1, 0), position = UDim2.new(0.5, -200, 0, 0), textSize = 18, font = Enum.Font.GothamBold, align = Enum.TextXAlignment.Center })
	lagLabel = Kit.label(bar, "", { size = UDim2.new(0, 70, 1, 0), position = UDim2.new(0.5, -110, 0, 0), textSize = 11, colour = Kit.HOSTILE })
	local speeds = { 1, 2, 4 }
	for i, s in speeds do
		local b = Kit.button(bar, "×" .. s, function()
			Net.control("speed", s)
		end, { size = UDim2.fromOffset(40, 26), position = UDim2.new(0.5, -40 + (i - 1) * 46, 0, 5), tooltip = "Speed ×" .. s .. " (key " .. i .. ")" })
		speedButtons[s] = b
	end
	pauseButton = Kit.button(bar, "Pause", function()
		if BattleState.state == "paused" then
			Net.control("resume")
		else
			Net.control("pause")
		end
	end, { size = UDim2.fromOffset(70, 26), position = UDim2.new(0.5, 104, 0, 5), tooltip = "Space" })
	local right = Instance.new("Frame") :: Frame
	right.Size = UDim2.fromOffset(250, 26)
	right.Position = UDim2.new(1, -8, 0, 5)
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

	local strip = Instance.new("Frame") :: Frame
	strip.Size = UDim2.new(0, 600, 0, 24)
	strip.Position = UDim2.new(0.5, 0, 0, 40)
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.BackgroundTransparency = 1
	strip.Parent = sg
	local sl = Kit.list(strip, 8, true)
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	objectiveStrip = strip
end

local function updateObjectives()
	local strip = objectiveStrip
	if not strip then
		return
	end
	for i, o in BattleState.objectives do
		local chip = objectiveChips[o.id]
		if not chip then
			local f = Kit.panel(strip, { size = UDim2.fromOffset(150, 24), position = UDim2.new(), transparency = 0.15 })
			f.LayoutOrder = i
			local lbl = Kit.label(f, o.name, { size = UDim2.new(1, -12, 1, -4), position = UDim2.new(0, 6, 0, 0), textSize = 12, align = Enum.TextXAlignment.Center })
			local bar = Instance.new("Frame") :: Frame
			bar.Size = UDim2.new(0, 0, 0, 3)
			bar.Position = UDim2.new(0, 0, 1, -3)
			bar.BorderSizePixel = 0
			bar.Parent = f
			chip = { frame = f, label = lbl, bar = bar }
			objectiveChips[o.id] = chip
		end
		local colour = if o.contested then Kit.HOSTILE else Kit.factionColour(o.owner)
		chip.label.TextColor3 = if o.owner or o.contested then colour else Kit.INK
		chip.label.Text = if o.contested then o.name .. " · contested" else o.name
		chip.bar.BackgroundColor3 = Kit.factionColour(o.capturing or o.owner)
		chip.bar.Size = UDim2.new(math.clamp(o.progress or 0, 0, 1), 0, 0, 3)
	end
end

-- ------------------------------------------------------------------ ticker

local function buildTicker(sg: ScreenGui)
	local f = Instance.new("Frame") :: Frame
	f.Size = UDim2.fromOffset(420, 90)
	f.Position = UDim2.new(0, 12, 0, 72)
	f.BackgroundTransparency = 1
	f.Parent = sg
	Kit.list(f, 2)
	tickerFrame = f
end

function HUD.message(text: string, colour: Color3?)
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
	local l = Kit.label(f, text, { size = UDim2.new(1, 0, 0, 18), textSize = 13, colour = colour or Kit.CREAM })
	l.TextStrokeTransparency = 0.4
	l.TextStrokeColor3 = Kit.INK
	l.LayoutOrder = math.floor(os.clock() * 10) % 1000000000
	table.insert(tickerLines, { label = l, t0 = os.clock() })
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
			e.label.TextTransparency = math.clamp((age - TICKER_LIFE + 3) / 3, 0, 1)
			i += 1
		end
	end
	if toast and now - toastT0 > 3 then
		toast.Visible = false
	end
end

-- ------------------------------------------------------------------ roster

local function buildRoster(sg: ScreenGui)
	local panel = Kit.panel(sg, { size = UDim2.new(0, 240, 1, -300), position = UDim2.new(1, -8, 0, 72), anchor = Vector2.new(1, 0), transparency = 0.12 })
	Kit.title(panel, "Order of battle", { size = UDim2.new(1, -16, 0, 28), position = UDim2.new(0, 8, 0, 0), textSize = 20 })
	local s = Instance.new("ScrollingFrame") :: ScrollingFrame
	s.Size = UDim2.new(1, -8, 1, -34)
	s.Position = UDim2.new(0, 4, 0, 30)
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 4
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.Active = true
	s.Parent = panel
	Kit.list(s, 2)
	rosterScroll = s
end

local function rebuildRoster(forms: { any })
	local s = rosterScroll
	if not s then
		return
	end
	s:ClearAllChildren()
	Kit.list(s, 2)
	table.clear(rosterRows)
	table.sort(forms, function(a: any, b: any)
		if a.corps ~= b.corps then
			return tostring(a.corps) < tostring(b.corps)
		end
		return a.id < b.id
	end)
	local order = 0
	local lastCorps = nil
	for _, f in forms do
		if f.corps ~= lastCorps then
			lastCorps = f.corps
			order += 1
			local h = Kit.label(s, tostring(f.corps or "—"), { size = UDim2.new(1, 0, 0, 20), font = Enum.Font.Garamond, textSize = 17 })
			h.LayoutOrder = order
		end
		order += 1
		local row = Instance.new("TextButton") :: TextButton
		row.Size = UDim2.new(1, -4, 0, 30)
		row.BackgroundColor3 = Kit.PANEL_DARK
		row.BackgroundTransparency = 0.4
		row.BorderSizePixel = 0
		row.Text = ""
		row.AutoButtonColor = true
		row.LayoutOrder = order
		row.Active = true
		row.Parent = s
		local name = Kit.label(row, tostring(f.name or f.id), { size = UDim2.new(1, -8, 0, 16), position = UDim2.new(0, 6, 0, 1), textSize = 12 })
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local state = Kit.label(row, "", { size = UDim2.new(0, 110, 0, 12), position = UDim2.new(1, -116, 0, 17), textSize = 10, colour = Kit.MUTED, align = Enum.TextXAlignment.Right })
		local track = Instance.new("Frame") :: Frame
		track.Size = UDim2.new(0, 90, 0, 4)
		track.Position = UDim2.new(0, 6, 0, 22)
		track.BackgroundColor3 = Kit.INK
		track.BackgroundTransparency = 0.7
		track.BorderSizePixel = 0
		track.Parent = row
		local bar = Instance.new("Frame") :: Frame
		bar.Size = UDim2.fromScale(1, 1)
		bar.BackgroundColor3 = Kit.factionColour(f.faction)
		bar.BorderSizePixel = 0
		bar.Parent = track
		local id = f.id
		local entry = { frame = row, name = name, state = state, bar = bar, lastClick = 0 }
		rosterRows[id] = entry
		row.Activated:Connect(function()
			local now = os.clock()
			if now - entry.lastClick < 0.35 then
				local cur = BattleState.formations[id]
				if cur then
					Camera.focusOn(cur.x, cur.z)
				end
			else
				if Input.mode() ~= "off" then
					local uis = game:GetService("UserInputService") :: UserInputService
					if uis:IsKeyDown(Enum.KeyCode.LeftShift) or uis:IsKeyDown(Enum.KeyCode.RightShift) then
						Selection.toggle(id)
					else
						Selection.set({ id })
					end
				end
			end
			entry.lastClick = now
		end)
	end
end

local function updateRoster()
	local forms = BattleState.ownFormations()
	local ids = {}
	for _, f in forms do
		table.insert(ids, f.id)
	end
	local key = table.concat(ids, ",")
	if key ~= rosterKey then
		rosterKey = key
		rebuildRoster(forms)
	end
	for _, f in forms do
		local row = rosterRows[f.id]
		if row then
			row.bar.Size = UDim2.fromScale(math.clamp(f.strength / math.max(f.startStrength, 1), 0, 1), 1)
			local word = STATE_WORD[f.state] or f.state
			if f.moraleBand == "shaken" then
				word ..= " · shaken"
			elseif f.moraleBand == "shattered" then
				word = "Shattered"
			end
			row.state.Text = word
			row.state.TextColor3 = if f.state == "routing" or f.moraleBand == "shattered" then Kit.HOSTILE else Kit.MUTED
			local sel = Selection.isSelected(f.id)
			row.frame.BackgroundTransparency = if sel then 0 else 0.4
			row.frame.BackgroundColor3 = if sel then Kit.SELECT else Kit.PANEL_DARK
		end
	end
end

-- ------------------------------------------------------------------ inspector

local INSPECTOR_FIELDS = { "corps", "class", "strength", "morale", "fatigue", "ammo", "shape", "status" }

local function buildInspector(sg: ScreenGui)
	local p = Kit.panel(sg, { size = UDim2.fromOffset(300, 196), position = UDim2.new(0, 8, 1, -8), anchor = Vector2.new(0, 1), transparency = 0.1, padding = 10 })
	inspectorFields.name = Kit.title(p, "", { size = UDim2.new(1, 0, 0, 26), textSize = 22 })
	inspectorFields.name.TextTruncate = Enum.TextTruncate.AtEnd
	inspectorFields.exp = Kit.label(p, "", { size = UDim2.new(0, 60, 0, 26), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0), textSize = 16, align = Enum.TextXAlignment.Right, colour = Kit.MUTED })
	local track = Instance.new("Frame") :: Frame
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.new(0, 0, 0, 30)
	track.BackgroundColor3 = Kit.INK
	track.BackgroundTransparency = 0.7
	track.BorderSizePixel = 0
	track.Parent = p
	local fill = Instance.new("Frame") :: Frame
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Kit.FRANCE
	fill.BorderSizePixel = 0
	fill.Parent = track
	inspectorBarFill = fill
	local y = 40
	local names = { corps = "Corps", class = "Class", strength = "Strength", morale = "Morale", fatigue = "Fatigue", ammo = "Ammunition", shape = "Shape", status = "Status" }
	for i, key in INSPECTOR_FIELDS do
		local col = (i - 1) % 2
		local rowY = y + ((i - 1) // 2) * 32
		local k = Kit.label(p, names[key], { size = UDim2.new(0.5, -4, 0, 12), position = UDim2.new(col * 0.5, 0, 0, rowY), textSize = 10, colour = Kit.MUTED })
		k.Name = key .. "Key"
		inspectorFields[key] = Kit.label(p, "—", { size = UDim2.new(0.5, -4, 0, 18), position = UDim2.new(col * 0.5, 0, 0, rowY + 12), textSize = 13, font = Enum.Font.GothamBold })
		inspectorFields[key].TextTruncate = Enum.TextTruncate.AtEnd
	end
	p.Visible = false
	inspector = p
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
		inspectorBarFill.Size = UDim2.fromScale(math.clamp(f.strength / math.max(f.startStrength, 1), 0, 1), 1)
		inspectorBarFill.BackgroundColor3 = Kit.factionColour(f.faction)
	end
	F.morale.Text = string.format("%s%s", MORALE_WORD[f.moraleBand] or f.moraleBand, if f.morale then string.format(" (%d)", math.floor(f.morale)) else "")
	F.morale.TextColor3 = if f.moraleBand == "steady" then Kit.INK else Kit.HOSTILE
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
		status ..= string.format(" · reloading %ds", math.ceil(f.reload))
	end
	F.status.Text = status
end

-- ------------------------------------------------------------------ command bar

type CommandDef = { key: string, text: string, tip: string, width: number? }
local COMMANDS: { CommandDef } = {
	{ key = "line", text = "Line", tip = "Three ranks: full fire, slow (infantry/cavalry)" },
	{ key = "column", text = "Column", tip = "Twelve ranks: fast, strong in the charge, weak to fire" },
	{ key = "square", text = "Square", tip = "Hollow box against cavalry; artillery loves it" },
	{ key = "wedge", text = "Wedge", tip = "Cavalry charge formation" },
	{ key = "fire", text = "Fire at will", tip = "Toggle: fire at any target in range", width = 84 },
	{ key = "charge", text = "Charge", tip = "Then right-click a target or a point" },
	{ key = "hold", text = "Hold", tip = "Stand and hold position" },
	{ key = "stop", text = "Stop", tip = "Cancel orders" },
	{ key = "retreat", text = "Retreat", tip = "Fall back toward your edge" },
	{ key = "limber", text = "Limber", tip = "Guns: limber to move, unlimber to fire" },
	{ key = "ammo", text = "Ammo: auto", tip = "Round shot (long) / canister (short) / auto", width = 84 },
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

local function buildCommandBar(sg: ScreenGui)
	local bar = Kit.panel(sg, { size = UDim2.fromOffset(740, 46), position = UDim2.new(0.5, 0, 1, -8), anchor = Vector2.new(0.5, 1), transparency = 0.1 })
	local l = Kit.list(bar, 4, true)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	for i, c in COMMANDS do
		local key = c.key
		local b = Kit.button(bar, c.text, function()
			runCommand(key)
		end, { size = UDim2.fromOffset(c.width or 56, 32), order = i, textSize = 12, tooltip = c.tip })
		commandButtons[c.key] = b
	end
	toast = Kit.label(sg, "", { size = UDim2.fromOffset(500, 24), position = UDim2.new(0.5, 0, 1, -60), anchor = Vector2.new(0.5, 1), textSize = 13, align = Enum.TextXAlignment.Center, colour = Kit.CREAM })
	toast.TextStrokeTransparency = 0.3
	toast.TextStrokeColor3 = Kit.INK
	toast.Visible = false
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
		b.Text = "Ammo: " .. (if mode == "roundShot" then "shot" elseif mode == "canister" then "canister" else "auto")
	elseif key == "rally" then
		for _, f in forms do
			if f.class == "hq" and f.rallyCd and f.rallyCd > 0 then
				return string.format("Recharging (%ds)", math.ceil(f.rallyCd))
			end
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

local function updateTopBar()
	if clockLabel then
		clockLabel.Text = Kit.formatClock(BattleState.clock)
	end
	if lagLabel then
		lagLabel.Text = if BattleState.simLag > 0.5 then string.format("lag %.1fs", BattleState.simLag) else ""
	end
	for s, b in speedButtons do
		Kit.setActiveLook(b, BattleState.speed == s)
		Kit.setEnabled(b, BattleState.isCommander, "Only the commander sets the speed")
	end
	if pauseButton then
		pauseButton.Text = if BattleState.state == "paused" then "Resume" else "Pause"
		Kit.setActiveLook(pauseButton, BattleState.state == "paused")
		Kit.setEnabled(pauseButton, BattleState.isCommander, "Only the commander may pause")
	end
end

function HUD.show(callbacks: Callbacks)
	HUD.destroy()
	cb = callbacks
	local sg = Kit.screen("EoEHUD", 10)
	buildTopBar(sg)
	buildTicker(sg)
	buildRoster(sg)
	buildInspector(sg)
	buildCommandBar(sg)
	Minimap.create(sg, UDim2.fromOffset(200, 150), UDim2.new(1, -8, 1, -8), Vector2.new(1, 1))
	if BattleState.map then
		task.spawn(Minimap.paint, BattleState.map)
	end
	gui = sg
	table.insert(conns, BattleState.updated:Connect(function()
		updateTopBar()
		updateObjectives()
		updateRoster()
		updateInspector()
		HUD.refreshCommands()
	end))
	table.insert(conns, Selection.changed:Connect(function()
		updateRoster()
		updateInspector()
		HUD.refreshCommands()
	end))
	table.insert(conns, BattleState.orderRejected:Connect(function(reason: string)
		HUD.toast(reason)
	end))
	table.insert(conns, Input.action:Connect(function(name: string)
		if name == "disarm" then
			HUD.refreshCommands()
		end
	end))
	updateTopBar()
	updateObjectives()
	updateRoster()
	updateInspector()
	HUD.refreshCommands()
end

function HUD.onEvent(ev: any)
	local names = if BattleState.scenario and BattleState.scenario.factionNames then BattleState.scenario.factionNames else {}
	local who = if ev.faction then (names[ev.faction] or ev.faction) else nil
	local f = if ev.id then BattleState.formations[ev.id] else nil
	local name = if f and f.name then f.name else (if ev.id then "#" .. tostring(ev.id) else nil)
	local kind = ev.kind
	if kind == "message" and ev.text then
		HUD.message(ev.text)
	elseif kind == "rout" and name then
		HUD.message(name .. " is routing!", if ev.faction == BattleState.viewerFaction then Kit.HOSTILE else Kit.CREAM)
	elseif kind == "rally" and name then
		HUD.message(name .. " has rallied.")
	elseif kind == "capture" then
		HUD.message(string.format("%s captured %s", who or "Someone", ev.text or "an objective"))
	elseif kind == "destroyed" and name then
		HUD.message(name .. " is destroyed.", Kit.HOSTILE)
	elseif kind == "charge" and name then
		HUD.message(name .. " charges!")
	end
end

function HUD.update(_dt: number)
	if not gui then
		return
	end
	updateTicker()
	Minimap.update()
end

function HUD.destroy()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	Minimap.destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
	cb = nil
	clockLabel = nil
	lagLabel = nil
	pauseButton = nil
	objectiveStrip = nil
	tickerFrame = nil
	rosterScroll = nil
	rosterKey = ""
	inspector = nil
	inspectorBarFill = nil
	toast = nil
	table.clear(speedButtons)
	table.clear(objectiveChips)
	table.clear(tickerLines)
	table.clear(rosterRows)
	table.clear(inspectorFields)
	table.clear(commandButtons)
end

return HUD
