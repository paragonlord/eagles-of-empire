--!strict
-- End-of-battle screen in the Napoleon: Total War manner: the verdict, casualties per side as
-- bars, the objectives with their final owners, notes from the field and the way out.

local Kit = require(script.Parent.Kit)
local BattleState = require(script.Parent.Parent.BattleState)

local Results = {}

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

local function objectiveChip(parent: Instance, o: any, names: { [string]: string }, order: number)
	local f = Kit.panel(parent, { size = UDim2.fromOffset(170, 26), position = UDim2.new(), transparency = 0.1, plain = true })
	f.LayoutOrder = order
	local pennant = Instance.new("Frame") :: Frame
	pennant.Size = UDim2.new(0, 8, 1, 0)
	pennant.BackgroundColor3 = if o.owner then Kit.factionColour(o.owner) else Kit.SLATE
	pennant.BorderSizePixel = 0
	pennant.Parent = f
	local owner = if o.owner then (names[o.owner] or Kit.factionName(o.owner)) else "unclaimed"
	local l = Kit.label(f, string.format("%s — %s", tostring(o.name), owner), { size = UDim2.new(1, -16, 1, 0), position = UDim2.fromOffset(13, 0), textSize = 12 })
	l.TextTruncate = Enum.TextTruncate.AtEnd
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

	Kit.title(panel, "Objectives", { size = UDim2.new(1, 0, 0, 24), position = UDim2.new(0, 0, 0, 264), textSize = 19, spaced = true })
	local objRow = Instance.new("Frame") :: Frame
	objRow.Size = UDim2.new(1, 0, 0, 26)
	objRow.Position = UDim2.new(0, 0, 0, 290)
	objRow.BackgroundTransparency = 1
	objRow.Parent = panel
	local ol = Kit.list(objRow, 6, true)
	ol.Wraps = true
	local objs = results.objectives or {}
	for i, o in objs do
		objectiveChip(objRow, o, names, i)
	end
	if #objs == 0 then
		Kit.label(objRow, "None on this field.", { size = UDim2.new(1, 0, 1, 0), textSize = 12, colour = Kit.MUTED })
	end

	Kit.title(panel, "Notes from the field", { size = UDim2.new(1, 0, 0, 24), position = UDim2.new(0, 0, 0, 326), textSize = 19, spaced = true })
	local fb = Instance.new("ScrollingFrame") :: ScrollingFrame
	fb.Size = UDim2.new(1, 0, 1, -352 - 52)
	fb.Position = UDim2.new(0, 0, 0, 352)
	fb.BackgroundTransparency = 1
	fb.BorderSizePixel = 0
	fb.ScrollBarThickness = 4
	fb.ScrollBarImageColor3 = Kit.INK
	fb.AutomaticCanvasSize = Enum.AutomaticSize.Y
	fb.CanvasSize = UDim2.new()
	fb.Parent = panel
	Kit.list(fb, 4)
	local lines = results.feedback or {}
	if #lines == 0 then
		lines = { "No particular lessons this time." }
	end
	for i, line in lines do
		local l = Kit.label(fb, "· " .. tostring(line), { size = UDim2.new(1, -8, 0, 20), textSize = 17, font = Enum.Font.Garamond, wrap = true })
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.LayoutOrder = i
	end

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
