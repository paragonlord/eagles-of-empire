--!strict
-- Army movement by province path. Movement points per turn: 2, 3 under a general rated 4+.
-- Entering a province costs 1, +1 inside an enemy zone of control (a neighbouring province holds
-- an army at war with the mover). Movement ends on entering a province that holds a hostile army
-- (battle) or that a nation at war with the mover controls (siege / occupation). Sea lanes join two
-- ports, need a full allowance and use all of it; after Trafalgar no nation at war with Britain
-- may use them. Armies may enter only their own, allied or enemy (at war) provinces.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local EuropeData = require(Shared.EuropeData)
local State = require(script.Parent.State)

type State = State.State
type Army = State.Army

local Movement = {}

Movement.MAX_PATH = 8

-- Static hop distances over the province graph (land and sea), all pairs.
local hops: { [string]: { [string]: number } } = {}
for _, from in EuropeData.ProvinceIds do
	local d: { [string]: number } = { [from] = 0 }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		for _, n in State.province(id).neighbours do
			if d[n] == nil then
				d[n] = d[id] + 1
				queue[#queue + 1] = n
			end
		end
	end
	hops[from] = d
end
Movement.hops = hops

function Movement.adjacent(a: string, b: string): boolean
	local p = EuropeData.province(a)
	return p ~= nil and table.find(p.neighbours, b) ~= nil
end

function Movement.canEnter(s: State, nation: string, provinceId: string): boolean
	local c = State.controller(s, provinceId)
	return State.friendly(s, nation, c) or State.atWar(s, nation, c)
end

function Movement.inZoc(s: State, nation: string, provinceId: string): boolean
	for _, n in State.province(provinceId).neighbours do
		if State.hostileArmyIn(s, n, nation) then
			return true
		end
	end
	return false
end

function Movement.seaBlocked(s: State, nation: string): boolean
	return s.flags.navalSupremacy == true and State.atWar(s, nation, "britain")
end

-- Cost of one step for an army with `movesLeft` of `maxMoves`. Returns cost, stops, error.
function Movement.step(s: State, nation: string, from: string, to: string, movesLeft: number, maxMoves: number): (number, boolean, string?)
	if EuropeData.province(to) == nil or not Movement.adjacent(from, to) then
		return 0, false, "notAdjacent"
	end
	if not Movement.canEnter(s, nation, to) then
		return 0, false, "noAccess"
	end
	local stops = State.hostileArmyIn(s, to, nation) or State.atWar(s, nation, State.controller(s, to))
	if EuropeData.isSeaLane(from, to) then
		if Movement.seaBlocked(s, nation) then
			return 0, false, "navalSupremacy"
		end
		if movesLeft < maxMoves then
			return 0, false, "seaNeedsFullMoves"
		end
		return movesLeft, true, nil
	end
	local cost = 1
	if not stops and Movement.inZoc(s, nation, to) then
		cost = 2
	end
	return cost, stops, nil
end

-- Moves along `path` (excluding the current province) as far as the rules allow. Fails only if
-- the first step is impossible; otherwise returns the provinces actually entered.
function Movement.move(s: State, nation: string, armyId: string, path: { string }): (boolean, string?, { string }?)
	local a = State.armyById(s, armyId)
	if not a or a.nation ~= nation then
		return false, "notYourArmy", nil
	end
	if type(path) ~= "table" or #path == 0 or #path > Movement.MAX_PATH then
		return false, "badPath", nil
	end
	local army = a :: Army
	local entered: { string } = {}
	local maxMoves = State.maxMoves(army)
	for i, to in path do
		if type(to) ~= "string" then
			return if i == 1 then false else true, if i == 1 then "badPath" else nil, entered
		end
		local cost, stops, err = Movement.step(s, nation, army.provinceId, to, army.movesLeft, maxMoves)
		if err or cost > army.movesLeft then
			if i == 1 then
				return false, err or "noMovesLeft", nil
			end
			break
		end
		army.provinceId = to
		army.movesLeft -= cost
		entered[#entered + 1] = to
		if stops then
			army.movesLeft = 0
			break
		end
		if army.movesLeft <= 0 then
			break
		end
	end
	return true, nil, entered
end

-- BFS over provinces `nation` may enter (sea lanes only when open to it). Returns parent map.
function Movement.search(s: State, nation: string, from: string): ({ [string]: number }, { [string]: string })
	local dist: { [string]: number } = { [from] = 0 }
	local parent: { [string]: string } = {}
	local queue = { from }
	local head = 1
	local seaOk = not Movement.seaBlocked(s, nation)
	while head <= #queue do
		local id = queue[head]
		head += 1
		-- do not path through provinces that would stop the army, except as the destination
		local passable = id == from or not (State.hostileArmyIn(s, id, nation) or State.atWar(s, nation, State.controller(s, id)))
		if passable then
			for _, n in State.province(id).neighbours do
				if dist[n] == nil and Movement.canEnter(s, nation, n) and (seaOk or not EuropeData.isSeaLane(id, n)) then
					dist[n] = dist[id] + 1
					parent[n] = id
					queue[#queue + 1] = n
				end
			end
		end
	end
	return dist, parent
end

function Movement.pathFrom(parent: { [string]: string }, from: string, to: string): { string }
	local path = {}
	local cur = to
	while cur ~= from do
		table.insert(path, 1, cur)
		cur = parent[cur]
		if cur == nil then
			return {}
		end
	end
	return path
end

-- Where a beaten army falls back: a neighbouring land province its side controls, with no hostile
-- army, preferring its own provinces and then the one nearest its capital.
function Movement.retreatTarget(s: State, a: Army): string?
	local capital = EuropeData.Nations[a.nation].capital
	local best: string? = nil
	local bestScore = math.huge
	for _, n in State.province(a.provinceId).neighbours do
		if not EuropeData.isSeaLane(a.provinceId, n) then
			local c = State.controller(s, n)
			if State.friendly(s, a.nation, c) and not State.hostileArmyIn(s, n, a.nation) then
				local score = (hops[n][capital] or 99) + (if c == a.nation then 0 else 50)
				if score < bestScore or (score == bestScore and best ~= nil and n < best) then
					best, bestScore = n, score
				end
			end
		end
	end
	return best
end

-- Sends armies standing where they no longer may (after a peace or a broken alliance) to the
-- nearest province their side controls; disbands them if there is none.
function Movement.relocateStrays(s: State)
	for i = #s.armies, 1, -1 do
		local a = s.armies[i]
		local c = State.controller(s, a.provinceId)
		if not (State.friendly(s, a.nation, c) or State.atWar(s, a.nation, c)) then
			local best: string? = nil
			local bestD = math.huge
			for _, id in EuropeData.ProvinceIds do
				if State.friendly(s, a.nation, State.controller(s, id)) and not State.hostileArmyIn(s, id, a.nation) then
					local d = hops[a.provinceId][id] or math.huge
					if d < bestD then
						best, bestD = id, d
					end
				end
			end
			if best then
				a.provinceId = best
				a.movesLeft = 0
			else
				table.remove(s.armies, i)
				State.log(s, a.name .. " was disbanded: it had nowhere to go.")
			end
		end
	end
end

return Movement
