--!strict
-- Battle select: the scenarios from Scenarios.list() (fallback: Scenarios.jena alone), each with
-- name, date, sides, summary, difficulty note and a Fight button; a difficulty selector on top.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Scenarios = require(Shared.Scenarios)
local Kit = require(script.Parent.Kit)
local BattleState = require(script.Parent.Parent.BattleState)

local BattleSelect = {}

export type Callbacks = {
	fight: (id: string) -> (),
	difficulty: (value: string) -> (),
	back: () -> (),
}

type Entry = { id: string, name: string, date: string?, map: string?, factionNames: { [string]: string }?, summary: string?, difficultyNote: string? }

local gui: ScreenGui? = nil
local difficultyButtons: { [string]: TextButton } = {}

local function entries(): { Entry }
	local list = (Scenarios :: any).list
	if type(list) == "function" then
		local ok, result = pcall(list)
		if ok and type(result) == "table" and #result > 0 then
			return result
		end
	end
	local j = (Scenarios :: any).jena
	if j then
		return { { id = j.id, name = j.name, date = "14 October 1806", map = j.map, factionNames = j.factionNames, summary = j.briefing, difficultyNote = "The opening battle: even numbers, the French hold the high ground." } }
	end
	return {}
end

local function sides(e: Entry): string
	local names = {}
	for _, n in e.factionNames or {} do
		table.insert(names, tostring(n))
	end
	table.sort(names)
	return table.concat(names, "  vs  ")
end

local function refreshDifficulty()
	for key, b in difficultyButtons do
		Kit.setActiveLook(b, BattleState.difficulty == key)
	end
end

-- 1-3 gold stars from the note's opening word ("Even:", "Hard:", "Very hard:").
local function stars(note: string?): number
	local n = string.lower(note or "")
	if string.find(n, "^very hard") then
		return 3
	elseif string.find(n, "^hard") then
		return 2
	end
	return 1
end

local function star(parent: Instance, x: number, filled: boolean)
	for _, rot in { 0, 45 } do
		local d = Instance.new("Frame") :: Frame
		d.Size = UDim2.fromOffset(9, 9)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromOffset(x, 8)
		d.Rotation = rot
		d.BackgroundColor3 = if filled then Kit.GILT else Kit.INSET
		d.BorderSizePixel = 0
		d.Parent = parent
		local st = Instance.new("UIStroke") :: UIStroke
		st.Color = Kit.GILT_DARK
		st.Parent = d
	end
end

local function sideIds(e: Entry): { string }
	local ids = {}
	for id in e.factionNames or {} do
		table.insert(ids, id)
	end
	table.sort(ids, function(a: string, b: string)
		if a == "france" or b == "france" then
			return a == "france"
		end
		return a < b
	end)
	return ids
end

