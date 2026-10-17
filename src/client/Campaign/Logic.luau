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
	notYourArmy = "That army is not yours",
	notYourProvince = "You do not hold that province",
	noMovesLeft = "That army has no movement left this turn",
	notAdjacent = "No road leads there",
	noAccess = "Neutral ground: declare war first",
	badPath = "No road leads there",
	seaNeedsFullMoves = "A sea crossing needs the army's full movement",
	navalSupremacy = "The Royal Navy holds the seas against you",
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
	unknownCommand = "The server does not know that order",
}

function Logic.reason(code: any): string
	local s = tostring(code)
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

local function seaBlocked(view: any): boolean
	return view.flags ~= nil and view.flags.navalSupremacy == true and Logic.atWar(view, "britain")
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
	local seaOk = not seaBlocked(view)
	while head <= #queue do
		local id = queue[head]
		head += 1
		if id == goal then
			break
		end
		if id == start or not stops(view, id) then
			for _, n in (EuropeData.province(id) :: any).neighbours do
				if not seen[n] and canEnter(view, n) and (seaOk or not EuropeData.isSeaLane(id, n)) then
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

-- Log lines dated `turn` ("May 1805: …"); the newest dozen when none carry that date.
function Logic.turnLines(view: any, turn: number): { string }
	local prefix = EuropeData.dateOf(turn) .. ":"
	local all, dated = {}, {}
	for _, e in view.log or {} do
		local s = if type(e) == "table" then tostring(e.text or "") else tostring(e)
		table.insert(all, s)
		if string.sub(s, 1, #prefix) == prefix then
			table.insert(dated, (string.gsub(string.sub(s, #prefix + 1), "^%s+", "")))
		end
	end
	if #dated > 0 then
		return dated
	end
	return { table.unpack(all, math.max(1, #all - 11)) }
end

local function nationName(id: string?): string
	local n = EuropeData.Nations[id or ""]
	return if n then n.name else tostring(id)
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
	return string.format("%s proposes %s.", nationName(o.from), tostring(o.kind))
end

return Logic
