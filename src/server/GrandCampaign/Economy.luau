--!strict
-- Income, manpower, upkeep, recruitment and replenishment. Owners collect the full income and
-- manpower of provinces they hold; an occupier requisitions half the income and no manpower; the
-- dispossessed owner gets nothing. Upkeep is paid every turn; a shortfall empties the treasury and
-- every unit of that nation loses 5 %. Occupied provinces breed unrest; in Spain and Portugal
-- after Dos de Mayo the guerrilla costs occupying armies 3 % a turn.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local EuropeData = require(Shared.EuropeData)
local State = require(script.Parent.State)

type State = State.State
type Army = State.Army

local Economy = {}

Economy.OCCUPIER_SHARE = 0.5
Economy.MAX_MANPOWER = 30000
Economy.MAX_TREASURY = 50000
Economy.SHORTFALL_ATTRITION = 0.05
Economy.GUERRILLA_ATTRITION = 0.03
Economy.REPLENISH_COST_PER_MAN = 0.5
Economy.SUBSIDY = 60 -- British treasury per turn to each major fighting France
Economy.CONTINENTAL = { britain = 0.8, blockaded = 0.95 }

-- Tax levels: income multiplier and the unrest it breeds in the nation's own provinces.
Economy.TAX = {
	{ name = "Low", income = 0.75, unrest = -1 },
	{ name = "Normal", income = 1.0, unrest = 0 },
	{ name = "High", income = 1.2, unrest = 1 },
	{ name = "Very high", income = 1.4, unrest = 2 },
}
Economy.UNREST_PENALTY = 0.75 -- income of a province at unrest 3 or more
Economy.REVOLT_TURNS = 2 -- turns at unrest 5 before the province rises
Economy.REVOLT_ATTRITION = 0.05 -- the owner's troops in a revolted province, a turn
Economy.FORCED_MARCH = 0.03 -- the men a forced march costs
Economy.REFILL = 0.1 -- share of a unit's full strength regained a turn at rest in friendly land
Economy.WINTER_ATTRITION = { allied = 0.02, hostile = 0.04 } -- harsh lands, Nov–Feb (own land: none)
Economy.FARMS_INCOME = 0.05 -- per level of the farms chain (doubled by Crop rotation)
Economy.TRADE_INCOME = 0.1 -- per level of the trade chain (0.15 with Banking)
Economy.RESEARCH = { major = 20, minor = 10, school = 15, enlightenment = 1.5 }

Economy.TRADE_PACT = 0.1 -- a trade partner pays this share of its own provinces' income a turn

-- What a nation's trade agreements bring in a turn.
function Economy.tradeIncome(s: State, nation: string): number
	local t = 0
	for _, other in EuropeData.NationOrder do
		if State.trading(s, nation, other) then
			for _, id in State.provincesOwned(s, other) do
				if s.provinces[id].occupiedBy == nil then
					t += State.province(id).income
				end
			end
		end
	end
	return t * Economy.TRADE_PACT
end

-- A province's income with its farms and trade.
function Economy.provinceIncome(s: State, provinceId: string): number
	local ps = s.provinces[provinceId]
	local b = ps.buildings
	local farms = Economy.FARMS_INCOME * (if State.hasTech(s, ps.owner, "rotation") then 2 else 1)
	local trade = Economy.TRADE_INCOME + (if State.hasTech(s, ps.owner, "banking") then 0.05 else 0)
	local blockade = if State.blockaded(s, provinceId) then State.BLOCKADE else 1
	return State.province(provinceId).income * (1 + farms * (b.farms or 0) + trade * (b.trade or 0)) * blockade
end

-- The cost of a building's next level for this nation (Iron works: a fifth off).
function Economy.buildCost(s: State, nation: string, chain: string, level: number): number
	local cost = EuropeData.Buildings[chain].cost[level]
	return if State.hasTech(s, nation, "ironworks") then math.floor(cost * 0.8) else cost
end

-- Research points a turn: the nation's own, its schools, Enlightenment.
function Economy.researchPoints(s: State, nation: string): number
	local pts = if EuropeData.Nations[nation].major then Economy.RESEARCH.major else Economy.RESEARCH.minor
	for _, id in State.provincesOwned(s, nation) do
		local ps = s.provinces[id]
		if ps.occupiedBy == nil then
			pts += Economy.RESEARCH.school * (ps.buildings.school or 0)
		end
	end
	if State.hasTech(s, nation, "enlightenment") then
		pts *= Economy.RESEARCH.enlightenment
	end
	return math.floor(pts)
end

