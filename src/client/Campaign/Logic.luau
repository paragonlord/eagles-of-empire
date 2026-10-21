--!strict
-- Pure grand-campaign view logic (no Roblox types, so tests run it in the Luau CLI): who may act,
-- march routes mirroring the server's Movement rules, reachable provinces, readable reasons,
-- the turn summary and offer terms.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local EuropeData = require(Shared.EuropeData)

local Logic = {}

export type Step = { id: string, turn: number, stop: boolean }

Logic.REASONS = {
	noCampaign = "No grand campaign in progress",
	unreadable = "Your saved grand campaign could not be read. It has been kept; choosing a nation starts a new one and replaces it",
	notYourArmy = "That army is not yours",
	notYourProvince = "You do not hold that province",
	noMovesLeft = "That army has no movement left this turn",
	notAdjacent = "No road leads there",
	noAccess = "Neutral ground: declare war first",
	badPath = "No road leads there",
	seaNeedsFullMoves = "A sea crossing needs the army's full movement",
	navalSupremacy = "The Royal Navy holds the seas against you",
	noEscort = "No fleet of yours lies in that port to carry the army",
	notYourFleet = "That is not your fleet",
	notFleetLane = "Ships cannot sail there",
	notAPort = "Ships are built in ports",
	blockaded = "The port is blockaded",
	insufficientFunds = "Not enough treasury",
	insufficientManpower = "Not enough manpower",
	queueFull = "The recruitment queue is full",
	needsFortress = "Needs a fortress",
	needsCapital = "Only raised in a capital",
	majorsOnly = "Only the great powers raise these",
	underSiege = "Not while under siege",
	provinceBusy = "That province is already raising troops",
	tooManyArmies = "You field as many armies as you can supply",
	armyFull = "That army is at full establishment",
	notTogether = "The armies must stand in the same province",
	badSplit = "Leave at least one unit behind",
	nothingToReplenish = "At full strength",
	refused = "They refuse your proposal",
	truce = "A truce binds you: no war until it ends",
	notAtWar = "You are not at war with them",
	alreadyAtWar = "You are already at war",
	battlePending = "Resolve the pending battle first",
	noBattle = "There is no battle to fight",
	notInBattle = "Your army is not in that battle",
	noLineOfRetreat = "There is nowhere to retreat to",
	wrongPhase = "Not now",
	campaignOver = "The campaign is over",
	unknownOffer = "That offer has lapsed",
	unknownEvent = "That dispatch has been answered",
	badArgs = "Malformed order",
	building = "Already building here",
	alreadyForced = "Already marching hard",
	alreadyTrading = "You already trade with them",
	notYourSpy = "That is not your spy",
	tooFar = "Too far for this turn",
	spyHere = "You already have a spy here",
	tooManySpies = "You keep three spies at most",
	spyResting = "The spy has done enough this turn",
	nothingToSabotage = "It falls next turn anyway",
	alreadyAllowed = "Your armies may already cross their land",
	alreadyMarched = "Only before the army marches this turn",
	notBesieging = "You are not besieging that province",
	noArmyReady = "Your besiegers have already acted this turn",
	hasGeneral = "That army already has a general",
	noGenerals = "No general is free to take command",
	fullyBuilt = "Fully built",
	unknownCommand = "The server does not know that order",
}

function Logic.reason(code: any): string
	local s = tostring(code)
	-- "needsTech:<id>": a technology the nation lacks
	local tech = string.match(s, "^needsTech:(%a+)$")
	local t = tech and (EuropeData.TechById :: any)[tech]
	if t then
		return "Needs " .. t.name
	end
	-- "needs:<chain>:<level>": a building the province lacks
	local chain, level = string.match(s, "^needs:(%a+):(%d+)$")
	local def = chain and (EuropeData.Buildings :: any)[chain]
	if def then
		return "Needs a " .. string.lower(def.levels[tonumber(level) or 1] or def.name)
	end
	return Logic.REASONS[s] or s
end

function Logic.canAct(view: any): (boolean, string)
	if not view then
		return false, "Waiting for the campaign"
	elseif view.victory or view.phase == "ended" then
		return false, Logic.REASONS.campaignOver
	elseif view.pendingBattle or view.phase == "battle" then
		return false, Logic.REASONS.battlePending
	elseif view.phase ~= nil and view.phase ~= "player" then
		return false, Logic.REASONS.wrongPhase
	end
	return true, ""
end

function Logic.army(view: any, id: any): any
	if id == nil or not view or not view.armies then
		return nil
	end
	return view.armies[tostring(id)]
