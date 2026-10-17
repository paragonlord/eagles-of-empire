--!strict
-- Faction look-ups shared by the HUD, figures, props and minimap: colours (palette key from a
-- unit `colour` override, else the faction), display names and marker-flag designs.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)

local Factions = {}

local P = Config.Visual.Palette :: { [string]: { number } }

-- Fallbacks for palette keys the shared Config may not define yet.
local DEFAULTS: { [string]: { number } } = {
	France = { 44, 79, 166 },
	Prussia = { 58, 61, 66 },
	Saxony = { 108, 113, 128 },
	Russia = { 46, 98, 60 },
	Austria = { 232, 228, 220 },
	Britain = { 170, 40, 44 },
	Bavaria = { 92, 150, 200 },
	Netherlands = { 214, 120, 40 },
}

local NAMES: { [string]: string } = {
	france = "France",
	prussia = "Prussia",
	russia = "Russia",
	austria = "Austria",
	britain = "Britain",
	saxony = "Saxony",
	bavaria = "Bavaria",
	netherlands = "Netherlands",
}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function keyFor(faction: string?): string
	local f = faction or ""
	return string.upper(string.sub(f, 1, 1)) .. string.sub(f, 2)
end

-- Palette colour for a palette key ("Saxony") or a faction id ("prussia").
function Factions.colour(faction: string?, override: string?): Color3
	local key = override or keyFor(faction)
	local t = P[key] or DEFAULTS[key]
	if t then
		return rgb(t)
	end
	return Color3.fromRGB(120, 108, 96)
end

function Factions.name(faction: string?): string
	return NAMES[faction or ""] or tostring(faction or "—")
end

export type Flag = {
	bands: { Color3 }?, -- vertical bands, left to right
	stripes: { Color3 }?, -- horizontal bands, top to bottom (drawn over field/mark when supported)
	field: Color3?, -- plain field when there are no bands
	mark: string?, -- "diamond" | "x" | "plus" | "double" | "diagonal"
	markColour: Color3,
	cross: Color3?, -- an upright cross over the mark (Union flag: red cross over a white saltire)
}

local WHITE = Color3.fromRGB(242, 240, 232)
local BLACK = Color3.fromRGB(28, 26, 24)
local GOLD = Color3.fromRGB(205, 168, 62)

local FLAGS: { [string]: Flag } = {
	france = { bands = { Color3.fromRGB(30, 62, 150), Color3.fromRGB(240, 238, 230), Color3.fromRGB(190, 42, 50) }, mark = "diamond", markColour = GOLD },
	-- black-white-black; renderers without `stripes` fall back to white with two black bars
	prussia = { stripes = { BLACK, WHITE, BLACK }, field = WHITE, mark = "double", markColour = BLACK },
	russia = { field = Color3.fromRGB(40, 96, 56), mark = "diamond", markColour = GOLD },
	austria = { field = WHITE, mark = "double", markColour = BLACK },
	-- Union flag approximation: blue field, white saltire, red upright cross
	britain = { field = Color3.fromRGB(28, 44, 110), mark = "x", markColour = WHITE, cross = Color3.fromRGB(190, 34, 44) },
}

function Factions.flag(faction: string?): Flag
	local f = FLAGS[faction or ""]
	if f then
		return f
	end
	return { field = Factions.colour(faction), mark = "diagonal", markColour = WHITE }
end

-- How much the far-LOD slab is darkened (Prussian blocks read near-black in the reference).
function Factions.slabDarken(faction: string?): number
	return if faction == "prussia" then 0.45 else 0.12
end

return Factions
