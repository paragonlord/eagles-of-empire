--!strict
-- Battlefield light, graded like a painted campaign map: a warm late-afternoon sun by default,
-- a pale morning fog that lifts into clear sun (the Sun of Austerlitz), and a soft wet overcast
-- for rain and mud (Waterloo). Built-in sky and post effects only (no asset ids).
-- Studio history: Atmosphere haze with the default blue decay turned the field teal, and a warm
-- grade on olive-gold grass read orange; decay colours here stay neutral-warm grey and the
-- colour correction only nudges warmth. Quality 1 drops the costly bits.

local LightingService = game:GetService("Lighting") :: Lighting
local TweenService = game:GetService("TweenService") :: TweenService
local RunService = game:GetService("RunService") :: RunService

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

local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

type Grade = {
	clock: number,
	brightness: number,
	shadowSoftness: number,
	ambient: Color3,
	outdoor: Color3,
	shiftTop: Color3,
	exposure: number,
	tint: Color3,
	contrast: number,
	saturation: number,
	bloom: number,
	atmoDensity: number,
	atmoOffset: number,
	atmoColor: Color3,
	atmoDecay: Color3,
	atmoHaze: number,
	atmoGlare: number,
	cloudCover: number,
	cloudDensity: number,
	cloudColor: Color3,
	rays: number,
	fogStart: number, -- quality 1 (no Atmosphere) uses plain distance fog
	fogEnd: number,
	fogColor: Color3,
}

local GRADES: { [string]: Grade } = {
	-- Low sun from the south-west, long soft shadows, a golden but not orange cast; the horizon
	-- melts into a warm pale haze so the country beyond the map has no hard edge.
	afternoon = {
		clock = 15.7,
		brightness = 2.6,
		shadowSoftness = 0.3,
		ambient = c3(66, 62, 56),
		outdoor = c3(112, 110, 104),
		shiftTop = c3(255, 244, 226),
		exposure = 0.1,
		tint = c3(255, 248, 236),
		contrast = 0.14,
		saturation = 0.06,
		bloom = 0.3,
		atmoDensity = 0.3,
		atmoOffset = 0.2,
		atmoColor = c3(214, 206, 188),
		atmoDecay = c3(176, 166, 146),
		atmoHaze = 0.9,
		atmoGlare = 0.2,
		cloudCover = 0.48,
		cloudDensity = 0.3,
		cloudColor = c3(250, 244, 232),
		rays = 0.04,
		fogStart = 1400,
		fogEnd = 3800,
		fogColor = c3(206, 198, 180),
	},
	-- Dawn fog: pale, colourless, flat light; distance dissolves.
	-- Studio: a dense Atmosphere is lit by the blue sky, so a grey Color renders steel blue;
	-- these peach values come out neutral grey on screen (fog and overcast only; on a clear
	-- day the same shift turns the sky to sunset).
	fog = {
		clock = 8.4,
		brightness = 1.5,
		shadowSoftness = 0.6,
		ambient = c3(96, 94, 90),
		outdoor = c3(130, 128, 122),
		shiftTop = c3(240, 236, 228),
		exposure = 0.6,
		tint = c3(252, 250, 246),
		contrast = 0.04,
		saturation = -0.12,
		bloom = 0.2,
		atmoDensity = 0.4,
		atmoOffset = 0,
		atmoColor = c3(255, 172, 140),
		atmoDecay = c3(255, 172, 140),
		atmoHaze = 0.4,
		atmoGlare = 0,
		cloudCover = 0.75,
		cloudDensity = 0.4,
		cloudColor = c3(232, 230, 224),
		rays = 0,
		fogStart = 300,
		fogEnd = 1500,
		fogColor = c3(206, 202, 192),
	},
	-- The fog has burnt off: a bright, crisp morning sun from the south-east.
	sunrise = {
		clock = 10.1,
		brightness = 3.0,
		shadowSoftness = 0.22,
		ambient = c3(64, 62, 58),
		outdoor = c3(110, 110, 106),
		shiftTop = c3(255, 244, 222),
		exposure = 0.12,
		tint = c3(255, 250, 240),
		contrast = 0.16,
		saturation = 0.08,
		bloom = 0.35,
		atmoDensity = 0.24,
		atmoOffset = 0.2,
		atmoColor = c3(220, 216, 204),
		atmoDecay = c3(178, 172, 158),
		atmoHaze = 0.6,
		atmoGlare = 0.3,
		cloudCover = 0.3,
		cloudDensity = 0.25,
		cloudColor = c3(252, 250, 244),
		rays = 0.06,
		fogStart = 1600,
		fogEnd = 4200,
		fogColor = c3(214, 210, 198),
	},
	-- Rain and sodden ground: low grey cloud, no hard shadows, cooler and less saturated.
	overcast = {
		clock = 14.2,
		brightness = 1.6,
		shadowSoftness = 0.75,
		ambient = c3(84, 84, 82),
		outdoor = c3(124, 124, 120),
		shiftTop = c3(226, 228, 228),
		exposure = 0.15,
		tint = c3(250, 250, 248),
		contrast = 0.1,
		saturation = -0.1,
		bloom = 0.15,
		atmoDensity = 0.3,
		atmoOffset = 0.1,
		atmoColor = c3(255, 176, 146),
		atmoDecay = c3(240, 166, 138),
		atmoHaze = 1.2,
		atmoGlare = 0,
		cloudCover = 0.88,
		cloudDensity = 0.6,
		cloudColor = c3(184, 184, 182),
		rays = 0,
		fogStart = 700,
		fogEnd = 2600,
		fogColor = c3(178, 178, 174),
	},
}