end

local function me(view: any): any
	return view.nations and view.nations[view.playerNation] or {}
end

function Logic.atWar(view: any, nation: string?): boolean
	return nation ~= nil and table.find(me(view).atWarWith or {}, nation) ~= nil
end

function Logic.allied(view: any, nation: string?): boolean
	return nation ~= nil and table.find(me(view).allies or {}, nation) ~= nil
end

-- Who controls a province: the occupier if any, else the owner.
function Logic.controller(view: any, id: string): string
	local ps = view.provinces and view.provinces[id]
	local p = EuropeData.province(id)
	if ps then
		return ps.occupiedBy or ps.owner
	end
	return if p then p.occupied1805 or p.owner1805 else ""
end

local function friendly(view: any, n: string): boolean
	return n == view.playerNation or Logic.allied(view, n)
end

local function hostileArmyIn(view: any, id: string): boolean
	for _, a in view.armies or {} do
		if a.provinceId == id and Logic.atWar(view, a.nation) then
			return true
		end
	end
	return false
end

local function canEnter(view: any, id: string): boolean
	local c = Logic.controller(view, id)
	return friendly(view, c) or Logic.atWar(view, c)
end

local function stops(view: any, id: string): boolean
	return hostileArmyIn(view, id) or Logic.atWar(view, Logic.controller(view, id))
end

local function inZoc(view: any, id: string): boolean
	local p = EuropeData.province(id)
	for _, n in if p then p.neighbours else {} do
		if hostileArmyIn(view, n) then
			return true
		end
	end
	return false
end

-- Same rule as the server: an army sails only from a port where its side has a fleet.
local function escortAt(view: any, id: string): boolean
	for _, f in view.fleets or {} do
		if f.provinceId == id and friendly(view, f.nation) then
			return true
		end
	end
	return false
end

-- Shortest march for army `a` to `goal` as board steps (turn numbers from movement points;
-- `stop` where the march halts: enemy army or enemy ground). Nil when unreachable.
function Logic.route(view: any, a: any, goal: string): { Step }?
	local start = a.provinceId
	if start == goal or not EuropeData.province(goal) then
		return nil
	end
	local parent: { [string]: string } = {}
	local seen: { [string]: boolean } = { [start] = true }
	local queue = { start }
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		if id == goal then
			break
		end
		if id == start or not stops(view, id) then
			for _, n in (EuropeData.province(id) :: any).neighbours do
				if not seen[n] and canEnter(view, n) and (not EuropeData.isSeaLane(id, n) or escortAt(view, id)) then
					seen[n] = true
					parent[n] = id
					table.insert(queue, n)
				end
			end
		end
	end
	if not seen[goal] then
		return nil
	end
	local ids: { string } = {}
	local c: string = goal
	while c ~= start do
		table.insert(ids, 1, c)
		c = parent[c]
	end
	local max = math.max(1, tonumber(a.movesMax) or 2)
	local left = tonumber(a.movesLeft) or max
	local turn = 1
	local from = start
	local steps: { Step } = {}
	for _, id in ids do
		local halt = stops(view, id)
		local sea = EuropeData.isSeaLane(from, id)
		local cost = if sea then max elseif not halt and inZoc(view, id) then 2 else 1
		if cost > left or (sea and left < max) then
			turn += 1
			left = max
		end
		left = if sea or halt then 0 else left - math.min(cost, left)
		table.insert(steps, { id = id, turn = turn, stop = halt })
		from = id
	end
	return steps
end

-- Shortest sailing from a fleet's port to `goal` over the fleet lanes (ids after the start), or nil.
function Logic.fleetRoute(fleet: any, goal: string): { string }?
	local start = fleet.provinceId
	local parent: { [string]: string } = {}
	local seen: { [string]: boolean } = { [start] = true }
	local queue = { start }
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		for _, l in EuropeData.FleetLanes do
			local n = if l[1] == id then l[2] elseif l[2] == id then l[1] else nil
			if n and not seen[n] then
				seen[n] = true
				parent[n] = id
				table.insert(queue, n)
			end
		end
	end
	if goal == start or not seen[goal] then
		return nil
	end
	local ids: { string } = {}
	local c: string = goal
	while c ~= start do
		table.insert(ids, 1, c)
		c = parent[c]
	end
	return ids
end

