--!strict
-- Tiny native-GUI toolkit: cream panels, ink text, serif titles, Gotham data, buttons with
-- disabled-reason tooltips, sliders. Every panel is Active so clicks never reach the field.

local Players = game:GetService("Players") :: Players
local UserInputService = game:GetService("UserInputService") :: UserInputService
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Factions = require(script.Parent.Parent.Factions)

local Kit = {}

local P = Config.Visual.Palette
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

Kit.CREAM = rgb(P.Cream)
Kit.INK = rgb(P.Ink)
Kit.SELECT = rgb(P.Select)
Kit.HOSTILE = rgb(P.Hostile)
Kit.FRANCE = rgb(P.France)
Kit.PRUSSIA = rgb(P.Prussia)
Kit.MUTED = Color3.fromRGB(120, 108, 96)
Kit.PANEL_DARK = Color3.fromRGB(224, 214, 190)
Kit.GOLD = Color3.fromRGB(184, 148, 62)
Kit.MORALE = {
	steady = Color3.fromRGB(88, 128, 64),
	shaken = Color3.fromRGB(206, 160, 52),
	routing = Color3.fromRGB(178, 58, 44),
	shattered = Color3.fromRGB(70, 60, 54),
}

function Kit.factionColour(faction: string?): Color3
	if faction == nil or faction == "" then
		return Kit.MUTED
	end
	return Factions.colour(faction)
end

function Kit.factionName(faction: string?): string
	return Factions.name(faction)
end

function Kit.screen(name: string, order: number, ignoreInset: boolean?): ScreenGui
	local sg = Instance.new("ScreenGui") :: ScreenGui
	sg.Name = name
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = ignoreInset == true
	sg.DisplayOrder = order
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	return sg
end

export type PanelProps = {
	size: UDim2,
	position: UDim2,
	anchor: Vector2?,
	transparency: number?,
	padding: number?,
	dark: boolean?,
	plain: boolean?, -- no inner border or gold corners (small chips, cards)
}

-- Period trim: an inner hairline border 3 px inside the outer stroke and gold corner studs.
-- Added first so content drawn later sits on top; never Active, never in a layout (panels hold
-- layouts only in child frames).
local function trim(f: Frame, pad: number)
	local inner = Instance.new("Frame") :: Frame
	inner.Name = "Trim"
	inner.BackgroundTransparency = 1
	inner.Position = UDim2.fromOffset(3 - pad, 3 - pad)
	inner.Size = UDim2.new(1, 2 * pad - 6, 1, 2 * pad - 6)
	inner.Parent = f
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = Kit.GOLD
	s.Thickness = 1
	s.Transparency = 0.35
	s.Parent = inner
	for _, c in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		local d = Instance.new("Frame") :: Frame
		d.Name = "Stud"
		d.Size = UDim2.fromOffset(6, 6)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromScale(c.X, c.Y)
		d.Rotation = 45
		d.BackgroundColor3 = Kit.GOLD
		d.BorderSizePixel = 0
		d.Parent = inner
	end
end

function Kit.panel(parent: Instance, props: PanelProps): Frame
	local f = Instance.new("Frame") :: Frame
	f.Size = props.size
	f.Position = props.position
	f.AnchorPoint = props.anchor or Vector2.new(0, 0)
	f.BackgroundColor3 = if props.dark then Kit.PANEL_DARK else Kit.CREAM
	f.BackgroundTransparency = props.transparency or 0.06
	f.BorderSizePixel = 0
	f.Active = true
	f.Parent = parent
	local stroke = Instance.new("UIStroke") :: UIStroke
	stroke.Color = Kit.INK
	stroke.Thickness = 1
	stroke.Transparency = if props.plain then 0.5 else 0.2
	stroke.Parent = f
	if not props.plain then
		trim(f, props.padding or 0)
	end
	if props.padding then
		local pad = Instance.new("UIPadding") :: UIPadding
		pad.PaddingTop = UDim.new(0, props.padding)
		pad.PaddingBottom = UDim.new(0, props.padding)
		pad.PaddingLeft = UDim.new(0, props.padding)
		pad.PaddingRight = UDim.new(0, props.padding)
		pad.Parent = f
	end
	return f
end

