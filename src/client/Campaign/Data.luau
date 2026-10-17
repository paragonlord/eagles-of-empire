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

local cache: { [string]: Color3 } = {}

function Data.colour(nation: string?): Color3
	local id = nation or ""
	local c = cache[id]
	if c then
		return c
	end
	local n = Data.Nations[id]
	local key = if n and type(n.colour) == "string" then n.colour else string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2)
	c = Factions.colour(id, key)
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