function Logic.reachable(view: any, a: any): { [string]: boolean }
	local out = {}
	for _, id in EuropeData.ProvinceIds do
		local r = Logic.route(view, a, id)
		if r and r[#r].turn == 1 then
			out[id] = true
		end
	end
	return out
end

local function nationName(id: string?): string
	local n = EuropeData.Nations[id or ""]
	return if n then n.name else tostring(id)
end

export type Side = { nation: string, armies: { any }, men: number }

-- Both sides of a pending battle: every army that fights (`pb.armies`, else the lead armies),
-- the side totals (`attackerMen`/`defenderMen`, else summed) and the odds from the player's side.
function Logic.battleSides(view: any, pb: any): (Side, Side, string)
	local function side(key: string, nation: any, lead: any, total: any): Side
		local ids = if type(pb.armies) == "table" and type(pb.armies[key]) == "table" then pb.armies[key] else { lead }
		local list, sum = {}, 0
		for _, id in ids do
			local a = Logic.army(view, id)
			if a then
				table.insert(list, a)
				sum += tonumber(a.men or a.strength) or 0
			end
		end
		local first = list[1]
		return { nation = tostring(nation or (if first then first.nation else "")), armies = list, men = tonumber(total) or sum }
	end
	local att = side("attacker", pb.attackerNation, pb.attacker, pb.attackerMen)
	local def = side("defender", pb.defenderNation, pb.defender, pb.defenderMen)
	local player = view.playerNation
	local mineIsDefender = att.nation ~= player and (def.nation == player or table.find(pb.defenders or {}, player) ~= nil)
	local mine, theirs = if mineIsDefender then def.men else att.men, if mineIsDefender then att.men else def.men
	local odds = tostring(pb.odds or "even")
	-- a garrison behind walls is worth more than its men: keep the server's odds for an assault
	if mine > 0 and theirs > 0 and not pb.assault then
		local r = mine / theirs
		odds = if r >= 1.25 then "favourable" elseif r <= 0.8 then "poor" else "even"
	end
	return att, def, odds
end

-- One readable sentence for a diplomatic offer.
function Logic.offerText(o: any): string
	local t = o.terms
	if o.kind == "peace" and type(t) == "table" then
		if t.winner == nil or t.winner == "" then
			return string.format("%s offers a white peace.", nationName(o.from))
		end
		local names = {}
		for _, id in t.provinces or {} do
			local p = EuropeData.province(id)
			table.insert(names, if p then p.name else tostring(id))
		end
		local cede = if #names > 0 then " " .. nationName(t.loser) .. " cedes " .. table.concat(names, ", ") .. "." else " No provinces change hands."
		return string.format("%s offers peace%s: %s prevails (war score %s).%s", nationName(o.from), if t.dictated then ", dictated" else "", nationName(t.winner), tostring(t.score or 0), cede)
	end
	if o.kind == "trade" then
		return string.format("%s proposes a trade agreement: each side earns a tenth of the other's provincial income.", nationName(o.from))
	end
	return string.format("%s proposes %s.", nationName(o.from), tostring(o.kind))
end

-- Board label tiers by camera height, as text transparencies (0 shown, 1 hidden): province
-- names up close, nation names across their lands from high up, cross-fading in between.
local TIER_LOW, TIER_HIGH = 360, 560
-- Big names on the board, given largest first as { x, z, size, aspect } (world studs; a name is
-- size × aspect long along x, size deep along z): each that runs into one already placed steps
-- north or south a line at a time (up to two lines) at its own size, then the same a size
-- smaller, down to 14; where nothing is clear it keeps the smallest size, two lines off.
export type Name = { x: number, z: number, size: number, aspect: number }
function Logic.placeNames(names: { Name }): { Name }
	local placed: { Name } = {}
	local function clear(n: Name): boolean
		for _, o in placed do
			if math.abs(n.x - o.x) < (n.size * n.aspect + o.size * o.aspect) / 2 and math.abs(n.z - o.z) < (n.size + o.size) / 2 then
				return false
			end
		end
		return true
	end
	local OFFSETS = { 0, 1, -1, 2, -2 }
	for _, n0 in names do
		local n = table.clone(n0)
		local done = false
		while not done do
			for _, k in OFFSETS do
				n.z = n0.z + k * n.size * 1.1
				if clear(n) then
					done = true
					break
				end
			end
			if not done then
				if n.size <= 14 then
					done = true -- nowhere clear: the last offset tried, at the smallest size
				else
					n.size = math.max(14, n.size * 0.85)
				end
			end
		end
		table.insert(placed, n)
	end
	return placed
end

function Logic.labelTiers(cameraHeight: number): (number, number)
	local t = math.clamp((cameraHeight - TIER_LOW) / (TIER_HIGH - TIER_LOW), 0, 1)
	return t, 1 - t
end

return Logic
