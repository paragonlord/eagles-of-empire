--!strict
-- Grand campaign state: types, construction from EuropeData and the small helpers every rules
-- module shares. Pure Luau; all randomness through `state.rng`; every loop whose order matters
-- walks an array (NationOrder, ProvinceIds, armies by id), never `pairs` of a dictionary.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local RNG = require(Shared.RNG)
local EuropeData = require(Shared.EuropeData)

export type Unit = { key: string, type: string, name: string, strength: number, maxStrength: number, experience: number, honours: { string }? }
-- wins, losses, sieges: the career so far (State.recordBattle); traits follow from it (State.traits)
export type General = { name: string, rating: number, wins: number?, losses: number?, sieges: number? }
-- path: the rest of a player's march order beyond this turn's reach; it marches on each new turn
-- forced: marched hard this turn (one more province, a few men lost; it rests next turn)
export type Army = { id: string, nation: string, name: string, general: General?, provinceId: string, units: { Unit }, movesLeft: number, path: { string }?, forced: boolean? }
export type Siege = { by: string, turnsLeft: number }
-- A spy: moves SPY_MOVES provinces a turn over any border, sees armies within SPY_SIGHT marches
export type Agent = { id: string, nation: string, provinceId: string, movesLeft: number }
export type Construction = { chain: string, turnsLeft: number }
-- buildings: chain -> level (EuropeData.Buildings); construction: the one under way; unrestTurns:
-- turns in a row at the top of the unrest scale; revolt: in open revolt (Economy)
export type ProvinceState = { owner: string, occupiedBy: string?, siege: Siege?, occupiedTurns: number, buildings: { [string]: number }, construction: Construction?, unrestTurns: number?, revolt: boolean? }
-- tax: 1 low, 2 normal, 3 high, 4 very high (Economy.TAX); techs known; research under way
export type NationState = { treasury: number, manpower: number, tax: number?, techs: { [string]: boolean }, research: string?, progress: number? }
export type War = { a: string, b: string, score: number, since: number } -- score > 0 favours a
export type Peace = { winner: string, dictated: boolean, turn: number } -- winner "" = white peace
export type Recruit = { nation: string, provinceId: string, unitType: string, turnsLeft: number }
export type Offer = { id: string, from: string, to: string, kind: string, terms: { [string]: any }, turn: number }
-- reinforcements: army ids per side in neighbouring provinces that march to the battle
-- assault: the besiegers storm the fortress; its garrison (Battles.garrison) defends
export type Battle = { battleId: string, provinceId: string, turn: number, attacker: string, defender: string, attackers: { string }, defenders: { string }, scenarioId: string?, player: boolean, reinforcements: { attackers: { string }, defenders: { string } }?, assault: boolean? }
export type Applied = { battleId: string, winner: string, turn: number }
export type InboxChoice = { id: string, label: string }
export type Inbox = { id: string, title: string, text: string, turn: number, choices: { InboxChoice }? }
export type Victory = { outcome: "victory" | "defeat" | "draw", reason: string }

export type State = {
	campaignId: string,
	seed: number,
	revision: number,
	rng: RNG.RNG,
	turn: number,
	phase: "player" | "battle" | "ended",
	playerNation: string,
	provinces: { [string]: ProvinceState },
	nations: { [string]: NationState },
	relations: { [string]: number },
	wars: { [string]: War },
	alliances: { [string]: boolean },
	trades: { [string]: boolean }, -- pair -> a trade agreement
	access: { [string]: boolean }, -- "a>b" -> a's armies may march through b's land
	agents: { Agent },
	truces: { [string]: number }, -- pair -> last turn of the truce
	peaces: { [string]: Peace }, -- pair -> last peace
	armies: { Army }, -- ascending creation order
	recruitment: { Recruit },
	flags: { [string]: boolean },
	fired: { [string]: boolean },
	inbox: { Inbox },
	offers: { Offer },
	counters: { [string]: number },
	nextId: number,
	log: { string },
	pendingBattles: { Battle },
	appliedBattles: { Applied },
	usedSetPieces: { [string]: boolean },
	abdicatedTo: { string }?,
	victory: Victory?,
}

local State = {}