local currentQuality = 2
local currentWeather: string? = nil
local currentGrade = "afternoon"
local fogLifted = false -- the battle opened in fog: the clear light after it is morning, not afternoon

local atmosphere: Atmosphere? = nil
local groundFog: Folder? = nil
local tweens: { Tween } = {}
local heightConn: RBXScriptConnection? = nil
local cc: ColorCorrectionEffect? = nil
local bloom: BloomEffect? = nil
local rays: SunRaysEffect? = nil
local clouds: Clouds? = nil

local function gradeFor(weather: string?): string
	if weather == "fog" then
		return "fog"
	elseif weather == "rain" or weather == "mud" or weather == "snow" then
		return "overcast"
	elseif fogLifted then
		return "sunrise"
	end
	return "afternoon"
end

-- Applies grade `name`, tweened over `seconds` (0 = at once). A newer tween on the same
-- properties replaces an older one.
local FOG_RATE = 0.6 -- puffs per second per anchor: ~4 anchors x 0.6/s x 20 s = under 50 live

local function setFogRate(folder: Folder, rate: number, seconds: number)
	for _, pe in folder:GetDescendants() do
		if pe:IsA("ParticleEmitter") then
			if seconds <= 0 then
				(pe :: ParticleEmitter).Rate = rate
			else
				local t = TweenService:Create(pe, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Rate = rate })
				t:Play()
				table.insert(tweens, t)
			end
		end
	end
end

local function setGrade(name: string, seconds: number)
	currentGrade = name
	local g = GRADES[name]
	local L = LightingService
	for _, t in tweens do
		t:Cancel()
	end
	table.clear(tweens)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local function to(inst: Instance?, props: { [string]: any })
		if not inst then
			return
		end
		if seconds <= 0 then
			for k, v in props do
				(inst :: any)[k] = v
			end
		else
			local t = TweenService:Create(inst, info, props)
			t:Play()
			table.insert(tweens, t)
		end
	end
	to(L, {
		ClockTime = g.clock,
		Brightness = g.brightness,
		ShadowSoftness = g.shadowSoftness,
		Ambient = g.ambient,
		OutdoorAmbient = g.outdoor,
		ColorShift_Top = g.shiftTop,
		ExposureCompensation = g.exposure,
		FogStart = g.fogStart,
		FogEnd = g.fogEnd,
		FogColor = g.fogColor,
	})
	to(cc, { TintColor = g.tint, Contrast = g.contrast, Saturation = g.saturation })
	to(bloom, { Intensity = g.bloom })
	to(rays, { Intensity = g.rays })
	to(atmosphere, {
		Density = g.atmoDensity,
		Offset = g.atmoOffset,
		Color = g.atmoColor,
		Decay = g.atmoDecay,
		Haze = g.atmoHaze,
		Glare = g.atmoGlare,
	})
	to(clouds, { Cover = g.cloudCover, Density = g.cloudDensity, Color = g.cloudColor })
	-- valley mist emitters run only under the fog grade; their rate tweens to 0 with the lift
	-- and the puffs already out fade over their own lifetime
	if groundFog then
		setFogRate(groundFog, if name == "fog" then FOG_RATE else 0, seconds)
	end
