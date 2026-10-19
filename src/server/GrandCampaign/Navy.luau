--!strict
-- Fleets (docs/campaign.md "Navy"): sailing port to port along EuropeData.FleetLanes, naval
-- battles where fleets at war meet (auto-resolved at the end of the turn), and shipbuilding.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local EuropeData = require(Shared.EuropeData)
local State = require(script.Parent.State)
local Diplomacy = require(script.Parent.Diplomacy)

type State = State.State
type Fleet = State.Fleet

local Navy = {}

Navy.QUALITY = { britain = 1.5 } :: { [string]: number } -- the Royal Navy; everyone else 1
Navy.LOSER_LOSS = { 0.4, 0.6 }
Navy.WINNER_LOSS = { 0.1, 0.25 }

function Navy.fleetById(s: State, id: string): Fleet?
	for _, f in s.fleets do
		if f.id == id then
			return f
		end
	end
	return nil
end

local function hostileFleetIn(s: State, provinceId: string, nation: string): boolean
	for _, f in s.fleets do
		if f.provinceId == provinceId and State.atWar(s, nation, f.nation) then
			return true
		end
	end
	return false
end

-- Sails along `path` (fleet lanes, one move each); stops where an enemy fleet lies.
function Navy.move(s: State, nation: string, fleetId: string, path: { string }): (boolean, string?)
	local f = Navy.fleetById(s, fleetId)
	if not f or f.nation ~= nation then
		return false, "notYourFleet"
	end
	if #path == 0 or #path > State.FLEET_MOVES then
		return false, "badPath"
	end
	local from = f.provinceId
	for _, to in path do
		if type(to) ~= "string" or not EuropeData.isFleetLane(from, to) then
			return false, "notFleetLane"
		end
		from = to
	end
	if f.movesLeft <= 0 then
		return false, "noMovesLeft"
	end
	for _, to in path do
		if f.movesLeft <= 0 then
			break
		end
		f.provinceId = to
		f.movesLeft -= 1
		if hostileFleetIn(s, to, nation) then
			f.movesLeft = 0
			break
		end
	end
	return true, nil
end

local function power(fleets: { Fleet }): number
	local p = 0
	for _, f in fleets do
		p += (f.line * EuropeData.ShipClasses.line.power + f.frigates * EuropeData.ShipClasses.frigate.power) * (Navy.QUALITY[f.nation] or 1)
	end
	return p
end

local function lose(s: State, f: Fleet, range: { number })
	local frac = range[1] + s.rng:float() * (range[2] - range[1])
	f.line -= math.floor(f.line * frac + 0.5)
	f.frigates -= math.floor(f.frigates * frac + 0.5)
end

-- The nearest port (by fleet lanes) the fleet's side controls with no enemy fleet in it.
local function haven(s: State, f: Fleet): string?
	local seen: { [string]: boolean } = { [f.provinceId] = true }
	local queue = { f.provinceId }
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		for _, l in EuropeData.FleetLanes do
			local n = if l[1] == id then l[2] elseif l[2] == id then l[1] else nil
			if n and not seen[n] then
				seen[n] = true
				if State.friendly(s, f.nation, State.controller(s, n)) and not hostileFleetIn(s, n, f.nation) then
					return n
				end
				queue[#queue + 1] = n
			end
		end
	end
	return nil
end

-- Every port where fleets at war lie together: one battle, A^1.5 / (A^1.5 + B^1.5).
function Navy.battles(s: State)
	for _, pid in EuropeData.ProvinceIds do
		local here: { Fleet } = {}
		for _, f in s.fleets do
			if f.provinceId == pid then
				here[#here + 1] = f
			end
		end
		local a, b = {}, {}
		for _, f in here do
			if State.friendly(s, f.nation, here[1].nation) then
				a[#a + 1] = f
			elseif State.atWar(s, f.nation, here[1].nation) then
				b[#b + 1] = f
			end
		end
		if #b > 0 then
			local pa, pb = power(a) ^ 1.5, power(b) ^ 1.5
			local aWins = s.rng:float() < pa / math.max(1, pa + pb)
			local winners, losers = if aWins then a else b, if aWins then b else a
			local lostBefore = 0
			for _, f in losers do
				lostBefore += f.line + f.frigates
				lose(s, f, Navy.LOSER_LOSS)
			end
			for _, f in winners do
				lose(s, f, Navy.WINNER_LOSS)
			end
			local sunk = 0
			for _, f in losers do
				sunk += f.line + f.frigates
				local to = haven(s, f)
				if f.line + f.frigates > 0 and to then
					f.provinceId = to
					f.movesLeft = 0
				else
					f.line, f.frigates = 0, 0
				end
			end
			for i = #s.fleets, 1, -1 do
				local f = s.fleets[i]
				if f.line + f.frigates <= 0 then
					table.remove(s.fleets, i)
				end
			end
			Diplomacy.addScore(s, winners[1].nation, losers[1].nation, Diplomacy.SCORE.battle)
			State.log(s, string.format("Naval battle off %s: %s defeats %s, which loses %d of %d ships.", State.province(pid).name, State.nationName(winners[1].nation), State.nationName(losers[1].nation), lostBefore - sunk, lostBefore))
		end
	end
end

-- A ship for `nation` in an owned, unoccupied, unblockaded port: it joins the nation's fleet there
-- or forms a new squadron.
function Navy.build(s: State, nation: string, provinceId: string, ship: string): (boolean, string?)
	local cls = EuropeData.ShipClasses[ship]
	local p = EuropeData.province(provinceId)
	if not cls or not p then
		return false, "badArgs"
	end
	if not p.isPort then
		return false, "notAPort"
	end
	local ps = s.provinces[provinceId]
	if ps.owner ~= nation or ps.occupiedBy ~= nil then
		return false, "notYourProvince"
	end
	if State.blockaded(s, provinceId) then
		return false, "blockaded"
	end
	local ns = s.nations[nation]
	if ns.treasury < cls.cost then
		return false, "insufficientFunds"
	end
	ns.treasury -= cls.cost
	local fleet: Fleet? = nil
	for _, f in s.fleets do
		if f.nation == nation and f.provinceId == provinceId then
			fleet = f
		end
	end
	if not fleet then
		local nf: Fleet = { id = State.newFleetId(s), nation = nation, name = p.name .. " Squadron", provinceId = provinceId, line = 0, frigates = 0, movesLeft = 0 }
		s.fleets[#s.fleets + 1] = nf
		fleet = nf
	end
	local f = fleet :: Fleet
	if ship == "line" then
		f.line += 1
	else
		f.frigates += 1
	end
	return true, nil
end

return Navy
