--!strict
-- End-of-battle screen in the Napoleon: Total War manner: the verdict, casualties per side as
-- bars, the objectives with their final owners, notes from the field and the way out.

local Kit = require(script.Parent.Kit)
local BattleState = require(script.Parent.Parent.BattleState)

local Ledger = require(script.Parent.Ledger)

local Results = {}

local notes: (results: any) -> { string }
local formationTable: (parent: Instance, order: number) -> ()

export type Callbacks = { restart: () -> (), menu: () -> (), campaign: (() -> ())? }

local gui: ScreenGui? = nil

local function thousands(n: number): string
	local s = tostring(math.floor(n))
	local out = s
	repeat
		local k
		out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return out
end

-- Decisive when the enemy army collapsed or we lost less than half what they lost.
function Results.verdict(results: any, own: any, enemy: any): string
	local outcome = results.outcome or "draw"
	if outcome == "victory" then
		local collapsed = string.find(string.lower(tostring(results.reason or "")), "enemy army has collapsed", 1, true) ~= nil
		local cheap = own ~= nil and enemy ~= nil and (own.casualties or 0) < 0.5 * (enemy.casualties or 0)
		return if collapsed or cheap then "Decisive Victory" else "Close Victory"
	elseif outcome == "defeat" then
		return "Defeat"
	end
	return "Draw"
end

local function sideBlock(parent: Instance, faction: string, name: string, s: any, order: number)
	local f = Kit.panel(parent, { size = UDim2.new(0.5, -6, 1, 0), position = UDim2.new(), dark = true, padding = 10 })
	f.LayoutOrder = order
	local colour = Kit.factionColour(faction)
	local t = Kit.title(f, name, { size = UDim2.new(1, 0, 0, 26), textSize = 22, spaced = true, colour = Kit.GILT })
	t.Name = "Title"
	local deployed = math.max(s.deployed or 0, 1)
	local lost = s.casualties or 0
	-- the bar is the army: faction colour for those still standing, red for the fallen
	local track = Instance.new("Frame") :: Frame
	track.Size = UDim2.new(1, 0, 0, 14)
	track.Position = UDim2.fromOffset(0, 32)
	track.BackgroundColor3 = if faction == BattleState.viewerFaction then Kit.BLUE_LIGHT else colour
	track.BorderSizePixel = 0
	track.Parent = f
	local ts = Instance.new("UIStroke") :: UIStroke
	ts.Color = Kit.GILT_DARK
	ts.Parent = track
	local fallen = Instance.new("Frame") :: Frame
	fallen.AnchorPoint = Vector2.new(1, 0)
	fallen.Position = UDim2.fromScale(1, 0)
	fallen.Size = UDim2.fromScale(math.clamp(lost / deployed, 0, 1), 1)
	fallen.BackgroundColor3 = Kit.MORALE.routing
	fallen.BorderSizePixel = 0
	fallen.Parent = track
	Kit.label(f, string.format("Casualties  %s of %s  (%d%%)", thousands(lost), thousands(s.deployed or 0), math.floor(100 * lost / deployed + 0.5)), { size = UDim2.new(1, 0, 0, 18), position = UDim2.fromOffset(0, 50), textSize = 13, font = Enum.Font.GothamBold })
	local rows = {
		{ "Remaining", thousands(s.remaining or 0) },
		{ "Formations surviving", tostring(s.surviving or 0) },
		{ "Routed / shattered", string.format("%d / %d", s.routed or 0, s.shattered or 0) },
		{ "Destroyed / exited", string.format("%d / %d", s.destroyed or 0, s.exited or 0) },
	}
	for i, r in rows do
		local y = 52 + i * 20
		Kit.label(f, r[1], { size = UDim2.new(0.65, 0, 0, 18), position = UDim2.new(0, 0, 0, y), textSize = 12, colour = Kit.MUTED })
		Kit.label(f, r[2], { size = UDim2.new(0.35, 0, 0, 18), position = UDim2.new(0.65, 0, 0, y), textSize = 12, align = Enum.TextXAlignment.Right, font = Enum.Font.GothamBold })
	end
