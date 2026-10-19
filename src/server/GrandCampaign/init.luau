--!strict
-- Grand campaign, Europe 1805–1815 (docs/campaign.md, docs/grand-campaign-contract.md). Pure Luau,
-- deterministic through `state.rng`; no wall clock, no Roblox APIs.
--
-- Turn (two months): player phase (commands) -> endTurn: unanswered event choices take their
-- default -> every other nation in NationOrder runs its AI (diplomacy, armies, recruitment) ->
-- contacts become battles (AI-only ones auto-resolved now) -> sieges and occupation -> economy for
-- every nation -> turn + 1, movement restored -> scripted events -> victory check. While the
-- player has battles pending the phase is "battle": fight, auto-resolve or retreat each of them.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local EuropeData = require(Shared.EuropeData)
local Scenarios = require(Shared.Scenarios)
local Types = require(Shared.Types)

local State = require(script.State)
local Economy = require(script.Economy)
local Movement = require(script.Movement)
local Diplomacy = require(script.Diplomacy)
local Battles = require(script.Battles)
local Events = require(script.Events)
local AI = require(script.AI)
local Serialize = require(script.Serialize)

export type State = State.State
export type Survivor = Battles.Survivor
export type Command = { [string]: any }

local GrandCampaign = {}

GrandCampaign.State = State
GrandCampaign.Economy = Economy
GrandCampaign.Movement = Movement
GrandCampaign.Diplomacy = Diplomacy
GrandCampaign.Battles = Battles
GrandCampaign.Events = Events
GrandCampaign.AI = AI

function GrandCampaign.new(seed: number, playerNation: string?): State
	local s = State.new(seed, playerNation)
	Events.run(s, false)
	return s
end

-- Victory ---------------------------------------------------------------------------------------------

local function foreignCapitalsHeld(s: State): number
	local n = 0
	for _, m in EuropeData.Majors do
		if m ~= "france" and State.controller(s, EuropeData.Nations[m].capital) == "france" then
			n += 1
		end
	end
	return n
end

local function dictatedTo(s: State, loser: string, winner: string): boolean
	local p = s.peaces[State.pair(loser, winner)]
	return p ~= nil and p.winner == winner and p.dictated and not State.atWar(s, loser, winner)
end

local function allMajorsSubmitted(s: State): boolean
	for _, m in EuropeData.Majors do
		if m ~= "france" and not dictatedTo(s, m, "france") then
			return false
		end
	end
	return true
end

function GrandCampaign.victory(s: State): State.Victory?
	if s.victory then
		return s.victory
	end
	local player = s.playerNation
	local V = EuropeData.Victory
	local frenchTriumph: string? = nil
	if allMajorsSubmitted(s) then
		frenchTriumph = "Every great power has signed a peace dictated by France."
	elseif s.turn >= V.CapitalsFromTurn and foreignCapitalsHeld(s) >= V.CapitalsToHold then
		frenchTriumph = string.format("France holds %d foreign capitals in 1815.", foreignCapitalsHeld(s))
	end
	if s.flags.abdicated then
		if player == "france" then
			return { outcome = "defeat", reason = "Paris has fallen and the Emperor has abdicated." }
		elseif s.abdicatedTo and table.find(s.abdicatedTo, player) then
			return { outcome = "victory", reason = "Paris has fallen; Napoleon has abdicated and France accepts your terms." }
		end
		return { outcome = "draw", reason = "Napoleon has abdicated, but not to you." }
	end
	if frenchTriumph then
		return if player == "france" then { outcome = "victory", reason = frenchTriumph } else { outcome = "defeat", reason = frenchTriumph }
	end
	if not State.alive(s, player) then
		return { outcome = "defeat", reason = State.nationName(player) .. " has been wiped from the map." }
	end
	if s.turn > EuropeData.EndTurn and #s.pendingBattles == 0 then
		if player == "france" then
			return { outcome = "draw", reason = "The Empire endures into 1816, but Europe is not subdued." }
		end
		return { outcome = "defeat", reason = "Napoleon still rules in Paris." }
	end
	return nil