export type TextProps = {
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	font: EnumFont?,
	colour: Color3?,
	align: EnumTextXAlignment?,
	wrap: boolean?,
	rich: boolean?,
}

function Kit.label(parent: Instance, text: string, props: TextProps?): TextLabel
	local p: TextProps = props or {}
	local l = Instance.new("TextLabel") :: TextLabel
	l.Size = p.size or UDim2.new(1, 0, 0, 20)
	l.Position = p.position or UDim2.new(0, 0, 0, 0)
	l.AnchorPoint = p.anchor or Vector2.new(0, 0)
	l.BackgroundTransparency = 1
	l.Font = p.font or Enum.Font.Gotham
	l.TextSize = p.textSize or 14
	l.TextColor3 = p.colour or Kit.INK
	l.TextXAlignment = p.align or Enum.TextXAlignment.Left
	l.TextWrapped = p.wrap == true
	l.RichText = p.rich == true
	l.Text = text
	l.Parent = parent
	return l
end

function Kit.title(parent: Instance, text: string, props: TextProps?): TextLabel
	local p: TextProps = props or {}
	p.font = Enum.Font.Garamond
	p.textSize = p.textSize or 26
	return Kit.label(parent, text, p)
end

-- Vertical list container. Children lay out top to bottom.
function Kit.list(parent: Instance, gap: number, horizontal: boolean?): UIListLayout
	local l = Instance.new("UIListLayout") :: UIListLayout
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Parent = parent
	return l
end

-- ------------------------------------------------------------------ tooltip (one per screen)

local tooltip: TextLabel? = nil

local function ensureTooltip()
	if tooltip and tooltip.Parent then
		return
	end
	local sg = Kit.screen("EoETooltip", 50, true)
	local t = Kit.label(sg, "", { size = UDim2.fromOffset(240, 36), textSize = 13, wrap = true, align = Enum.TextXAlignment.Center })
	t.BackgroundTransparency = 0.05
	t.BackgroundColor3 = Kit.INK
	t.TextColor3 = Kit.CREAM
	t.Visible = false
	t.ZIndex = 100
	t.AutomaticSize = Enum.AutomaticSize.Y
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(0, 3)
	c.Parent = t
	tooltip = t
end

local function showTooltip(text: string)
	ensureTooltip()
	local t = tooltip :: TextLabel
	t.Text = text
	local m = UserInputService:GetMouseLocation()
	local cam = workspace.CurrentCamera
	local maxX = if cam then cam.ViewportSize.X - 248 else m.X + 14
	-- grows upward from just above the cursor and stays on screen at the right edge
	t.AnchorPoint = Vector2.new(0, 1)
	t.Position = UDim2.fromOffset(math.min(m.X + 14, maxX), math.max(m.Y - 10, 40))
	t.Visible = true
end

local function hideTooltip()
	if tooltip then
		tooltip.Visible = false
	end
end

-- ------------------------------------------------------------------ buttons

export type ButtonProps = {
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	font: EnumFont?,
	tooltip: string?,
	primary: boolean?,
	order: number?,
}

function Kit.button(parent: Instance, text: string, onClick: () -> (), props: ButtonProps?): TextButton
	local p: ButtonProps = props or {}
	local b = Instance.new("TextButton") :: TextButton
	b.Size = p.size or UDim2.new(0, 110, 0, 30)
	b.Position = p.position or UDim2.new(0, 0, 0, 0)
	b.AnchorPoint = p.anchor or Vector2.new(0, 0)
	b.BackgroundColor3 = if p.primary then Kit.INK else Kit.PANEL_DARK
	b.TextColor3 = if p.primary then Kit.CREAM else Kit.INK
	b.Font = p.font or Enum.Font.Gotham
	b.TextSize = p.textSize or 14
	b.Text = text
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.LayoutOrder = p.order or 0
	b.Active = true
	b.Parent = parent
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(0, 3)
	c.Parent = b
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = Kit.INK
	s.Thickness = 1
	s.Transparency = 0.6
	s.Parent = b
	b:SetAttribute("reason", "")
	b:SetAttribute("tip", p.tooltip or "")
	b.Activated:Connect(function()
		if b:GetAttribute("disabled") == true then
			return
		end
		onClick()
	end)
	b.MouseEnter:Connect(function()
		local reason = b:GetAttribute("reason")
		local tip = b:GetAttribute("tip")
		if type(reason) == "string" and reason ~= "" then
			showTooltip(reason)
		elseif type(tip) == "string" and tip ~= "" then
			showTooltip(tip)
		end
	end)
	b.MouseLeave:Connect(hideTooltip)
	return b
