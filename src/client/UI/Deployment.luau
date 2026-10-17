--!strict
-- Deployment phase: the pre-battle briefing (date, weather, orders, difficulty, history),
-- placement hints and a prominent Start Battle. Dragging formations is handled by Input in
-- "deploy" mode; this panel only explains and sends `ready`.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Kit = require(script.Parent.Kit)
local BattleState = require(script.Parent.Parent.BattleState)

local Deployment = {}

export type Callbacks = { ready: () -> (), settings: () -> (), assign: ((userId: number) -> ())? }

local gui: ScreenGui? = nil
local startBtn: TextButton? = nil
local playersBox: Frame? = nil -- co-op roster (hidden solo)
local callbacks: Callbacks? = nil

local HINTS = "· Left-drag a formation to re-place it inside your zone.\n· Right-drag from a formation to set its facing.\n· Objectives are marked with flags; north is up on the minimap."

local function section(parent: Instance, heading: string, body: string, order: number, colour: Color3?)
	local h = Kit.title(parent, heading, { size = UDim2.new(1, 0, 0, 22), textSize = 18, spaced = true })
	h.LayoutOrder = order
	local b = Kit.label(parent, body, { size = UDim2.new(1, -6, 0, 0), wrap = true, textSize = 16, font = Enum.Font.Garamond, colour = colour })
	b.AutomaticSize = Enum.AutomaticSize.Y
	b.TextYAlignment = Enum.TextYAlignment.Top
	b.LayoutOrder = order + 1
end

function Deployment.show(cb: Callbacks)
	Deployment.destroy()
	local sg = Kit.screen("EoEDeploy", 20)
	local sc = BattleState.scenario or {}
	-- the dispatch: a parchment document sealed in crimson
	local panel = Kit.panel(sg, { size = UDim2.new(0, 420, 1, -96), position = UDim2.new(0, 24, 0.5, 0), anchor = Vector2.new(0, 0.5), padding = 18, parchment = true })
	local cap = Instance.new("UISizeConstraint") :: UISizeConstraint
	cap.MaxSize = Vector2.new(420, 660)
	cap.Parent = panel

	local dated = Kit.label(panel, "Headquarters, " .. (sc.date or "the eve of battle"), { size = UDim2.new(1, -60, 0, 18), textSize = 17 })
	dated.FontFace = Kit.ITALIC
	local title = Kit.title(panel, sc.name or "Deployment", { size = UDim2.new(1, -60, 0, 30), position = UDim2.fromOffset(0, 18), textSize = 26 })
	title.TextTruncate = Enum.TextTruncate.AtEnd
	Kit.seal(panel, UDim2.new(1, 4, 0, 18), 52)
	local facts = {}
	local w = (Config.Weather :: any)[sc.weather or ""]
	if w then
		table.insert(facts, w.label)
	end
	if sc.timeLimit and sc.timeLimit > 0 then
		table.insert(facts, string.format("%d minutes", math.floor(sc.timeLimit / 60)))
	end
	Kit.title(panel, table.concat(facts, "  ·  "), { size = UDim2.new(1, 0, 0, 16), position = UDim2.fromOffset(0, 47), textSize = 16, colour = Kit.MUTED, caps = false })
	Kit.rule(panel, UDim2.fromOffset(0, 66))

	local body = Instance.new("ScrollingFrame") :: ScrollingFrame
	body.Size = UDim2.new(1, 0, 1, -72 - 62)
	body.Position = UDim2.fromOffset(0, 70)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 4
	body.ScrollBarImageColor3 = Kit.INK
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.Parent = panel
	Kit.list(body, 4)
	if sc.difficultyNote then
		local note = Kit.label(body, sc.difficultyNote, { size = UDim2.new(1, -6, 0, 0), wrap = true, textSize = 16, colour = Kit.CRIMSON })
		note.FontFace = Kit.BOLD
		note.AutomaticSize = Enum.AutomaticSize.Y
		note.LayoutOrder = 1
	end
	local pb = Instance.new("Frame") :: Frame
	pb.Size = UDim2.new(1, -6, 0, 0)
	pb.AutomaticSize = Enum.AutomaticSize.Y
	pb.BackgroundTransparency = 1
	pb.LayoutOrder = 5
	pb.Visible = false
	pb.Parent = body
	Kit.list(pb, 3)
	playersBox = pb
	callbacks = cb
	section(body, "Orders", sc.briefing or "", 10)
	section(body, "Deployment", HINTS, 20, Kit.MUTED)
	if sc.summary then
		section(body, "What happened", sc.summary, 30, Kit.MUTED)
	end

	local row = Instance.new("Frame") :: Frame
	row.Size = UDim2.new(1, 0, 0, 52)
	row.Position = UDim2.new(0, 0, 1, -52)
	row.BackgroundTransparency = 1
	row.Parent = panel
	Kit.list(row, 8, true)
	local b = Kit.button(row, "Start Battle", cb.ready, { size = UDim2.new(1, -98, 1, 0), primary = true, order = 1, textSize = 24, font = Enum.Font.Garamond })
	local bs = b:FindFirstChildOfClass("UIStroke") :: UIStroke?
	if bs then
		bs.Thickness = 2
	end
	Kit.button(row, "Settings", cb.settings, { size = UDim2.new(0, 90, 1, 0), order = 2 })
	if BattleState.coop() and BattleState.role == "officer" then
		b.Text = "Ready"
	elseif not BattleState.isCommander then
		Kit.setEnabled(b, false, "Waiting for the commander to start the battle")
	end
	startBtn = b
	gui = sg
	Deployment.refresh()