end

-- Props hands over the folder of valley-mist anchors (each with a ParticleEmitter) for the map.
function Lighting.setGroundFog(folder: Folder?)
	groundFog = folder
	if folder then
		setFogRate(folder, if currentGrade == "fog" then FOG_RATE else 0, 0)
	end
end

function Lighting.apply(quality: number)
	currentQuality = quality
	clearOwned()
	atmosphere, cc, bloom, rays, clouds = nil, nil, nil, nil, nil
	setTechnology()
	local L = LightingService
	-- Studio puts its own ColorGrading (Retro tonemapper) into Lighting; it turned the field teal
	-- (round 18). The grade here is ours alone.
	for _, c in L:GetChildren() do
		if c.ClassName == "ColorGradingEffect" then
			(c :: any).Enabled = false
		end
	end
	L.GeographicLatitude = 50
	L.GlobalShadows = true
	-- low environment light keeps the shaded side of a ridge dark, as in the reference
	L.EnvironmentDiffuseScale = 0.2
	L.EnvironmentSpecularScale = 0.08
	L.ColorShift_Bottom = c3(0, 0, 0)

	local sky = own(Instance.new("Sky") :: Sky, L)
	sky.CelestialBodiesShown = true
	sky.StarCount = 0
	sky.SunAngularSize = 12

	local colour = own(Instance.new("ColorCorrectionEffect") :: ColorCorrectionEffect, L)
	colour.Brightness = 0.01
	cc = colour

	local b = own(Instance.new("BloomEffect") :: BloomEffect, L)
	b.Size = 24
	b.Threshold = 1.5
	bloom = b

	if quality >= 2 then
		atmosphere = own(Instance.new("Atmosphere") :: Atmosphere, L)
		local r = own(Instance.new("SunRaysEffect") :: SunRaysEffect, L)
		r.Spread = 0.45
		rays = r
		clouds = own(Instance.new("Clouds") :: Clouds, workspace.Terrain)
	end
	setGrade(gradeFor(currentWeather), 0)
	-- Fog thins as the camera climbs (the intro sweep starts at 700; the default view is ~420):
	-- from high up a full-density Atmosphere shows nothing but fog, and plates must stay legible.
	if heightConn then
		heightConn:Disconnect()
	end
	local acc = 0
	heightConn = RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local atmo = atmosphere
		local cam = workspace.CurrentCamera
		if not atmo or not cam then
			return
		end
		for _, t in tweens do
			if t.PlaybackState == Enum.PlaybackState.Playing then
				return
			end
		end
		local g = GRADES[currentGrade]
		local factor = if currentGrade == "fog" then math.clamp(1 - (cam.CFrame.Position.Y - 330) / 900, 0.4, 1) else 1
		atmo.Density = g.atmoDensity * factor
	end)
end

-- A new battle (or map) opens in its scenario weather with nothing carried over from the last
-- one: a clear battle after a foggy one is an afternoon, not a fog lifting.
function Lighting.beginBattle()
	fogLifted = false
	local name = gradeFor(currentWeather)
	if name ~= currentGrade then
		setGrade(name, 0)
	end
end

function Lighting.setMap(_mapId: string?)
	Lighting.beginBattle()
end

-- Scenario weather (`fog`, `rain`, `mud`, ... or nil for clear). Fog arrives at once; when it
-- lifts the sun comes through over twenty seconds; other changes take a few seconds.
function Lighting.setWeather(weather: string?)
	if weather == currentWeather then
		return
	end
	local was = currentWeather
	currentWeather = weather
	if was == "fog" and weather ~= "fog" then
		fogLifted = true
	elseif weather ~= nil and weather ~= "clear" then
		fogLifted = false
	end
	local name = gradeFor(weather)
	if name == currentGrade then
		return
	end
	setGrade(name, if name == "fog" then 0 elseif was == "fog" then 20 else 3)
end

function Lighting.quality(): number
	return currentQuality
end

function Lighting.destroy()
	clearOwned()
	if heightConn then
		heightConn:Disconnect()
		heightConn = nil
	end
end

return Lighting
