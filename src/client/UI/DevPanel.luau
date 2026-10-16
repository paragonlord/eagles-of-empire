--!strict
-- F9 developer panel: AI goals from the server's Debug remote. Collapsible, hidden by default.

local Kit = require(script.Parent.Kit)

local DevPanel = {}

local gui: ScreenGui? = nil
local body: TextLabel? = nil
local bodyFrame: Frame? = nil
local collapsed = false
local lastGoals: { any } = {}

local function build()
	if gui then
		return
	end
	local sg = Kit.screen("EoEDev", 45)
	sg.Enabled = false
	local panel = Kit.panel(sg, { size = UDim2.fromOffset(420, 320), position = UDim2.new(1, -260, 0, 48), anchor = Vector2.new(1, 0), dark = true })
	local header = Kit.button(panel, "AI goals (F9)  ▾", function()
		collapsed = not collapsed
		if bodyFrame then
			bodyFrame.Visible = not collapsed
		end
		panel.Size = if collapsed then UDim2.fromOffset(420, 32) else UDim2.fromOffset(420, 320)
	end, { size = UDim2.new(1, 0, 0, 30), textSize = 13 })
	header.TextXAlignment = Enum.TextXAlignment.Left
	local bf = Instance.new("Frame") :: Frame
	bf.Size = UDim2.new(1, -8, 1, -38)
	bf.Position = UDim2.new(0, 4, 0, 34)
	bf.BackgroundTransparency = 1
	bf.Parent = panel
	local scroll = Instance.new("ScrollingFrame") :: ScrollingFrame
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = bf
	local b = Kit.label(scroll, "(no debug data; the server dev view is off)", { size = UDim2.new(1, -8, 0, 20), textSize = 12, wrap = true })
	b.AutomaticSize = Enum.AutomaticSize.Y
	b.TextYAlignment = Enum.TextYAlignment.Top
	gui = sg
	body = b
	bodyFrame = bf
end

function DevPanel.toggle()
	build()
	if gui then
		gui.Enabled = not gui.Enabled
	end
end

function DevPanel.setGoals(goals: { any })
	lastGoals = goals
	if not body then
		return
	end
	local lines = {}
	for _, g in goals do
		table.insert(lines, string.format("#%s  %s — %s", tostring(g.id), tostring(g.goal), tostring(g.reason)))
	end
	body.Text = if #lines > 0 then table.concat(lines, "\n") else "(no AI goals reported)"
end

function DevPanel.hide()
	if gui then
		gui.Enabled = false
	end
end

function DevPanel.destroy()
	if gui then
		gui:Destroy()
		gui = nil
		body = nil
		bodyFrame = nil
	end
	table.clear(lastGoals)
end

return DevPanel
