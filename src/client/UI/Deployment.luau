--!strict
-- Deployment phase: the pre-battle briefing (date, weather, orders, difficulty, history),
-- placement hints and a prominent Start Battle. Dragging formations is handled by Input in
-- "deploy" mode; this panel only explains and sends `ready`.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Kit = require(script.Parent.Kit)
local BattleState = require(script.Parent.Parent.BattleState)

local Deployment = {}

export type Callbacks = { ready: () -> (), settings: () -> () }

local gui: ScreenGui? = nil
local startBtn: TextButton? = nil

local HINTS = "· Left-drag a formation to re-place it inside your zone.\n· Right-drag from a formation to set its facing.\n· Objectives are marked with flags; north is up on the minimap."

local function section(parent: Instance, heading: string, body: string, order: number, colour: Color3?)
	local h = Kit.title(parent, heading, { size = UDim2.new(1, 0, 0, 22), textSize = 19 })
	h.LayoutOrder = order
	local b = Kit.label(parent, body, { size = UDim2.new(1, -6, 0, 0), wrap = true, textSize = 13, colour = colour })
	b.AutomaticSize = Enum.AutomaticSize.Y
	b.TextYAlignment = Enum.TextYAlignment.Top
	b.LayoutOrder = order + 1
end

function Deployment.show(cb: Callbacks)
	Deployment.destroy()
	local sg = Kit.screen("EoEDeploy", 20)
	local sc = BattleState.scenario or {}
	local panel = Kit.panel(sg, { size = UDim2.new(0, 420, 1, -96), position = UDim2.new(0, 24, 0.5, 0), anchor = Vector2.new(0, 0.5), padding = 18 })
	local cap = Instance.new("UISizeConstraint") :: UISizeConstraint
	cap.MaxSize = Vector2.new(420, 660)
	cap.Parent = panel

	local title = Kit.title(panel, sc.name or "Deployment", { size = UDim2.new(1, 0, 0, 34), textSize = 28 })
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local facts = {}
	if sc.date then
		table.insert(facts, sc.date)
	end
	local w = (Config.Weather :: any)[sc.weather or ""]
	if w then
		table.insert(facts, w.label)
	end
	if sc.timeLimit and sc.timeLimit > 0 then
		table.insert(facts, string.format("%d minutes", math.floor(sc.timeLimit / 60)))
	end
	Kit.title(panel, table.concat(facts, "  ·  "), { size = UDim2.new(1, 0, 0, 20), position = UDim2.fromOffset(0, 36), textSize = 17, colour = Kit.MUTED })
	local rule = Instance.new("Frame") :: Frame
	rule.Size = UDim2.new(1, 0, 0, 1)
	rule.Position = UDim2.fromOffset(0, 62)
	rule.BackgroundColor3 = Kit.GOLD
	rule.BorderSizePixel = 0
	rule.Parent = panel

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
		local note = Kit.label(body, sc.difficultyNote, { size = UDim2.new(1, -6, 0, 0), wrap = true, textSize = 13, font = Enum.Font.GothamBold, colour = Kit.HOSTILE })
		note.AutomaticSize = Enum.AutomaticSize.Y
		note.LayoutOrder = 1
	end
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
		bs.Color = Kit.GOLD
		bs.Thickness = 2
		bs.Transparency = 0
	end
	Kit.button(row, "Settings", cb.settings, { size = UDim2.new(0, 90, 1, 0), order = 2 })
	if not BattleState.isCommander then
		Kit.setEnabled(b, false, "Waiting for the commander to start the battle")
	end
	startBtn = b
	gui = sg
end

function Deployment.setWaiting(text: string)
	if startBtn then
		startBtn.Text = text
		Kit.setEnabled(startBtn, false, "The battle is starting")
	end
end

function Deployment.destroy()
	if gui then
		gui:Destroy()
		gui = nil
		startBtn = nil
	end
end

return Deployment
