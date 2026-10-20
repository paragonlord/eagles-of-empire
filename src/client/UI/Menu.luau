--!strict
-- Main menu: a full-height imperial column on the left (laurel badge, title, tricolour, gilt
-- text entries) over the live battlefield. Entries call back into Main.

local Kit = require(script.Parent.Kit)
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Assets = require(Shared.Assets)

local Menu = {}

export type Callbacks = {
	play: () -> (),
	campaign: () -> (),
	help: () -> (),
	settings: () -> (),
	tutorial: () -> (),
}

local gui: ScreenGui? = nil

-- Imperial badge: a gold laurel wreath (two branches of leaves open at the top) around an "N".
local function badge(parent: Instance, centre: UDim2)
	local holder = Instance.new("Frame") :: Frame
	holder.Size = UDim2.fromOffset(120, 120)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = centre
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local R = 46
	for side = -1, 1, 2 do
		for i = 0, 8 do
			-- from the bottom (90 deg) up each side to about 35 deg short of the top
			local deg = 90 + side * (14 + i * 17)
			local th = math.rad(deg)
			for _, off in { -1, 1 } do
				local leaf = Instance.new("Frame") :: Frame
				leaf.Size = UDim2.fromOffset(6, 13)
				leaf.AnchorPoint = Vector2.new(0.5, 0.5)
				local r = R + off * 5
				leaf.Position = UDim2.fromOffset(60 + math.cos(th) * r, 60 + math.sin(th) * r)
				leaf.Rotation = deg + off * side * 28
				leaf.BackgroundColor3 = if off < 0 then Kit.GILT else Kit.GILT_DARK
				leaf.BorderSizePixel = 0
				leaf.Parent = holder
				local c = Instance.new("UICorner") :: UICorner
				c.CornerRadius = UDim.new(1, 0)
				c.Parent = leaf
			end
		end
	end
	local n = Kit.title(holder, "N", { size = UDim2.fromScale(1, 1), textSize = 64, colour = Kit.GILT_BRIGHT, align = Enum.TextXAlignment.Center })
	n.FontFace = Kit.BOLD
	n.TextStrokeColor3 = Kit.GILT_DARK
	n.TextStrokeTransparency = 0.4
	-- a crowning star of three small diamonds
	for i = -1, 1 do
		local d = Instance.new("Frame") :: Frame
		d.Size = UDim2.fromOffset(6, 6)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromOffset(60 + i * 11, 8 + math.abs(i) * 3)
		d.Rotation = 45
		d.BackgroundColor3 = Kit.GILT
		d.BorderSizePixel = 0
		d.Parent = holder
	end
end
local campaignBtn: TextButton? = nil
local playBtn: TextButton? = nil
local note: TextLabel? = nil

