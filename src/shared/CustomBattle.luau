--!strict
-- Custom battles (docs/battles.md "Custom battle"): two great powers, a field and a budget. The
-- player buys regiments from the campaign's unit table (EuropeData.UnitClasses: cost, strength,
-- battle type; national units only for their nations); the AI buys a mixed army for the same
-- budget. Both deploy in rows in their zones, an HQ behind each line.

local EuropeData = require(script.Parent.EuropeData)
local MapGen = require(script.Parent.MapGen)
local Scenarios = require(script.Parent.Scenarios)

local CustomBattle = {}

export type Spec = { player: string, enemy: string, map: string, budget: number, units: { [string]: number } }

CustomBattle.Nations = EuropeData.Majors
CustomBattle.Maps = { "jena", "auerstedt", "austerlitz", "waterloo", "province:lombardy", "province:saxony", "province:belgium", "province:smolensk" }
CustomBattle.Budgets = { 5000, 8000, 12000 }
CustomBattle.MAX_UNITS = 20 -- a side, as a campaign army
CustomBattle.TIME_LIMIT = 1500

function CustomBattle.cost(units: { [string]: number }): number
	local c = 0
	for t, n in units do
		local cls = EuropeData.UnitClasses[t]
		c += if cls then cls.cost * n else 0
	end
	return c
end

-- The AI's purchase: a third of the budget on line infantry, then light infantry, cavalry, guns
-- and the nation's elite in turn, each while it fits.
local AI_ORDER = { "line", "line", "artillery", "cavalry", "line", "light", "heavy", "line", "artillery", "guard", "cavalry", "line", "light" }
function CustomBattle.enemyArmy(nation: string, budget: number): { [string]: number }
	local out: { [string]: number } = {}
	local left, count = budget, 0
	local bought = true
	while bought and count < CustomBattle.MAX_UNITS do
		bought = false
		for _, t in AI_ORDER do
			local cls = EuropeData.UnitClasses[t]
			if count < CustomBattle.MAX_UNITS and EuropeData.inRoster(t, nation) and cls.cost <= left then
				out[t] = (out[t] or 0) + 1
				left -= cls.cost
				count += 1
				bought = true
			end
		end
	end
	return out
end

-- Which deploy zone each side takes: a nation whose id names a zone on the field keeps it.
local function zones(map: MapGen.MapData, player: string, enemy: string): (string, string)
	local keys: { string } = {}
	for k in map.deployZones do
		table.insert(keys, k)
	end
	table.sort(keys)
	local function other(k: string): string
		return if keys[1] == k then keys[2] else keys[1]
	end
	if map.deployZones[player] then
		return player, other(player)
	elseif map.deployZones[enemy] then
		return other(enemy), enemy
	end
	return keys[1], keys[2]
end

local function place(map: MapGen.MapData, key: string, otherKey: string, nation: string, units: { [string]: number }, out: { Scenarios.UnitDef })
	local zone, ez = map.deployZones[key], map.deployZones[otherKey]
	local cx, cz = (zone.x0 + zone.x1) / 2, (zone.z0 + zone.z1) / 2
	local dx, dz = (ez.x0 + ez.x1) / 2 - cx, (ez.z0 + ez.z1) / 2 - cz
	local len = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
	dx, dz = dx / len, dz / len
	local px, pz = -dz, dx
	local heading = math.atan2(dz, dx)
	local function clampTo(x: number, z: number): (number, number)
		return math.clamp(x, zone.x0 + 20, zone.x1 - 20), math.clamp(z, zone.z0 + 20, zone.z1 - 20)
	end
	local list: { string } = {}
	for _, t in EuropeData.UnitTypeOrder do
		for _ = 1, units[t] or 0 do
			table.insert(list, t)
		end
	end
	local perRow = 8
	local rows = math.max(1, math.ceil(#list / perRow))
	local nation_ = EuropeData.Nations[nation]
	local counts: { [string]: number } = {}
	for i, t in list do
		local cls = EuropeData.UnitClasses[t]
		counts[t] = (counts[t] or 0) + 1
		local row = (i - 1) // perRow
		local inRow = math.min(perRow, #list - row * perRow)
		local along, back = ((i - 1) % perRow - (inRow - 1) / 2) * 90, (row - (rows - 1) / 2) * 70
		local x, z = clampTo(cx + px * along - dx * back, cz + pz * along - dz * back)
		table.insert(out, {
			name = EuropeData.unitName(nation, t, counts[t]),
			class = cls.class,
			type = cls.sim,
			corps = nation_.adjective .. " army",
			strength = cls.strength,
			experience = if t == "guard" or t == "oldguard" then 3 else 1,
			pos = { x = x, z = z },
			heading = heading,
			faction = key,
			colour = nation_.colour,
		})
	end
	local hx, hz = clampTo(cx - dx * (rows * 35 + 60), cz - dz * (rows * 35 + 60))
	local hq: Scenarios.UnitDef = { name = nation_.adjective .. " HQ", class = "hq", corps = "HQ", strength = 120, experience = 1, pos = { x = hx, z = hz }, heading = heading, faction = key, colour = nation_.colour, commander = true }
	table.insert(out, hq)
end

-- A scenario from the player's choices, or nil and a reason.
function CustomBattle.build(spec: any): (Scenarios.Scenario?, string?)
	if type(spec) ~= "table" or type(spec.units) ~= "table" then
		return nil, "badArgs"
	end
	local player, enemy = spec.player, spec.enemy
	if not table.find(CustomBattle.Nations, player) or not table.find(CustomBattle.Nations, enemy) then
		return nil, "badNation"
	end
	if player == enemy then
		return nil, "sameNation"
	end
	if not table.find(CustomBattle.Maps, spec.map) then
		return nil, "badMap"
	end
	if not table.find(CustomBattle.Budgets, spec.budget) then
		return nil, "badBudget"
	end
	local units: { [string]: number } = {}
	local count = 0
	for t, n in spec.units do
		if type(t) ~= "string" or EuropeData.UnitClasses[t] == nil or type(n) ~= "number" or n ~= math.floor(n) or n < 0 then
			return nil, "badArgs"
		end
		if n > 0 and not EuropeData.inRoster(t, player) then
			return nil, "notInRoster"
		end
		units[t] = n
		count += n
	end
	if count == 0 then
		return nil, "noUnits"
	end
	if count > CustomBattle.MAX_UNITS then
		return nil, "tooManyUnits"
	end
	if CustomBattle.cost(units) > spec.budget then
		return nil, "overBudget"
	end
	local map = MapGen.generate(spec.map)
	local pk, ek = zones(map, player, enemy)
	local out: { Scenarios.UnitDef } = {}
	place(map, pk, ek, player, units, out)
	place(map, ek, pk, enemy, CustomBattle.enemyArmy(enemy, spec.budget), out)
	local pn, en = EuropeData.Nations[player].name, EuropeData.Nations[enemy].name
	return {
		id = "custom",
		name = string.format("%s against %s", pn, en),
		map = spec.map,
		briefing = string.format("A battle of your own making: %s against %s, %s gold a side. Take the objectives or break the enemy army.", pn, en, tostring(spec.budget)),
		factions = { player = pk, enemy = ek },
		factionNames = { [pk] = pn, [ek] = en },
		units = out,
		timeLimit = CustomBattle.TIME_LIMIT,
	},
		nil
end

return CustomBattle
