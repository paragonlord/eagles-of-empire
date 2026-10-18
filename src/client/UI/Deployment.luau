--!strict
-- Deployment phase: the pre-battle briefing (date, weather, orders, difficulty, history),
-- placement hints and a prominent Start Battle. Dragging formations is handled by Input in
-- "deploy" mode; this panel only explains and sends `ready`.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Kit = require(script.Parent.Kit)
local BattleState = require(script.Parent.Parent.BattleState)

local Deployment = {}

export type Callbacks = {
	ready: () -> (),
	settings: () -> (),
	assign: ((userId: number) -> ())?,
	mode: ((mode: string) -> ())?, -- host: "coop" | "pvp"
	side: ((faction: string) -> ())?, -- PvP: command this side
	balance: (() -> ())?, -- host, PvP: even the sides out
}

local gui: ScreenGui? = nil
local startBtn: TextButton? = nil
local playersBox: Frame? = nil -- co-op / PvP roster (hidden solo co-op)
local callbacks: Callbacks? = nil

local HINTS = "· Left-drag a formation to re-place it inside your zone.\n· Right-drag from a formation to set its facing.\n· Objectives are marked with flags; north is up on the minimap."
local TOUCH_HINTS = "· Drag a formation to re-place it inside your zone.\n· Hold a formation, then drag, to set its facing.\n· Drag the ground to look around; pinch to zoom, twist to turn."

local function section(parent: Instance, heading: string, body: string, order: number, colour: Color3?)
	local h = Kit.title(parent, heading, { size = UDim2.new(1, 0, 0, 22), textSize = 18, spaced = true })
	h.LayoutOrder = order
	local b = Kit.label(parent, body, { size = UDim2.new(1, -6, 0, 0), wrap = true, textSize = 16, font = Enum.Font.Garamond, colour = colour })
	b.AutomaticSize = Enum.AutomaticSize.Y
	b.TextYAlignment = Enum.TextYAlignment.Top
	b.LayoutOrder = order + 1
end

