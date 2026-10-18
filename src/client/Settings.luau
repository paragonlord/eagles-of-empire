--!strict
-- Viewer settings store. Lives for the session; `changed` fires (key, value) on every set.

local UserInputService = game:GetService("UserInputService") :: UserInputService
local Signal = require(script.Parent.Signal)
local Touch = require(script.Parent.Touch)

export type Values = {
	quality: number, -- 1..3
	master: number, -- 0..1
	sfx: number,
	music: number,
	ambience: number,
	ui: number,
	debugAudio: boolean, -- print every audio hook (Audio.luau) to the output
	reducedShake: boolean,
	reducedEffects: boolean,
	typeface: string, -- one of Settings.TYPEFACES (UI/Kit presets)
	placeNames: string, -- one of Settings.PLACE_NAMES (World/Props label modes)
	controls: string, -- one of Touch.CONTROLS: auto / touch / desktop (docs/mobile-contract.md)
}

local Settings = {}

-- Device flags, guarded so the headless test runner (no UserInputService members) loads too.
local function flag(name: string): boolean
	local ok, v = pcall(function()
		return (UserInputService :: any)[name]
	end)
	return ok and v == true
end

-- Touch devices start on quality 1 (figure budget, no near tier, fewer smoke parts).
local touchDevice = Touch.detect(flag("TouchEnabled"), flag("KeyboardEnabled"), "auto")

local values: Values = {
	quality = if touchDevice then 1 else 2,
	master = 0.8,
	sfx = 1.0,
	music = 0.6,
	ambience = 0.7,
	ui = 0.8,
	debugAudio = false,
	reducedShake = false,
	reducedEffects = false,
	typeface = "Garamond",
	placeNames = "ground",
	controls = "auto",
}

-- Type presets the owner can switch live to judge readability (built in UI/Kit).
Settings.TYPEFACES = { "Garamond", "Bodoni", "Legible", "Antique" }
-- Battlefield place names: on the ground, floating above the place, only under the cursor, or off.
Settings.PLACE_NAMES = { "ground", "floating", "hover", "off" }

Settings.changed = Signal.new()
Settings.CONTROLS = Touch.CONTROLS

-- Touch mode: a touch screen without a keyboard, or the controls override.
function Settings.touch(): boolean
	return Touch.detect(flag("TouchEnabled"), flag("KeyboardEnabled"), values.controls)
end

function Settings.get(): Values
	return values
end

function Settings.set(key: string, value: any)
	local v = values :: any
	if v[key] == value then
		return
	end
	if key == "quality" then
		value = math.clamp(math.round(value), 1, 3)
	elseif key == "master" or key == "sfx" or key == "music" or key == "ambience" or key == "ui" then
		value = math.clamp(value, 0, 1)
	elseif key == "typeface" or key == "placeNames" or key == "controls" then
		local list = if key == "typeface" then Settings.TYPEFACES elseif key == "placeNames" then Settings.PLACE_NAMES else Settings.CONTROLS
		if table.find(list, value) == nil then
			return
		end
	end
	v[key] = value
	Settings.changed:Fire(key, value)
end

return Settings
