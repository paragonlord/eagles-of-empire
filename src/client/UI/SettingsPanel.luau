--!strict
-- Settings: quality, volumes, reduced shake/effects, AI difficulty. Applies live via Settings.

local Kit = require(script.Parent.Kit)
local Settings = require(script.Parent.Parent.Settings)
local Audio = require(script.Parent.Parent.Audio)
local Net = require(script.Parent.Parent.Net)
local BattleState = require(script.Parent.Parent.BattleState)

local SettingsPanel = {}

local gui: ScreenGui? = nil
local qualityButtons: { TextButton } = {}
local difficultyButtons: { [string]: TextButton } = {}

local function refreshQuality()
	for i, b in qualityButtons do
		Kit.setActiveLook(b, Settings.get().quality == i)
	end
end

local function refreshDifficulty()
	for key, b in difficultyButtons do
		Kit.setActiveLook(b, BattleState.difficulty == key)
		Kit.setEnabled(b, BattleState.isCommander and (BattleState.state == "menu" or BattleState.state == "deployment"), "Difficulty is set before the battle starts")
	end
end

function SettingsPanel.show()
	if not gui then
		local sg = Kit.screen("EoESettings", 36)
		local panel = Kit.panel(sg, { size = UDim2.fromOffset(420, 540), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), padding = 20 })
		Kit.title(panel, "Settings", { size = UDim2.new(1, 0, 0, 36), textSize = 30 })
		Kit.button(panel, "Close (Esc)", SettingsPanel.hide, { size = UDim2.fromOffset(110, 28), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0) })
		local list = Instance.new("Frame") :: Frame
		list.Size = UDim2.new(1, 0, 1, -48)
		list.Position = UDim2.new(0, 0, 0, 44)
		list.BackgroundTransparency = 1
		list.Parent = panel
		Kit.list(list, 10)
		local order = 0
		local function next(): number
			order += 1
			return order
		end

		local q = Kit.label(list, "Quality (figure count, trees, effects)", { size = UDim2.new(1, 0, 0, 18) })
		q.LayoutOrder = next()
		local qRow = Instance.new("Frame") :: Frame
		qRow.Size = UDim2.new(1, 0, 0, 30)
		qRow.BackgroundTransparency = 1
		qRow.LayoutOrder = next()
		qRow.Parent = list
		Kit.list(qRow, 6, true)
		for i, name in { "Low", "Medium", "High" } do
			local b = Kit.button(qRow, name, function()
				Settings.set("quality", i)
				refreshQuality()
			end, { size = UDim2.new(0.32, 0, 1, 0), order = i })
			qualityButtons[i] = b
		end
		refreshQuality()

		local v = Settings.get()
		Kit.slider(list, "Master volume", v.master, function(x)
			Settings.set("master", x)
		end).LayoutOrder = next()
		Kit.slider(list, "Effects volume", v.sfx, function(x)
			Settings.set("sfx", x)
		end).LayoutOrder = next()
		Kit.slider(list, "Music volume", v.music, function(x)
			Settings.set("music", x)
		end).LayoutOrder = next()
		if Audio.isSilent() then
			local n = Kit.label(list, "No sound assets installed: the game is silent. Volumes are kept for when they are.", { size = UDim2.new(1, 0, 0, 32), wrap = true, colour = Kit.MUTED, textSize = 12 })
			n.LayoutOrder = next()
		end
		Kit.toggle(list, "Reduced screen shake", v.reducedShake, function(x)
			Settings.set("reducedShake", x)
		end).LayoutOrder = next()
		Kit.toggle(list, "Reduced effects (half the smoke and dust)", v.reducedEffects, function(x)
			Settings.set("reducedEffects", x)
		end).LayoutOrder = next()

		local d = Kit.label(list, "AI difficulty (Hard: the enemy gets +5 morale)", { size = UDim2.new(1, 0, 0, 18) })
		d.LayoutOrder = next()
		local dRow = Instance.new("Frame") :: Frame
		dRow.Size = UDim2.new(1, 0, 0, 30)
		dRow.BackgroundTransparency = 1
		dRow.LayoutOrder = next()
		dRow.Parent = list
		Kit.list(dRow, 6, true)
		for i, key in { "easy", "normal", "hard" } do
			local b = Kit.button(dRow, string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2), function()
				Net.control("difficulty", key)
				BattleState.difficulty = key
				refreshDifficulty()
			end, { size = UDim2.new(0.32, 0, 1, 0), order = i })
			difficultyButtons[key] = b
		end
		gui = sg
	end
	refreshQuality()
	refreshDifficulty()
	if gui then
		gui.Enabled = true
	end
end

function SettingsPanel.hide()
	if gui then
		gui.Enabled = false
	end
end

function SettingsPanel.isOpen(): boolean
	return gui ~= nil and (gui :: ScreenGui).Enabled
end

function SettingsPanel.destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(qualityButtons)
	table.clear(difficultyButtons)
end

return SettingsPanel