end

-- Specific notes from what we saw happen, then the server's lessons.
notes = function(results: any): { string }
	local c = Ledger.counts()
	local out: { string } = {}
	local function plural(k: number, one: string, many: string): string
		return string.format("%d %s", k, if k == 1 then one else many)
	end
	if c.squares > 0 then
		table.insert(out, string.format("Your infantry formed square %s.", plural(c.squares, "time", "times")))
	end
	if c.enemyIntoSquares > 0 then
		table.insert(out, string.format("%s broke against your squares.", plural(c.enemyIntoSquares, "enemy charge", "enemy charges")))
	end
	if c.ownIntoSquares > 0 then
		table.insert(out, string.format("Your cavalry rode into formed squares %s; charge flanks, guns or broken troops instead.", plural(c.ownIntoSquares, "time", "times")))
	end
	if c.ownCharges + c.enemyCharges > 0 then
		table.insert(out, string.format("You launched %s; the enemy %d.", plural(c.ownCharges, "charge", "charges"), c.enemyCharges))
	end
	if c.ownRouts + c.enemyRouts > 0 then
		table.insert(out, string.format("Your formations broke %s and rallied %s; the enemy broke %s that you saw.", plural(c.ownRouts, "time", "times"), plural(c.ownRallies, "time", "times"), plural(c.enemyRouts, "time", "times")))
	else
		table.insert(out, "No formation on either side broke: the lines never came to a decision.")
	end
	if c.ownDestroyed > 0 or c.enemyDestroyed > 0 then
		table.insert(out, string.format("You lost %s%s; the enemy lost %d that you saw.", plural(c.ownDestroyed, "formation", "formations"), if c.gunsLost > 0 then string.format(" (guns lost: %d %s)", c.gunsLost, if c.gunsLost == 1 then "battery" else "batteries") else "", c.enemyDestroyed))
	end
	for _, line in results.feedback or {} do
		table.insert(out, tostring(line))
	end
	return out
end

