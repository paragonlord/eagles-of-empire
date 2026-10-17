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

local function card(parent: Instance, e: Entry, order: number, cb: Callbacks, isCommander: boolean)
	local f = Kit.panel(parent, { size = UDim2.new(1, -8, 0, 150), position = UDim2.new(), dark = true, padding = 12 })
	f.LayoutOrder = order
	f.AutomaticSize = Enum.AutomaticSize.Y
	Kit.title(f, e.name, { size = UDim2.new(1, -130, 0, 28), textSize = 24 })
	Kit.label(f, string.format("%s   ·   %s", tostring(e.date or ""), sides(e)), { size = UDim2.new(1, -130, 0, 18), position = UDim2.new(0, 0, 0, 30), textSize = 12, colour = Kit.MUTED })
	local summary = Kit.label(f, tostring(e.summary or ""), { size = UDim2.new(1, -130, 0, 40), position = UDim2.new(0, 0, 0, 52), textSize = 13, wrap = true })
	summary.AutomaticSize = Enum.AutomaticSize.Y
	summary.TextYAlignment = Enum.TextYAlignment.Top
	local note = Kit.label(f, if e.difficultyNote then "Difficulty: " .. tostring(e.difficultyNote) else "", { size = UDim2.new(1, -130, 0, 18), position = UDim2.new(0, 0, 1, -22), anchor = Vector2.new(0, 1), textSize = 12, colour = Kit.MUTED, wrap = true })
	note.AutomaticSize = Enum.AutomaticSize.Y
	local b = Kit.button(f, "Fight", function()
		cb.fight(e.id)
	end, { size = UDim2.fromOffset(110, 40), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0), primary = true, textSize = 16 })
	Kit.setEnabled(b, isCommander, "Only the commander starts a battle")
end

function BattleSelect.show(cb: Callbacks, isCommander: boolean)
	BattleSelect.destroy()
	local sg = Kit.screen("EoEBattleSelect", 31)
	local panel = Kit.panel(sg, { size = UDim2.fromOffset(720, 640), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), padding = 20 })
	Kit.title(panel, "Choose a battle", { size = UDim2.new(1, 0, 0, 36), textSize = 30 })
	Kit.button(panel, "Back (Esc)", cb.back, { size = UDim2.fromOffset(110, 28), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0) })
	Kit.label(panel, "Enemy difficulty", { size = UDim2.new(0, 160, 0, 30), position = UDim2.new(0, 0, 0, 44), textSize = 13, colour = Kit.MUTED })
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
