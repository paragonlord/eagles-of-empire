--!strict
-- Full-screen loading overlay with a progress bar (terrain + props build).

local Kit = require(script.Parent.Kit)

local Loading = {}

local gui: ScreenGui? = nil
local fill: Frame? = nil
local caption: TextLabel? = nil

local function build()
	if gui then
		return
	end
	local sg = Kit.screen("EoELoading", 40, true)
	local back = Instance.new("Frame") :: Frame
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	Kit.gradient(back, Kit.BLUE, Kit.INSET)
	back.BorderSizePixel = 0
	back.Active = true
	back.Parent = sg
	Kit.title(back, "Eagles of Empire", { size = UDim2.new(1, 0, 0, 60), position = UDim2.new(0, 0, 0.38, -10), textSize = 48, align = Enum.TextXAlignment.Center, spaced = true, colour = Kit.GILT, rule = true })
	local c = Kit.label(back, "Surveying the ground…", { size = UDim2.new(1, 0, 0, 22), position = UDim2.new(0, 0, 0.38, 64), align = Enum.TextXAlignment.Center, colour = Kit.MUTED })
	local track = Instance.new("Frame") :: Frame
	track.Size = UDim2.new(0, 420, 0, 10)
	track.Position = UDim2.new(0.5, -210, 0.38, 100)
	track.BackgroundColor3 = Kit.INSET
	local ts = Instance.new("UIStroke") :: UIStroke
	ts.Color = Kit.GILT_DARK
	ts.Parent = track
	track.BorderSizePixel = 0
	track.Parent = back
	local f = Instance.new("Frame") :: Frame
	f.Size = UDim2.new(0, 0, 1, 0)
	f.BackgroundColor3 = Kit.GILT
	f.BorderSizePixel = 0
	f.Parent = track
	gui = sg
	fill = f
	caption = c
end

function Loading.show(text: string?)
	build()
	if gui then
		gui.Enabled = true
	end
	Loading.setProgress(0, text)
end

function Loading.setProgress(fraction: number, text: string?)
	if fill then
		fill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
	end
	if caption and text then
		caption.Text = text
	end
end

function Loading.hide()
	if gui then
		gui.Enabled = false
	end
end

function Loading.destroy()
	if gui then
		gui:Destroy()
		gui = nil
		fill = nil
		caption = nil
	end
end

return Loading