end

-- Co-op roster: slot colour, name, ready tick; the commander can hand the selection to an ally.
function Deployment.refresh()
	local pb = playersBox
	if not pb then
		return
	end
	for _, c in pb:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
	pb.Visible = BattleState.coop()
	if not pb.Visible then
		return
	end
	local h = Kit.title(pb, "Officers", { size = UDim2.new(1, 0, 0, 22), textSize = 18, spaced = true })
	h.LayoutOrder = 0
	local giver = BattleState.role == "commander" and callbacks and callbacks.assign
	for i, p in BattleState.players do
		if p.role ~= "spectator" then
			local row = Instance.new("Frame") :: Frame
			row.Size = UDim2.new(1, 0, 0, 22)
			row.BackgroundTransparency = 1
			row.LayoutOrder = i * 2
			row.Parent = pb
			local chip = Instance.new("Frame") :: Frame
			chip.Size = UDim2.fromOffset(12, 12)
			chip.Position = UDim2.fromOffset(0, 5)
			chip.BackgroundColor3 = Kit.slotColour(p.slot)
			chip.BorderSizePixel = 0
			chip.Parent = row
			local who = tostring(p.name) .. (if p.role == "commander" then " (commander)" else "") .. (if p.ready then "  ✓" else "")
			Kit.label(row, who, { size = UDim2.new(1, -20, 1, 0), position = UDim2.fromOffset(20, 0), textSize = 16, font = Enum.Font.Garamond })
			if giver and p.userId ~= BattleState.userId then
				local uid = p.userId
				local g = Kit.button(pb, "Give selected to " .. tostring(p.name), function()
					giver(uid)
				end, { size = UDim2.new(1, 0, 0, 24), order = i * 2 + 1, textSize = 14, tooltip = "Hand the selected formations to this officer" })
				g.LayoutOrder = i * 2 + 1
			end
		end
	end
end

function Deployment.setWaiting(text: string, keepEnabled: boolean?)
	if startBtn then
		startBtn.Text = text
		if keepEnabled then
			Kit.setEnabled(startBtn, true, "Start without waiting for every officer")
		else
			Kit.setEnabled(startBtn, false, "The battle is starting")
		end
	end
end

function Deployment.destroy()
	if gui then
		gui:Destroy()
		gui = nil
		startBtn = nil
		playersBox = nil
		callbacks = nil
	end
end

return Deployment
