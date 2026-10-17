--!strict
-- Grand-campaign static data (shared EuropeData) and the nation look-ups the board and panels
-- share: colour, name, flag.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Factions = require(script.Parent.Parent.Factions)

local Europe = require(Shared.EuropeData)

local Data = {}

Data.Europe = Europe
Data.Nations = Europe.Nations :: { [string]: any }
Data.Provinces = Europe.Provinces :: { any }
Data.byId = {} :: { [string]: any }
for _, p in Data.Provinces do
	Data.byId[p.id] = p
end

-- Palette keys the shared Config does not carry (minor powers).
local EXTRA: { [string]: { number } } = {
	Spain = { 196, 152, 44 },
	Portugal = { 52, 118, 92 },
	Naples = { 214, 196, 130 },
	Ottoman = { 118, 146, 84 },
	Sweden = { 64, 108, 172 },
	Denmark = { 186, 86, 76 },
	Poland = { 196, 74, 98 },
	Warsaw = { 196, 74, 98 },
	Switzerland = { 176, 64, 60 },
	Italy = { 84, 140, 110 },
	Sardinia = { 150, 120, 170 },
	Westphalia = { 140, 116, 168 },
	Rhine = { 132, 110, 158 },
	Wurttemberg = { 168, 132, 64 },
	Hanover = { 200, 170, 90 },
}

local cache: { [string]: Color3 } = {}

function Data.colour(nation: string?): Color3
	local id = nation or ""
	local c = cache[id]
	if c then
		return c
	end
	local n = Data.Nations[id]
	local key = if n and type(n.colour) == "string" then n.colour else string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2)
	local t = EXTRA[key]
	c = if t then Color3.fromRGB(t[1], t[2], t[3]) else Factions.colour(id, key)
	cache[id] = c
	return c
end

function Data.name(nation: string?): string
	local n = Data.Nations[nation or ""]
	return if n then n.name else Factions.name(nation)
end

local OWN_FLAGS = { france = true, prussia = true, russia = true, austria = true, britain = true }

-- Factions has flags for the majors; everyone else gets their colour with a white diagonal.
function Data.hasFlag(nation: string?): boolean
	return OWN_FLAGS[nation or ""] == true
end

function Data.flag(nation: string?): Factions.Flag
	if Data.hasFlag(nation) then
		return Factions.flag(nation)
	end
	return { field = Data.colour(nation), mark = "diagonal", markColour = Color3.fromRGB(242, 240, 232) }
end

return Data