end

local function checkVictory(s: State)
	if s.victory then
		return
	end
	local v = GrandCampaign.victory(s)
	if v then
		s.victory = v
		s.phase = "ended"
		State.log(s, string.upper(v.outcome) .. ": " .. v.reason)
	end
end

-- Turn ------------------------------------------------------------------------------------------------

export type EndTurnOpts = { autoplay: boolean? }

function GrandCampaign.endTurn(s: State, opts: EndTurnOpts?): (boolean, string?)
	if s.phase ~= "player" then
		return false, "wrongPhase"
	end
	local autoplay = opts ~= nil and opts.autoplay == true
	Events.closeTurn(s)
	s.offers = {}
	for _, n in EuropeData.NationOrder do
		if n ~= s.playerNation or autoplay then
			AI.turn(s, n, autoplay)
		end
	end
	local battles = Battles.detect(s, autoplay)
	for _, b in battles do
		if not b.player then
			Battles.autoResolve(s, b.battleId)
		end
	end
	Battles.sieges(s)
	for _, n in EuropeData.NationOrder do
		Economy.run(s, n)
	end
	s.turn += 1
	for _, a in s.armies do
		a.movesLeft = State.maxMoves(a)
	end
	-- an army still facing a pending battle cannot march away from it
	for _, b in s.pendingBattles do
		for _, a in Battles.armies(s, b) do
			a.movesLeft = 0
		end
	end
	Events.run(s, autoplay)
	-- the player's standing march orders go on (the rules may stop them again)
	for _, a in table.clone(s.armies) do
		local rest = a.path
		if rest and a.nation == s.playerNation and a.movesLeft > 0 then
			a.path = nil
			Movement.move(s, a.nation, a.id, rest, true)
		end
	end
	s.phase = if #s.pendingBattles > 0 then "battle" else "player"
	checkVictory(s)
	return true, nil
end

-- Commands --------------------------------------------------------------------------------------------

local function firstPlayerBattle(s: State): State.Battle?
	for _, b in s.pendingBattles do
		if b.player then
			return b
		end
	end
	return nil
end
GrandCampaign.pendingPlayerBattle = firstPlayerBattle

local function afterBattle(s: State)
	if s.phase == "battle" and firstPlayerBattle(s) == nil then
		s.phase = "player"
	end
	checkVictory(s)
end

function GrandCampaign.applyBattleResult(s: State, battleId: string, results: Types.Results, survivors: { [string]: Survivor }): (boolean, string?)
	local ok, why = Battles.apply(s, battleId, results, survivors)
	if ok and why == nil then
		afterBattle(s)
	end
	return ok, why
end

function GrandCampaign.autoResolve(s: State, battleId: string): (boolean, string?)
	local ok, why = Battles.autoResolve(s, battleId)
	if ok and why == nil then
		afterBattle(s)
	end
	return ok, why
end

function GrandCampaign.battleScenario(s: State, battleId: string): Scenarios.Scenario?
	return Battles.scenario(s, battleId)
end

local function str(v: any): string?
	return if type(v) == "string" and #v <= 64 then v else nil
end

local function myArmy(s: State, id: any): State.Army?
	local a = if str(id) then State.armyById(s, id) else nil
	return if a and a.nation == s.playerNation then a else nil
end

