--!strict
-- War, peace, alliances, offers and coalitions.
--
-- War score per pair (-100..100): battle won +8 (+4 if an enemy army is destroyed), province
-- taken +5, capital taken +20. Peace: the side ahead by >= 20 takes floor(score / 20) of the
-- loser's provinces it occupies (never the capital, richest first); everything else occupied
-- reverts. A peace at >= 50, or with the loser's capital in the winner's hands, is dictated.
-- Truce afterwards: 6 turns, 10 after a dictated peace (scripted events may break it).
-- Declaring war brings the target's allies in against the aggressor (minors only when their capital
-- is within four marches of the aggressor's).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local EuropeData = require(Shared.EuropeData)
local State = require(script.Parent.State)
local Movement = require(script.Parent.Movement)

type State = State.State

local Diplomacy = {}

Diplomacy.SCORE = { battle = 8, destroyed = 4, province = 5, capital = 20 }
Diplomacy.PER_PROVINCE = 20
Diplomacy.DICTATED = 50
Diplomacy.TRUCE = 6
Diplomacy.TRUCE_DICTATED = 10

function Diplomacy.score(s: State, a: string, b: string): number
	local w = s.wars[State.pair(a, b)]
	if not w then
		return 0
	end
	return if w.a == a then w.score else -w.score
end

function Diplomacy.addScore(s: State, winner: string, loser: string, amount: number)
	local w = s.wars[State.pair(winner, loser)]
	if w then
		w.score = math.clamp(w.score + (if w.a == winner then amount else -amount), -100, 100)
	end
end

function Diplomacy.inTruce(s: State, a: string, b: string): boolean
	local t = s.truces[State.pair(a, b)]
	return t ~= nil and s.turn <= t
end

local function startWar(s: State, a: string, b: string)
	local k = State.pair(a, b)
	if s.wars[k] or a == b then
		return
	end
	s.alliances[k] = nil
	s.truces[k] = nil
	s.wars[k] = { a = a, b = b, score = 0, since = s.turn }
	State.addRelation(s, a, b, -40)
	State.log(s, string.format("%s declares war on %s.", State.nationName(a), State.nationName(b)))
end

-- a declares war on b; b's allies join b.
function Diplomacy.declareWar(s: State, a: string, b: string)
	if State.atWar(s, a, b) or a == b then
		return
	end
	startWar(s, a, b)
	for _, ally in State.alliesOf(s, b) do
		local near = (Movement.hops[EuropeData.Nations[ally].capital][EuropeData.Nations[a].capital] or 99) <= 4
		if ally ~= a and (EuropeData.Nations[ally].major or near) and not State.allied(s, ally, a) and not State.atWar(s, ally, a) then
			startWar(s, ally, a)
		end
	end
end

function Diplomacy.makeAlliance(s: State, a: string, b: string)
	if a ~= b and not State.atWar(s, a, b) and not State.allied(s, a, b) then
		s.alliances[State.pair(a, b)] = true
		State.addRelation(s, a, b, 30)
		State.log(s, string.format("%s and %s are allied.", State.nationName(a), State.nationName(b)))
	end
end

function Diplomacy.breakAlliance(s: State, a: string, b: string)
	if State.allied(s, a, b) then
		s.alliances[State.pair(a, b)] = nil
		State.addRelation(s, a, b, -20)
		State.log(s, string.format("The alliance between %s and %s is over.", State.nationName(a), State.nationName(b)))
	end
end