-- A framed "painting": gold-bordered dark card with the name, the date in italic, the two
-- flags facing each other, the history on a parchment strip and the difficulty in stars.
local function card(parent: Instance, e: Entry, order: number, cb: Callbacks, isCommander: boolean)
	local f = Kit.panel(parent, { size = UDim2.new(1, -8, 0, 150), position = UDim2.new(), dark = true, padding = 12 })
	f.LayoutOrder = order
	f.AutomaticSize = Enum.AutomaticSize.Y
	local fs = f:FindFirstChildOfClass("UIStroke") :: UIStroke?
	if fs then
		fs.Color = Kit.GILT
		fs.Thickness = 2
	end
	local name = Kit.title(f, e.name, { size = UDim2.new(1, -240, 0, 28), textSize = 23, colour = Kit.IVORY })
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local date = Kit.label(f, string.format("%s   ·   %s", tostring(e.date or ""), sides(e)), { size = UDim2.new(1, -240, 0, 20), position = UDim2.new(0, 0, 0, 28), textSize = 17, colour = Kit.MUTED })
	date.FontFace = Kit.ITALIC
	-- the colours, facing each other across the field
	local ids = sideIds(e)
	local flags = Instance.new("Frame") :: Frame
	flags.Size = UDim2.fromOffset(112, 36)
	flags.Position = UDim2.new(1, -232, 0, 4)
	flags.BackgroundTransparency = 1
	flags.Parent = f
	if ids[1] then
		Kit.flag(flags, ids[1], Vector2.new(36, 24), UDim2.fromOffset(0, 0))
	end
	local vs = Kit.label(flags, "vs", { size = UDim2.fromOffset(24, 24), position = UDim2.fromOffset(44, 0), textSize = 17, colour = Kit.GILT, align = Enum.TextXAlignment.Center })
	vs.FontFace = Kit.ITALIC
	for i = 2, math.min(#ids, 3) do
		Kit.flag(flags, ids[i], Vector2.new(36, 24), UDim2.fromOffset(72 + (i - 2) * 10, (i - 2) * 6), true)
	end
	-- summary on a parchment strip, then the difficulty
	local body = Instance.new("Frame") :: Frame
	body.Size = UDim2.new(1, -124, 0, 0)
	body.Position = UDim2.new(0, 0, 0, 56)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.Parent = f
	Kit.list(body, 8)
	local strip = Kit.panel(body, { size = UDim2.new(1, 0, 0, 0), position = UDim2.new(), parchment = true, padding = 10 })
	strip.AutomaticSize = Enum.AutomaticSize.Y
	strip.LayoutOrder = 1
	local summary = Kit.label(strip, tostring(e.summary or ""), { size = UDim2.new(1, 0, 0, 0), textSize = 16, font = Enum.Font.Garamond, wrap = true })
	summary.AutomaticSize = Enum.AutomaticSize.Y
	summary.TextYAlignment = Enum.TextYAlignment.Top
	local diff = Instance.new("Frame") :: Frame
	diff.Size = UDim2.new(1, 0, 0, 16)
	diff.AutomaticSize = Enum.AutomaticSize.Y
	diff.BackgroundTransparency = 1
	diff.LayoutOrder = 2
	diff.Parent = body
	local n = stars(e.difficultyNote)
	for i = 1, 3 do
		star(diff, 6 + (i - 1) * 16, i <= n)
	end
	local note = Kit.label(diff, tostring(e.difficultyNote or ""), { size = UDim2.new(1, -56, 0, 0), position = UDim2.fromOffset(56, 0), textSize = 14, colour = Kit.MUTED, wrap = true })
	note.AutomaticSize = Enum.AutomaticSize.Y
	local b = Kit.button(f, "Fight", function()
		cb.fight(e.id)
	end, { size = UDim2.fromOffset(110, 40), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0), primary = true, textSize = 18 })
	Kit.setEnabled(b, isCommander, "Only the commander starts a battle")
end

function BattleSelect.show(cb: Callbacks, isCommander: boolean)
	BattleSelect.destroy()
	local sg = Kit.screen("EoEBattleSelect", 31)
	local panel = Kit.panel(sg, { size = UDim2.fromOffset(720, 640), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), padding = 20 })
	Kit.title(panel, "Choose a battle", { size = UDim2.new(1, -130, 0, 34), textSize = 28, spaced = true, colour = Kit.GILT, rule = true })
	Kit.button(panel, "Back (Esc)", cb.back, { size = UDim2.fromOffset(110, 28), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0) })
	Kit.label(panel, "Enemy difficulty", { size = UDim2.new(0, 160, 0, 30), position = UDim2.new(0, 0, 0, 44), textSize = 15, colour = Kit.MUTED })
	local dRow = Instance.new("Frame") :: Frame
	dRow.Size = UDim2.new(0, 300, 0, 30)
	dRow.Position = UDim2.new(0, 150, 0, 44)
	dRow.BackgroundTransparency = 1
	dRow.Parent = panel
	Kit.list(dRow, 6, true)
	table.clear(difficultyButtons)
	for i, key in { "easy", "normal", "hard" } do
		local b = Kit.button(dRow, string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2), function()
			cb.difficulty(key)
			BattleState.difficulty = key
			refreshDifficulty()
		end, { size = UDim2.fromOffset(94, 30), order = i, tooltip = if key == "hard" then "The enemy gets +5 morale" else nil })
		Kit.setEnabled(b, isCommander, "Only the commander sets the difficulty")
		difficultyButtons[key] = b
	end
	refreshDifficulty()
	local scroll = Instance.new("ScrollingFrame") :: ScrollingFrame
	scroll.Size = UDim2.new(1, 0, 1, -86)
	scroll.Position = UDim2.new(0, 0, 0, 82)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Kit.GILT
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Active = true
	scroll.Parent = panel
	Kit.list(scroll, 10)
	local list = entries()
	for i, e in list do
		card(scroll, e, i, cb, isCommander)
	end
	if #list == 0 then
		Kit.label(scroll, "No scenarios are installed.", { size = UDim2.new(1, 0, 0, 24), colour = Kit.MUTED })
	end
	gui = sg
end

function BattleSelect.isOpen(): boolean
	return gui ~= nil
end

function BattleSelect.hide()
	BattleSelect.destroy()
end

function BattleSelect.destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(difficultyButtons)
end

return BattleSelect