-- Can `nation` research `tech` now? Returns ok, reason.
function Economy.canResearch(s: State, nation: string, tech: string): (boolean, string?)
	local t = EuropeData.TechById[tech]
	if not t then
		return false, "badArgs"
	end
	if State.hasTech(s, nation, tech) then
		return false, "known"
	end
	for _, r in t.requires do
		if not State.hasTech(s, nation, r) then
			return false, "needsTech:" .. r
		end
	end
	return true, nil
end

function Economy.setResearch(s: State, nation: string, tech: string): (boolean, string?)
	local ok, why = Economy.canResearch(s, nation, tech)
	if not ok then
		return false, why
	end
	local ns = s.nations[nation]
	if ns.research ~= tech then
		ns.research, ns.progress = tech, 0 -- switching subjects loses the work done
	end
	return true, nil
end

local function research(s: State, nation: string)
	local ns = s.nations[nation]
	local tech = ns.research and EuropeData.TechById[ns.research]
	if not tech then
		return
	end
	ns.progress = (ns.progress or 0) + Economy.researchPoints(s, nation)
	if (ns.progress :: number) >= tech.cost then
		ns.techs[tech.id] = true
		ns.research, ns.progress = nil, nil
		if nation == s.playerNation then
			State.log(s, tech.name .. " is understood: " .. tech.text)
		end
	end
end

function Economy.income(s: State, nation: string): (number, number)
	local income, manpower = 0, 0
	local tax = Economy.TAX[s.nations[nation].tax or 2]
	for _, p in EuropeData.Provinces do
		local ps = s.provinces[p.id]
		if ps.occupiedBy == nil and ps.owner == nation and not ps.revolt then
			local order = if Economy.unrest(s, p.id) >= 3 then Economy.UNREST_PENALTY else 1
			income += Economy.provinceIncome(s, p.id) * tax.income * order
			manpower += p.manpower
		elseif ps.occupiedBy == nation then
			income += Economy.provinceIncome(s, p.id) * Economy.OCCUPIER_SHARE
		end
	end
	if State.hasTech(s, nation, "conscription") then
		manpower *= 1.25
	end
	income += Economy.tradeIncome(s, nation)
	if s.flags.continentalSystem then
		if nation == "britain" then
			income *= Economy.CONTINENTAL.britain
		elseif nation == "france" or (State.allied(s, nation, "france") and State.atWar(s, nation, "britain")) then
			income *= Economy.CONTINENTAL.blockaded
		end
	end
	return math.floor(income), manpower
end

function Economy.upkeep(s: State, nation: string): number
	local u = 0
	for _, a in s.armies do
		if a.nation == nation then
			for _, unit in a.units do
				u += EuropeData.UnitClasses[unit.type].upkeep
			end
		end
	end
	return u
end

function Economy.queueCount(s: State, nation: string, provinceId: string?): number
	local n = 0
	for _, q in s.recruitment do
		if q.nation == nation and (provinceId == nil or q.provinceId == provinceId) then
			n += 1
		end
	end
	return n
end

local function attrit(s: State, a: Army, fraction: number)
	for i = #a.units, 1, -1 do
		local u = a.units[i]
		u.strength = math.floor(u.strength * (1 - fraction))
		if u.strength < u.maxStrength * 0.15 then
			table.remove(a.units, i)
		end
	end
end
Economy.attrit = attrit

function Economy.removeEmpty(s: State)
	for i = #s.armies, 1, -1 do
		local a = s.armies[i]
		if #a.units == 0 then
			table.remove(s.armies, i)
			State.log(s, a.name .. " has melted away.")
		end
	end
end

-- Can `nation` raise `unitType` in `provinceId` now? Returns ok, reason.
function Economy.canRecruit(s: State, nation: string, provinceId: string, unitType: string): (boolean, string?)
	local c = EuropeData.UnitClasses[unitType]
	local p = EuropeData.province(provinceId)
	if not c then
		return false, "unknownUnit"
	end
	if not p then
		return false, "unknownProvince"
	end
	local ps = s.provinces[provinceId]
	if ps.owner ~= nation or ps.occupiedBy ~= nil then
		return false, "notYourProvince"
	end
	if ps.siege ~= nil or State.hostileArmyIn(s, provinceId, nation) then
		return false, "underSiege"
	end
	local major = EuropeData.Nations[nation].major
	if c.majorOnly and not major then
		return false, "majorsOnly"
	end
	if c.needs == "capital" and EuropeData.Nations[nation].capital ~= provinceId then
		return false, "needsCapital"
	end
	if not EuropeData.inRoster(unitType, nation) then
		return false, "notInRoster"
	end
	if c.tech and not State.hasTech(s, nation, c.tech) then
		return false, "needsTech:" .. c.tech
	end
	if (ps.buildings[c.building.chain] or 0) < c.building.level then
		return false, "needs:" .. c.building.chain .. ":" .. c.building.level
	end
	if Economy.queueCount(s, nation, provinceId) >= 2 then
		return false, "provinceBusy"
	end
	if Economy.queueCount(s, nation) >= (if major then State.MAX_QUEUE.major else State.MAX_QUEUE.minor) then
		return false, "queueFull"
	end
	local ns = s.nations[nation]
	if ns.treasury < c.cost then
		return false, "insufficientFunds"
	end
	if ns.manpower < c.manpower then
		return false, "insufficientManpower"
	end
	return true, nil
