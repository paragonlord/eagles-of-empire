--!strict
-- Full-screen loading overlay with a progress bar (world replication + terrain settle).
-- Fades out rather than cutting, so the first frame of the field is never a pop.

local TweenService = game:GetService("TweenService") :: TweenService
local Kit = require(script.Parent.Kit)

local Loading = {}

local gui: ScreenGui? = nil
local back: CanvasGroup? = nil
local fill: Frame? = nil
local caption: TextLabel? = nil
local fade: Tween? = nil

local function build()
	if gui then
		return
	end
	local sg = Kit.screen("EoELoading", 40, true)
	local bg = Instance.new("CanvasGroup") :: CanvasGroup
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	Kit.gradient(bg, Kit.BLUE, Kit.INSET)
	bg.BorderSizePixel = 0
	bg.Active = true
	bg.Parent = sg
	Kit.title(bg, "Eagles of Empire", { size = UDim2.new(1, 0, 0, 60), position = UDim2.new(0, 0, 0.38, -10), textSize = 48, align = Enum.TextXAlignment.Center, spaced = true, colour = Kit.GILT, rule = true })
	local c = Kit.label(bg, "Surveying the ground…", { size = UDim2.new(1, 0, 0, 22), position = UDim2.new(0, 0, 0.38, 64), align = Enum.TextXAlignment.Center, colour = Kit.MUTED })
	local track = Instance.new("Frame") :: Frame
	track.Size = UDim2.new(0, 420, 0, 10)
	track.Position = UDim2.new(0.5, -210, 0.38, 100)
	track.BackgroundColor3 = Kit.INSET
	local ts = Instance.new("UIStroke") :: UIStroke
	ts.Color = Kit.GILT_DARK
	ts.Parent = track
	track.BorderSizePixel = 0
	track.Parent = bg
	local f = Instance.new("Frame") :: Frame
	f.Size = UDim2.new(0, 0, 1, 0)
	f.BackgroundColor3 = Kit.GILT
	f.BorderSizePixel = 0
	f.Parent = track
	gui = sg
	back = bg
	fill = f
	caption = c
end

local function stopFade()
	if fade then
		fade:Cancel()
		fade = nil
	end
end

function Loading.show(text: string?)
	build()
	stopFade()
	if back then
		back.GroupTransparency = 0
	end
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
	stopFade()
	if gui then
		gui.Enabled = false
	end
end

-- Fades the overlay out over `seconds` (default 0.8), then disables it.
function Loading.fade(seconds: number?)
	local b, g = back, gui
	if not b or not g or not g.Enabled then
		return
	end
	stopFade()
	local t = TweenService:Create(b, TweenInfo.new(seconds or 0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { GroupTransparency = 1 })
	fade = t
	t.Completed:Connect(function()
		if fade == t then
			fade = nil
			g.Enabled = false
		end
	end)
	t:Play()
end

function Loading.destroy()
	if gui then
		stopFade()
		gui:Destroy()
		gui = nil
		back = nil
		fill = nil
		caption = nil
	end
end

return Loading