State.LOG_MAX = 80
State.APPLIED_MAX = 64
State.MAX_UNITS = 20 -- per army
State.APPOINT_COST = 500 -- a new general for an army that has none
State.SPY_COST = 300
State.SPY_MAX = 3 -- spies a nation keeps at once
State.SPY_MOVES = 2
State.SPY_SIGHT = 2 -- marches within which a spy sees armies and their units
State.SPY_CAUGHT = 0.25 -- chance a saboteur is taken
State.MAX_ARMIES = 16 -- per nation
State.MAX_QUEUE = { major = 6, minor = 2 }
State.MAX_HONOURS = 5 -- battle honours per unit; the oldest gives way
State.HONOUR_LEN = 40

-- Basics -------------------------------------------------------------------------------------------

function State.copy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = State.copy(x)
	end
	return out
end

function State.isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function State.pair(a: string, b: string): string
	return if a < b then a .. "|" .. b else b .. "|" .. a
end

function State.sortedKeys(t: { [string]: any }): { string }
	local out = {}
	for k in t do
		out[#out + 1] = k
	end
	table.sort(out)
	return out
end

-- Fortress level 0..3: what its fortifications have reached (sieges, auto-resolve).
function State.fortLevel(s: State, provinceId: string): number
	return s.provinces[provinceId].buildings.fort or 0
end

function State.hasTech(s: State, nation: string, tech: string): boolean
	return s.nations[nation].techs[tech] == true
end

function State.province(id: string): EuropeData.Province
	return EuropeData.province(id) or error("unknown province " .. tostring(id))
end

function State.nationName(id: string): string
	local n = EuropeData.Nations[id]
	return if n then n.name else id
end

function State.log(s: State, text: string)
	s.log[#s.log + 1] = EuropeData.dateOf(s.turn) .. ": " .. text
	while #s.log > State.LOG_MAX do
		table.remove(s.log, 1)
	end
end

-- Battle honour ("Austerlitz 1805") carried by a unit that won; at most MAX_HONOURS, no repeats.
function State.addHonour(u: Unit, honour: string)
	local h = u.honours or {}
	if table.find(h, honour) then
		return
	end
	h[#h + 1] = string.sub(honour, 1, State.HONOUR_LEN)
	while #h > State.MAX_HONOURS do
		table.remove(h, 1)
	end
	u.honours = h
end

function State.newId(s: State, prefix: string): string
	local id = prefix .. tostring(s.nextId)
	s.nextId += 1
	return id
end

-- Diplomacy look-ups -------------------------------------------------------------------------------

function State.atWar(s: State, a: string, b: string): boolean
	return a ~= b and s.wars[State.pair(a, b)] ~= nil
end

function State.allied(s: State, a: string, b: string): boolean
	return a ~= b and s.alliances[State.pair(a, b)] == true
end

function State.agentById(s: State, id: string): Agent?
	for _, a in s.agents do
		if a.id == id then
			return a
		end
	end
	return nil
end

function State.trading(s: State, a: string, b: string): boolean
	return a ~= b and s.trades[State.pair(a, b)] == true
end

function State.friendly(s: State, a: string, b: string): boolean
	return a == b or State.allied(s, a, b)
end

function State.relation(s: State, a: string, b: string): number
	if a == b then
		return 100
	end
	return s.relations[State.pair(a, b)] or 0
end

function State.addRelation(s: State, a: string, b: string, delta: number)
	if a ~= b then
		local k = State.pair(a, b)
		s.relations[k] = math.clamp((s.relations[k] or 0) + delta, -100, 100)
	end
end

function State.enemiesOf(s: State, nation: string): { string }
	local out = {}
	for _, n in EuropeData.NationOrder do
		if State.atWar(s, nation, n) then
			out[#out + 1] = n
		end
	end
	return out
end

function State.alliesOf(s: State, nation: string): { string }
	local out = {}
	for _, n in EuropeData.NationOrder do
		if State.allied(s, nation, n) then
			out[#out + 1] = n
		end
	end
	return out
end

-- Provinces --------------------------------------------------------------------------------------

function State.controller(s: State, id: string): string
	local ps = s.provinces[id]
	return ps.occupiedBy or ps.owner
end

function State.provincesOwned(s: State, nation: string): { string }
	local out = {}
	for _, id in EuropeData.ProvinceIds do
		if s.provinces[id].owner == nation then
			out[#out + 1] = id
		end
	end
	return out
end

function State.alive(s: State, nation: string): boolean
	for _, id in EuropeData.ProvinceIds do
		local ps = s.provinces[id]
		if ps.owner == nation or ps.occupiedBy == nation then
			return true
		end
	end
	for _, a in s.armies do
		if a.nation == nation then
			return true
		end
	end
	return false
end

-- Armies ------------------------------------------------------------------------------------------

function State.armyById(s: State, id: string): Army?
	for _, a in s.armies do
		if a.id == id then
			return a
		end
	end
	return nil
end

function State.armiesIn(s: State, provinceId: string, nation: string?): { Army }
	local out = {}
	for _, a in s.armies do
		if a.provinceId == provinceId and (nation == nil or a.nation == nation) then
			out[#out + 1] = a
		end
	end
	return out
end

function State.armiesOf(s: State, nation: string): { Army }
	local out = {}
	for _, a in s.armies do
		if a.nation == nation then
			out[#out + 1] = a
		end
	end
	return out
end

function State.removeArmy(s: State, id: string)
	for i, a in s.armies do
		if a.id == id then
			table.remove(s.armies, i)
			return
		end
	end
end

function State.maxMoves(a: Army): number
	return if a.general and a.general.rating >= 4 then 3 else 2
end

function State.unitPower(u: Unit): number
	local c = EuropeData.UnitClasses[u.type]
	return u.strength * (if c then c.power else 1) * (1 + 0.1 * u.experience)
end

-- Every third win raises a general's rating (max 5), every third loss lowers it (min 1).
function State.recordBattle(g: General, won: boolean)
	if won then
		g.wins = (g.wins or 0) + 1
		if (g.wins :: number) % 3 == 0 then
			g.rating = math.min(5, g.rating + 1)
		end
	else
		g.losses = (g.losses or 0) + 1
		if (g.losses :: number) % 3 == 0 then
			g.rating = math.max(1, g.rating - 1)
		end
	end
end

-- Victor: 3+ wins, more than losses. Unlucky: the reverse. Siege-master: 2+ fortresses taken.
function State.traits(g: General): { string }
	local w, l, out = g.wins or 0, g.losses or 0, {}
	if w >= 3 and w > l then
		out[#out + 1] = "Victor"
	elseif l >= 3 and l > w then
		out[#out + 1] = "Unlucky"
	end
	if (g.sieges or 0) >= 2 then
		out[#out + 1] = "Siege-master"
	end
	return out
end

-- +5 % a rating star; Victor another +5 %, Unlucky -5 %.
function State.generalFactor(g: General?): number
	if not g then
		return 1
	end
	local f = 1 + 0.05 * g.rating
	for _, trait in State.traits(g) do
		f += if trait == "Victor" then 0.05 elseif trait == "Unlucky" then -0.05 else 0
	end
	return f
end

function State.armyStrength(a: Army): number
	local s = 0
	for _, u in a.units do
		s += State.unitPower(u)
	end
	return s * State.generalFactor(a.general) * EuropeData.Nations[a.nation].quality
end

function State.men(a: Army): number
	local n = 0
	for _, u in a.units do
		n += u.strength
	end
	return n
end

-- Strength of armies at war with `nation` in a province.
function State.hostileStrengthIn(s: State, provinceId: string, nation: string): number
	local t = 0
	for _, a in s.armies do
		if a.provinceId == provinceId and State.atWar(s, nation, a.nation) then
			t += State.armyStrength(a)
		end
	end
	return t
end

function State.hostileArmyIn(s: State, provinceId: string, nation: string): boolean
	for _, a in s.armies do
		if a.provinceId == provinceId and State.atWar(s, nation, a.nation) then
			return true
		end
	end
	return false
end

local function ordinal(nation: string, n: number): string
	if nation == "france" then
		return if n == 1 then "1er" else tostring(n) .. "e"
	elseif nation == "britain" or nation == "russia" then
		local m100, m10 = n % 100, n % 10
		local suf = if m100 >= 11 and m100 <= 13 then "th" elseif m10 == 1 then "st" elseif m10 == 2 then "nd" elseif m10 == 3 then "rd" else "th"
		return tostring(n) .. suf
	end
	return tostring(n) .. "."
end

function State.newUnit(s: State, nation: string, unitType: string, experience: number?): Unit
	local c = EuropeData.UnitClasses[unitType] or error("unknown unit type " .. tostring(unitType))
	local ck = nation .. "." .. unitType
	local n = (s.counters[ck] or 0) + 1
	s.counters[ck] = n
	local names = EuropeData.UnitNames[nation]
	local name = if names and names[unitType] then string.format(names[unitType], ordinal(nation, n)) else string.format("%s %s %d", EuropeData.Nations[nation].adjective, c.name, n)
	return { key = State.newId(s, "u"), type = unitType, name = name, strength = c.strength, maxStrength = c.strength, experience = experience or c.experience }
end

function State.newArmy(s: State, nation: string, name: string, provinceId: string, general: { name: string, rating: number }?): Army
	local a: Army = { id = State.newId(s, "a"), nation = nation, name = name, general = if general then { name = general.name, rating = general.rating } else nil, provinceId = provinceId, units = {}, movesLeft = 0 }
	a.movesLeft = State.maxMoves(a)
	s.armies[#s.armies + 1] = a
	return a
end

-- Expands { line = 3, cavalry = 1 } in UnitTypeOrder.
function State.addUnits(s: State, a: Army, units: { [string]: number }, experience: number)
	for _, t in EuropeData.UnitTypeOrder do
		for _ = 1, units[t] or 0 do
			if #a.units < State.MAX_UNITS then
				local exp = if t == "guard" then 3 else experience
				a.units[#a.units + 1] = State.newUnit(s, a.nation, t, exp)
			end
		end
	end
end

-- Generals can be in only one army at a time.
function State.generalInService(s: State, name: string): boolean
	for _, a in s.armies do
		if a.general and a.general.name == name then
			return true
		end
	end
	return false
end

-- Construction ---------------------------------------------------------------------------------------

function State.new(seed: number, playerNation: string?): State
	seed = math.floor(seed)
	local player = playerNation or "france"
	assert(EuropeData.Nations[player] and EuropeData.Nations[player].playable, "nation not playable: " .. tostring(player))
	local s: State = {
		campaignId = string.format("g%d-%s", seed, player),
		seed = seed,
		revision = 0,
		rng = RNG.new(seed * 2 + 1),
		turn = EuropeData.StartTurn,
		phase = "player",
		playerNation = player,
		provinces = {},
		nations = {},
		relations = {},
		wars = {},
		alliances = {},
		trades = {},
		access = {},
		agents = {},
		truces = {},
		peaces = {},
		armies = {},
		recruitment = {},
		flags = {},
		fired = {},
		inbox = {},
		offers = {},
		counters = {},
		nextId = 1,
		log = {},
		pendingBattles = {},
		appliedBattles = {},
		usedSetPieces = {},
		abdicatedTo = nil,
		victory = nil,
	}
	for _, p in EuropeData.Provinces do
		s.provinces[p.id] = { owner = p.owner1805, occupiedBy = p.occupied1805, siege = nil, occupiedTurns = 0, buildings = EuropeData.startBuildings(p) }
	end
	for _, id in EuropeData.NationOrder do
		local n = EuropeData.Nations[id]
		local techs: { [string]: boolean } = {}
		for _, t in EuropeData.StartTechs[id] or {} do
			techs[t] = true
		end
		s.nations[id] = { treasury = n.treasury, manpower = n.manpower, techs = techs }
	end
	for _, r: any in EuropeData.StartRelations do
		s.relations[State.pair(r[1], r[2])] = r[3]
	end
	for _, w in EuropeData.StartWars do
		s.wars[State.pair(w[1], w[2])] = { a = w[1], b = w[2], score = 0, since = 0 }
	end
	for _, al in EuropeData.StartAlliances do
		s.alliances[State.pair(al[1], al[2])] = true
	end
	for _, def in EuropeData.StartArmies do
		local a = State.newArmy(s, def.nation, def.name, def.province, def.general)
		State.addUnits(s, a, def.units, def.experience)
	end
	State.log(s, string.format("The campaign opens. You lead the %s.", State.nationName(player)))
	return s
end

return State