function Menu.show(cb: Callbacks, isCommander: boolean, campaignAvailable: boolean)
	if not gui then
		local sg = Kit.screen("EoEMenu", 30, true) -- the column runs up under the Roblox top-bar inset
		-- full-height column on the left; the live battlefield stays visible on the right
		local col = Instance.new("Frame") :: Frame
		col.Size = UDim2.new(0, 400, 1, 0)
		col.BackgroundColor3 = Color3.new(1, 1, 1)
		col.BackgroundTransparency = 0.04
		col.BorderSizePixel = 0
		col.Active = true
		col.Parent = sg
		Kit.gradient(col, Kit.BLUE, Kit.INSET)
		-- a painted sky over the badge and title (Philippoteaux), fading into the column
		local pic = Instance.new("ImageLabel") :: ImageLabel
		pic.Size = UDim2.new(1, 0, 0, 300)
		pic.BackgroundTransparency = 1
		pic.ScaleType = Enum.ScaleType.Crop
		pic.Image = Assets.paintingFor(nil)
		pic.ImageTransparency = 0.5
		pic.Parent = col
		local fadePic = Instance.new("UIGradient") :: UIGradient
		fadePic.Rotation = 90
		fadePic.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.55, 0.15), NumberSequenceKeypoint.new(1, 1) })
		fadePic.Parent = pic
		for _, e in { { 2, 0, Kit.GILT }, { 1, 3, Kit.CRIMSON }, { 1, 5, Kit.GILT_DARK } } do
			local edge = Instance.new("Frame") :: Frame
			edge.Size = UDim2.new(0, e[1] :: number, 1, 0)
			edge.Position = UDim2.new(1, -(e[2] :: number) - (e[1] :: number), 0, 0)
			edge.BackgroundColor3 = e[3] :: Color3
			edge.BorderSizePixel = 0
			edge.Parent = col
		end
		badge(col, UDim2.new(0.5, 0, 0, 96))
		local t = Kit.title(col, "Eagles of Empire", { size = UDim2.new(1, -40, 0, 36), position = UDim2.new(0, 20, 0, 170), spaced = true, textSize = 30, colour = Kit.GILT, align = Enum.TextXAlignment.Center })
		t.TextScaled = true
		local tc = Instance.new("UITextSizeConstraint") :: UITextSizeConstraint
		tc.MaxTextSize = 30
		tc.Parent = t
		Kit.tricolour(col, UDim2.fromOffset(150, 6), UDim2.new(0.5, 0, 0, 214), Vector2.new(0.5, 0))
		local sub = Kit.label(col, "Napoleonic real-time tactics", { size = UDim2.new(1, 0, 0, 22), position = UDim2.new(0, 0, 0, 226), textSize = 18, colour = Kit.MUTED, align = Enum.TextXAlignment.Center })
		sub.FontFace = Kit.ITALIC
		local list = Instance.new("Frame") :: Frame
		list.Size = UDim2.new(1, -80, 0, 340)
		list.Position = UDim2.new(0, 40, 0, 280)
		list.BackgroundTransparency = 1
		list.Parent = col
		local ll = Kit.list(list, 6)
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local function item(text: string, fn: () -> (), order: number): TextButton
			if order > 1 then
				local sep = Instance.new("Frame") :: Frame
				sep.Size = UDim2.fromOffset(80, 6)
				sep.BackgroundTransparency = 1
				sep.LayoutOrder = order * 2 - 1
				sep.Parent = list
				Kit.rule(sep, UDim2.fromScale(0, 0.5))
			end
			local b = Kit.button(list, Kit.spaced(text), fn, { size = UDim2.new(1, 0, 0, 40), flat = true, order = order * 2, textSize = 22 })
			return b
		end
		playBtn = item("Play Battle", cb.play, 1)
		campaignBtn = item("Campaign", cb.campaign, 2)
		item("How to Command", cb.help, 3)
		item("Settings", cb.settings, 4)
		local grand = (cb :: any).grand
		if grand then
			item("Grand Campaign", grand, 5)
		end
		item("Tutorial", cb.tutorial, 6) -- the aide-de-camp's training ground (Tutorial.luau)
		note = Kit.label(col, "", { size = UDim2.new(1, -48, 0, 40), position = UDim2.new(0, 24, 1, -56), wrap = true, colour = Kit.MUTED, textSize = 14, align = Enum.TextXAlignment.Center })
		gui = sg
	end
	if campaignBtn then
		campaignBtn.Visible = campaignAvailable
	end
	if playBtn then
		Kit.setEnabled(playBtn, isCommander, "Another player commands this battlefield; you are spectating.")
	end
	if note then
		note.Text = if isCommander then "WASD pan · Q/E rotate · wheel zoom · F1 help" else "Spectating: the commander controls the match."
	end
	if gui then
		gui.Enabled = true
	end
end

function Menu.hide()
	if gui then
		gui.Enabled = false
	end
end

function Menu.destroy()
	if gui then
		gui:Destroy()
		gui = nil
		campaignBtn = nil
		playBtn = nil
		note = nil
	end
end

return Menu
