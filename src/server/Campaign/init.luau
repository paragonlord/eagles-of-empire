--!strict
-- Operational campaign (Release B). Pure Luau, deterministic through `state.rng`; no wall clock,
-- no Roblox APIs. The tactical battle is delegated to the Sim through `battleScenario` and the
-- outcome returns through `applyBattleResult` (idempotent by battle id).
--
-- Turn: player phase (commands) -> endTurn: enemy AI acts with the same rules -> contacts become
-- battle contexts (one per contested region, regions in ascending id order, so an army is in at
-- most one battle and never in two regions) -> uncontested enemy regions are captured -> economy
-- for both factions (income, manpower, upkeep, recruitment completion) -> next turn. While
-- battles are pending the phase is "battle"; apply or auto-resolve every pending battle to get
-- back to "player".
--
-- Supply: upkeep paid in full raises faction supply by SupplyRecovery (cap 100); a shortfall
-- empties the treasury and lowers supply by SupplyShortage; at supply 0 every unit loses
-- AttritionFraction of its strength per turn. Ammunition is not tracked between battles: every
-- battle scenario starts with full ammunition (Formation.fromDef).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local RNG = require(Shared.RNG)
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)
local Types = require(Shared.Types)
local CampaignData = require(Shared.CampaignData)

export type Unit = { key: string, type: string, name: string, strength: number, maxStrength: number, experience: number }
export type Army = { id: number, faction: string, name: string, regionId: string, units: { Unit }, movesLeft: number, supplied: boolean }
export type Recruit = { faction: string, regionId: string, unitType: string, turnsLeft: number, name: string }
export type Battle = { battleId: string, regionId: string, attacker: string, defender: string, turn: number }
export type Applied = { battleId: string, winner: string, outcome: string, turn: number }
export type FactionState = { treasury: number, manpower: number, supply: number }
export type Victory = { outcome: "victory" | "defeat", reason: string }
export type Survivor = { strength: number, experience: number, destroyed: boolean? }
type Placed = { u: Unit, a: Army }

export type State = {
	campaignId: string,
	seed: number,
	restarts: number,
	revision: number,
	rng: RNG.RNG,
	turn: number,
	phase: "player" | "battle" | "ended",
	owners: { [string]: string },
	armies: { Army }, -- ascending id
	factions: { [string]: FactionState },
	recruitment: { Recruit },
	nextArmyId: number,
	nextUnitId: number,
	log: { string },
	pendingBattles: { Battle },
	appliedBattles: { Applied },
	victory: Victory?,
}

export type Command = { kind: string, armyId: number?, regionId: string?, unitType: string?, army: number? }

local Campaign = {}

local PLAYER = CampaignData.Factions.player
local ENEMY = CampaignData.Factions.enemy
local FACTIONS = { PLAYER, ENEMY }
local ECON = CampaignData.Economy
local LOG_MAX = 40
local APPLIED_MAX = 64
local PHASES = { player = true, battle = true, ended = true }

-- Helpers ------------------------------------------------------------------------------------

local function copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function region(id: string): CampaignData.Region
	return CampaignData.region(id) or error("unknown region " .. tostring(id))
end

