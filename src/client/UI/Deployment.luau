--!strict
-- Deployment phase: briefing panel, placement hints, Start Battle. Dragging formations is
-- handled by Input in "deploy" mode; this panel only explains and sends `ready`.

local Kit = require(script.Parent.Kit)
local BattleState = require(script.Parent.Parent.BattleState)

local Deployment = {}

export type Callbacks = { ready: () -> (), settings: () -> () }

local gui: ScreenGui? = nil
local startBtn: TextButton? = nil

function Deployment.show(cb: Callbacks)
	Deployment.destroy()
	local sg = Kit.screen("EoEDeploy", 20)
	local sc = BattleState.scenario
	local panel = Kit.panel(sg, { size = UDim2.fromOffset(380, 420), position = UDim2.new(0, 24, 0.5, 0), anchor = Vector2.new(0, 0.5), padding = 18 })
	Kit.title(panel, if sc then sc.name else "Deployment", { size = UDim2.new(1, 0, 0, 34), textSize = 26 })
	local brief = Kit.label(panel, if sc then sc.briefing else "", { size = UDim2.new(1, 0, 0, 180), position = UDim2.new(0, 0, 0, 40), wrap = true, textSize = 14 })
	brief.TextYAlignment = Enum.TextYAlignment.Top
	local hint = Kit.label(panel, "Deployment\n· Left-drag a formation to re-place it inside your zone.\n· Right-drag from a formation to set its facing.\n· Objectives are marked with flags; +z (up on the minimap) is north.", { size = UDim2.new(1, 0, 0, 100), position = UDim2.new(0, 0, 0, 230), wrap = true, textSize = 13, colour = Kit.MUTED })
	hint.TextYAlignment = Enum.TextYAlignment.Top
	local row = Instance.new("Frame") :: Frame
	row.Size = UDim2.new(1, 0, 0, 40)
	row.Position = UDim2.new(0, 0, 1, -40)
	row.BackgroundTransparency = 1
	row.Parent = panel
	Kit.list(row, 8, true)
	local b = Kit.button(row, "Start Battle", cb.ready, { size = UDim2.new(0.62, 0, 1, 0), primary = true, order = 1, textSize = 16 })
	Kit.button(row, "Settings", cb.settings, { size = UDim2.new(0.34, 0, 1, 0), order = 2 })
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
