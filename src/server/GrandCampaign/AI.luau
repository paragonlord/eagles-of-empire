--!strict
-- Per-nation AI. Same rules as the player (Movement.move, Economy.recruit, Diplomacy). Each army
-- scores every province it can reach within three hops and marches toward the best:
--   hold          20 (+50 at an own capital threatened beyond the other troops there, +35 while besieging, home guard +40)
--   defend        30 + 40 own capital, own/allied province next to a hostile army we can face
--   attack        45 + income / 10 (+30 capital, +10 if undefended), enemy-held province within
--                 FRONT marches of our land whose defenders we outnumber 1.3 : 1 (the weakest is
--                 preferred through the strength term)
--   follow        50 - 6 per march: a major's field armies join its main army (strongest with a general)
--   clear         60 (+80 next to the capital), a hostile army inside our side's land we outnumber 1.3 : 1
--   go home       15, for armies at peace standing outside their side's territory
--   (detachments without a general and under 4 units never attack enemy land)
--   march on the strategic target 70 - 4 per march still to go: field armies (a general or 6+
--                 units) step to any reachable province nearer the enemy capital chosen by
--                 AI.strategicTarget where the stack they march with (plus ours already there) is
--                 not outnumbered 1 : 1.25; an assault on a defended province takes the stack along
-- minus 8 per hop, plus up to 5 of seeded noise. Only Britain's AI crosses the sea, into friendly ports. Theatre: no target more than THEATRE marches from
-- a province the nation controls (allied land does not extend it), so armies stay at the front. Diplomacy: accept or offer peace when losing,
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

AI.THEATRE = 4
AI.FRONT = 2 -- ordinary attacks: at most this many marches beyond the land we control
AI.TARGET_RANGE = AI.THEATRE

-- Hops from the nearest province `nation` controls (owned and not occupied, or occupied by it);
-- sea lanes count only for Britain (the only AI that sails; it ferries armies to friendly ports and
-- never makes opposed landings) while the sea is open to it.
local function seaAI(s: State, nation: string): boolean
	return nation == "britain" and not Movement.seaBlocked(s, nation)
end

