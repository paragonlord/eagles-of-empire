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

function Lighting.apply(quality: number)
	clearOwned()
	setTechnology()
	local L = LightingService
	-- ~10:12, latitude 50: the sun stands in the south-east, so north/west slopes read darker
	L.ClockTime = 10.2
	L.GeographicLatitude = 50
	L.Brightness = 2.4
	L.ShadowSoftness = 0.2
	L.GlobalShadows = true
	L.EnvironmentDiffuseScale = 0.5
	L.EnvironmentSpecularScale = 0.25
	L.Ambient = Color3.fromRGB(88, 92, 82)
	L.OutdoorAmbient = Color3.fromRGB(126, 128, 112)
	L.ExposureCompensation = 0.1

	local sky = own(Instance.new("Sky") :: Sky, L)
	sky.CelestialBodiesShown = true
	sky.StarCount = 0
	sky.SunAngularSize = 14

	local cc = own(Instance.new("ColorCorrectionEffect") :: ColorCorrectionEffect, L)
	cc.TintColor = Color3.fromRGB(255, 248, 236) -- slight warmth
	cc.Contrast = 0.08
	cc.Saturation = 0.04
	cc.Brightness = 0.0

	local bloom = own(Instance.new("BloomEffect") :: BloomEffect, L)
	bloom.Intensity = 0.15
	bloom.Size = 18
	bloom.Threshold = 1.6

	if quality >= 2 then
		local atmo = own(Instance.new("Atmosphere") :: Atmosphere, L)
		atmo.Density = 0.28
		atmo.Offset = 0.12
		atmo.Color = Color3.fromRGB(214, 206, 186)
		atmo.Decay = Color3.fromRGB(120, 118, 104)
		atmo.Glare = 0.15
		atmo.Haze = 1.2

		local rays = own(Instance.new("SunRaysEffect") :: SunRaysEffect, L)
		rays.Intensity = 0.04
		rays.Spread = 0.6

		local clouds = own(Instance.new("Clouds") :: Clouds, workspace.Terrain)
		clouds.Cover = 0.45
		clouds.Density = 0.25
		clouds.Color = Color3.fromRGB(246, 242, 232)
	else
		-- without Atmosphere, plain distance fog hides the horizon past the map edge
		L.FogColor = Color3.fromRGB(200, 198, 182)
		L.FogStart = 1400
		L.FogEnd = 3400
	end
end

function Lighting.destroy()
	clearOwned()
end

return Lighting
