--!strict
-- Tutorial dispatch from the aide-de-camp: a walnut panel at the right under the top bar with
-- the step's objective, Skip step / Skip tutorial, plus the two pointers the lesson needs: a
-- pulsing gilt frame over a HUD element and a gilt ring on the ground. Logic lives in Tutorial.

local Kit = require(script.Parent.Kit)

local TutorialPanel = {}

export type Callbacks = { skipStep: () -> (), skipAll: () -> () }

local gui: ScreenGui? = nil
local counter: TextLabel? = nil
local title: TextLabel? = nil
local body: TextLabel? = nil
local doneLabel: TextLabel? = nil
local frame: Frame? = nil -- the highlight over a HUD element
local target: GuiObject? = nil
local ring: CylinderHandleAdornment? = nil

function TutorialPanel.show(cb: Callbacks)
	if gui then
		gui.Enabled = true
		return
	end
	local sg = Kit.screen("EoETutorial", 20)
	local p = Kit.panel(sg, { size = UDim2.fromOffset(340, 0), position = UDim2.new(1, -8, 0, 84), anchor = Vector2.new(1, 0), padding = 14, transparency = 0.06 })
	p.AutomaticSize = Enum.AutomaticSize.Y
	-- the list goes on an inner frame: on the panel itself it would also stack the panel's trim
	-- and rosettes, and the trim (sized to the panel) pushed every line below the screen
	local content = Instance.new("Frame") :: Frame
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.Parent = p
	Kit.list(content, 6)
	counter = Kit.label(content, "", { size = UDim2.new(1, 0, 0, 16), textSize = 12, colour = Kit.MUTED })
	local t = Kit.title(content, "", { size = UDim2.new(1, 0, 0, 26), textSize = 22, colour = Kit.GILT, rule = true })
	t.LayoutOrder = 1
	title = t
	local spacer = Instance.new("Frame") :: Frame
	spacer.Size = UDim2.fromOffset(1, 4)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 2
	spacer.Parent = content
	local b = Kit.label(content, "", { size = UDim2.new(1, 0, 0, 0), textSize = 15, wrap = true })
	b.AutomaticSize = Enum.AutomaticSize.Y
	b.FontFace = Kit.ITALIC
	b.TextSize = 18
	b.LayoutOrder = 3
	body = b
	local d = Kit.label(content, "Well done.", { size = UDim2.new(1, 0, 0, 20), textSize = 15, colour = Kit.GILT_BRIGHT })
	d.LayoutOrder = 4
	d.Visible = false
	doneLabel = d
	local row = Instance.new("Frame") :: Frame
	row.Size = UDim2.new(1, 0, 0, 28)
	row.BackgroundTransparency = 1
	row.LayoutOrder = 5
	row.Parent = content
	Kit.list(row, 8, true)
	Kit.button(row, "Skip step", cb.skipStep, { size = UDim2.fromOffset(120, 28), order = 1, tooltip = "Move on to the next lesson" })
	Kit.button(row, "Skip tutorial", cb.skipAll, { size = UDim2.fromOffset(140, 28), order = 2, tooltip = "Dismiss the aide-de-camp and fight the battle out" })

	local f = Instance.new("Frame") :: Frame
	f.BackgroundTransparency = 1
	f.Visible = false
	f.Parent = sg
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = Kit.GILT_BRIGHT
	s.Thickness = 3
	s.Parent = f
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = f
	frame = f
	gui = sg
end

function TutorialPanel.setStep(index: number, total: number, heading: string, text: string)
	if counter and title and body and doneLabel then
		counter.Text = Kit.spaced("Aide-de-camp") .. string.format("   ·   %d / %d", index, total)
		title.Text = string.upper(heading)
		body.Text = text
		doneLabel.Visible = false
	end
end

function TutorialPanel.setDone(text: string?)
	if doneLabel then
		doneLabel.Text = text or "Well done."
		doneLabel.Visible = true
	end
end

-- Pulsing gilt frame around a HUD element; nil hides it.
function TutorialPanel.highlight(obj: GuiObject?)
	target = obj
end

-- Gilt ring on the ground at (x, z) with radius r; nil hides it. y is the ground height.
function TutorialPanel.ring(x: number?, y: number?, z: number?, r: number?)
	if not (x and y and z and r) then
		if ring then
			ring:Destroy()
			ring = nil
		end
		return
	end
	if not ring then
		-- a hollow cylinder: a solid neon Part drew as an opaque disc over the spot
		local a = Instance.new("CylinderHandleAdornment") :: CylinderHandleAdornment
		a.Name = "EoETutorialRing"
		a.Color3 = Kit.GILT_BRIGHT
		a.Height = 0.3
		a.Adornee = workspace.Terrain -- terrain sits at the origin, so CFrame below is world space
		a.Parent = workspace.Terrain
		ring = a
	end
	local a = ring :: CylinderHandleAdornment
	a.Radius = r
	a.InnerRadius = math.max(0, r - 2.5)
	a.CFrame = CFrame.new(x, y + 0.6, z) * CFrame.Angles(math.pi / 2, 0, 0)
end

function TutorialPanel.update(t: number)
	local pulse = 0.5 + 0.5 * math.sin(t * 5)
	local f = frame
	local obj = target
	if f then
		local visible = obj ~= nil and obj.Parent ~= nil and obj.Visible and obj.AbsoluteSize.X > 0
		f.Visible = visible
		if visible and obj then
			local pad = 4 + pulse * 3
			f.Position = UDim2.fromOffset(obj.AbsolutePosition.X - pad, obj.AbsolutePosition.Y - pad)
			f.Size = UDim2.fromOffset(obj.AbsoluteSize.X + pad * 2, obj.AbsoluteSize.Y + pad * 2)
			local s = f:FindFirstChildOfClass("UIStroke") :: UIStroke?
			if s then
				s.Transparency = 0.5 * (1 - pulse)
			end
		end
	end
	if ring then
		ring.Transparency = 0.15 + 0.35 * pulse
	end
end

function TutorialPanel.hide()
	TutorialPanel.highlight(nil)
	TutorialPanel.ring(nil, nil, nil, nil)
	if gui then
		gui:Destroy()
		gui = nil
		counter = nil
		title = nil
		body = nil
		doneLabel = nil
		frame = nil
	end
end

return TutorialPanel