local function theatre(s: State, nation: string): { [string]: number }
	local seaOk = seaAI(s, nation)
	local d: { [string]: number } = {}
	local queue = {}
	for _, id in EuropeData.ProvinceIds do
		if State.controller(s, id) == nation then
			d[id] = 0
			queue[#queue + 1] = id
		end
	end
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		for _, n in State.province(id).neighbours do
			if d[n] == nil and (seaOk or not EuropeData.isSeaLane(id, n)) then
				d[n] = d[id] + 1
				queue[#queue + 1] = n
			end
		end
	end
	return d
end

local function totalStrength(s: State, nation: string): number
	local t = 0
	for _, a in State.armiesOf(s, nation) do
		t += State.armyStrength(a)
	end
	return t
end

-- The enemy capital worth marching on: within TARGET_RANGE marches of our land (by sea only while
-- the sea is open to us), against an enemy whose field strength is at most 1.25 times ours: a
-- major's capital before any minor's, then our strength over theirs (+5000) per march.
function AI.strategicTarget(s: State, nation: string, near: { [string]: number }?): string?
	local d = near or theatre(s, nation)
	local ours = totalStrength(s, nation)
	local best: string? = nil
	local bestScore = 0
	for _, e in State.enemiesOf(s, nation) do
		local cap = EuropeData.Nations[e].capital
		local dist = d[cap]
		if dist and dist > 0 and dist <= AI.TARGET_RANGE and State.controller(s, cap) ~= nation and ours >= 0.8 * totalStrength(s, e) then
			local score = ours / (totalStrength(s, e) + 5000) / (1 + dist) + (if EuropeData.Nations[e].major then 1000 else 0)
			if score > bestScore then
				best, bestScore = cap, score
			end
		end
	end
	return best
end

local RECRUIT_CYCLE = { "line", "line", "cavalry", "line", "artillery", "light", "line", "heavy" }

local function threatAt(s: State, nation: string, pid: string): number
	local t = State.hostileStrengthIn(s, pid, nation)
	for _, n in State.province(pid).neighbours do
		if not EuropeData.isSeaLane(pid, n) then
			t += State.hostileStrengthIn(s, n, nation)
		end
	end
	return t
end

local function moveArmy(s: State, nation: string, a: Army, homeGuard: boolean, rally: boolean, near: { [string]: number }, target: string?, main: Army?)
	local atWar = #State.enemiesOf(s, nation) > 0
	local capital = EuropeData.Nations[nation].capital
	local here = a.provinceId
	local myStr = State.armyStrength(a)
	local dist, parent = Movement.search(s, nation, here, if seaAI(s, nation) then "friendly" else "none")
	local best: string? = nil
	local hereCtl = State.controller(s, here)
	local holdScore = 20
	if here == capital then
		local others = 0
		for _, o in State.armiesIn(s, here, nation) do
			if o ~= a then
				others += State.armyStrength(o)
			end
		end
		if threatAt(s, nation, here) > others then
			holdScore += 50
		end
	end
	-- detachments (no general, under 4 units) defend; they do not invade
	local offensive = a.general ~= nil or #a.units >= 4
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
		if d and d > 0 and d <= 3 and (near[pid] or 99) <= AI.THEATRE and (major or (Movement.hops[capital][pid] or 99) <= 3) then
			local score: number? = nil
			local c = State.controller(s, pid)
			local p = State.province(pid)
			if atWar then
				local hostile = State.hostileStrengthIn(s, pid, nation)
				if State.atWar(s, nation, c) then
					if offensive and myStr > hostile * 1.3 and (near[pid] or 99) <= AI.FRONT then
						score = 45 + p.income / 10 + (if p.isCapital then 30 else 0) + (if hostile == 0 then 10 else 0) - hostile / 2000
					end
				elseif State.friendly(s, nation, c) and hostile > 0 then
					if myStr > hostile * 1.3 then
						score = 60 + (if (Movement.landHops[capital][pid] or 99) <= 1 then 80 else 0) -- clear intruders
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
	local together = false -- the whole stack here marches with this army (assault on the target road)
	-- field armies march with the main army
	if main and main ~= a and main.provinceId ~= here and offensive and not homeGuard and atWar then
		local d = dist[main.provinceId]
		if d and d <= 3 then
			local total = 50 - 6 * d + s.rng:float() * 5
			if total > bestScore then
				best, bestScore = main.provinceId, total
			end
		end
	end
	if target and target ~= here and (a.general ~= nil or #a.units >= 6) and not homeGuard then
		local t = target :: string
		local toT = Movement.landHops[here][t] or 99
		-- every reachable province on the way counts: total marches to the target, the stack we
		-- march with (plus ours already there) not outnumbered 1 : 1.25 where we stop
		local stack = 0
		for _, o in State.armiesIn(s, here, nation) do
			if o.movesLeft > 0 then
				stack += State.armyStrength(o)
			end
		end
		for _, pid in EuropeData.ProvinceIds do
			local d = dist[pid]
			local rest = Movement.landHops[pid][t] or 99
			if d and d > 0 and d <= 3 and (pid == t or rest < toT) then
				local there = stack
				for _, o in State.armiesIn(s, pid, nation) do
					there += State.armyStrength(o)
				end
				if there * 1.25 > State.hostileStrengthIn(s, pid, nation) then
					local total = 70 - 4 * (d + rest) + s.rng:float() * 5
					if total > bestScore then
						best, bestScore = pid, total
						together = State.hostileStrengthIn(s, pid, nation) > 0
					end
				end
			end
		end
	end
	if best then
		local path = Movement.pathFrom(parent, here, best :: string)
		if #path > 0 then
			local others = if together then State.armiesIn(s, here, nation) else {}
			Movement.move(s, nation, a.id, path)
			for _, o in others do
				if o ~= a and o.movesLeft > 0 and (o.general ~= nil or #o.units >= 4) then
					Movement.move(s, nation, o.id, path)
				end
			end
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

function AI.turn(s: State, nation: string, autoplay: boolean?)
	if not State.alive(s, nation) then
		return
	end
	Diplomacy.aiTurn(s, nation, autoplay)
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
		if (Movement.landHops[capital][pid] or 99) <= 2 then
			threat += State.hostileStrengthIn(s, pid, nation)
		end
	end
	local near = theatre(s, nation)
	local main: Army? = nil
	if EuropeData.Nations[nation].major then
		local bestStr = 0
		for _, a in State.armiesOf(s, nation) do
			local st = State.armyStrength(a)
			if a.general and st > bestStr then
				main, bestStr = a, st
			end
		end
	end
	local target = if EuropeData.Nations[nation].major then AI.strategicTarget(s, nation, near) else nil
	local cover, garrison = 0, 0
	for _, a in State.armiesIn(s, capital, nation) do
		cover += State.armyStrength(a)
		if a.general == nil then
			garrison += State.armyStrength(a)
		end
	end
	for _, a in State.armiesOf(s, nation) do
		if a.movesLeft > 0 then
			local rally = false
			if threat > 0 and cover < threat * 1.2 and a.provinceId ~= capital and (Movement.landHops[a.provinceId][capital] or 99) <= 4 then
				rally = true
				cover += State.armyStrength(a)
			end
			local guard = atWar and a.provinceId == capital and (a.general == nil or garrison < threat * 1.2)
			moveArmy(s, nation, a, guard, rally, near, target, main)
		end
	end
	recruit(s, nation)
end

return AI
