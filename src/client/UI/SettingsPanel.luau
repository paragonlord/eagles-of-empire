--!strict
-- Settings: quality, volumes, reduced shake/effects, typeface, place names, AI difficulty.
-- Applies live via Settings.

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
		local touch = Kit.touch()
		-- on a phone the sheet takes the height it can get and the list scrolls inside it
		-- desktop: 710 tall; rows past that scroll (the audio rows pushed AI difficulty out of sight)
		local panel = Kit.panel(sg, { size = if touch then UDim2.new(0, 420, 1, -16) else UDim2.fromOffset(420, 710), position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5), padding = if touch then 12 else 20 })
		if not touch then
			Kit.fit(panel, 420, 710) -- a short window cuts the sheet, not its Close button
		end
		if touch then
			local cap = Instance.new("UISizeConstraint") :: UISizeConstraint
			cap.MaxSize = Vector2.new(420, 640)
			cap.Parent = panel
		end
		Kit.title(panel, "Settings", { size = UDim2.new(1, 0, 0, 36), textSize = 30 })
		Kit.button(panel, "Close", SettingsPanel.hide, { size = UDim2.fromOffset(110, if touch then 34 else 28), position = UDim2.new(1, 0, 0, 0), anchor = Vector2.new(1, 0) })
		local list = Instance.new("ScrollingFrame") :: ScrollingFrame
		list.Size = UDim2.new(1, 0, 1, -48)
		list.Position = UDim2.new(0, 0, 0, 44)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 6
		list.ScrollBarImageColor3 = Kit.GILT
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.Parent = panel
		-- the content column stops short of the scrollbar so nothing sits under it
		local pad = Instance.new("UIPadding") :: UIPadding
		pad.PaddingRight = UDim.new(0, list.ScrollBarThickness + 6)
		pad.Parent = list
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
		Kit.slider(list, "Ambience volume", v.ambience, function(x)
			Settings.set("ambience", x)
		end).LayoutOrder = next()
		Kit.slider(list, "Interface volume", v.ui, function(x)
			Settings.set("ui", x)
		end).LayoutOrder = next()
		if Audio.isSilent() then
			local n = Kit.label(list, "No sound assets installed: the game is silent. Volumes are kept for when they are.", { size = UDim2.new(1, 0, 0, 32), wrap = true, colour = Kit.MUTED, textSize = 12 })
			n.LayoutOrder = next()
		end
		Kit.toggle(list, "Edge scrolling (mouse at the window's edge pans)", v.edgeScroll, function(x)
			Settings.set("edgeScroll", x)
		end).LayoutOrder = next()
		Kit.toggle(list, "Reduced screen shake", v.reducedShake, function(x)
			Settings.set("reducedShake", x)
		end).LayoutOrder = next()
		Kit.toggle(list, "Reduced effects (half the smoke and dust)", v.reducedEffects, function(x)
			Settings.set("reducedEffects", x)
		end).LayoutOrder = next()
		local studio = game:GetService("RunService"):IsStudio() -- developer rows stay out of players' way
		if studio then
			Kit.toggle(list, "Audio log (prints every sound hook to the output)", v.debugAudio, function(x)
				Settings.set("debugAudio", x)
			end).LayoutOrder = next()
		end

		-- a row of choices: the chosen one sits sunk
		local function choices(label: string, key: string, options: { string }, names: { string }?)
			local l = Kit.label(list, label, { size = UDim2.new(1, 0, 0, 18) })
			l.LayoutOrder = next()
			local rowF = Instance.new("Frame") :: Frame
			rowF.Size = UDim2.new(1, 0, 0, 30)
			rowF.BackgroundTransparency = 1
			rowF.LayoutOrder = next()
			rowF.Parent = list
			Kit.list(rowF, 6, true)
			local buttons: { TextButton } = {}
			local function refresh()
				for i, b in buttons do
					Kit.setActiveLook(b, (Settings.get() :: any)[key] == options[i])
				end
			end
			for i, opt in options do
				buttons[i] = Kit.button(rowF, if names then names[i] else opt, function()
					Settings.set(key, opt)
					refresh()
				end, { size = UDim2.new(1 / #options, -5, 1, 0), order = i, textSize = 13 })
			end
			refresh()
		end
		choices(if studio then "Controls (choose Touch in Studio's device emulator)" else "Controls", "controls", Settings.CONTROLS, { "Auto", "Touch", "Desktop" })
		choices("Typeface (headings and text)", "typeface", Settings.TYPEFACES, nil)
		choices("Place names on the field", "placeNames", Settings.PLACE_NAMES, { "On the ground", "Floating", "Under cursor", "Off" })

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

-- The sheet is laid out for touch or desktop when it is built, and it is built once: rebuild it
-- when Controls changes, or picking Touch in Studio's emulator never shows the touch sheet.
Settings.changed:Connect(function(key: string)
	if key == "controls" and gui then
		local open = SettingsPanel.isOpen()
		SettingsPanel.destroy()
		if open then
			SettingsPanel.show()
		end
	end
end)

return SettingsPanel
