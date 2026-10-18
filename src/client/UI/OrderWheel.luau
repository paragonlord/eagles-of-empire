--!strict
-- Radial order wheel for touch (docs/mobile-contract.md): eight brass plaques around a gilt
-- ring under the finger that held a selected unit. Slide onto a plaque and lift to pick it.
-- Positions come in screen pixels; the screen carries Kit's UIScale, so they are divided out.

local Kit = require(script.Parent.Kit)

local OrderWheel = {}

export type Item = { key: string, text: string }
local ITEMS: { Item } = {
	{ key = "move", text = "Move" },
	{ key = "attackmove", text = "Attack-move" },
	{ key = "charge", text = "Charge" },
	{ key = "hold", text = "Hold" },
	{ key = "square", text = "Square" },
	{ key = "line", text = "Line" },
	{ key = "column", text = "Column" },
	{ key = "retreat", text = "Retreat" },
}
OrderWheel.ITEMS = ITEMS

local RADIUS = 96
local DEAD = 34 -- inside this nothing is chosen (lift to cancel)
local PLAQUE = Vector2.new(92, 32)

local gui: ScreenGui? = nil
local plaques: { TextButton } = {}
local centre = Vector2.new(0, 0) -- logical (scaled) pixels
local hovered: number? = nil
local onPick: ((key: string) -> ())? = nil

local function build()
	local sg = Kit.screen("EoEWheel", 30) -- InputObject positions are in GUI (inset) space
	local ring = Instance.new("Frame") :: Frame
	ring.Name = "Ring"
	ring.Size = UDim2.fromOffset(2 * RADIUS, 2 * RADIUS)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundColor3 = Kit.INSET
	ring.BackgroundTransparency = 0.55
	ring.BorderSizePixel = 0
	ring.Parent = sg
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = ring
	local s = Instance.new("UIStroke") :: UIStroke
	s.Color = Kit.GILT
	s.Thickness = 2
	s.Parent = ring
	local hub = Instance.new("Frame") :: Frame
	hub.Size = UDim2.fromOffset(2 * DEAD, 2 * DEAD)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.BackgroundTransparency = 1
	hub.Parent = ring
	local hs = Instance.new("UIStroke") :: UIStroke
	hs.Color = Kit.GILT_DARK
	hs.Parent = hub
	local hc = Instance.new("UICorner") :: UICorner
	hc.CornerRadius = UDim.new(1, 0)
	hc.Parent = hub
	for i, item in ITEMS do
		local a = (i - 1) / #ITEMS * 2 * math.pi - math.pi / 2 -- first plaque at the top, clockwise
		local key = item.key
		local b = Kit.button(ring, item.text, function()
			local pick = onPick
			OrderWheel.hide()
			if pick then
				pick(key)
			end
		end, { size = UDim2.fromOffset(PLAQUE.X, PLAQUE.Y), position = UDim2.new(0.5, math.round(math.cos(a) * RADIUS), 0.5, math.round(math.sin(a) * RADIUS)), anchor = Vector2.new(0.5, 0.5), textSize = 13 })
		plaques[i] = b
	end
	gui = sg
end

local function ring(): Frame?
	return if gui then gui:FindFirstChild("Ring") :: Frame? else nil
end

local function setHovered(i: number?)
	if hovered == i then
		return
	end
	hovered = i
	for j, b in plaques do
		Kit.setActiveLook(b, j == i)
	end
end

-- Opens the wheel around a screen point, kept wholly on screen.
function OrderWheel.show(x: number, y: number, pick: (key: string) -> ())
	if not gui then
		build()
	end
	local sg = gui :: ScreenGui
	local k = Kit.scale()
	local cam = workspace.CurrentCamera
	local view = if cam then cam.ViewportSize / k else Vector2.new(1280, 720)
	local pad = RADIUS + PLAQUE.X / 2 + 4
	centre = Vector2.new(math.clamp(x / k, pad, math.max(pad, view.X - pad)), math.clamp(y / k, RADIUS + PLAQUE.Y, math.max(RADIUS + PLAQUE.Y, view.Y - RADIUS - PLAQUE.Y)))
	local r = ring()
	if r then
		r.Position = UDim2.fromOffset(centre.X, centre.Y)
	end
	onPick = pick
	setHovered(nil)
	sg.Enabled = true
end

function OrderWheel.isOpen(): boolean
	return gui ~= nil and (gui :: ScreenGui).Enabled
end

-- The finger moved: the plaque in its direction lights up (none inside the hub).
function OrderWheel.hover(x: number, y: number)
	if not OrderWheel.isOpen() then
		return
	end
	local k = Kit.scale()
	local d = Vector2.new(x / k, y / k) - centre
	if d.Magnitude < DEAD then
		setHovered(nil)
		return
	end
	local a = (math.atan2(d.Y, d.X) + math.pi / 2) % (2 * math.pi)
	local n = #ITEMS
	setHovered(math.floor(a / (2 * math.pi) * n + 0.5) % n + 1)
end

-- The finger lifted: the lit plaque is picked.
function OrderWheel.release(x: number, y: number)
	if not OrderWheel.isOpen() then
		return
	end
	OrderWheel.hover(x, y)
	local i, pick = hovered, onPick
	OrderWheel.hide()
	if i and pick then
		pick(ITEMS[i].key)
	end
end

function OrderWheel.hide()
	if gui then
		(gui :: ScreenGui).Enabled = false
	end
	hovered = nil
	onPick = nil
end

function OrderWheel.destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(plaques)
	hovered = nil
	onPick = nil
end

return OrderWheel
