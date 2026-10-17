--!strict
-- Historical moments on screen (server: Sim/Moments). A `moment` event shows a title card in the
-- First Empire manner (spaced gilt Garamond capitals over ivory italic text on a translucent dark
-- ribbon) between letterbox bars, and pans the camera to the moment's spot and back over ~6 s.
-- In a solo battle the commander's client pauses the match while the card is up (and resumes it
-- after, unless it was already paused), so no game time passes at x4 while the player reads.
-- Any key, click or touch skips it (the camera snaps back at once). The card never takes input:
-- nothing here is Active, so clicks fall through to the field. No pan while a mouse button is
-- held (the player is dragging) or while the intro plays; with reduced effects, only the card.

local Players = game:GetService("Players") :: Players
local TweenService = game:GetService("TweenService") :: TweenService
local UserInputService = game:GetService("UserInputService") :: UserInputService
local Kit = require(script.Parent.UI.Kit)
local HUD = require(script.Parent.UI.HUD)
local Camera = require(script.Parent.Camera)
local Settings = require(script.Parent.Settings)
local Net = require(script.Parent.Net)
local BattleState = require(script.Parent.BattleState)

local Cinematic = {}

local FADE = 0.45
local HOLD = 6 -- seconds the card stays up (the pan's length)
local PAN_BACK_AT = 4.5 -- seconds into the hold the camera starts back
local BAR = 0.085 -- letterbox bar height, fraction of the screen

type Card = { gui: ScreenGui, group: CanvasGroup, bars: { Frame }, back: ((snap: boolean) -> ())?, paused: boolean? }

local queue: { any } = {}
local current: Card? = nil
local skipConn: RBXScriptConnection? = nil

local function tween(inst: Instance, t: number, props: { [string]: any })
	TweenService:Create(inst, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local showNext: () -> ()

local function close(card: Card, fast: boolean)
	if current ~= card then
		return
	end
	current = nil
	if card.back then
		card.back(fast) -- skipped: snap back so a drag starting now sees a still camera
		card.back = nil
	end
	if card.paused and BattleState.state == "paused" then
		Net.control("resume")
	end
	local t = if fast then 0.2 else FADE
	tween(card.group, t, { GroupTransparency = 1 })
	for i, b in card.bars do
		tween(b, t, { Position = if i == 1 then UDim2.fromScale(0, -BAR) else UDim2.fromScale(0, 1) })
	end
	task.delay(t, function()
		card.gui:Destroy()
		showNext()
	end)
end

local function build(ev: any, letterbox: boolean): Card
	local sg = Kit.screen("EoEMoment", 15, true)
	local bars: { Frame } = {}
	if letterbox then
		for i = 1, 2 do
			local b = Instance.new("Frame") :: Frame
			b.Size = UDim2.fromScale(1, BAR)
			b.Position = if i == 1 then UDim2.fromScale(0, -BAR) else UDim2.fromScale(0, 1)
			b.BackgroundColor3 = Color3.new(0, 0, 0)
			b.BorderSizePixel = 0
			b.Active = false
			b.Parent = sg
			bars[i] = b
		end
	end
	local g = Instance.new("CanvasGroup") :: CanvasGroup
	g.AnchorPoint = Vector2.new(0.5, 0)
	g.Position = UDim2.fromScale(0.5, 0.62)
	g.Size = UDim2.new(1, 0, 0, 118)
	g.BackgroundColor3 = Kit.INSET
	g.BackgroundTransparency = 0.1
	g.BorderSizePixel = 0
	g.GroupTransparency = 1
	g.Active = false
	g.Parent = sg
	for _, y in { 0, 1 } do
		local edge = Instance.new("Frame") :: Frame
		edge.Size = UDim2.new(1, 0, 0, 1)
		edge.Position = UDim2.fromScale(0, y)
		edge.AnchorPoint = Vector2.new(0, y)
		edge.BackgroundColor3 = Kit.GILT_DARK
		edge.BorderSizePixel = 0
		edge.Parent = g
	end
	local title = Kit.title(g, tostring(ev.title or ""), { spaced = true, align = Enum.TextXAlignment.Center, colour = Kit.GILT_BRIGHT, textSize = 28, size = UDim2.new(1, -40, 0, 34), position = UDim2.fromOffset(20, 14) })
	title.TextStrokeTransparency = 0.6
	title.TextStrokeColor3 = Kit.INK
	Kit.rule(g, UDim2.new(0.5, 0, 0, 54), 180, 0.5)
	local body = Kit.label(g, tostring(ev.text or ""), { align = Enum.TextXAlignment.Center, colour = Kit.IVORY, textSize = 19, wrap = true, size = UDim2.new(0.7, 0, 0, 48), position = UDim2.new(0.15, 0, 0, 62) })
	body.FontFace = Kit.ITALIC
	return { gui = sg, group = g, bars = bars }
end

showNext = function()
	if current or #queue == 0 then
		return
	end
	local ev = table.remove(queue, 1)
	local reduced = Settings.get().reducedEffects == true
	local card = build(ev, not reduced)
	current = card
	if BattleState.isCommander and BattleState.state == "running" and #Players:GetPlayers() == 1 then
		card.paused = Net.control("pause") ~= nil
	end
	tween(card.group, FADE, { GroupTransparency = 0 })
	for i, b in card.bars do
		tween(b, FADE, { Position = if i == 1 then UDim2.fromScale(0, 0) else UDim2.fromScale(0, 1 - BAR) })
	end
	local dragging = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	if not reduced and not dragging and not Camera.introPlaying() and type(ev.x) == "number" and type(ev.z) == "number" then
		local fx, fz = Camera.getFocus()
		Camera.focusOn(ev.x, ev.z)
		card.back = function(snap: boolean)
			Camera.focusOn(fx, fz, snap)
		end
		task.delay(PAN_BACK_AT, function()
			if current == card and card.back then
				card.back(false)
				card.back = nil
			end
		end)
	end
	task.delay(HOLD, function()
		close(card, false) -- no-op if it was skipped
	end)
end

-- Called with every snapshot event; acts on moments only.
function Cinematic.onEvent(ev: any)
	if type(ev) ~= "table" or ev.kind ~= "moment" then
		return
	end
	HUD.message(tostring(ev.title or ""), Kit.GILT_BRIGHT, true)
	if #queue < 3 then
		table.insert(queue, ev)
	end
	if not skipConn then
		skipConn = UserInputService.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			local card = current
			if card and (t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Gamepad1) then
				close(card, true)
			end
		end)
	end
	showNext()
end

-- Drop any card and queued moments (leaving a battle).
function Cinematic.clear()
	table.clear(queue)
	local card = current
	if card then
		close(card, true)
	end
end

return Cinematic
