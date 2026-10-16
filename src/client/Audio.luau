--!strict
-- Sound registry + pooled Sound instances. Asset ids are intentionally empty: nothing is
-- invented. With an empty id a play() is a silent no-op and Audio.isSilent() reports it.

local SoundService = game:GetService("SoundService") :: SoundService
local Settings = require(script.Parent.Settings)
local Signal = require(script.Parent.Signal)

type Entry = { id: string, category: "sfx" | "music", volume: number, pool: number }

local REGISTRY: { [string]: Entry } = {
	volley = { id = "", category = "sfx", volume = 0.7, pool = 6 },
	cannon = { id = "", category = "sfx", volume = 0.9, pool = 4 },
	melee = { id = "", category = "sfx", volume = 0.6, pool = 3 },
	charge = { id = "", category = "sfx", volume = 0.7, pool = 2 },
	rout = { id = "", category = "sfx", volume = 0.5, pool = 2 },
	rally = { id = "", category = "sfx", volume = 0.5, pool = 2 },
	capture = { id = "", category = "sfx", volume = 0.6, pool = 2 },
	click = { id = "", category = "sfx", volume = 0.4, pool = 2 },
	battleMusic = { id = "", category = "music", volume = 0.5, pool = 1 },
}

local Audio = {}

local group: SoundGroup? = nil
local pools: { [string]: { Sound } } = {}
local cursor: { [string]: number } = {}
local settingsConn: Signal.Connection? = nil

local function applyVolume(name: string, s: Sound)
	local e = REGISTRY[name]
	local v = Settings.get()
	local cat = if e.category == "music" then v.music else v.sfx
	s.Volume = e.volume * cat * v.master
end

function Audio.init()
	if group then
		return
	end
	local g = Instance.new("SoundGroup") :: SoundGroup
	g.Name = "EoEAudio"
	g.Parent = SoundService
	group = g
	for name, e in REGISTRY do
		local list: { Sound } = {}
		if e.id ~= "" then
			for i = 1, e.pool do
				local s = Instance.new("Sound") :: Sound
				s.Name = name .. i
				s.SoundId = e.id
				s.Looped = e.category == "music"
				s.SoundGroup = g
				s.Parent = g
				applyVolume(name, s)
				list[i] = s
			end
		end
		pools[name] = list
		cursor[name] = 0
	end
	settingsConn = Settings.changed:Connect(function()
		for name, list in pools do
			for _, s in list do
				applyVolume(name, s)
			end
		end
	end)
end

-- True when no registered asset id is installed (the settings panel says so).
function Audio.isSilent(): boolean
	for _, e in REGISTRY do
		if e.id ~= "" then
			return false
		end
	end
	return true
end

function Audio.play(name: string)
	local list = pools[name]
	if not list or #list == 0 then
		return -- silent fallback
	end
	local i = cursor[name] % #list + 1
	cursor[name] = i
	local s = list[i]
	if s.IsPlaying and not s.Looped then
		s:Stop()
	end
	if not s.IsPlaying then
		s:Play()
	end
end

function Audio.stop(name: string)
	local list = pools[name]
	if list then
		for _, s in list do
			s:Stop()
		end
	end
end

function Audio.destroy()
	if settingsConn then
		settingsConn:Disconnect()
		settingsConn = nil
	end
	if group then
		group:Destroy()
		group = nil
	end
	table.clear(pools)
end

return Audio
