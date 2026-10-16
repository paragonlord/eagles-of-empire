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
}

local Settings = {}

local values: Values = {
	quality = 2,
	master = 0.8,
	sfx = 1.0,
	music = 0.6,
	reducedShake = false,
	reducedEffects = false,
}

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
	end
	v[key] = value
	Settings.changed:Fire(key, value)
end

return Settings