-- Own army, one row per formation: name, start, end, casualties, final status.
formationTable = function(parent: Instance, order: number)
	local t = Instance.new("Frame") :: Frame
	t.Size = UDim2.new(1, -14, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.BackgroundTransparency = 1
	t.LayoutOrder = order
	t.Parent = parent
	Kit.list(t, 0)
	local COLS = { { "Formation", 0.44 }, { "Start", 0.11 }, { "End", 0.11 }, { "Lost", 0.11 }, { "Status", 0.23 } }
	local function row(cells: { string }, i: number, header: boolean)
		local r = Instance.new("Frame") :: Frame
		r.Size = UDim2.new(1, 0, 0, 20)
		r.BackgroundColor3 = Kit.PARCHMENT_EDGE
		r.BackgroundTransparency = if header then 0.4 elseif i % 2 == 0 then 0.75 else 1
		r.BorderSizePixel = 0
		r.LayoutOrder = i
		r.Parent = t
		local x = 0
		for k, col in COLS do
			local w = col[2] :: number
			local l = Kit.label(r, cells[k], { size = UDim2.new(w, -6, 1, 0), position = UDim2.new(x, 4, 0, 0), textSize = if header then 13 else 14, font = if header then Enum.Font.SourceSansBold else nil, align = if k > 1 and k < 5 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left })
			l.TextTruncate = Enum.TextTruncate.AtEnd
			x += w
		end
	end
	row({ "Formation", "Start", "End", "Lost", "Status" }, 0, true)
	local recs = Ledger.records()
	for i, r in recs do
		row({ r.name, tostring(r.start), tostring(r.last), tostring(math.max(0, r.start - r.last)), r.status }, i, false)
	end
	if #recs == 0 then
		row({ "No formations recorded", "", "", "", "" }, 1, false)
	end
end

local function objectiveChip(parent: Instance, o: any, names: { [string]: string }, order: number)
	local f = Kit.panel(parent, { size = UDim2.fromOffset(0, 26), position = UDim2.new(), transparency = 0.1, plain = true })
	f.AutomaticSize = Enum.AutomaticSize.X
	f.LayoutOrder = order
	local pennant = Instance.new("Frame") :: Frame
	pennant.Size = UDim2.new(0, 8, 1, 0)
	pennant.BackgroundColor3 = if o.owner then Kit.factionColour(o.owner) else Kit.SLATE
	pennant.BorderSizePixel = 0
	pennant.Parent = f
	local owner = if o.owner then (names[o.owner] or Kit.factionName(o.owner)) else "unclaimed"
	local l = Kit.label(f, string.format("%s — %s", tostring(o.name), owner), { size = UDim2.fromOffset(0, 26), position = UDim2.fromOffset(13, 0), textSize = 14 })
	l.AutomaticSize = Enum.AutomaticSize.X
	local pad = Instance.new("UIPadding") :: UIPadding
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = l
end

function Results.show(results: any, cb: Callbacks)
	Results.destroy()
	local sg = Kit.screen("EoEResults", 38)
	local panel = Kit.panel(sg, { size = UDim2.fromOffset(760, 640), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), padding = 22, parchment = true })
	local cap = Instance.new("UISizeConstraint") :: UISizeConstraint
	cap.MaxSize = Vector2.new(760, 640)
	cap.Parent = panel
	local names = if BattleState.scenario and BattleState.scenario.factionNames then BattleState.scenario.factionNames else {}
	local sides = results.sides or {}
	local own, enemy = sides[BattleState.viewerFaction], sides[BattleState.enemyFaction]
	local outcome = results.outcome or "draw"
	local word = Results.verdict(results, own, enemy)
	-- the verdict on a ribbon: gold on crimson for victory, ivory on black for defeat
	local ribbon = Instance.new("Frame") :: Frame
	ribbon.Size = UDim2.new(1, 20, 0, 54)
	ribbon.Position = UDim2.fromOffset(-10, -4)
	ribbon.BackgroundColor3 = if outcome == "victory" then Kit.CRIMSON elseif outcome == "defeat" then Kit.INSET else Kit.BLUE
	ribbon.BorderSizePixel = 0
	ribbon.Parent = panel
	ribbon:SetAttribute("parchment", false)
	Kit.gradient(ribbon, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	local rs = Instance.new("UIStroke") :: UIStroke
	rs.Color = Kit.GILT
	rs.Thickness = 2
	rs.Parent = ribbon
	for _, x in { 0, 1 } do
		Kit.rosette(ribbon, UDim2.fromScale(x, 0.5), 12)
	end
	Kit.title(ribbon, word, { size = UDim2.fromScale(1, 1), textSize = 34, align = Enum.TextXAlignment.Center, spaced = true, colour = if outcome == "victory" then Kit.GILT_BRIGHT else Kit.IVORY })
	local sub = BattleState.scenario and BattleState.scenario.name or ""
	local subLine = Kit.label(panel, string.format("%s%s · %s", if sub ~= "" then sub .. " · " else "", tostring(results.reason or ""), Kit.formatClock(results.clock or 0)), { size = UDim2.new(1, 0, 0, 20), position = UDim2.new(0, 0, 0, 56), textSize = 18, colour = Kit.MUTED, align = Enum.TextXAlignment.Center })
	subLine.FontFace = Kit.ITALIC
	Kit.rule(panel, UDim2.new(0.5, 0, 0, 84), 320, 0.5)

	local sidesRow = Instance.new("Frame") :: Frame
	sidesRow.Size = UDim2.new(1, 0, 0, 160)
	sidesRow.Position = UDim2.new(0, 0, 0, 94)
	sidesRow.BackgroundTransparency = 1
	sidesRow.Parent = panel
	Kit.list(sidesRow, 12, true)
	local order = 0
	for _, faction in { BattleState.viewerFaction, BattleState.enemyFaction } do
		local s = sides[faction]
		if s then
			order += 1
			sideBlock(sidesRow, faction, names[faction] or Kit.factionName(faction), s, order)
		end
	end

	-- the rest of the report scrolls: objectives, notes, the chronicle, the order of battle
	local body = Instance.new("ScrollingFrame") :: ScrollingFrame
	body.Size = UDim2.new(1, 0, 1, -264 - 52)
	body.Position = UDim2.new(0, 0, 0, 264)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 6
	body.ScrollBarImageColor3 = Kit.GILT_DARK
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.Parent = panel
	Kit.list(body, 6)
	local n = 0
	local function nextOrder(): number
		n += 1
		return n
	end
	local function heading(text: string)
		local t = Kit.title(body, text, { size = UDim2.new(1, -10, 0, 24), textSize = 19, spaced = true })
		t.LayoutOrder = nextOrder()
	end
	local function para(text: string, colour: Color3?)
		local l = Kit.label(body, text, { size = UDim2.new(1, -14, 0, 0), textSize = 17, font = Enum.Font.Garamond, wrap = true, colour = colour })
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.LayoutOrder = nextOrder()
	end

	heading("Objectives")
	local objRow = Instance.new("Frame") :: Frame
	objRow.Size = UDim2.new(1, -10, 0, 0)
	objRow.AutomaticSize = Enum.AutomaticSize.Y
	objRow.BackgroundTransparency = 1
	objRow.LayoutOrder = nextOrder()
	objRow.Parent = body
	local ol = Kit.list(objRow, 6, true)
	ol.Wraps = true
	local objs = results.objectives or {}
	for i, o in objs do
		objectiveChip(objRow, o, names, i)
	end
	if #objs == 0 then
		para("None on this field.", Kit.MUTED)
	end

	heading("Notes from the field")
	for _, line in notes(results) do
		para("· " .. line)
	end

	local chronicle: { string } = {}
	for _, line in results.log or {} do
		local l = tostring(line)
		if string.find(l, " broke ", 1, true) or string.find(l, "abandoned", 1, true) or string.find(l, "destroyed", 1, true) or string.find(l, "captured", 1, true) or string.find(l, " fell", 1, true) then
			table.insert(chronicle, l)
		end
	end
	if #chronicle > 0 then
		heading("Chronicle")
		for _, l in chronicle do
			para(l, Kit.MUTED)
		end
	end

	heading("Order of battle")
	formationTable(body, nextOrder())

	local buttons = Instance.new("Frame") :: Frame
	buttons.Size = UDim2.new(1, 0, 0, 42)
	buttons.Position = UDim2.new(0, 0, 1, -42)
	buttons.BackgroundTransparency = 1
	buttons.Parent = panel
	local bl = Kit.list(buttons, 10, true)
	bl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local campaign = cb.campaign
	local returnBtn: TextButton? = nil
	if campaign then
		returnBtn = Kit.button(buttons, "Return to Campaign", campaign, { size = UDim2.fromOffset(200, 42), primary = true, order = 1, textSize = 20, font = Enum.Font.Garamond })
	end
	-- Restart stays available for a campaign battle until the server refuses it.
	local restart = Kit.button(buttons, "Restart", cb.restart, { size = UDim2.fromOffset(160, 42), primary = campaign == nil, order = 2, textSize = 20, font = Enum.Font.Garamond })
	local menu = Kit.button(buttons, "Main Menu", cb.menu, { size = UDim2.fromOffset(160, 42), order = 3, textSize = 20, font = Enum.Font.Garamond })
	if not BattleState.isCommander then
		Kit.setEnabled(restart, false, "Only the commander can restart")
		Kit.setEnabled(menu, false, "Only the commander can leave")
		if returnBtn then
			Kit.setEnabled(returnBtn, false, "Only the commander runs the campaign")
		end
	end
	gui = sg
end

function Results.hide()
	if gui then
		gui.Enabled = false
	end
end

function Results.destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
end

return Results