-- Members go to war with `against` (and its allies, defensively) and ally each other.
function Diplomacy.coalition(s: State, members: { string }, against: string)
	local joined = {}
	for _, m in members do
		if m ~= against and State.alive(s, m) and EuropeData.Nations[m] then
			if State.allied(s, m, against) then
				Diplomacy.breakAlliance(s, m, against)
			end
			Diplomacy.declareWar(s, m, against)
			joined[#joined + 1] = m
		end
	end
	-- join every existing enemy of `against`, so coalitions are one alliance
	local enemies = State.enemiesOf(s, against)
	for _, m in joined do
		for _, e in enemies do
			if EuropeData.Nations[e].major or table.find(joined, e) then
				Diplomacy.makeAlliance(s, m, e)
			end
		end
	end
end

-- Preview of a peace between a and b: winner, loser, score (>= 0 from winner's view), provinces.
function Diplomacy.terms(s: State, a: string, b: string): (string?, string?, number, { string }, boolean)
	local sc = Diplomacy.score(s, a, b)
	local winner, loser = a, b
	if sc < 0 then
		winner, loser, sc = b, a, -sc
	end
	local capital = EuropeData.Nations[loser].capital
	local dictated = sc >= Diplomacy.DICTATED or State.controller(s, capital) == winner
	local n = sc // Diplomacy.PER_PROVINCE
	local candidates = {}
	for _, id in EuropeData.ProvinceIds do
		local ps = s.provinces[id]
		if ps.owner == loser and ps.occupiedBy == winner and id ~= capital then
			candidates[#candidates + 1] = id
		end
	end
	table.sort(candidates, function(x: string, y: string): boolean
		local px, py = State.province(x), State.province(y)
		if px.income ~= py.income then
			return px.income > py.income
		end
		return x < y
	end)
	local transfers = {}
	for i = 1, math.min(n, #candidates) do
		transfers[i] = candidates[i]
	end
	if sc < Diplomacy.PER_PROVINCE and not dictated then
		return nil, nil, sc, transfers, false
	end
	return winner, loser, sc, transfers, dictated
end

function Diplomacy.makePeace(s: State, a: string, b: string, forceWinner: string?): { string }
	if not State.atWar(s, a, b) then
		return {}
	end
	if forceWinner then
		local w = s.wars[State.pair(a, b)]
		w.score = if w.a == forceWinner then math.max(w.score, 60) else math.min(w.score, -60)
	end
	local winner, loser, _, transfers, dictated = Diplomacy.terms(s, a, b)
	for _, id in transfers do
		local ps = s.provinces[id]
		ps.owner = winner :: string
		ps.occupiedBy = nil
		ps.occupiedTurns = 0
	end
	for _, id in EuropeData.ProvinceIds do
		local ps = s.provinces[id]
		if (ps.owner == a and ps.occupiedBy == b) or (ps.owner == b and ps.occupiedBy == a) then
			ps.occupiedBy = nil
			ps.occupiedTurns = 0
		end
		if ps.siege and ((ps.siege.by == a and State.friendly(s, ps.owner, b)) or (ps.siege.by == b and State.friendly(s, ps.owner, a))) then
			ps.siege = nil
		end
	end
	local k = State.pair(a, b)
	s.wars[k] = nil
	s.truces[k] = s.turn + (if dictated then Diplomacy.TRUCE_DICTATED else Diplomacy.TRUCE)
	s.peaces[k] = { winner = winner or "", dictated = dictated, turn = s.turn }
	State.addRelation(s, a, b, 20)
	for i = #s.offers, 1, -1 do
		local o = s.offers[i]
		if State.pair(o.from, o.to) == k then
			table.remove(s.offers, i)
		end
	end
	local names = {}
	for _, id in transfers do
		names[#names + 1] = State.province(id).name
	end
	if winner then
		State.log(s, string.format("%s %s peace on %s%s.", State.nationName(winner), if dictated then "dictates" else "makes", State.nationName(loser :: string), if #names > 0 then " and takes " .. table.concat(names, ", ") else ""))
	else
		State.log(s, string.format("%s and %s make peace on the old borders.", State.nationName(a), State.nationName(b)))
	end
	Movement.relocateStrays(s)
	return transfers
end

-- Does the AI `nation` accept peace with `other` now?
function Diplomacy.aiAccepts(s: State, nation: string, other: string): boolean
	local w = s.wars[State.pair(nation, other)]
	if not w then
		return false
	end
	local sc = Diplomacy.score(s, nation, other)
	local resolve = EuropeData.Nations[nation].peaceResolve
	local age = s.turn - w.since
	if State.atWar(s, State.controller(s, EuropeData.Nations[nation].capital), nation) then
		return true -- our capital is in enemy hands
	end
	if sc <= -resolve then
		return true
	end
	if sc >= Diplomacy.PER_PROVINCE and age >= 2 and not (nation == "britain" and other == "france") then
		return true -- we gain land
	end
	return age >= 14 and math.abs(sc) < 15 and nation ~= "britain"
end

function Diplomacy.aiAcceptsAlliance(s: State, nation: string, other: string): boolean
	if State.atWar(s, nation, other) or State.allied(s, nation, other) then
		return false
	end
	local rel = State.relation(s, nation, other)
	if rel >= 70 then
		return true
	end
	if rel < 30 then
		return false
	end
	for _, e in State.enemiesOf(s, nation) do
		if State.atWar(s, other, e) then
			return true
		end
	end
	return false
end

-- Player-initiated diplomacy. Returns ok, reason.
function Diplomacy.propose(s: State, from: string, to: string, kind: string): (boolean, string?)
	if not EuropeData.Nations[to] or to == from then
		return false, "unknownNation"
	end
	if kind == "war" then
		if State.atWar(s, from, to) then
			return false, "alreadyAtWar"
		end
		if Diplomacy.inTruce(s, from, to) then
			return false, "truce"
		end
		if State.allied(s, from, to) then
			Diplomacy.breakAlliance(s, from, to)
		end
		Diplomacy.declareWar(s, from, to)
		return true, nil
	elseif kind == "peace" then
		if not State.atWar(s, from, to) then
			return false, "notAtWar"
		end
		if not Diplomacy.aiAccepts(s, to, from) then
			State.log(s, State.nationName(to) .. " refuses peace.")
			return false, "refused"
		end
		Diplomacy.makePeace(s, from, to)
		return true, nil
	elseif kind == "alliance" then
		if not Diplomacy.aiAcceptsAlliance(s, to, from) then
			return false, "refused"
		end
		Diplomacy.makeAlliance(s, from, to)
		return true, nil
	end
	return false, "unknownKind"
end

function Diplomacy.answer(s: State, nation: string, offerId: string, accept: boolean): (boolean, string?)
	for i, o in s.offers do
		if o.id == offerId and o.to == nation then
			table.remove(s.offers, i)
			if not accept then
				State.log(s, "Offer from " .. State.nationName(o.from) .. " rejected.")
				return true, nil
			end
			if o.kind == "peace" then
				if not State.atWar(s, o.from, o.to) then
					return false, "notAtWar"
				end
				Diplomacy.makePeace(s, o.from, o.to)
			elseif o.kind == "alliance" then
				Diplomacy.makeAlliance(s, o.from, o.to)
			end
			return true, nil
		end
	end
	return false, "unknownOffer"
end

local function offer(s: State, from: string, to: string, kind: string)
	for _, o in s.offers do
		if o.from == from and o.to == to and o.kind == kind then
			return
		end
	end
	local terms: { [string]: any } = {}
	if kind == "peace" then
		local winner, loser, sc, transfers, dictated = Diplomacy.terms(s, from, to)
		terms = { winner = winner, loser = loser, score = sc, provinces = transfers, dictated = dictated }
	end
	s.offers[#s.offers + 1] = { id = State.newId(s, "o"), from = from, to = to, kind = kind, terms = terms, turn = s.turn }
end

-- Share of provinces controlled by France and its allies.
function Diplomacy.frenchShare(s: State): number
	local n = 0
	for _, id in EuropeData.ProvinceIds do
		if State.friendly(s, "france", State.controller(s, id)) then
			n += 1
		end
	end
	return n / #EuropeData.ProvinceIds
end

-- AI diplomacy for one nation's turn.
function Diplomacy.aiTurn(s: State, nation: string)
	for _, other in State.enemiesOf(s, nation) do
		if Diplomacy.aiAccepts(s, nation, other) then
			if other == s.playerNation then
				offer(s, nation, other, "peace")
			elseif Diplomacy.aiAccepts(s, other, nation) or Diplomacy.score(s, nation, other) <= -EuropeData.Nations[nation].peaceResolve then
				Diplomacy.makePeace(s, nation, other)
			end
		end
	end
	-- the powers combine against a France grown too large
	if nation ~= "france" and EuropeData.Nations[nation].major and not State.atWar(s, nation, "france") and not State.allied(s, nation, "france") and not Diplomacy.inTruce(s, nation, "france") and State.relation(s, nation, "france") < 20 then
		local p = math.clamp((Diplomacy.frenchShare(s) - 0.4) * 0.6, 0, 0.2)
		if s.rng:float() < p then
			State.log(s, State.nationName(nation) .. " will not suffer French hegemony any longer.")
			Diplomacy.coalition(s, { nation }, "france")
		end
	end
	-- alliance offers to the player from friends with a common enemy
	local player = s.playerNation
	if nation ~= player and Diplomacy.aiAcceptsAlliance(s, nation, player) and State.relation(s, nation, player) >= 50 then
		offer(s, nation, player, "alliance")
	end
end

return Diplomacy