end

function Economy.recruit(s: State, nation: string, provinceId: string, unitType: string): (boolean, string?)
	local ok, why = Economy.canRecruit(s, nation, provinceId, unitType)
	if not ok then
		return false, why
	end
	local c = EuropeData.UnitClasses[unitType]
	local ns = s.nations[nation]
	ns.treasury -= c.cost
	ns.manpower -= c.manpower
	s.recruitment[#s.recruitment + 1] = { nation = nation, provinceId = provinceId, unitType = unitType, turnsLeft = c.turns }
	return true, nil
end

local function deliver(s: State, q: State.Recruit)
	local ps = s.provinces[q.provinceId]
	local pname = State.province(q.provinceId).name
	if ps.owner ~= q.nation or ps.occupiedBy ~= nil then
		State.log(s, string.format("Recruits at %s dispersed: the province was lost.", pname))
		return
	end
	local target: Army? = nil
	for _, a in State.armiesIn(s, q.provinceId, q.nation) do
		if #a.units < State.MAX_UNITS then
			target = a
			break
		end
	end
	if not target then
		if #State.armiesOf(s, q.nation) >= State.MAX_ARMIES then
			State.log(s, "Recruits at " .. pname .. " could not form a new army.")
			return
		end
		target = State.newArmy(s, q.nation, "Garrison of " .. pname, q.provinceId, nil)
		local t = target :: Army
		t.movesLeft = 0
	end
	local t = target :: Army
	local u = State.newUnit(s, q.nation, q.unitType, nil)
	t.units[#t.units + 1] = u
	if q.nation == s.playerNation then
		State.log(s, string.format("%s joined %s at %s.", u.name, t.name, pname))
	end
end

-- Restores strength up to maxStrength in an owned or allied province: treasury and one manpower per man.
-- A spy at an owned, unoccupied province with a government building; one a province, SPY_MAX in all.
function Economy.recruitSpy(s: State, nation: string, provinceId: string): (boolean, string?)
	local ps = s.provinces[provinceId]
	if ps.owner ~= nation or ps.occupiedBy ~= nil then
		return false, "notYourProvince"
	end
	if (ps.buildings.government or 0) < 1 then
		return false, "needs:government:1"
	end
	local mine = 0
	for _, ag in s.agents do
		if ag.nation == nation then
			mine += 1
			if ag.provinceId == provinceId then
				return false, "spyHere"
			end
		end
	end
	if mine >= State.SPY_MAX then
		return false, "tooManySpies"
	end
	if s.nations[nation].treasury < State.SPY_COST then
		return false, "insufficientFunds"
	end
	s.nations[nation].treasury -= State.SPY_COST
	s.agents[#s.agents + 1] = { id = State.newId(s, "s"), nation = nation, provinceId = provinceId, movesLeft = State.SPY_MOVES }
	return true, nil
end

-- A new general (rating 2) from the nation's pool for an army that has none.
function Economy.appoint(s: State, a: Army): (boolean, string?)
	if a.general then
		return false, "hasGeneral"
	end
	local ns = s.nations[a.nation]
	if ns.treasury < State.APPOINT_COST then
		return false, "insufficientFunds"
	end
	for _, name in EuropeData.GeneralPool[a.nation] or {} do
		if not State.generalInService(s, name) then
			ns.treasury -= State.APPOINT_COST
			local g: State.General = { name = name, rating = 2 }
			a.general = g
			return true, nil
		end
	end
	return false, "noGenerals"
end

function Economy.replenish(s: State, a: Army): number
	local controller = State.controller(s, a.provinceId)
	if not State.friendly(s, a.nation, controller) then
		return 0
	end
	local ns = s.nations[a.nation]
	local restored = 0
	for _, u in a.units do
		local need = u.maxStrength - u.strength
		if need > 0 then
			local n = math.min(need, math.floor(ns.treasury / Economy.REPLENISH_COST_PER_MAN), ns.manpower)
			if n > 0 then
				u.strength += n
				ns.treasury -= n * Economy.REPLENISH_COST_PER_MAN
				ns.manpower -= n
				restored += n
			end
		end
	end
	ns.treasury = math.floor(ns.treasury)
	return restored
end

-- One nation's end-of-turn economy.
-- Can `nation` start the next level of `chain` in `provinceId`? Returns ok, reason, next level.
function Economy.canBuild(s: State, nation: string, provinceId: string, chain: string): (boolean, string?, number)
	local def = EuropeData.Buildings[chain]
	local ps = s.provinces[provinceId]
	if not def or not ps then
		return false, "badArgs", 0
	end
	local nextLevel = (ps.buildings[chain] or 0) + 1
	if ps.owner ~= nation or ps.occupiedBy ~= nil then
		return false, "notYourProvince", nextLevel
	end
	if nextLevel > EuropeData.BuildingMax then
		return false, "fullyBuilt", nextLevel
	end
	if ps.construction then
		return false, "building", nextLevel
	end
	if ps.siege ~= nil or State.hostileArmyIn(s, provinceId, nation) then
		return false, "underSiege", nextLevel
	end
	if s.nations[nation].treasury < Economy.buildCost(s, nation, chain, nextLevel) then
		return false, "insufficientFunds", nextLevel
	end
	return true, nil, nextLevel
end

function Economy.build(s: State, nation: string, provinceId: string, chain: string): (boolean, string?)
	local ok, why, nextLevel = Economy.canBuild(s, nation, provinceId, chain)
	if not ok then
		return false, why
	end
	local def = EuropeData.Buildings[chain]
	s.nations[nation].treasury -= Economy.buildCost(s, nation, chain, nextLevel)
	s.provinces[provinceId].construction = { chain = chain, turnsLeft = def.turns[nextLevel] }
	return true, nil
end

-- Constructions in the nation's own, unoccupied provinces advance a turn; the rest wait.
local function construct(s: State, nation: string)
	for _, id in EuropeData.ProvinceIds do
		local ps = s.provinces[id]
		local c = ps.construction
		if c and ps.owner == nation and ps.occupiedBy == nil then
			c.turnsLeft -= 1
			if c.turnsLeft <= 0 then
				ps.construction = nil
				local level = (ps.buildings[c.chain] or 0) + 1
				ps.buildings[c.chain] = level
				if nation == s.playerNation then
					State.log(s, string.format("%s: the %s is finished.", State.province(id).name, string.lower(EuropeData.Buildings[c.chain].levels[level])))
				end
			end
		end
	end
end

-- Unrest 0..5: occupation breeds it (a turn a level), the guerrilla adds 2; in the owner's own
-- hands the tax adds its share and foreign rule (not its 1805 owner) 3; every level of government
-- and every 1000 of the owner's men standing there (at most 2) take one away.
Economy.FOREIGN_UNREST = 3
function Economy.unrest(s: State, provinceId: string): number
	local ps = s.provinces[provinceId]
	if ps.occupiedBy ~= nil then
		local u = math.min(5, ps.occupiedTurns)
		if s.flags.guerrilla and (ps.owner == "spain" or ps.owner == "portugal") then
			u += 2
		end
		return math.min(5, u)
	end
	local tax = Economy.TAX[s.nations[ps.owner].tax or 2]
	local foreign = if State.province(provinceId).owner1805 ~= ps.owner then Economy.FOREIGN_UNREST else 0
	local men = 0
	for _, a in State.armiesIn(s, provinceId, ps.owner) do
		men += State.men(a)
	end
	local garrison = math.min(2, math.floor(men / 1000))
	local code = if State.hasTech(s, ps.owner, "civilcode") then 1 else 0
	return math.clamp(tax.unrest + foreign - (ps.buildings.government or 0) - garrison - code, 0, 5)
end

-- Public order in the nation's own provinces: two turns at unrest 5 and the province rises (no
-- income or manpower, its garrison bleeds); it settles once unrest is below 3.
local function publicOrder(s: State, nation: string)
	for _, id in EuropeData.ProvinceIds do
		local ps = s.provinces[id]
		if ps.owner == nation and ps.occupiedBy == nil then
			local u = Economy.unrest(s, id)
			ps.unrestTurns = if u >= 5 then (ps.unrestTurns or 0) + 1 else 0
			if not ps.revolt and (ps.unrestTurns or 0) >= Economy.REVOLT_TURNS then
				ps.revolt = true
				State.log(s, string.format("%s rises against %s!", State.province(id).name, State.nationName(nation)))
			elseif ps.revolt and u < 3 then
				ps.revolt = nil
				State.log(s, string.format("Order is restored in %s.", State.province(id).name))
			end
			if ps.revolt then
				for _, a in State.armiesIn(s, id, nation) do
					attrit(s, a, Economy.REVOLT_ATTRITION)
				end
			end
		else
			ps.unrestTurns, ps.revolt = nil, nil
		end
	end
end

function Economy.setTax(s: State, nation: string, level: number): (boolean, string?)
	if level ~= math.floor(level) or Economy.TAX[level] == nil then
		return false, "badArgs"
	end
	s.nations[nation].tax = level
	return true, nil
end

-- At rest by a depot (own, unoccupied province with barracks 2+, not in revolt) with no hostile army
-- in or next to the province, units refill a tenth of their full strength a turn (treasury and manpower as for
-- Replenish, while they last).
local function refill(s: State, nation: string)
	local ns = s.nations[nation]
	for _, a in State.armiesOf(s, nation) do
		local here = a.provinceId
		local ps = s.provinces[here]
		local quiet = ps.owner == nation and ps.occupiedBy == nil and not ps.revolt and (ps.buildings.barracks or 0) >= 2 and not State.hostileArmyIn(s, here, nation)
		if quiet then
			for _, n in State.province(here).neighbours do
				if not EuropeData.isSeaLane(here, n) and State.hostileArmyIn(s, n, nation) then
					quiet = false
				end
			end
		end
		if quiet then
			for _, u in a.units do
				local n = math.min(u.maxStrength - u.strength, math.ceil(u.maxStrength * Economy.REFILL), math.floor(ns.treasury / Economy.REPLENISH_COST_PER_MAN), ns.manpower)
				if n > 0 then
					u.strength += n
					ns.treasury -= n * Economy.REPLENISH_COST_PER_MAN
					ns.manpower -= n
				end
			end
		end
	end
	ns.treasury = math.floor(ns.treasury)
end

-- Winter in the harsh lands: men fall out of the ranks away from their own country's depots.
local function winter(s: State, nation: string)
	if not EuropeData.isWinter(s.turn) then
		return
	end
	for _, a in State.armiesOf(s, nation) do
		if EuropeData.HarshWinter[a.provinceId] then
			local c = State.controller(s, a.provinceId)
			if c ~= nation then
				attrit(s, a, if State.friendly(s, nation, c) then Economy.WINTER_ATTRITION.allied else Economy.WINTER_ATTRITION.hostile)
			end
		end
	end
end

function Economy.run(s: State, nation: string)
	local ns = s.nations[nation]
	local income, manpower = Economy.income(s, nation)
	ns.treasury = math.min(Economy.MAX_TREASURY, ns.treasury + income)
	ns.manpower = math.min(Economy.MAX_MANPOWER, ns.manpower + manpower)
	if nation == "britain" and State.atWar(s, "britain", "france") then
		for _, m in EuropeData.Majors do
			if m ~= "britain" and State.atWar(s, m, "france") and ns.treasury >= Economy.SUBSIDY * 5 then
				ns.treasury -= Economy.SUBSIDY
				s.nations[m].treasury += Economy.SUBSIDY
			end
		end
	end
	local upkeep = Economy.upkeep(s, nation)
	if ns.treasury >= upkeep then
		ns.treasury -= upkeep
	else
		if nation == s.playerNation then
			State.log(s, string.format("The treasury cannot pay the armies (%d short): every regiment loses men.", upkeep - ns.treasury))
		end
		ns.treasury = 0
		for _, a in State.armiesOf(s, nation) do
			attrit(s, a, Economy.SHORTFALL_ATTRITION)
		end
	end
	if s.flags.guerrilla then
		for _, a in State.armiesOf(s, nation) do
			local ps = s.provinces[a.provinceId]
			if (ps.owner == "spain" or ps.owner == "portugal") and State.atWar(s, nation, ps.owner) then
				attrit(s, a, Economy.GUERRILLA_ATTRITION)
			end
		end
	end
	construct(s, nation)
	publicOrder(s, nation)
	refill(s, nation)
	winter(s, nation)
	research(s, nation)
	for i = #s.recruitment, 1, -1 do
		local q = s.recruitment[i]
		if q.nation == nation then
			q.turnsLeft -= 1
			if q.turnsLeft <= 0 then
				table.remove(s.recruitment, i)
				deliver(s, q)
			end
		end
	end
	Economy.removeEmpty(s)
end

-- Unrest 0..5: turns under occupation (+2 under the guerrilla).
return Economy
