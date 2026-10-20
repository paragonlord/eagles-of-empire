--!strict
-- Full-screen loading overlay with a progress bar (world replication + terrain settle).
-- Fades out rather than cutting, so the first frame of the field is never a pop.

local TweenService = game:GetService("TweenService") :: TweenService
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Tips = require(Shared.Tips)
local Assets = require(Shared.Assets)
local Kit = require(script.Parent.Kit)

local Loading = {}

local gui: ScreenGui? = nil
local back: CanvasGroup? = nil
local fill: Frame? = nil
local caption: TextLabel? = nil
local fade: Tween? = nil
local tip: TextLabel? = nil
local painting: ImageLabel? = nil
local tipAt = Random.new():NextInteger(1, #Tips)
local tipRun = 0 -- the rotation thread of the current show
local TIP_SECONDS = 9

local function build()
	if gui then
		return
	end
	local sg = Kit.screen("EoELoading", 40, true)
	local bg = Instance.new("CanvasGroup") :: CanvasGroup
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundTransparency = 1
	bg.BorderSizePixel = 0
	bg.Active = true
	bg.Parent = sg
	-- the gradient lives on its own backdrop: on the CanvasGroup it would tint the title and bar too
	local paint = Instance.new("Frame") :: Frame
	paint.Size = UDim2.fromScale(1, 1)
	paint.BackgroundColor3 = Color3.new(1, 1, 1)
	paint.BorderSizePixel = 0
	paint.ZIndex = 0
	Kit.gradient(paint, Kit.BLUE, Kit.INSET)
	paint.Parent = bg
	-- the battle's painting across the screen, as in TW, darkened under the title and tips
	local pic = Instance.new("ImageLabel") :: ImageLabel
	pic.Size = UDim2.fromScale(1, 1)
	pic.BackgroundTransparency = 1
	pic.ScaleType = Enum.ScaleType.Crop
	pic.Image = Assets.paintingFor(nil)
	pic.ZIndex = 0
	pic.Parent = bg
	local veil = Instance.new("Frame") :: Frame
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.new(1, 1, 1)
	veil.BorderSizePixel = 0
	veil.ZIndex = 0
	veil.Parent = bg
	local shade = Kit.gradient(veil, Kit.INSET, Kit.INSET, 90)
	shade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(0.35, 0.35), NumberSequenceKeypoint.new(0.65, 0.2), NumberSequenceKeypoint.new(1, 0.55) })
	painting = pic
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
	local tl = Kit.label(bg, "", { size = UDim2.new(0, 640, 0, 44), position = UDim2.new(0.5, -320, 0.38, 132), align = Enum.TextXAlignment.Center, colour = Kit.MUTED, font = Enum.Font.Garamond, textSize = 18, wrap = true })
	gui = sg
	back = bg
	fill = f
	caption = c
	tip = tl
end

local function stopFade()
	if fade then
		fade:Cancel()
		fade = nil
	end
end

-- `mapId` picks the battle's painting (Assets.paintingFor); nil keeps the one showing.
function Loading.show(text: string?, mapId: string?)
	build()
	stopFade()
	local pic = painting
	if pic and mapId then
		pic.Image = Assets.paintingFor(mapId)
	end
	if back then
		back.GroupTransparency = 0
	end
	if gui then
		gui.Enabled = true
	end
	Loading.setProgress(0, text)
	-- a tip, and the next one every few seconds while the overlay is up
	tipRun += 1
	local run = tipRun
	task.spawn(function()
		while run == tipRun do
			local g, l = gui, tip
			if not g or not l or not g.Enabled then
				break
			end
			l.Text = Tips[tipAt]
			tipAt = tipAt % #Tips + 1
			task.wait(TIP_SECONDS)
		end
	end)
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
		tip = nil
	end
end

return Loading
