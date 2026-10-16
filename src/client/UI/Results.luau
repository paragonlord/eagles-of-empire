--!strict
-- End-of-battle panel: outcome, objectives, per-side tallies, feedback lines.

local Kit = require(script.Parent.Kit)
local BattleState = require(script.Parent.Parent.BattleState)

local Results = {}

export type Callbacks = { restart: () -> (), menu: () -> (), campaign: (() -> ())? }

local gui: ScreenGui? = nil

local function sideBlock(parent: Instance, faction: string, name: string, s: any, order: number)
	local f = Kit.panel(parent, { size = UDim2.new(0.5, -6, 0, 190), position = UDim2.new(), dark = true, padding = 10 })
	f.LayoutOrder = order
	local t = Kit.title(f, name, { size = UDim2.new(1, 0, 0, 26), textSize = 22, colour = Kit.factionColour(faction) })
	t.Name = "Title"
	local rows = {
		{ "Deployed", s.deployed },
		{ "Casualties", s.casualties },
		{ "Remaining", s.remaining },
		{ "Formations surviving", s.surviving },
		{ "Routed / shattered", string.format("%d / %d", s.routed or 0, s.shattered or 0) },
		{ "Destroyed / exited", string.format("%d / %d", s.destroyed or 0, s.exited or 0) },
	}
	for i, r in rows do
		Kit.label(f, r[1], { size = UDim2.new(0.6, 0, 0, 20), position = UDim2.new(0, 0, 0, 26 + i * 22), textSize = 13 })
		Kit.label(f, tostring(r[2]), { size = UDim2.new(0.4, 0, 0, 20), position = UDim2.new(0.6, 0, 0, 26 + i * 22), textSize = 13, align = Enum.TextXAlignment.Right, font = Enum.Font.GothamBold })
	end
end

function Results.show(results: any, cb: Callbacks)
	Results.destroy()
	local sg = Kit.screen("EoEResults", 38)
	local panel = Kit.panel(sg, { size = UDim2.fromOffset(760, 640), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), padding = 22 })
	local outcome = results.outcome or "draw"
	local word = if outcome == "victory" then "Victory" elseif outcome == "defeat" then "Defeat" else "Indecisive"
	Kit.title(panel, word, { size = UDim2.new(1, 0, 0, 48), textSize = 42 })
	Kit.label(panel, string.format("%s · %s", tostring(results.reason or ""), Kit.formatClock(results.clock or 0)), { size = UDim2.new(1, 0, 0, 20), position = UDim2.new(0, 0, 0, 50), colour = Kit.MUTED })

	-- objectives
	local objText = {}
	for _, o in results.objectives or {} do
		local owner = o.owner
		local names = if BattleState.scenario and BattleState.scenario.factionNames then BattleState.scenario.factionNames else {}
		local ownerName = if owner then (names[owner] or owner) else "unclaimed"
		table.insert(objText, string.format("%s — %s", o.name, ownerName))
	end
	Kit.label(panel, "Objectives: " .. (if #objText > 0 then table.concat(objText, "   ·   ") else "none"), { size = UDim2.new(1, 0, 0, 20), position = UDim2.new(0, 0, 0, 76), textSize = 13, wrap = true })

	local sides = Instance.new("Frame") :: Frame
	sides.Size = UDim2.new(1, 0, 0, 190)
	sides.Position = UDim2.new(0, 0, 0, 104)
	sides.BackgroundTransparency = 1
	sides.Parent = panel
	Kit.list(sides, 12, true)
	local order = 0
	local names = if BattleState.scenario and BattleState.scenario.factionNames then BattleState.scenario.factionNames else {}
	local factions = { BattleState.viewerFaction, BattleState.enemyFaction }
	for _, faction in factions do
		local s = results.sides and results.sides[faction]
		if s then
			order += 1
			sideBlock(sides, faction, names[faction] or faction, s, order)
		end
	end

	Kit.title(panel, "Notes from the field", { size = UDim2.new(1, 0, 0, 28), position = UDim2.new(0, 0, 0, 306), textSize = 22 })
	local fb = Instance.new("ScrollingFrame") :: ScrollingFrame
	fb.Size = UDim2.new(1, 0, 0, 200)
	fb.Position = UDim2.new(0, 0, 0, 336)
	fb.BackgroundTransparency = 1
	fb.BorderSizePixel = 0
	fb.ScrollBarThickness = 4
	fb.AutomaticCanvasSize = Enum.AutomaticSize.Y
	fb.CanvasSize = UDim2.new()
	fb.Parent = panel
	Kit.list(fb, 4)
	local lines = results.feedback or {}
	if #lines == 0 then
		lines = { "No particular lessons this time." }
	end
	for i, line in lines do
		local l = Kit.label(fb, "· " .. tostring(line), { size = UDim2.new(1, -8, 0, 20), textSize = 13, wrap = true })
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.LayoutOrder = i
	end

	local buttons = Instance.new("Frame") :: Frame
	buttons.Size = UDim2.new(1, 0, 0, 40)
	buttons.Position = UDim2.new(0, 0, 1, -40)
	buttons.BackgroundTransparency = 1
	buttons.Parent = panel
	Kit.list(buttons, 10, true)
	local campaign = cb.campaign
	local returnBtn: TextButton? = nil
	if campaign then
		returnBtn = Kit.button(buttons, "Return to Campaign", campaign, { size = UDim2.fromOffset(190, 40), primary = true, order = 1, textSize = 16 })
	end
	-- Restart stays available for a campaign battle until the server refuses it.
	local restart = Kit.button(buttons, "Restart", cb.restart, { size = UDim2.fromOffset(160, 40), primary = campaign == nil, order = 2, textSize = 16 })
	local menu = Kit.button(buttons, "Main Menu", cb.menu, { size = UDim2.fromOffset(160, 40), order = 3, textSize = 16 })
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