function Deployment.show(cb: Callbacks)
	Deployment.destroy()
	local sg = Kit.screen("EoEDeploy", 20)
	local sc = BattleState.scenario or {}
	local touch = Kit.touch()
	-- the dispatch: a parchment document sealed in crimson (on a phone it fills the height)
	local panel = Kit.panel(sg, { size = UDim2.new(0, 420, 1, if touch then -16 else -96), position = UDim2.new(0, if touch then 8 else 24, 0.5, 0), anchor = Vector2.new(0, 0.5), padding = if touch then 12 else 18, parchment = true })
	local cap = Instance.new("UISizeConstraint") :: UISizeConstraint
	cap.MaxSize = Vector2.new(420, 660)
	cap.Parent = panel

	-- The sheet is set as a letter: a text column on the left and a margin on the right that
	-- carries the seal, the notes (weather, time) and, at its foot, the stamp. The column
	-- (and the scrolling body below) never reaches the margin, so the stamp covers no text.
	local MARGIN = 96
	local col = UDim2.new(1, -MARGIN - 12, 0, 18)
	local dated = Kit.label(panel, "Headquarters, " .. (sc.date or "the eve of battle"), { size = col, textSize = 17 })
	dated.FontFace = Kit.ITALIC
	local title = Kit.title(panel, sc.name or "Deployment", { size = UDim2.new(1, -MARGIN - 12, 0, 30), position = UDim2.fromOffset(0, 18), textSize = 26 })
	-- long episode names ("The Fight for Vierzehnheiligen") shrink to fit instead of "THE FIGHT FOR…"
	title.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint") :: UITextSizeConstraint
	fit.MaxTextSize = 26
	fit.Parent = title
	local margin = Instance.new("Frame") :: Frame
	margin.Size = UDim2.new(0, MARGIN, 1, -62)
	margin.Position = UDim2.fromScale(1, 0)
	margin.AnchorPoint = Vector2.new(1, 0)
	margin.BackgroundTransparency = 1
	margin.Parent = panel
	Kit.seal(margin, UDim2.new(0.5, 0, 0, 26), 52)
	local facts = {}
	local w = (Config.Weather :: any)[sc.weather or ""]
	if w then
		table.insert(facts, w.label)
	end
	if sc.timeLimit and sc.timeLimit > 0 then
		table.insert(facts, string.format("%d minutes", math.floor(sc.timeLimit / 60)))
	end
	for i, fact in facts do
		local n = Kit.label(margin, fact, { size = UDim2.new(1, 0, 0, 18), position = UDim2.fromOffset(0, 50 + i * 18), textSize = 15, colour = Kit.MUTED, align = Enum.TextXAlignment.Center })
		n.FontFace = Kit.ITALIC
	end
	-- the stamp fills the foot of the margin; a short sheet (small viewport) gets a smaller one
	local cam = workspace.CurrentCamera
	local sheetH = math.min(660, (if cam then cam.ViewportSize.Y / Kit.scale() else 720) - (if touch then 16 else 96))
	local d = math.clamp(math.floor((sheetH - 260) / 3), 56, 88)
	Kit.stamp(margin, "Dépôt de la Guerre", UDim2.new(0.5, 0, 1, -d / 2 - 6), d)
	local rule = Kit.rule(panel, UDim2.fromOffset(0, 66))
	rule.Size = UDim2.new(1, -MARGIN - 12, 0, 1)
	local body = Instance.new("ScrollingFrame") :: ScrollingFrame
	body.Size = UDim2.new(1, -MARGIN - 12, 1, -72 - 62)
	body.Position = UDim2.fromOffset(0, 70)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 4
	body.ScrollBarImageColor3 = Kit.INK
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.Parent = panel
	Kit.list(body, 4)
	if sc.difficultyNote then
		local note = Kit.label(body, sc.difficultyNote, { size = UDim2.new(1, -6, 0, 0), wrap = true, textSize = 16, colour = Kit.CRIMSON })
		note.FontFace = Kit.BOLD
		note.AutomaticSize = Enum.AutomaticSize.Y
		note.LayoutOrder = 1
	end
	local pb = Instance.new("Frame") :: Frame
	pb.Size = UDim2.new(1, -6, 0, 0)
	pb.AutomaticSize = Enum.AutomaticSize.Y
	pb.BackgroundTransparency = 1
	pb.LayoutOrder = 5
	pb.Visible = false
	pb.Parent = body
	Kit.list(pb, 3)
	playersBox = pb
	callbacks = cb
	section(body, "Orders", sc.briefing or "", 10)
	section(body, "Deployment", if touch then TOUCH_HINTS else HINTS, 20, Kit.MUTED)
	if sc.summary then
		section(body, "What happened", sc.summary, 30, Kit.MUTED)
	end

	local row = Instance.new("Frame") :: Frame
	row.Size = UDim2.new(1, 0, 0, 52)
	row.Position = UDim2.new(0, 0, 1, -52)
	row.BackgroundTransparency = 1
	row.Parent = panel
	Kit.list(row, 8, true)
	local b = Kit.button(row, "Start Battle", cb.ready, { size = UDim2.new(1, if touch then -74 else -98, 1, 0), primary = true, order = 1, textSize = 24, font = Enum.Font.Garamond })
	local bs = b:FindFirstChildOfClass("UIStroke") :: UIStroke?
	if bs then
		bs.Thickness = 2
	end
	Kit.button(row, if touch then "Set." else "Settings", cb.settings, { size = UDim2.new(0, if touch then 66 else 90, 1, 0), order = 2 })
	if (BattleState.coop() and BattleState.role == "officer") or BattleState.pvp() then
		b.Text = "Ready"
	elseif not BattleState.isCommander then
		Kit.setEnabled(b, false, "Waiting for the commander to start the battle")
	end
	startBtn = b
	gui = sg
	Deployment.refresh()
end