end

-- Hover text for any GUI object; the text is computed when the pointer arrives.
function Kit.hoverTip(obj: GuiObject, text: () -> string)
	obj.MouseEnter:Connect(function()
		local t = text()
		if t ~= "" then
			showTooltip(t)
		end
	end)
	obj.MouseLeave:Connect(hideTooltip)
end

-- Disabled buttons stay visible (dimmed) and explain themselves on hover.
function Kit.setEnabled(b: TextButton, enabled: boolean, reason: string?)
	b:SetAttribute("disabled", not enabled)
	b:SetAttribute("reason", if enabled then "" else (reason or ""))
	b.TextTransparency = if enabled then 0 else 0.55
	b.AutoButtonColor = enabled
end

function Kit.setActiveLook(b: TextButton, active: boolean)
	b.BackgroundColor3 = if active then Kit.INK else Kit.PANEL_DARK
	b.TextColor3 = if active then Kit.CREAM else Kit.INK
end

-- ------------------------------------------------------------------ slider

function Kit.slider(parent: Instance, labelText: string, value: number, onChange: (v: number) -> ()): Frame
	local row = Instance.new("Frame") :: Frame
	row.Size = UDim2.new(1, 0, 0, 36)
	row.BackgroundTransparency = 1
	row.Parent = parent
	local l = Kit.label(row, labelText, { size = UDim2.new(1, 0, 0, 16) })
	local valueLabel = Kit.label(row, "", { size = UDim2.new(0, 48, 0, 16), position = UDim2.new(1, -48, 0, 0), align = Enum.TextXAlignment.Right })
	local track = Instance.new("TextButton") :: TextButton
	track.Size = UDim2.new(1, 0, 0, 12)
	track.Position = UDim2.new(0, 0, 0, 20)
	track.BackgroundColor3 = Kit.PANEL_DARK
	track.BorderSizePixel = 0
	track.Text = ""
	track.AutoButtonColor = false
	track.Parent = row
	local fill = Instance.new("Frame") :: Frame
	fill.BackgroundColor3 = Kit.INK
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(value, 0, 1, 0)
	fill.Parent = track
	local dragging = false
	local function apply(px: number)
		local v = math.clamp((px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		fill.Size = UDim2.new(v, 0, 1, 0)
		valueLabel.Text = string.format("%d%%", math.round(v * 100))
		onChange(v)
	end
	valueLabel.Text = string.format("%d%%", math.round(value * 100))
	track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			apply(input.Position.X)
		end
	end)
	track.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	local c1 = UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			apply(input.Position.X)
		end
	end)
	local c2 = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	row.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
	end)
	l.Name = "Label"
	return row
end

function Kit.toggle(parent: Instance, labelText: string, value: boolean, onChange: (v: boolean) -> ()): TextButton
	local b: TextButton
	local function text(v: boolean): string
		return (if v then "[x] " else "[ ] ") .. labelText
	end
	b = Kit.button(parent, text(value), function()
		value = not value
		b.Text = text(value)
		onChange(value)
	end, { size = UDim2.new(1, 0, 0, 28) })
	b.TextXAlignment = Enum.TextXAlignment.Left
	return b
end

-- Horizontal bar: dark track with a fill sized by `frac` (0..1). Returns the fill.
function Kit.bar(parent: Instance, size: UDim2, position: UDim2, colour: Color3): Frame
	local track = Instance.new("Frame") :: Frame
	track.Size = size
	track.Position = position
	track.BackgroundColor3 = Kit.INK
	track.BackgroundTransparency = 0.65
	track.BorderSizePixel = 0
	track.Parent = parent
	local fill = Instance.new("Frame") :: Frame
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = colour
	fill.BorderSizePixel = 0
	fill.Parent = track
	return fill
end

function Kit.setBar(fill: Frame, frac: number)
	fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
end

function Kit.formatClock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", s // 60, s % 60)
end

function Kit.hideTooltip()
	hideTooltip()
end

return Kit
