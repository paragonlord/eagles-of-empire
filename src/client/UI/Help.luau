--!strict
-- "How to Command": controls table and one-line formation explanations (docs/architecture.md,
-- docs/rules.md). Static text; shown as a centred panel.

local Kit = require(script.Parent.Kit)

local Help = {}

local gui: ScreenGui? = nil

local CONTROLS = {
	{ "Left click", "Select a formation · drag to box-select · Shift adds or removes · double-click: all of its type" },
	{ "Right click", "Move there (keeps the selection's spacing) · on an enemy: Engage · double: run there" },
	{ "Right drag", "Draw the line: formations spread along it and face its open side" },
	{ "Alt + right click", "Turn in place to face that point" },
	{ "Shift + order", "Queue the order after the current one (up to 4)" },
	{ "WASD / arrows", "Pan the camera · Q / E rotate · X / Z or the wheel: up / down · PgUp / PgDn pitch" },
	{ "F / Home / V", "Focus the selection / return to the army / follow the selected formation" },
	{ "Space · + / −", "Pause or resume · faster / slower (×1 ×2 ×4)" },
	{ "Ctrl + 1…9 / 1…9", "Assign a control group / recall it (twice: centre on it) · Ctrl + A: everyone" },
	{ "L C B K Y", "Line · column · square (box) · skirmish · wedge" },
	{ "T J M R", "Fire at will · charge · attack-move · run / walk" },
	{ "H ⌫ N", "Hold · halt · retreat" },
	{ "U I P O", "Guns: limber · ammunition · HQ: rally · Occupy a village or farm (then right-click it)" },
	{ "Esc", "Clear the selection, close panels" },
	{ "F1 · F9", "This help · developer panel (when the server allows it)" },
}

local FORMATIONS = {
	{ "Line", "Three ranks: full musketry, slow, vulnerable to cavalry on the flanks." },
	{ "Column", "Twelve ranks: fast on roads, strong in the bayonet charge, weak to fire and round shot." },
	{ "Square", "Hollow box: nearly immune to cavalry, half the fire, a gift to artillery. Slow to form." },
	{ "Run", "R or a double right-click: marches at the double, 1.4x speed for 3x the fatigue. Tired men shoot and fight worse." },
	{ "Skirmish", "Light infantry and rifles only: open order, hard to hit, fires on the move and all round. Cavalry rides it down." },
	{ "Travel column", "Adopted automatically at choke points; cannot fire. Reforms when clearance allows." },
	{ "Cavalry wedge", "Charge formation: impact grows with the run-up. Never charge a formed square." },
	{ "Limbered / deployed", "Guns move only when limbered and fire only when deployed (20–25 s to change)." },
	{ "Status words", "Shaken: morale under 40 — rally with the HQ nearby. Routing: no orders accepted until it rallies." },
	{ "Objectives", "Infantry or cavalry inside the ring for 30 s capture it; both sides inside = contested." },
}

local function row(parent: Instance, key: string, text: string, order: number)
	local f = Instance.new("Frame") :: Frame
	f.Size = UDim2.new(1, 0, 0, 22)
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.Parent = parent
	Kit.label(f, key, { size = UDim2.new(0, 150, 0, 22), font = Enum.Font.GothamBold, textSize = 13 })
	local t = Kit.label(f, text, { size = UDim2.new(1, -160, 0, 22), position = UDim2.new(0, 160, 0, 0), textSize = 13, wrap = true })
	t.AutomaticSize = Enum.AutomaticSize.Y
end

function Help.show()
	if not gui then
		local sg = Kit.screen("EoEHelp", 35)
		local panel = Kit.panel(sg, { size = UDim2.fromOffset(720, 620), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), padding = 20 })
		Kit.fit(panel, 720, 620)
		Kit.title(panel, "How to Command", { size = UDim2.new(1, 0, 0, 36), textSize = 30 })
		Kit.button(panel, "Close (Esc)", Help.hide, { size = UDim2.fromOffset(110, 28), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0) })
		local scroll = Instance.new("ScrollingFrame") :: ScrollingFrame
		scroll.Size = UDim2.new(1, 0, 1, -48)
		scroll.Position = UDim2.new(0, 0, 0, 44)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 6
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new()
		scroll.Parent = panel
		Kit.list(scroll, 4)
		local order = 0
		local function heading(text: string)
			order += 1
			local h = Kit.title(scroll, text, { size = UDim2.new(1, 0, 0, 30), textSize = 22 })
			h.LayoutOrder = order
		end
		heading("Controls")
		for _, c in CONTROLS do
			order += 1
			row(scroll, c[1], c[2], order)
		end
		heading("Formations and words on the field")
		for _, c in FORMATIONS do
			order += 1
			row(scroll, c[1], c[2], order)
		end
		gui = sg
	end
	if gui then
		gui.Enabled = true
	end
end

function Help.hide()
	if gui then
		gui.Enabled = false
	end
end

function Help.isOpen(): boolean
	return gui ~= nil and (gui :: ScreenGui).Enabled
end

function Help.destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
end

return Help