-- Co-op / PvP roster: slot colour, name, ready tick; the side's lead can hand the selection to an
-- officer of the side. The host toggles co-op / PvP; in PvP everyone picks a side by its flag.
function Deployment.refresh()
	local pb = playersBox
	if not pb then
		return
	end
	for _, c in pb:GetChildren() do
		if not c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
	local pvp = BattleState.pvp()
	pb.Visible = BattleState.coop() or pvp
	if not pb.Visible then
		return
	end
	local cb = callbacks
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local setMode = cb and cb.mode
	if BattleState.isCommander and setMode then
		Kit.button(pb, if pvp then "Mode: PvP, side against side" else "Mode: Co-op against the AI", function()
			setMode(if pvp then "coop" else "pvp")
		end, { size = UDim2.new(1, 0, 0, 26), order = nextOrder(), textSize = 15, tooltip = "Switch between every player against the AI and two human sides" })
	end
	local sides = BattleState.sides()
	if pvp then
		local row = Instance.new("Frame") :: Frame
		row.Size = UDim2.new(1, 0, 0, 40)
		row.BackgroundTransparency = 1
		row.LayoutOrder = nextOrder()
		row.Parent = pb
		Kit.list(row, 6, true)
		local pick = cb and cb.side
		for i, side in sides do
			local faction = side.faction
			local b = Kit.button(row, string.format("%s (%d)", Kit.factionName(faction), #side.players), function()
				if pick then
					pick(faction)
				end
			end, { size = UDim2.new(0.5, -3, 1, 0), order = i, textSize = 15, tooltip = "Command this side" })
			Kit.flag(b, faction, Vector2.new(24, 16), UDim2.fromOffset(6, 10))
			Kit.setActiveLook(b, faction == BattleState.viewerFaction)
			Kit.setEnabled(b, BattleState.canOrder(), "Spectators do not pick a side")
		end
		local balance = cb and cb.balance
		if BattleState.isCommander and balance then
			Kit.button(pb, "Balance sides", balance, { size = UDim2.new(1, 0, 0, 24), order = nextOrder(), textSize = 14, tooltip = "Share the players out evenly between the sides" })
		end
	end
	local giver = BattleState.isLead() and cb and cb.assign
	for gi, group in sides do
		if gi == 1 or pvp then
			Kit.title(pb, if pvp then Kit.factionName(group.faction) else "Officers", { size = UDim2.new(1, 0, 0, 22), textSize = 18, spaced = true }).LayoutOrder = nextOrder()
			for _, p in group.players do
				local row = Instance.new("Frame") :: Frame
				row.Size = UDim2.new(1, 0, 0, 22)
				row.BackgroundTransparency = 1
				row.LayoutOrder = nextOrder()
				row.Parent = pb
				local chip = Instance.new("Frame") :: Frame
				chip.Size = UDim2.fromOffset(12, 12)
				chip.Position = UDim2.fromOffset(0, 5)
				chip.BackgroundColor3 = Kit.slotColour(p.slot)
				chip.BorderSizePixel = 0
				chip.Parent = row
				local who = tostring(p.name) .. (if p.role == "commander" then " (commander)" else "") .. (if p.ready then " · ready" else "")
				Kit.label(row, who, { size = UDim2.new(1, -20, 1, 0), position = UDim2.fromOffset(20, 0), textSize = 16, font = Enum.Font.Garamond })
				if giver and p.userId ~= BattleState.userId and group.faction == BattleState.viewerFaction then
					local uid = p.userId
					Kit.button(pb, "Give selected to " .. tostring(p.name), function()
						giver(uid)
					end, { size = UDim2.new(1, 0, 0, 24), order = nextOrder(), textSize = 14, tooltip = "Hand the selected formations to this officer" })
				end
			end
		end
	end
end

function Deployment.setWaiting(text: string, keepEnabled: boolean?)
	if startBtn then
		startBtn.Text = text
		if keepEnabled then
			Kit.setEnabled(startBtn, true, "Start without waiting for every officer")
		else
			Kit.setEnabled(startBtn, false, "The battle is starting")
		end
	end
end

function Deployment.destroy()
	if gui then
		gui:Destroy()
		gui = nil
		startBtn = nil
		playersBox = nil
		callbacks = nil
	end
end

return Deployment