function GrandCampaign.command(s: State, cmd: Command): (boolean, string?)
	local kind = cmd.kind
	local player = s.playerNation
	if s.phase == "ended" then
		return false, "campaignOver"
	end
	if kind == "eventChoice" then
		local id = str(cmd.eventId)
		if not id then
			return false, "badArgs"
		end
		local ok, why = Events.choose(s, id, str(cmd.choice))
		checkVictory(s)
		return ok, why
	elseif kind == "fight" or kind == "autoResolve" or kind == "retreat" then
		local b = if str(cmd.battleId) then Battles.pending(s, cmd.battleId) else firstPlayerBattle(s)
		if not b or not b.player then
			return false, "noBattle"
		end
		if kind == "autoResolve" then
			return GrandCampaign.autoResolve(s, b.battleId)
		elseif kind == "retreat" then
			local ok, why = Battles.retreat(s, b.battleId, player)
			if ok then
				afterBattle(s)
			end
			return ok, why
		end
		return true, nil -- "fight": the session layer starts the tactical battle
	end
	if s.phase ~= "player" then
		return false, "battlePending"
	end
	if kind == "move" then
		local a = myArmy(s, cmd.armyId)
		if not a or type(cmd.path) ~= "table" then
			return false, if a then "badPath" else "notYourArmy"
		end
		local path: { string } = {}
		for i, p in cmd.path do
			if type(i) ~= "number" or not str(p) then
				return false, "badPath"
			end
			path[i] = p :: string
		end
		local ok, why = Movement.move(s, player, a.id, path, true)
		return ok, why
	elseif kind == "recruit" then
		local pid, t = str(cmd.provinceId), str(cmd.unitType)
		if not pid or not t then
			return false, "badArgs"
		end
		local ok, why = Economy.recruit(s, player, pid, t)
		if ok then
			State.log(s, string.format("%s ordered at %s.", EuropeData.UnitClasses[t].name, State.province(pid).name))
		end
		return ok, why
	elseif kind == "tax" then
		local level = tonumber(cmd.level)
		if not level then
			return false, "badArgs"
		end
		local ok, why = Economy.setTax(s, player, level)
		if ok then
			State.log(s, "Taxes set to " .. string.lower(Economy.TAX[level].name) .. ".")
		end
		return ok, why
	elseif kind == "build" then
		local pid, chain = str(cmd.provinceId), str(cmd.chain)
		if not pid or not chain then
			return false, "badArgs"
		end
		local ok, why = Economy.build(s, player, pid, chain)
		if ok then
			local level = (s.provinces[pid].buildings[chain] or 0) + 1
			State.log(s, string.format("Work begins on the %s at %s.", string.lower(EuropeData.Buildings[chain].levels[level]), State.province(pid).name))
		end
		return ok, why
	elseif kind == "replenish" then
		local a = myArmy(s, cmd.armyId)
		if not a then
			return false, "notYourArmy"
		end
		if Economy.replenish(s, a) == 0 then
			return false, "nothingToReplenish"
		end
		return true, nil
	elseif kind == "merge" then
		local a, into = myArmy(s, cmd.armyId), myArmy(s, cmd.intoArmyId)
		if not a or not into or a == into then
			return false, "notYourArmy"
		end
		if a.provinceId ~= into.provinceId then
			return false, "notTogether"
		end
		if #a.units + #into.units > State.MAX_UNITS then
			return false, "armyFull"
		end
		for _, u in a.units do
			into.units[#into.units + 1] = u
		end
		if into.general == nil then
			into.general = a.general
		elseif a.general and a.general.rating > into.general.rating then
			into.general = a.general
		end
		into.movesLeft = math.min(into.movesLeft, a.movesLeft)
		State.removeArmy(s, a.id)
		return true, nil
	elseif kind == "split" then
		local a = myArmy(s, cmd.armyId)
		if not a or type(cmd.unitKeys) ~= "table" then
			return false, "notYourArmy"
		end
		local keys: { [string]: boolean } = {}
		for _, k in cmd.unitKeys do
			if str(k) then
				keys[k :: string] = true
			end
		end
		local moving, staying = {}, {}
		for _, u in a.units do
			if keys[u.key] then
				moving[#moving + 1] = u
			else
				staying[#staying + 1] = u
			end
		end
		if #moving == 0 or #staying == 0 then
			return false, "badSplit"
		end
		if #State.armiesOf(s, player) >= State.MAX_ARMIES then
			return false, "tooManyArmies"
		end
		local new = State.newArmy(s, player, a.name .. " (detachment)", a.provinceId, nil)
		new.units = moving
		new.movesLeft = math.min(a.movesLeft, State.maxMoves(new))
		a.units = staying
		return true, nil
	elseif kind == "diplomacy" then
		local what = str(cmd.action) or str(cmd.diplomacy) or str(cmd.type)
		local nation = str(cmd.nation)
		if what == "accept" or what == "reject" then
			local offerId = str(cmd.offerId)
			if not offerId then
				return false, "badArgs"
			end
			local ok, why = Diplomacy.answer(s, player, offerId, what == "accept")
			checkVictory(s)
			return ok, why
		end
		if not nation or not what then
			return false, "badArgs"
		end
		local ok, why = Diplomacy.propose(s, player, nation, what)
		checkVictory(s)
		return ok, why
	elseif kind == "endTurn" then
		return GrandCampaign.endTurn(s)
	end
	return false, "unknownCommand"
end

-- View --------------------------------------------------------------------------------------------------

local function visibleProvinces(s: State): { [string]: boolean }
	local seen: { [string]: boolean } = {}
	local player = s.playerNation
	local function mark(id: string)
		seen[id] = true
		for _, n in State.province(id).neighbours do
			seen[n] = true
		end
	end
	for _, id in EuropeData.ProvinceIds do
		if State.friendly(s, player, State.controller(s, id)) then
			mark(id)
		end
	end
	for _, a in s.armies do
		if State.friendly(s, player, a.nation) then
			mark(a.provinceId)
		end
	end
	return seen
end

local function objectives(s: State): { { [string]: any } }
	local out = {}
	local V = EuropeData.Victory
	if s.playerNation == "france" then
		for _, m in EuropeData.Majors do
			if m ~= "france" then
				out[#out + 1] = { id = "peace-" .. m, text = "Dictate peace to " .. State.nationName(m), done = dictatedTo(s, m, "france") }
			end
		end
		out[#out + 1] = { id = "capitals", text = string.format("Or hold %d foreign capitals from Jan 1815 (%d held)", V.CapitalsToHold, foreignCapitalsHeld(s)), done = s.turn >= V.CapitalsFromTurn and foreignCapitalsHeld(s) >= V.CapitalsToHold }
		out[#out + 1] = { id = "paris", text = "Never lose Paris", done = State.controller(s, "paris") == "france" }
	else
		out[#out + 1] = { id = "paris", text = "Take Paris and force the Emperor to abdicate", done = s.flags.abdicated == true }
		local cap = EuropeData.Nations[s.playerNation].capital
		out[#out + 1] = { id = "capital", text = "Hold " .. State.province(cap).name, done = State.controller(s, cap) == s.playerNation }
	end
	return out
end

local function strongestArmy(s: State, provinceId: string, nation: string): string?
	local best, bestStr = nil, -1
	for _, a in State.armiesIn(s, provinceId, nation) do
		local st = State.armyStrength(a)
		if st > bestStr then
			best, bestStr = a.id, st
		end
	end
	return best
end

function GrandCampaign.view(s: State): { [string]: any }
	local player = s.playerNation
	local seen = visibleProvinces(s)
	local nations = {}
	for _, id in EuropeData.NationOrder do
		local n = EuropeData.Nations[id]
		local entry: { [string]: any } = {
			name = n.name,
			adjective = n.adjective,
			colour = n.colour,
			capital = n.capital,
			major = n.major,
			alive = State.alive(s, id),
			atWarWith = State.enemiesOf(s, id),
			allies = State.alliesOf(s, id),
			relationToPlayer = State.relation(s, id, player),
			truceUntil = s.truces[State.pair(id, player)],
			warScore = if State.atWar(s, player, id) then Diplomacy.score(s, player, id) else nil,
			provinces = State.provincesOwned(s, id),
		}
		if id == player then
			local ns = s.nations[id]
			local income, manpower = Economy.income(s, id)
			entry.treasury = ns.treasury
			entry.manpower = ns.manpower
			entry.income = income
			entry.manpowerIncome = manpower
			entry.tax = s.nations[id].tax or 2
			entry.upkeep = Economy.upkeep(s, id)
		end
		nations[id] = entry
	end
	local provinces = {}
	for _, id in EuropeData.ProvinceIds do
		local ps = s.provinces[id]
		local vis = {}
		for _, a in State.armiesIn(s, id) do
			if seen[id] or State.friendly(s, player, a.nation) then
				vis[#vis + 1] = a.id
			end
		end
		provinces[id] = {
			owner = ps.owner,
			occupiedBy = ps.occupiedBy,
			siege = if ps.siege then { by = ps.siege.by, turnsLeft = ps.siege.turnsLeft } else nil,
			unrest = Economy.unrest(s, id),
			buildings = if ps.owner == player then State.copy(ps.buildings) else nil,
			construction = if ps.owner == player and ps.construction then State.copy(ps.construction) else nil,
			fort = State.fortLevel(s, id),
			revolt = ps.revolt,
			visibleArmies = vis,
		}
	end
	local armies = {}
	for _, a in s.armies do
		local own = a.nation == player
		if own or State.friendly(s, player, a.nation) or seen[a.provinceId] then
			armies[a.id] = {
				id = a.id,
				nation = a.nation,
				name = a.name,
				general = if a.general then a.general.name else nil,
				rating = if a.general then a.general.rating else nil,
				provinceId = a.provinceId,
				strength = math.floor(State.armyStrength(a)),
				men = State.men(a),
				unitCount = #a.units,
				units = if own then State.copy(a.units) else nil,
				movesLeft = if own then a.movesLeft else nil,
				movesMax = if own then State.maxMoves(a) else nil,
				path = if own and a.path then table.clone(a.path) else nil,
			}
		end
	end
	local options = {}
	local buildOptions = {}
	for _, pid in State.provincesOwned(s, player) do
		if s.provinces[pid].occupiedBy == nil then
			local list = {}
			for _, t in EuropeData.UnitTypeOrder do
				local c = EuropeData.UnitClasses[t]
				local ok, why = Economy.canRecruit(s, player, pid, t)
				if why ~= "majorsOnly" then
					list[#list + 1] = { unitType = t, name = c.name, class = c.class, cost = c.cost, manpower = c.manpower, turns = c.turns, upkeep = c.upkeep, available = ok, reason = why }
				end
			end
			options[pid] = list
			local blist = {}
			for _, chain in EuropeData.BuildingOrder do
				local def = EuropeData.Buildings[chain]
				local ok, why, nextLevel = Economy.canBuild(s, player, pid, chain)
				if nextLevel <= EuropeData.BuildingMax then
					blist[#blist + 1] = { chain = chain, name = def.levels[nextLevel], level = nextLevel, cost = def.cost[nextLevel], turns = def.turns[nextLevel], available = ok, reason = why }
				end
			end
			buildOptions[pid] = blist
		end
	end
	local queue = {}
	for _, q in s.recruitment do
		if q.nation == player then
			queue[#queue + 1] = { provinceId = q.provinceId, unitType = q.unitType, name = EuropeData.UnitClasses[q.unitType].name, turnsLeft = q.turnsLeft }
		end
	end
	local offers = {}
	for _, o in s.offers do
		if o.to == player then
			offers[#offers + 1] = { id = o.id, from = o.from, kind = o.kind, terms = State.copy(o.terms) }
		end
	end
	local pending: { [string]: any }? = nil
	local b = firstPlayerBattle(s)
	if b then
		local ids: { [string]: { string } } = { attackers = {}, defenders = {} }
		local men: { [string]: number } = { attackers = 0, defenders = 0 }
		for _, a in Battles.armies(s, b) do
			local side = Battles.sideOf(b, a.nation) :: string
			table.insert(ids[side], a.id)
			men[side] += State.men(a)
		end
		pending = {
			armies = { attacker = ids.attackers, defender = ids.defenders },
			attackerMen = men.attackers,
			defenderMen = men.defenders,
			battleId = b.battleId,
			provinceId = b.provinceId,
			attacker = strongestArmy(s, b.provinceId, b.attacker),
			defender = strongestArmy(s, b.provinceId, b.defender),
			attackerNation = b.attacker,
			defenderNation = b.defender,
			attackers = State.copy(b.attackers),
			defenders = State.copy(b.defenders),
			scenarioId = b.scenarioId,
			odds = Battles.odds(s, b, player),
		}
	end
	local events = {}
	for _, e in s.inbox do
		events[#events + 1] = { id = e.id, title = e.title, text = e.text, choices = State.copy(e.choices) }
	end
	return {
		campaignId = s.campaignId,
		turn = s.turn,
		endTurn = EuropeData.EndTurn,
		date = EuropeData.dateOf(s.turn),
		phase = s.phase,
		playerNation = player,
		flags = State.copy(s.flags),
		nations = nations,
		provinces = provinces,
		armies = armies,
		recruitment = { options = options, queue = queue },
		buildings = { options = buildOptions },
		diplomacy = { offers = offers },
		events = events,
		pendingBattle = pending,
		log = table.clone(s.log),
		victory = State.copy(s.victory),
		objectives = objectives(s),
	}
end

-- Serialization and persistence ---------------------------------------------------------------------

GrandCampaign.serialize = Serialize.serialize
GrandCampaign.deserialize = Serialize.deserialize

type Store = { update: (any, number, number?, (any) -> (any, string?)) -> (boolean, any, string?) }

-- Saves `state` (session-owned, revision-checked); advances `state.revision` on success.
function GrandCampaign.checkpoint(store: Store, userId: number, sessionId: string, state: State): (boolean, string?)
	local ok, profile, reason = store:update(userId, state.revision, function(old: any): (any, string?)
		if old ~= nil and (type(old.session) ~= "table" or old.session.id ~= sessionId) then
			return nil, "notOwner"
		end
		local p = Serialize.serialize(state)
		p.session = if old then old.session else { id = sessionId, expires = 0 }
		return p, nil
	end)
	if ok then
		state.revision = profile.revision
	end
	return ok, reason
end

-- Commits a battle result against the stored profile (exactly once by battle id). Returns the
-- state rebuilt from the committed profile; a repeat returns it with "alreadyApplied".
function GrandCampaign.commitBattle(store: Store, userId: number, sessionId: string, state: State, battleId: string, results: Types.Results, survivors: { [string]: Survivor }): (boolean, State?, string?)
	local ok, profile, reason = store:update(userId, nil, function(old: any): (any, string?)
		if old == nil then
			return nil, "noProfile"
		end
		if type(old.session) ~= "table" or old.session.id ~= sessionId then
			return nil, "notOwner"
		end
		if old.campaignId ~= state.campaignId then
			return nil, "campaignMismatch"
		end
		local s = Serialize.deserialize(old)
		if not s then
			return nil, "corrupt"
		end
		if Battles.isApplied(s, battleId) then
			return nil, "alreadyApplied"
		end
		if old.revision ~= state.revision then
			return nil, "stale"
		end
		local okA, why = GrandCampaign.applyBattleResult(s, battleId, results, survivors)
		if not okA then
			return nil, why
		end
		local p = Serialize.serialize(s)
		p.session = old.session
		return p, nil
	end)
	if ok or reason == "alreadyApplied" then
		local s = if profile then Serialize.deserialize(profile) else nil
		if not s then
			return false, nil, "corrupt"
		end
		return true, s, if ok then nil else reason
	end
	return false, nil, reason
end

return GrandCampaign
