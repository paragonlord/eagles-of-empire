--!strict
-- Viewer settings store. Lives for the session; `changed` fires (key, value) on every set.

local Signal = require(script.Parent.Signal)

export type Values = {
	quality: number, -- 1..3
	master: number, -- 0..1
	sfx: number,
	music: number,
	reducedShake: boolean,
	reducedEffects: boolean,
	typeface: string, -- one of Settings.TYPEFACES (UI/Kit presets)
	placeNames: string, -- one of Settings.PLACE_NAMES (World/Props label modes)
}

local Settings = {}

local values: Values = {
	quality = 2,
	master = 0.8,
	sfx = 1.0,
	music = 0.6,
	reducedShake = false,
	reducedEffects = false,
	typeface = "Garamond",
	placeNames = "ground",
}

-- Type presets the owner can switch live to judge readability (built in UI/Kit).
Settings.TYPEFACES = { "Garamond", "Bodoni", "Legible", "Antique" }
-- Battlefield place names: on the ground, floating above the place, only under the cursor, or off.
Settings.PLACE_NAMES = { "ground", "floating", "hover", "off" }

Settings.changed = Signal.new()

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
	elseif key == "master" or key == "sfx" or key == "music" then
		value = math.clamp(value, 0, 1)
	elseif key == "typeface" or key == "placeNames" then
		if table.find(if key == "typeface" then Settings.TYPEFACES else Settings.PLACE_NAMES, value) == nil then
			return
		end
	end
	v[key] = value
	Settings.changed:Fire(key, value)
end

return Settings