local function sortedRegionIds(): { string }
	local ids = {}
	for _, reg in CampaignData.Regions do
		ids[#ids + 1] = reg.id
	end
	table.sort(ids)
	return ids
end

local function adjacent(a: string, b: string): boolean
	return table.find(region(a).adjacent, b) ~= nil
end

local function other(faction: string): string
	return if faction == PLAYER then ENEMY else PLAYER
end

local function log(state: State, text: string)
	state.log[#state.log + 1] = string.format("T%d: %s", state.turn, text)
	while #state.log > LOG_MAX do
		table.remove(state.log, 1)
	end
end

local function armyById(state: State, id: number): Army?
	for _, a in state.armies do
		if a.id == id then
			return a
		end
	end
	return nil
end

local function armiesIn(state: State, regionId: string, faction: string?): { Army }
	local out = {}
	for _, a in state.armies do
		if a.regionId == regionId and (faction == nil or a.faction == faction) then
			out[#out + 1] = a
		end
	end
	return out
end

local function armiesOf(state: State, faction: string): { Army }
	local out = {}
	for _, a in state.armies do
		if a.faction == faction then
			out[#out + 1] = a
		end
	end
	return out
end

local function removeArmy(state: State, id: number)
	for i, a in state.armies do
		if a.id == id then
			table.remove(state.armies, i)
			return
		end
	end
end

-- Fighting strength (HQ staff excluded), experience weighted.
local function armyStrength(a: Army): number
	local s = 0
	for _, u in a.units do
		if CampaignData.UnitTypes[u.type].class ~= "hq" then
			s += u.strength * (1 + 0.1 * u.experience)
		end
	end
	return s
end

local function strengthIn(state: State, regionId: string, faction: string): number
	local s = 0
	for _, a in armiesIn(state, regionId, faction) do
		s += armyStrength(a)
	end
	return s
end

local function factionStrength(state: State, faction: string): number
	local s = 0
	for _, a in armiesOf(state, faction) do
		for _, u in a.units do
			s += u.strength
		end
	end
	return s
end

local function newArmy(state: State, faction: string, name: string, regionId: string): Army
	local a: Army = { id = state.nextArmyId, faction = faction, name = name, regionId = regionId, units = {}, movesLeft = 0, supplied = true }
	state.nextArmyId += 1
	state.armies[#state.armies + 1] = a
	return a
end

local function newUnit(state: State, unitType: string, name: string, experience: number): Unit
	local def = CampaignData.UnitTypes[unitType]
	local u: Unit = { key = "u" .. state.nextUnitId, type = unitType, name = name, strength = def.strength, maxStrength = def.strength, experience = experience }
	state.nextUnitId += 1
	return u
end

local function queueCount(state: State, faction: string): number
	local n = 0
	for _, q in state.recruitment do
		if q.faction == faction then
			n += 1
		end
	end
	return n
end

local function isApplied(state: State, battleId: string): boolean
	for _, b in state.appliedBattles do
		if b.battleId == battleId then
			return true
		end
	end
	return false
end

local function pendingBattle(state: State, battleId: string): (Battle?, number)
	for i, b in state.pendingBattles do
		if b.battleId == battleId then
			return b, i
		end
	end
	return nil, 0
end

-- Construction ---------------------------------------------------------------------------------

local function build(seed: number, restarts: number): State
	seed = math.floor(seed)
	local state: State = {
		campaignId = string.format("%d-%d", seed, restarts),
		seed = seed,
		restarts = restarts,
		revision = 0,
		rng = RNG.new(seed + restarts * 7919),
		turn = 1,
		phase = "player",
		owners = {},
		armies = {},
		factions = {},
		recruitment = {},
		nextArmyId = 1,
		nextUnitId = 1,
		log = {},
		pendingBattles = {},
		appliedBattles = {},
		victory = nil,
	}
	for _, reg in CampaignData.Regions do
		state.owners[reg.id] = reg.owner
	end
	for _, f in FACTIONS do
		state.factions[f] = { treasury = ECON.StartTreasury[f], manpower = ECON.StartManpower[f], supply = 100 }
	end
	for _, def in CampaignData.StartArmies do
		local a = newArmy(state, def.faction, def.name, def.regionId)
		a.movesLeft = 1
		for _, su in def.units do
			a.units[#a.units + 1] = newUnit(state, su.type, su.name, su.experience)
		end
	end
	log(state, "Campaign opened. Hold Jena, Weimar and Naumburg by turn " .. CampaignData.Victory.TurnLimit .. ".")
	return state
end

function Campaign.new(seed: number): State
	return build(seed, 0)
end

-- Victory ----------------------------------------------------------------------------------------

function Campaign.victory(state: State): Victory?
	if state.victory then
		return state.victory
	end
	local V = CampaignData.Victory
	local held = true
	for _, id in V.Objectives do
		if state.owners[id] ~= PLAYER then
			held = false
		end
	end
	local strength = factionStrength(state, PLAYER)
	if held and strength >= V.MinArmyStrength then
		return { outcome = "victory", reason = "Jena, Weimar and Naumburg are in French hands and the army stands." }
	end
	local owned = 0
	for _, f in state.owners do
		if f == PLAYER then
			owned += 1
		end
	end
	if owned == 0 then
		return { outcome = "defeat", reason = "France holds no region in Thuringia." }
	end
	local cheapest = math.huge
	for _, t in CampaignData.UnitTypes do
		if t.recruitable then
			cheapest = math.min(cheapest, t.cost)
		end
	end
	if #armiesOf(state, PLAYER) == 0 and queueCount(state, PLAYER) == 0 and state.factions[PLAYER].treasury < cheapest then
		return { outcome = "defeat", reason = "The French army is destroyed and the treasury cannot raise another." }
	end
	if #state.pendingBattles == 0 and state.turn > V.TurnLimit then
		return { outcome = "defeat", reason = "Turn " .. V.TurnLimit .. " passed without securing the objectives." }
	end
	return nil
end

local function checkVictory(state: State)
	if state.victory then
		return
	end
	local v = Campaign.victory(state)
	if v then
		state.victory = v
		state.phase = "ended"
		log(state, (if v.outcome == "victory" then "VICTORY: " else "DEFEAT: ") .. v.reason)
	end
end

-- Economy ----------------------------------------------------------------------------------------

-- Restores strength up to maxStrength; costs ReplenishCostPerMan treasury and one manpower per man.
local function replenish(state: State, army: Army): number
	local fs = state.factions[army.faction]
	local restored = 0
	for _, u in army.units do
		local need = u.maxStrength - u.strength
		if need > 0 then
			local n = math.min(need, math.floor(fs.treasury / ECON.ReplenishCostPerMan), fs.manpower)
			if n > 0 then
				u.strength += n
				fs.treasury -= n * ECON.ReplenishCostPerMan
				fs.manpower -= n
				restored += n
			end
		end
	end
	return restored
end

local function deliverRecruit(state: State, q: Recruit)
	if state.owners[q.regionId] ~= q.faction then
		log(state, string.format("%s raised at %s dispersed: the town was lost.", q.name, region(q.regionId).name))
		return
	end
	local target: Army? = nil
	for _, a in armiesIn(state, q.regionId, q.faction) do
		if #a.units < ECON.MaxUnitsPerArmy then
			target = a
			break
		end
	end
	if not target then
		if #armiesOf(state, q.faction) >= ECON.MaxArmies then
			log(state, q.name .. " could not be formed: too many armies.")
			return
		end
		target = newArmy(state, q.faction, "Garrison of " .. region(q.regionId).name, q.regionId)
	end
	local t = target :: Army
	t.units[#t.units + 1] = newUnit(state, q.unitType, q.name, 0)
	log(state, string.format("%s joined %s at %s.", q.name, t.name, region(q.regionId).name))
end

local function economy(state: State, faction: string)
	local fs = state.factions[faction]
	local income, manpower = 0, 0
	for _, reg in CampaignData.Regions do
		if state.owners[reg.id] == faction then
			income += reg.income
			manpower += reg.manpower
		end
	end
	fs.treasury = math.min(ECON.MaxTreasury, fs.treasury + income)
	fs.manpower = math.min(ECON.MaxManpower, fs.manpower + manpower)
	local upkeep = 0
	for _, a in armiesOf(state, faction) do
		for _, u in a.units do
			upkeep += CampaignData.UnitTypes[u.type].upkeep
		end
	end
	if fs.treasury >= upkeep then
		fs.treasury -= upkeep
		fs.supply = math.min(100, fs.supply + ECON.SupplyRecovery)
	else
		fs.treasury = 0
		fs.supply = math.max(0, fs.supply - ECON.SupplyShortage)
		log(state, string.format("%s cannot pay upkeep (%d short); supply falls to %d.", CampaignData.FactionNames[faction], upkeep - fs.treasury, fs.supply))
		if fs.supply == 0 then
			for _, a in armiesOf(state, faction) do
				for i = #a.units, 1, -1 do
					local u = a.units[i]
					u.strength = math.floor(u.strength * (1 - ECON.AttritionFraction))
					if u.strength <= 0 then
						table.remove(a.units, i)
					end
				end
			end
		end
	end
	for _, a in armiesOf(state, faction) do
		a.supplied = fs.supply > 0
	end
	for i = #state.recruitment, 1, -1 do
		local q = state.recruitment[i]
		if q.faction == faction then
			q.turnsLeft -= 1
			if q.turnsLeft <= 0 then
				table.remove(state.recruitment, i)
				deliverRecruit(state, q)
			end
		end
	end
	-- armies emptied by attrition disappear
	for i = #state.armies, 1, -1 do
		if #state.armies[i].units == 0 then
			table.remove(state.armies, i)
		end
	end
end

-- Rules shared by player and AI ------------------------------------------------------------

local function tryMove(state: State, faction: string, armyId: number, regionId: string): (boolean, string?)
	local a = armyById(state, armyId)
	if not a or a.faction ~= faction then
		return false, "notYourArmy"
	end
	if a.movesLeft <= 0 then
		return false, "alreadyMoved"
	end
	if CampaignData.region(regionId) == nil or not adjacent(a.regionId, regionId) then
		return false, "notAdjacent"
	end
	a.regionId = regionId
	a.movesLeft = 0
	return true, nil
end

local function tryRecruit(state: State, faction: string, regionId: string, unitType: string): (boolean, string?)
	local t = CampaignData.UnitTypes[unitType]
	if not t or not t.recruitable then
		return false, "unknownUnit"
	end
	if state.owners[regionId] ~= faction then
		return false, "notYourRegion"
	end
	if queueCount(state, faction) >= ECON.MaxQueue then
		return false, "queueFull"
	end
	local fs = state.factions[faction]
	if fs.treasury < t.cost then
		return false, "insufficientFunds"
	end
	fs.treasury -= t.cost
	local n = 0
	for _, a in armiesOf(state, faction) do
		n += #a.units
	end
	local name = string.format("%s %d", t.name, n + queueCount(state, faction) + 1)
	state.recruitment[#state.recruitment + 1] = { faction = faction, regionId = regionId, unitType = unitType, turnsLeft = t.turns, name = name }
	return true, nil
end

-- Enemy AI ---------------------------------------------------------------------------------------

local function aiTurn(state: State)
	local fs = state.factions[ENEMY]
	local capital = CampaignData.Capitals[ENEMY]
	local mine = armiesOf(state, ENEMY)
	local homeGuard = if #mine > 0 then mine[1].id else nil
	for _, a in mine do
		if state.owners[a.regionId] == ENEMY and fs.treasury > ECON.AIReserve then
			replenish(state, a)
		end
	end
	for _, a in mine do
		if a.movesLeft > 0 then
			local here = region(a.regionId)
			local myStr = armyStrength(a)
			local threat = 0
			for _, adj in here.adjacent do
				threat = math.max(threat, strengthIn(state, adj, PLAYER))
			end
			local hold = (if here.isCity then 20 else 0) + (if threat > 0 and here.isCity then 30 else 0) + (if a.id == homeGuard then 25 else 0)
			local bestId: string? = nil
			local best = hold + state.rng:float() * 10
			for _, adj in here.adjacent do
				local score: number
				local enemyStr = strengthIn(state, adj, PLAYER)
				local adjReg = region(adj)
				if state.owners[adj] == PLAYER then
					if enemyStr == 0 then
						score = 40 + (if adjReg.isCity then 15 else 0)
					elseif myStr > enemyStr * 1.2 then
						score = 50 + (if adjReg.isCity then 10 else 0) - enemyStr / 100
					else
						score = -100
					end
				elseif adjReg.isCity and strengthIn(state, adj, ENEMY) == 0 then
					local threatened = false
					for _, n in adjReg.adjacent do
						threatened = threatened or strengthIn(state, n, PLAYER) > 0
					end
					score = if threatened then 35 else -10
				else
					score = -10
				end
				if a.id == homeGuard and adj ~= capital and not adjacent(adj, capital) then
					score -= 30
				end
				score += state.rng:float() * 10
				if score > best then
					best, bestId = score, adj
				end
			end
			if bestId then
				tryMove(state, ENEMY, a.id, bestId)
				log(state, string.format("%s marches to %s.", a.name, region(bestId).name))
			end
		end
	end
	-- recruit with spare treasury, preferring the capital, then any city, then any owned region
	local recruitAt: string? = nil
	for _, id in sortedRegionIds() do
		if state.owners[id] == ENEMY then
			if id == capital then
				recruitAt = id
				break
			elseif recruitAt == nil or (region(id).isCity and not region(recruitAt).isCity) then
				recruitAt = id
			end
		end
	end
	while recruitAt ~= nil and fs.treasury - ECON.AIReserve >= CampaignData.UnitTypes.line.cost and queueCount(state, ENEMY) < ECON.MaxQueue do
		local r = state.rng:float()
		local t = if r < 0.6 then "line" elseif r < 0.8 then "cavalry" else "artillery"
		if fs.treasury - ECON.AIReserve < CampaignData.UnitTypes[t].cost then
			t = "line"
		end
		if not tryRecruit(state, ENEMY, recruitAt, t) then
			break
		end
	end
end

-- Contacts ---------------------------------------------------------------------------------------

local function resolveContacts(state: State): { Battle }
	local battles = {}
	for _, id in sortedRegionIds() do
		local p = #armiesIn(state, id, PLAYER)
		local e = #armiesIn(state, id, ENEMY)
		local owner = state.owners[id]
		if p > 0 and e > 0 then
			local attacker = if owner == PLAYER then ENEMY else PLAYER
			local b: Battle = { battleId = string.format("%s-t%d-%s", state.campaignId, state.turn, id), regionId = id, attacker = attacker, defender = other(attacker), turn = state.turn }
			state.pendingBattles[#state.pendingBattles + 1] = b
			battles[#battles + 1] = b
			log(state, string.format("Battle at %s: %s attacks.", region(id).name, CampaignData.FactionNames[attacker]))
		elseif p > 0 and owner ~= PLAYER then
			state.owners[id] = PLAYER
			log(state, region(id).name .. " occupied by France.")
		elseif e > 0 and owner ~= ENEMY then
			state.owners[id] = ENEMY
			log(state, region(id).name .. " occupied by Prussia.")
		end
	end
	return battles
end

-- Public turn API ------------------------------------------------------------------------------

function Campaign.endTurn(state: State): (State, { Battle })
	if state.phase ~= "player" then
		return state, {}
	end
	aiTurn(state)
	local battles = resolveContacts(state)
	for _, f in FACTIONS do
		economy(state, f)
	end
	state.turn += 1
	for _, a in state.armies do
		a.movesLeft = 1
	end
	state.phase = if #state.pendingBattles > 0 then "battle" else "player"
	checkVictory(state)
	return state, battles
end

function Campaign.command(state: State, cmd: Command): (boolean, string?)
	if cmd.kind == "restart" then
		local fresh = build(state.seed, state.restarts + 1)
		for k in pairs(state :: any) do
			(state :: any)[k] = nil
		end
		for k, v in pairs(fresh :: any) do
			(state :: any)[k] = v
		end
		return true, nil
	end
	if state.phase ~= "player" then
		return false, "wrongPhase"
	end
	if cmd.kind == "move" then
		if type(cmd.armyId) ~= "number" or type(cmd.regionId) ~= "string" then
			return false, "badArgs"
		end
		local ok, why = tryMove(state, PLAYER, cmd.armyId, cmd.regionId)
		if ok then
			local a = armyById(state, cmd.armyId) :: Army
			log(state, string.format("%s marches to %s.", a.name, region(cmd.regionId).name))
		end
		return ok, why
	elseif cmd.kind == "recruit" then
		if type(cmd.regionId) ~= "string" or type(cmd.unitType) ~= "string" then
			return false, "badArgs"
		end
		local ok, why = tryRecruit(state, PLAYER, cmd.regionId, cmd.unitType)
		if ok then
			local t = CampaignData.UnitTypes[cmd.unitType]
			log(state, string.format("%s ordered at %s: %d treasury, ready in %d turns.", t.name, region(cmd.regionId).name, t.cost, t.turns))
		end
		return ok, why
	elseif cmd.kind == "replenish" then
		local a = if type(cmd.armyId) == "number" then armyById(state, cmd.armyId) else nil
		if not a or a.faction ~= PLAYER then
			return false, "notYourArmy"
		end
		if state.owners[a.regionId] ~= PLAYER then
			return false, "notYourRegion"
		end
		local n = replenish(state, a)
		if n == 0 then
			return false, "nothingToReplenish"
		end
		log(state, string.format("%s took on %d replacements.", a.name, n))
		return true, nil
	elseif cmd.kind == "endTurn" then
		Campaign.endTurn(state)
		return true, nil
	end
	return false, "unknownCommand"
end

-- Battle hand-off --------------------------------------------------------------------------------

local mapCache: { [string]: MapGen.MapData } = {}
local function mapFor(id: string): MapGen.MapData
	local m = mapCache[id]
	if not m then
		m = MapGen.generate(id)
		mapCache[id] = m
	end
	return m
end

local function clampTo(z: MapGen.Rect, x: number, y: number): (number, number)
	local m = 30
	return math.clamp(x, z.x0 + m, z.x1 - m), math.clamp(y, z.z0 + m, z.z1 - m)
end

function Campaign.battleScenario(state: State, battleId: string): Scenarios.Scenario?
	local b = pendingBattle(state, battleId)
	if not b then
		return nil
	end
	local reg = region(b.regionId)
	local map = mapFor(reg.terrain)
	local units: { Scenarios.UnitDef } = {}
	for _, faction in FACTIONS do
		local zone = map.deployZones[faction]
		local ez = map.deployZones[other(faction)]
		local cx, cz = (zone.x0 + zone.x1) / 2, (zone.z0 + zone.z1) / 2
		local dx, dz = (ez.x0 + ez.x1) / 2 - cx, (ez.z0 + ez.z1) / 2 - cz
		local len = math.sqrt(dx * dx + dz * dz)
		dx, dz = dx / len, dz / len
		local heading = math.atan2(dz, dx)
		local px, pz = -dz, dx
		local line: { Placed } = {}
		local hqs: { Placed } = {}
		for _, a in armiesIn(state, b.regionId, faction) do
			for _, u in a.units do
				if CampaignData.UnitTypes[u.type].class == "hq" then
					hqs[#hqs + 1] = { u = u, a = a }
				else
					line[#line + 1] = { u = u, a = a }
				end
			end
		end
		local perRow = 8
		local rows = math.max(1, math.ceil(#line / perRow))
		local function add(pair: Placed, along: number, back: number)
			local u, a = pair.u, pair.a
			local x, z = clampTo(zone, cx + px * along - dx * back, cz + pz * along - dz * back)
			units[#units + 1] = {
				name = u.name,
				class = CampaignData.UnitTypes[u.type].class,
				corps = a.name,
				strength = u.strength,
				experience = u.experience,
				pos = { x = x, z = z },
				heading = heading,
				faction = faction,
				commander = if CampaignData.UnitTypes[u.type].class == "hq" then true else nil,
				key = u.key,
			}
		end
		for i, pair in line do
			local row = math.floor((i - 1) / perRow)
			local inRow = math.min(perRow, #line - row * perRow)
			local col = (i - 1) % perRow
			add(pair, (col - (inRow - 1) / 2) * 90, (row - (rows - 1) / 2) * 70)
		end
		for i, pair in hqs do
			add(pair, (i - 1) * 60, rows * 35 + 60)
		end
	end
	return {
		id = battleId,
		name = "Battle of " .. reg.name,
		map = reg.terrain,
		briefing = string.format("Turn %d. %s attacks %s at %s. Hold the field or break the enemy army.", b.turn, CampaignData.FactionNames[b.attacker], CampaignData.FactionNames[b.defender], reg.name),
		factions = { player = PLAYER, enemy = ENEMY },
		factionNames = CampaignData.FactionNames,
		units = units,
		timeLimit = nil,
	}
end

-- Survivor keys missing from `survivors` are left unchanged; strength <= 0 or destroyed removes.
function Campaign.applyBattleResult(state: State, battleId: string, results: Types.Results, survivors: { [string]: Survivor }): (boolean, string?)
	if isApplied(state, battleId) then
		return true, "alreadyApplied"
	end
	local b, index = pendingBattle(state, battleId)
	if not b then
		return false, "unknownBattle"
	end
	local winner = if results.outcome == "victory" then PLAYER elseif results.outcome == "defeat" then ENEMY else b.defender
	local loser = other(winner)
	for _, a in armiesIn(state, b.regionId) do
		for i = #a.units, 1, -1 do
			local u = a.units[i]
			local s = survivors[u.key]
			if s and (s.destroyed or not isNum(s.strength) or s.strength <= 0) then
				table.remove(a.units, i)
			else
				if s then
					u.strength = math.clamp(math.floor(s.strength), 1, u.maxStrength)
					if isNum(s.experience) then
						u.experience = math.clamp(math.floor(s.experience), 0, 3)
					end
				end
				if a.faction == winner then
					u.experience = math.min(3, u.experience + 1)
				end
			end
		end
	end
	state.owners[b.regionId] = winner
	for _, a in armiesIn(state, b.regionId) do
		if #a.units == 0 then
			removeArmy(state, a.id)
			log(state, a.name .. " was destroyed.")
		elseif a.faction == loser then
			local dest: string? = nil
			local adj = table.clone(region(b.regionId).adjacent)
			table.sort(adj)
			for _, id in adj do
				if state.owners[id] == loser and #armiesIn(state, id, winner) == 0 then
					dest = id
					break
				end
			end
			if dest then
				a.regionId = dest
				a.movesLeft = 0
				log(state, string.format("%s retreats to %s.", a.name, region(dest).name))
			else
				removeArmy(state, a.id)
				log(state, a.name .. " had no line of retreat and surrendered.")
			end
		end
	end
	table.remove(state.pendingBattles, index)
	state.appliedBattles[#state.appliedBattles + 1] = { battleId = battleId, winner = winner, outcome = results.outcome, turn = b.turn }
	while #state.appliedBattles > APPLIED_MAX do
		table.remove(state.appliedBattles, 1)
	end
	log(state, string.format("%s wins at %s (%s).", CampaignData.FactionNames[winner], region(b.regionId).name, results.reason))
	if #state.pendingBattles == 0 and state.phase == "battle" then
		state.phase = "player"
	end
	checkVictory(state)
	return true, nil
end

-- Abstract resolution: p(attacker wins) = A / (A + 1.2 D); loser loses 25-40 %, winner 8-18 %;
-- units under 15 % of authorised strength are destroyed.
function Campaign.autoResolve(state: State, battleId: string): (boolean, string?)
	if isApplied(state, battleId) then
		return true, "alreadyApplied"
	end
	local b = pendingBattle(state, battleId)
	if not b then
		return false, "unknownBattle"
	end
	local att = strengthIn(state, b.regionId, b.attacker)
	local def = strengthIn(state, b.regionId, b.defender)
	local winner = if state.rng:float() < att / math.max(1, att + 1.2 * def) then b.attacker else b.defender
	local loserLoss = 0.25 + state.rng:float() * 0.15
	local winnerLoss = 0.08 + state.rng:float() * 0.10
	local survivors: { [string]: Survivor } = {}
	local sides: { [string]: any } = {}
	for _, f in FACTIONS do
		sides[f] = { deployed = 0, casualties = 0, remaining = 0, surviving = 0, routed = 0, shattered = 0, destroyed = 0, exited = 0, formations = 0 }
	end
	for _, a in armiesIn(state, b.regionId) do
		local loss = if a.faction == winner then winnerLoss else loserLoss
		local side = sides[a.faction]
		for _, u in a.units do
			local keep = math.floor(u.strength * (1 - loss))
			local dead = keep < u.maxStrength * 0.15
			survivors[u.key] = { strength = if dead then 0 else keep, experience = u.experience, destroyed = dead }
			side.deployed += u.strength
			side.formations += 1
			if dead then
				side.destroyed += 1
				side.casualties += u.strength
			else
				side.surviving += 1
				side.remaining += keep
				side.casualties += u.strength - keep
			end
		end
	end
	local results: Types.Results = {
		outcome = if winner == PLAYER then "victory" else "defeat",
		reason = "auto-resolved",
		clock = 0,
		objectives = {},
		sides = sides,
		feedback = {},
		log = {},
	}
	return Campaign.applyBattleResult(state, battleId, results, survivors)
end

-- View -------------------------------------------------------------------------------------------

function Campaign.view(state: State): { [string]: any }
	local regions = {}
	for _, reg in CampaignData.Regions do
		local ids = {}
		for _, a in armiesIn(state, reg.id) do
			ids[#ids + 1] = a.id
		end
		regions[#regions + 1] = { id = reg.id, name = reg.name, pos = reg.pos, adjacent = reg.adjacent, terrain = reg.terrain, isCity = reg.isCity, income = reg.income, manpower = reg.manpower, owner = state.owners[reg.id], armies = ids }
	end
	local objectives = {}
	for _, id in CampaignData.Victory.Objectives do
		objectives[#objectives + 1] = { id = id, name = region(id).name, held = state.owners[id] == PLAYER }
	end
	local recent = {}
	for i = math.max(1, #state.log - 19), #state.log do
		recent[#recent + 1] = state.log[i]
	end
	local fs = state.factions[PLAYER]
	local pending = state.pendingBattles[1]
	return {
		campaignId = state.campaignId,
		turn = state.turn,
		turnLimit = CampaignData.Victory.TurnLimit,
		phase = state.phase,
		treasury = fs.treasury,
		manpower = fs.manpower,
		supply = fs.supply,
		regions = regions,
		armies = copy(state.armies),
		recruitment = copy(state.recruitment),
		unitTypes = copy(CampaignData.UnitTypes),
		objectives = { regions = objectives, armyStrength = factionStrength(state, PLAYER), minArmyStrength = CampaignData.Victory.MinArmyStrength },
		log = recent,
		victory = copy(state.victory),
		pendingBattle = if pending then { battleId = pending.battleId, regionId = pending.regionId, attacker = pending.attacker, defender = pending.defender } else nil,
	}
end

-- Serialization ------------------------------------------------------------------------------

function Campaign.serialize(state: State): { [string]: any }
	return {
		version = 1,
		revision = state.revision,
		campaignId = state.campaignId,
		seed = state.seed,
		restarts = state.restarts,
		rngState = state.rng.state,
		turn = state.turn,
		phase = state.phase,
		owners = copy(state.owners),
		armies = copy(state.armies),
		factions = copy(state.factions),
		recruitment = copy(state.recruitment),
		nextArmyId = state.nextArmyId,
		nextUnitId = state.nextUnitId,
		log = copy(state.log),
		pendingBattles = copy(state.pendingBattles),
		appliedBattles = copy(state.appliedBattles),
		victory = copy(state.victory),
	}
end

local function validArmy(a: any): boolean
	if type(a) ~= "table" or not isNum(a.id) or type(a.faction) ~= "string" or type(a.name) ~= "string" or type(a.units) ~= "table" or not isNum(a.movesLeft) or type(a.supplied) ~= "boolean" then
		return false
	end
	if not CampaignData.region(a.regionId) or not table.find(FACTIONS, a.faction) or #a.units > ECON.MaxUnitsPerArmy then
		return false
	end
	for _, u in a.units do
		if type(u) ~= "table" or type(u.key) ~= "string" or not CampaignData.UnitTypes[u.type] or type(u.name) ~= "string" or not isNum(u.strength) or not isNum(u.maxStrength) or not isNum(u.experience) then
			return false
		end
		if u.strength < 0 or u.strength > u.maxStrength or u.experience < 0 or u.experience > 3 then
			return false
		end
	end
	return true
end

function Campaign.deserialize(profile: any): State?
	local p = profile
	if type(p) ~= "table" or p.version ~= 1 or type(p.campaignId) ~= "string" or not isNum(p.seed) or not isNum(p.rngState) or not isNum(p.turn) or not PHASES[p.phase] then
		return nil
	end
	if type(p.owners) ~= "table" or type(p.armies) ~= "table" or type(p.factions) ~= "table" or type(p.recruitment) ~= "table" or type(p.log) ~= "table" or type(p.pendingBattles) ~= "table" or type(p.appliedBattles) ~= "table" then
		return nil
	end
	if not isNum(p.nextArmyId) or not isNum(p.nextUnitId) or not isNum(p.restarts) then
		return nil
	end
	for _, reg in CampaignData.Regions do
		if not table.find(FACTIONS, p.owners[reg.id]) then
			return nil
		end
	end
	for _, f in FACTIONS do
		local fs = p.factions[f]
		if type(fs) ~= "table" or not isNum(fs.treasury) or not isNum(fs.manpower) or not isNum(fs.supply) then
			return nil
		end
	end
	if #p.armies > ECON.MaxArmies * 2 or #p.recruitment > ECON.MaxQueue * 2 or #p.pendingBattles > #CampaignData.Regions or #p.appliedBattles > APPLIED_MAX then
		return nil
	end
	for _, a in p.armies do
		if not validArmy(a) then
			return nil
		end
	end
	for _, q in p.recruitment do
		if type(q) ~= "table" or not table.find(FACTIONS, q.faction) or not CampaignData.region(q.regionId) or not CampaignData.UnitTypes[q.unitType] or not isNum(q.turnsLeft) or type(q.name) ~= "string" then
			return nil
		end
	end
	for _, b in p.pendingBattles do
		if type(b) ~= "table" or type(b.battleId) ~= "string" or not CampaignData.region(b.regionId) or not table.find(FACTIONS, b.attacker) or not table.find(FACTIONS, b.defender) or not isNum(b.turn) then
			return nil
		end
	end
	for _, b in p.appliedBattles do
		if type(b) ~= "table" or type(b.battleId) ~= "string" or type(b.winner) ~= "string" or type(b.outcome) ~= "string" or not isNum(b.turn) then
			return nil
		end
	end
	if p.victory ~= nil and (type(p.victory) ~= "table" or (p.victory.outcome ~= "victory" and p.victory.outcome ~= "defeat") or type(p.victory.reason) ~= "string") then
		return nil
	end
	local state: State = {
		campaignId = p.campaignId,
		seed = p.seed,
		restarts = p.restarts,
		revision = if isNum(p.revision) then p.revision else 0,
		rng = RNG.fromState(p.rngState),
		turn = p.turn,
		phase = p.phase,
		owners = copy(p.owners),
		armies = copy(p.armies),
		factions = copy(p.factions),
		recruitment = copy(p.recruitment),
		nextArmyId = p.nextArmyId,
		nextUnitId = p.nextUnitId,
		log = copy(p.log),
		pendingBattles = copy(p.pendingBattles),
		appliedBattles = copy(p.appliedBattles),
		victory = copy(p.victory),
	}
	table.sort(state.armies, function(a: Army, b: Army)
		return a.id < b.id
	end)
	while #state.log > LOG_MAX do
		table.remove(state.log, 1)
	end
	return state
end

-- Persistence helpers for the match layer -----------------------------------------------------

type Store = { update: (any, number, number?, (any) -> (any, string?)) -> (boolean, any, string?) }

-- Saves `state` as the pre-battle checkpoint. Requires session ownership and the revision the
-- state was loaded with; on success `state.revision` is advanced.
function Campaign.checkpoint(store: Store, userId: number, sessionId: string, state: State): (boolean, string?)
	local ok, profile, reason = store:update(userId, state.revision, function(old: any): (any, string?)
		if old ~= nil and (type(old.session) ~= "table" or old.session.id ~= sessionId) then
			return nil, "notOwner"
		end
		if old ~= nil and old.campaignId ~= nil and old.campaignId ~= state.campaignId and old.restarts > state.restarts then
			return nil, "campaignMismatch"
		end
		local p = Campaign.serialize(state)
		p.session = if old then old.session else { id = sessionId, expires = 0 }
		return p, nil
	end)
	if ok then
		state.revision = profile.revision
	end
	return ok, reason
end

-- Commits a battle result against the *stored* profile through a pure mutate. Returns the state
-- rebuilt from the committed profile; a repeat commit returns the stored state with
-- "alreadyApplied". Fails with "stale" (profile moved on), "notOwner", "campaignMismatch",
-- "unknownBattle" or "error".
function Campaign.commitBattle(store: Store, userId: number, sessionId: string, state: State, battleId: string, results: Types.Results, survivors: { [string]: Survivor }): (boolean, State?, string?)
	local ok, profile, reason = store:update(userId, state.revision, function(old: any): (any, string?)
		if old == nil then
			return nil, "noProfile"
		end
		if type(old.session) ~= "table" or old.session.id ~= sessionId then
			return nil, "notOwner"
		end
		if old.campaignId ~= state.campaignId then
			return nil, "campaignMismatch"
		end
		local s = Campaign.deserialize(old)
		if not s then
			return nil, "corrupt"
		end
		if isApplied(s, battleId) then
			return nil, "alreadyApplied"
		end
		local okA, why = Campaign.applyBattleResult(s, battleId, results, survivors)
		if not okA then
			return nil, why
		end
		local p = Campaign.serialize(s)
		p.session = old.session
		return p, nil
	end)
	if ok or reason == "alreadyApplied" then
		local s = if profile then Campaign.deserialize(profile) else nil
		if not s then
			return false, nil, "corrupt"
		end
		return true, s, if ok then nil else reason
	end
	return false, nil, reason
end

return Campaign
