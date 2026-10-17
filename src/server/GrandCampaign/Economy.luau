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

function Economy.income(s: State, nation: string): (number, number)
	local income, manpower = 0, 0
	for _, p in EuropeData.Provinces do
		local ps = s.provinces[p.id]
		if ps.occupiedBy == nil and ps.owner == nation then
			income += p.income
			manpower += p.manpower
		elseif ps.occupiedBy == nation then
			income += p.income * Economy.OCCUPIER_SHARE
		end
	end
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
	if c.needs == "fort" and p.fort == 0 and not p.isCapital then
		return false, "needsFortress"
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
function Economy.unrest(s: State, provinceId: string): number
	local ps = s.provinces[provinceId]
	if ps.occupiedBy == nil then
		return 0
	end
	local u = math.min(5, ps.occupiedTurns)
	if s.flags.guerrilla and (ps.owner == "spain" or ps.owner == "portugal") then
		u = math.min(5, u + 2)
	end
	return u
end

return Economy
