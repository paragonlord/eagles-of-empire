--!strict
-- Morning battlefield light: warm sun from the south-east, light haze, soft clouds, slight
-- warmth and contrast. Built-in defaults only (no asset ids). Quality 1 drops the costly bits.

local LightingService = game:GetService("Lighting") :: Lighting

local Lighting = {}

local NAME = "EoE"
local applied: { Instance } = {}

local function clearOwned()
	for _, i in applied do
		i:Destroy()
	end
	table.clear(applied)
end

local function own<T>(i: T & Instance, parent: Instance): T
	i.Name = NAME .. i.ClassName
	i.Parent = parent
	table.insert(applied, i)
	return i
end

-- Technology is not writable from every context; try Future, then ShadowMap, else keep the place's.
local function setTechnology()
	local ok = pcall(function()
		(LightingService :: any).Technology = Enum.Technology.Future
	end)
	if not ok then
		pcall(function()
			(LightingService :: any).Technology = Enum.Technology.ShadowMap
		end)
	end
end

local currentQuality = 2
local currentWeather: string? = nil

-- Weather tints only the distance. Atmosphere haze turned the whole field teal in Studio
-- under fog, so fog weather switches the Atmosphere off and uses plain distance fog in a pale
-- warm grey, which leaves the near ground untouched.
local function applyHaze(L: Lighting, atmo: Atmosphere?)
	local foggy = currentWeather == "fog"
	if atmo then
		atmo.Parent = if foggy then nil else L
		atmo.Density = 0.08
		atmo.Offset = 0.3
		atmo.Color = Color3.fromRGB(226, 216, 190)
		atmo.Decay = Color3.fromRGB(196, 184, 150)
		atmo.Glare = 0
		atmo.Haze = 0.2
	end
	L.FogColor = Color3.fromRGB(206, 200, 186)
	L.FogStart = if foggy then 380 else 1800
	L.FogEnd = if foggy then 1700 else 4600
end

local atmosphere: Atmosphere? = nil

function Lighting.apply(quality: number)
	currentQuality = quality
	clearOwned()
	atmosphere = nil
	setTechnology()
	local L = LightingService
	-- Low morning sun from the south-east: long shadows so north/west slopes read dark.
	L.ClockTime = 8.9
	L.GeographicLatitude = 50
	L.Brightness = 2.8
	L.ShadowSoftness = 0.12
	L.GlobalShadows = true
	-- low ambient keeps the shaded side of a ridge dark, as in the reference
	L.EnvironmentDiffuseScale = 0.25
	L.EnvironmentSpecularScale = 0.1
	L.Ambient = Color3.fromRGB(64, 60, 50)
	L.OutdoorAmbient = Color3.fromRGB(104, 98, 82)
	L.ExposureCompensation = 0.15

	local sky = own(Instance.new("Sky") :: Sky, L)
	sky.CelestialBodiesShown = true
	sky.StarCount = 0
	sky.SunAngularSize = 14

	local cc = own(Instance.new("ColorCorrectionEffect") :: ColorCorrectionEffect, L)
	cc.TintColor = Color3.fromRGB(255, 250, 240) -- a touch warm, never cyan or orange
	cc.Contrast = 0.16
	cc.Saturation = 0.08
	cc.Brightness = 0.02

	local bloom = own(Instance.new("BloomEffect") :: BloomEffect, L)
	bloom.Intensity = 0.12
	bloom.Size = 18
	bloom.Threshold = 1.8

	if quality >= 2 then
		atmosphere = own(Instance.new("Atmosphere") :: Atmosphere, L)

		local rays = own(Instance.new("SunRaysEffect") :: SunRaysEffect, L)
		rays.Intensity = 0.03
		rays.Spread = 0.5

		local clouds = own(Instance.new("Clouds") :: Clouds, workspace.Terrain)
		clouds.Cover = 0.4
		clouds.Density = 0.2
		clouds.Color = Color3.fromRGB(248, 244, 234)
	end
	applyHaze(L, atmosphere)
end

-- Scenario weather (`fog`, `rain`, ... or nil). Only fog changes the light.
function Lighting.setWeather(weather: string?)
	if weather == currentWeather then
		return
	end
	currentWeather = weather
	applyHaze(LightingService, atmosphere)
end

function Lighting.quality(): number
	return currentQuality
end

function Lighting.destroy()
	clearOwned()
end

return Lighting
