--!strict
-- Per-nation AI. Same rules as the player (Movement.move, Economy.recruit, Diplomacy). Each army
-- scores every province it can reach within three hops and marches toward the best:
--   hold          20 (+50 at a threatened own capital, +35 while besieging, home guard +40)
--   defend        30 + 40 own capital, own/allied province next to a hostile army we can face
--   attack        45 + income / 10 (+30 capital, +10 if undefended), enemy-held province whose
--                 defenders we outnumber 1.3 : 1 (the weakest is preferred through the strength term)
--   go home       15, for armies at peace standing outside their side's territory
-- minus 8 per hop, plus up to 5 of seeded noise. Diplomacy: accept or offer peace when losing,
-- join coalitions against a dominant France (Diplomacy.aiTurn); scripted events choose for it.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local EuropeData = require(Shared.EuropeData)
local State = require(script.Parent.State)
local Movement = require(script.Parent.Movement)
local Diplomacy = require(script.Parent.Diplomacy)
local Economy = require(script.Parent.Economy)

type State = State.State
type Army = State.Army

local AI = {}

local RECRUIT_CYCLE = { "line", "line", "cavalry", "line", "artillery", "light", "line", "heavy" }

local function threatAt(s: State, nation: string, pid: string): number
	local t = State.hostileStrengthIn(s, pid, nation)
	for _, n in State.province(pid).neighbours do
		t += State.hostileStrengthIn(s, n, nation)
	end
	return t
end

local function moveArmy(s: State, nation: string, a: Army, homeGuard: boolean, rally: boolean)
	local atWar = #State.enemiesOf(s, nation) > 0
	local capital = EuropeData.Nations[nation].capital
	local here = a.provinceId
	local myStr = State.armyStrength(a)
	local dist, parent = Movement.search(s, nation, here)
	local best: string? = nil
	local hereCtl = State.controller(s, here)
	local holdScore = 20
	if here == capital and threatAt(s, nation, here) > 0 then
		holdScore += 50
	end
	local siege = s.provinces[here].siege
	if siege and siege.by == nation then
		holdScore += 35
	end
	if homeGuard then
		holdScore += 40
	end
	local bestScore = holdScore + s.rng:float() * 5
	if rally and here ~= capital and dist[capital] then
		Movement.move(s, nation, a.id, Movement.pathFrom(parent, here, capital))
		return
	end
	local major = EuropeData.Nations[nation].major
	for _, pid in EuropeData.ProvinceIds do
		local d = dist[pid]
		if d and d > 0 and d <= 3 and (major or (Movement.hops[capital][pid] or 99) <= 3) then
			local score: number? = nil
			local c = State.controller(s, pid)
			local p = State.province(pid)
			if atWar then
				local hostile = State.hostileStrengthIn(s, pid, nation)
				if State.atWar(s, nation, c) then
					if myStr > hostile * 1.3 then
						score = 45 + p.income / 10 + (if p.isCapital then 30 else 0) + (if hostile == 0 then 10 else 0) - hostile / 2000
					end
				elseif State.friendly(s, nation, c) then
					local threat = 0
					for _, n in p.neighbours do
						threat += State.hostileStrengthIn(s, n, nation)
					end
					if threat > 0 and myStr * 1.5 > threat then
						score = 30 + (if pid == capital then 40 else 0) + (if c == nation then 5 else 0)
					end
				end
			elseif not State.friendly(s, nation, hereCtl) and State.friendly(s, nation, c) then
				score = 15 + (if c == nation then 10 else 0)
			end
			if score then
				local total = (score :: number) - 8 * d + s.rng:float() * 5
				if total > bestScore then
					best, bestScore = pid, total
				end
			end
		end
	end
	if best then
		local path = Movement.pathFrom(parent, here, best :: string)
		if #path > 0 then
			Movement.move(s, nation, a.id, path)
		end
	end
end

local function recruit(s: State, nation: string)
	local ns = s.nations[nation]
	local n = EuropeData.Nations[nation]
	local reserve = if n.major then 300 else 150
	local atWar = #State.enemiesOf(s, nation) > 0
	local units = 0
	for _, a in State.armiesOf(s, nation) do
		units += #a.units
	end
	if not atWar and units >= (if n.major then 12 else 4) then
		return
	end
	local where = {}
	if s.provinces[n.capital].owner == nation then
		where[1] = n.capital
	end
	for _, id in State.provincesOwned(s, nation) do
		if id ~= n.capital then
			where[#where + 1] = id
		end
	end
	local income = Economy.income(s, nation)
	for _ = 1, 4 do
		local k = (s.counters["ai." .. nation] or 0) % #RECRUIT_CYCLE + 1
		local t = RECRUIT_CYCLE[k]
		local c = EuropeData.UnitClasses[t]
		if ns.treasury - c.cost < reserve or income - Economy.upkeep(s, nation) - c.upkeep < 0 then
			return
		end
		local done = false
		for _, pid in where do
			if Economy.recruit(s, nation, pid, t) then
				done = true
				break
			end
		end
		if not done and t ~= "line" then
			for _, pid in where do
				if Economy.recruit(s, nation, pid, "line") then
					done = true
					break
				end
			end
		end
		s.counters["ai." .. nation] = k
		if not done then
			return
		end
	end
end

function AI.turn(s: State, nation: string)
	if not State.alive(s, nation) then
		return
	end
	Diplomacy.aiTurn(s, nation)
	local ns = s.nations[nation]
	-- replenish and merge
	for _, a in State.armiesOf(s, nation) do
		if ns.treasury > 400 then
			Economy.replenish(s, a)
		end
	end
	local mine = State.armiesOf(s, nation)
	for i = #mine, 1, -1 do
		local a = mine[i]
		for j = 1, i - 1 do
			local into = mine[j]
			if State.armyById(s, into.id) and into.provinceId == a.provinceId and #into.units + #a.units <= 12 and (into.general == nil or a.general == nil) then
				for _, u in a.units do
					into.units[#into.units + 1] = u
				end
				into.general = into.general or a.general
				into.movesLeft = math.min(into.movesLeft, a.movesLeft)
				State.removeArmy(s, a.id)
				break
			end
		end
	end
	-- garrisons (armies without a general) hold the capital in wartime; when a hostile army is
	-- within two marches of the capital, armies within four rally to it until it is covered 1.2 : 1
	local capital = EuropeData.Nations[nation].capital
	local atWar = #State.enemiesOf(s, nation) > 0
	local threat = 0
	for _, pid in EuropeData.ProvinceIds do
		if (Movement.hops[capital][pid] or 99) <= 2 then
			threat += State.hostileStrengthIn(s, pid, nation)
		end
	end
	local cover = 0
	for _, a in State.armiesIn(s, capital, nation) do
		cover += State.armyStrength(a)
	end
	for _, a in State.armiesOf(s, nation) do
		if a.movesLeft > 0 then
			local rally = false
			if threat > 0 and cover < threat * 1.2 and a.provinceId ~= capital and (Movement.hops[a.provinceId][capital] or 99) <= 4 then
				rally = true
				cover += State.armyStrength(a)
			end
			local guard = atWar and a.provinceId == capital and (a.general == nil or threat > 0)
			moveArmy(s, nation, a, guard, rally)
		end
	end
	recruit(s, nation)
end

return AI
