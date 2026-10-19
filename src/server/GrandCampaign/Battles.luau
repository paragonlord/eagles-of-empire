--!strict
-- Contacts, battles, sieges and occupation.
--
-- After every nation has moved, each province holding armies at war with each other produces one
-- battle (provinces in ProvinceIds order). Defender: the province's controller if it has troops
-- there, else the side of the earliest army; its side is every nation present friendly to it; the
-- attackers are every nation present at war with it. Battles without the player's armies are
-- auto-resolved at once; the player's are pending until fought, auto-resolved or avoided.
--
-- Auto-resolve: p(attacker wins) = A^1.5 / (A^1.5 + D^1.5), D including a defence bonus of
-- 1.15 + 0.1 per fort level when the defenders hold the province; loser loses 25–40 %, winner
-- 8–18 %; units under 15 % of their authorised strength are destroyed. Losers fall back to a
-- neighbouring friendly province or surrender.
--
-- Sieges: an uncontested army at war with a province's controller besieges it for fort + 1 turns
-- (fort 0: taken at once); the province is then occupied. Owners retaking a province end the
-- occupation.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local EuropeData = require(Shared.EuropeData)
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)
local Types = require(Shared.Types)
local Moments = require(Shared.Moments)
local State = require(script.Parent.State)
local Movement = require(script.Parent.Movement)
local Diplomacy = require(script.Parent.Diplomacy)
local Economy = require(script.Parent.Economy)

type State = State.State
type Army = State.Army
type Battle = State.Battle
type Unit = State.Unit

export type Survivor = { strength: number, experience: number, destroyed: boolean?, initial: number? }

local Battles = {}

Battles.MAX_UNITS_PER_SIDE = 24
Battles.RETREAT_LOSS = 0.05

local function sideOf(b: Battle, nation: string): string?
	if table.find(b.attackers, nation) then
		return "attackers"
	elseif table.find(b.defenders, nation) then
		return "defenders"
	end
	return nil
end
Battles.sideOf = sideOf

function Battles.armies(s: State, b: Battle, side: string?): { Army }
	local out = {}
	for _, a in State.armiesIn(s, b.provinceId) do
		local sd = sideOf(b, a.nation)
		if sd and (side == nil or sd == side) then
			out[#out + 1] = a
		end
	end
	return out
end

function Battles.pending(s: State, battleId: string): (Battle?, number)
	for i, b in s.pendingBattles do
		if b.battleId == battleId then
			return b, i
		end
	end
	return nil, 0
end

function Battles.isApplied(s: State, battleId: string): boolean
	for _, b in s.appliedBattles do
		if b.battleId == battleId then
			return true
		end
	end
	return false
end

-- Side containing `nation`, or containing one of its allies.
local function sideHas(s: State, side: { string }, nation: string): boolean
	for _, n in side do
		if n == nation or State.allied(s, n, nation) then
			return true
		end
	end
	return false
end

function Battles.matchSetPiece(s: State, provinceId: string, turn: number, attackers: { string }, defenders: { string }): string?
	for _, sp in EuropeData.SetPieces do
		if sp.province == provinceId and turn >= sp.turnFrom and turn <= sp.turnTo and not s.usedSetPieces[sp.scenarioId] and Scenarios.get(sp.scenarioId) then
			if (sideHas(s, attackers, sp.attacker) and sideHas(s, defenders, sp.defender)) or (sideHas(s, defenders, sp.attacker) and sideHas(s, attackers, sp.defender)) then
				return sp.scenarioId
			end
		end
	end
	return nil
end

local function sideStrength(s: State, b: Battle, side: string): number
	local t = 0
	for _, a in Battles.armies(s, b, side) do
		t += State.armyStrength(a)
	end
	if side == "defenders" and table.find(b.defenders, State.controller(s, b.provinceId)) then
		t *= 1.15 + 0.1 * State.fortLevel(s, b.provinceId)
	end
	return t
end
Battles.sideStrength = sideStrength

function Battles.odds(s: State, b: Battle, nation: string): string
	local mine = sideOf(b, nation) or "attackers"
	local other = if mine == "attackers" then "defenders" else "attackers"
	local r = sideStrength(s, b, mine) / math.max(1, sideStrength(s, b, other))
	return if r >= 1.25 then "favourable" elseif r <= 0.8 then "poor" else "even"
end

-- Finds the contacts and records them as pending battles. Returns the new battles.
function Battles.detect(s: State, autoplay: boolean?): { Battle }
	local out = {}
	for _, pid in EuropeData.ProvinceIds do
		local here = State.armiesIn(s, pid)
		if #here >= 2 then
			local hostile = false
			for i = 1, #here do
				for j = i + 1, #here do
					hostile = hostile or State.atWar(s, here[i].nation, here[j].nation)
				end
			end
			if hostile then
				local c = State.controller(s, pid)
				local leader = here[1].nation
				for _, a in here do
					if State.friendly(s, a.nation, c) then
						leader = a.nation
						break
					end
				end
				for _, a in here do
					if a.nation == c then
						leader = c
					end
				end
				local defenders, attackers = {}, {}
				for _, a in here do
					if State.friendly(s, a.nation, leader) and not table.find(defenders, a.nation) then
						defenders[#defenders + 1] = a.nation
					end
				end
				for _, a in here do
					if State.atWar(s, a.nation, leader) and not table.find(attackers, a.nation) and not table.find(defenders, a.nation) then
						attackers[#attackers + 1] = a.nation
					end
				end
				if #attackers > 0 then
					local best, bestStr = attackers[1], -1
					for _, n in attackers do
						local str = 0
						for _, a in State.armiesIn(s, pid, n) do
							str += State.armyStrength(a)
						end
						if str > bestStr then
							best, bestStr = n, str
						end
					end
					local player = not autoplay and (table.find(attackers, s.playerNation) ~= nil or table.find(defenders, s.playerNation) ~= nil)
					local b: Battle = {
						battleId = string.format("%s-t%d-%s", s.campaignId, s.turn, pid),
						provinceId = pid,
						turn = s.turn,
						attacker = best,
						defender = leader,
						attackers = attackers,
						defenders = defenders,
						scenarioId = Battles.matchSetPiece(s, pid, s.turn, attackers, defenders),
						player = player,
					}
					s.pendingBattles[#s.pendingBattles + 1] = b
					out[#out + 1] = b
				end
			end
		end
	end
	return out
end

-- Applies survivors (by unit key) and the winner. `survivors` entries keyed "h:<side>:<n>" (set-piece
-- units) or units the battle did not deploy are covered by their side's overall survival fraction.
local function applyOutcome(s: State, b: Battle, index: number, winnerSide: string, survivors: { [string]: Survivor }, reason: string)
	local loserSide = if winnerSide == "attackers" then "defenders" else "attackers"
	local unitSide: { [string]: string } = {}
	for _, a in Battles.armies(s, b) do
		local sd = sideOf(b, a.nation) :: string
		for _, u in a.units do
			unitSide[u.key] = sd
		end
	end
	local kept: { [string]: number } = { attackers = 0, defenders = 0 }
	local initial: { [string]: number } = { attackers = 0, defenders = 0 }
	for key, sv in survivors do
		local sd = unitSide[key]
		if sd == nil and string.sub(key, 1, 2) == "h:" then
			sd = if string.sub(key, 3, 11) == "attackers" then "attackers" elseif string.sub(key, 3, 11) == "defenders" then "defenders" else nil
		end
		if sd and State.isNum(sv.strength) and State.isNum(sv.initial) and (sv.initial :: number) > 0 then
			kept[sd] += if sv.destroyed then 0 else math.max(0, sv.strength)
			initial[sd] += sv.initial :: number
		end
	end
	local frac: { [string]: number } = {}
	for _, sd in { "attackers", "defenders" } do
		frac[sd] = if initial[sd] > 0 then math.clamp(kept[sd] / initial[sd], 0, 1) else 1
	end
	local destroyedArmy = false
	local honour = Battles.honourName(b)
	for _, a in Battles.armies(s, b) do
		local sd = sideOf(b, a.nation) :: string
		local honoured = 0
		for i = #a.units, 1, -1 do
			local u = a.units[i]
			local sv = survivors[u.key]
			local strength = u.strength
			if sv then
				strength = if sv.destroyed or not State.isNum(sv.strength) then 0 else math.floor(sv.strength)
				if State.isNum(sv.experience) then
					u.experience = math.clamp(math.floor(sv.experience), 0, 3)
				end
			else
				strength = math.floor(u.strength * frac[sd])
			end
			if strength < u.maxStrength * 0.15 then
				table.remove(a.units, i)
			else
				u.strength = math.min(strength, u.maxStrength)
				if sd == winnerSide then
					u.experience = math.min(3, u.experience + 1)
					State.addHonour(u, honour)
					honoured += 1
				end
			end
		end
		if honoured > 0 and a.nation == s.playerNation then -- chronicle only the player's own
			State.log(s, string.format("%s: %d unit%s carry the battle honour \"%s\".", a.name, honoured, if honoured == 1 then "" else "s", honour))
		end
	end
	local pname = State.province(b.provinceId).name
	for _, a in Battles.armies(s, b) do
		if #a.units == 0 then
			destroyedArmy = destroyedArmy or sideOf(b, a.nation) == loserSide
			State.removeArmy(s, a.id)
			State.log(s, string.format("%s was destroyed at %s%s.", a.name, pname, if a.general then "; " .. a.general.name .. " is taken" else ""))
		end
	end
	local winners = if winnerSide == "attackers" then b.attackers else b.defenders
	local losers = if winnerSide == "attackers" then b.defenders else b.attackers
	for _, w in winners do
		for _, l in losers do
			Diplomacy.addScore(s, w, l, Diplomacy.SCORE.battle + (if destroyedArmy then Diplomacy.SCORE.destroyed else 0))
		end
	end
	for _, a in Battles.armies(s, b, loserSide) do
		local dest = Movement.retreatTarget(s, a)
		if dest then
			a.provinceId = dest
			a.movesLeft = 0
		else
			State.removeArmy(s, a.id)
			State.log(s, string.format("%s had no line of retreat from %s and surrendered.", a.name, pname))
		end
	end
	table.remove(s.pendingBattles, index)
	local winnerNation = if winnerSide == "attackers" then b.attacker else b.defender
	s.appliedBattles[#s.appliedBattles + 1] = { battleId = b.battleId, winner = winnerNation, turn = b.turn }
	while #s.appliedBattles > State.APPLIED_MAX do
		table.remove(s.appliedBattles, 1)
	end
	if b.scenarioId then
		s.usedSetPieces[b.scenarioId] = true
	end
	State.log(s, string.format("Battle of %s: %s defeats %s (%s).", pname, State.nationName(winnerNation), State.nationName(if winnerSide == "attackers" then b.defender else b.attacker), reason))
end

-- "Austerlitz 1805": the set piece's name when there is one, else the province; year of the turn.
function Battles.honourName(b: Battle): string
	local year = EuropeData.StartYear + ((b.turn - 1) * 2) // 12
	local sp = if b.scenarioId then Scenarios.get(b.scenarioId) else nil
	if sp then
		return string.format("%s %d", string.match(sp.name, "^[^,]+") or sp.name, sp.year or year)
	end
	return string.format("%s %d", State.province(b.provinceId).name, year)
end

-- Side the human commands in the tactical battle (the attackers when the player is not there).
function Battles.playerSide(s: State, b: Battle): string
	return sideOf(b, s.playerNation) or "attackers"
end

function Battles.apply(s: State, battleId: string, results: Types.Results, survivors: { [string]: Survivor }): (boolean, string?)
	if Battles.isApplied(s, battleId) then
		return true, "alreadyApplied"
	end
	local b, index = Battles.pending(s, battleId)
	if not b then
		return false, "unknownBattle"
	end
	local ps = Battles.playerSide(s, b)
	local other = if ps == "attackers" then "defenders" else "attackers"
	local winner = if results.outcome == "victory" then ps elseif results.outcome == "defeat" then other else "defenders"
	applyOutcome(s, b, index, winner, survivors, tostring(results.reason))
	return true, nil
end

function Battles.autoResolve(s: State, battleId: string): (boolean, string?)
	if Battles.isApplied(s, battleId) then
		return true, "alreadyApplied"
	end
	local b, index = Battles.pending(s, battleId)
	if not b then
		return false, "unknownBattle"
	end
	local att = sideStrength(s, b, "attackers") ^ 1.5
	local def = sideStrength(s, b, "defenders") ^ 1.5
	local winner = if s.rng:float() < att / math.max(1, att + def) then "attackers" else "defenders"
	local loserLoss = 0.25 + s.rng:float() * 0.15
	local winnerLoss = 0.08 + s.rng:float() * 0.10
	local survivors: { [string]: Survivor } = {}
	for _, a in Battles.armies(s, b) do
		local loss = if sideOf(b, a.nation) == winner then winnerLoss else loserLoss
		for _, u in a.units do
			survivors[u.key] = { strength = math.floor(u.strength * (1 - loss)), experience = u.experience, initial = u.strength }
		end
	end
	applyOutcome(s, b, index, winner, survivors, "auto-resolved")
	return true, nil
end

-- The player's armies avoid the battle: 5 % stragglers, a little war score to the enemy, and the
-- rest of the battle (allies left behind) is auto-resolved.
function Battles.retreat(s: State, battleId: string, nation: string): (boolean, string?)
	local b, index = Battles.pending(s, battleId)
	if not b then
		return false, "unknownBattle"
	end
	local side = sideOf(b, nation)
	if not side then
		return false, "notInBattle"
	end
	local mine = State.armiesIn(s, b.provinceId, nation)
	local dests = {}
	for i, a in mine do
		dests[i] = Movement.retreatTarget(s, a)
		if not dests[i] then
			return false, "noLineOfRetreat"
		end
	end
	for i, a in mine do
		Economy.attrit(s, a, Battles.RETREAT_LOSS)
		a.provinceId = dests[i] :: string
		a.movesLeft = 0
	end
	Economy.removeEmpty(s)
	local enemy = if side == "attackers" then b.defender else b.attacker
	Diplomacy.addScore(s, enemy, nation, 3)
	State.log(s, string.format("%s refuses battle at %s and falls back.", State.nationName(nation), State.province(b.provinceId).name))
	local list = if side == "attackers" then b.attackers else b.defenders
	table.remove(list, table.find(list, nation) :: number)
	b.player = false
	if #Battles.armies(s, b, "attackers") > 0 and #Battles.armies(s, b, "defenders") > 0 then
		if #b.attackers > 0 and #b.defenders > 0 then
			b.attacker = if table.find(b.attackers, b.attacker) then b.attacker else b.attackers[1]
			b.defender = if table.find(b.defenders, b.defender) then b.defender else b.defenders[1]
		end
		return Battles.autoResolve(s, battleId)
	end
	table.remove(s.pendingBattles, index)
	s.appliedBattles[#s.appliedBattles + 1] = { battleId = battleId, winner = enemy, turn = b.turn }
	return true, nil
end

-- Sieges and occupation for provinces without a battle pending.
function Battles.sieges(s: State)
	local contested: { [string]: boolean } = {}
	for _, b in s.pendingBattles do
		contested[b.provinceId] = true
	end
	for _, pid in EuropeData.ProvinceIds do
		local ps = s.provinces[pid]
		local p = State.province(pid)
		local c = State.controller(s, pid)
		local here = State.armiesIn(s, pid)
		local besieger: string? = nil
		local defended = false
		for _, a in here do
			if State.atWar(s, a.nation, c) then
				besieger = besieger or a.nation
			elseif State.friendly(s, a.nation, c) then
				defended = true
			end
		end
		if ps.occupiedBy then
			ps.occupiedTurns += 1
		end
		if contested[pid] or defended or not besieger then
			if not besieger or defended then
				ps.siege = nil
			end
			continue
		end
		local by = besieger :: string
		if not ps.siege or ps.siege.by ~= by then
			ps.siege = { by = by, turnsLeft = State.fortLevel(s, p.id) + 1 }
		end
		local siege = ps.siege :: State.Siege
		siege.turnsLeft -= 1
		if siege.turnsLeft <= 0 then
			ps.siege = nil
			local wasOwner = ps.owner
			if ps.owner == by or State.friendly(s, ps.owner, by) then
				ps.occupiedBy = nil -- liberated
			else
				ps.occupiedBy = by
			end
			ps.occupiedTurns = 0
			Diplomacy.addScore(s, by, c, if p.isCapital then Diplomacy.SCORE.capital else Diplomacy.SCORE.province)
			if wasOwner ~= c and ps.occupiedBy == nil then
				State.log(s, string.format("%s liberates %s.", State.nationName(by), p.name))
			else
				State.log(s, string.format("%s %s %s.", State.nationName(by), if State.fortLevel(s, p.id) > 0 then "takes the fortress of" else "occupies", p.name))
			end
		end
	end
end

-- Tactical scenario ---------------------------------------------------------------------------------

local mapCache: { [string]: MapGen.MapData } = {}
local function mapFor(id: string): MapGen.MapData
	local m = mapCache[id]
	if not m then
		m = MapGen.generate(id)
		mapCache[id] = m
	end
	return m
end

local function sideName(s: State, nations: { string }): string
	local n = State.nationName(nations[1])
	return if #nations > 1 then n .. " & allies" else n
end

local function clampTo(z: MapGen.Rect, x: number, y: number): (number, number)
	local m = 30
	return math.clamp(x, z.x0 + m, z.x1 - m), math.clamp(y, z.z0 + m, z.z1 - m)
end

-- Battle map for a province: the province's own generated map (`"province:<id>"`, villages and
-- river named from EuropeData towns/river, landscape from `terrain`) once MapGen provides it
-- (`MapGen.provinceMaps`); until then the authored map named by `terrain`.
function Battles.mapId(p: EuropeData.Province): string
	return if (MapGen :: any).provinceMaps == true then "province:" .. p.id else p.terrain
end

-- Zone key (the map's deploy-zone faction id) used for each side.
function Battles.zoneKeys(s: State, b: Battle, map: MapGen.MapData): { [string]: string }
	local keys = State.sortedKeys(map.deployZones)
	local ps = Battles.playerSide(s, b)
	local order = { ps, if ps == "attackers" then "defenders" else "attackers" }
	local out: { [string]: string } = {}
	local taken: { [string]: boolean } = {}
	for _, side in order do
		for _, n in (if side == "attackers" then b.attackers else b.defenders) do
			if map.deployZones[n] and not taken[n] and not out[side] then
				out[side], taken[n] = n, true
			end
		end
	end
	for _, side in order do
		if not out[side] then
			for _, k in keys do
				if not taken[k] then
					out[side], taken[k] = k, true
					break
				end
			end
		end
	end
	return out
end

-- Moments whose selectors (and releases) still find a formation in `units`; the rest are dropped.
local function keptMoments(base: Scenarios.Scenario, units: { Scenarios.UnitDef }): { Moments.Moment }?
	if not base.moments then
		return nil
	end
	local function found(sel: Moments.Selector): boolean
		for _, u in units do
			if Moments.matches(sel, u :: any) then
				return true
			end
		end
		return false
	end
	local function condOk(c: Moments.Condition): boolean
		for _, sel in { c.formationRouted, c.strengthBelow, c.formationNear } do
			if sel and not found(sel) then
				return false
			end
		end
		for _, sub in c.all or {} do
			if not condOk(sub) then
				return false
			end
		end
		for _, sub in c.any or {} do
			if not condOk(sub) then
				return false
			end
		end
		return true
	end
	local out: { Moments.Moment } = {}
	for _, m in base.moments do
		local ok = condOk(m.when)
		local e = m.effect
		if ok and e then
			for _, sel in e.morale or {} do
				ok = ok and found(sel)
			end
			if e.release then
				local released = false
				for _, u in units do
					released = released or (u.arrival ~= nil and string.find(u.name, e.release :: string, 1, true) ~= nil)
				end
				ok = ok and released
			end
		end
		if ok then
			out[#out + 1] = table.clone(m)
		end
	end
	return out
end

local function setPieceScenario(s: State, b: Battle, base: Scenarios.Scenario): Scenarios.Scenario
	-- which campaign side plays which scenario faction
	local sp: EuropeData.SetPiece? = nil
	for _, x in EuropeData.SetPieces do
		if x.scenarioId == base.id then
			sp = x
			break
		end
	end
	local piece = sp :: EuropeData.SetPiece
	local spAttackerSide = if sideHas(s, b.attackers, piece.attacker) then "attackers" else "defenders"
	local factionSide: { [string]: string } = {}
	-- the scenario faction whose id is the set piece's attacker (or, failing that, its player faction)
	local fa = if base.factions.player == piece.attacker or base.factions.enemy ~= piece.attacker then base.factions.player else base.factions.enemy
	local fb = if fa == base.factions.player then base.factions.enemy else base.factions.player
	factionSide[fa] = spAttackerSide
	factionSide[fb] = if spAttackerSide == "attackers" then "defenders" else "attackers"
	local histMen: { [string]: number } = { attackers = 0, defenders = 0 }
	for _, d in base.units do
		if d.arrival == nil and d.class ~= "hq" then -- off-map reinforcements do not set the scale
			histMen[factionSide[d.faction]] += d.strength
		end
	end
	local ratio: { [string]: number } = {}
	for _, side in { "attackers", "defenders" } do
		local men = 0
		for _, a in Battles.armies(s, b, side) do
			men += State.men(a)
		end
		ratio[side] = math.clamp(men / math.max(1, histMen[side]), 0.5, 1.5)
	end
	local units: { Scenarios.UnitDef } = {}
	for i, d in base.units do
		local side = factionSide[d.faction]
		local u = table.clone(d)
		u.pos = { x = d.pos.x, z = d.pos.z }
		if d.arrival then
			u.arrival = { seconds = d.arrival.seconds, pos = { x = d.arrival.pos.x, z = d.arrival.pos.z } }
		end
		if d.class ~= "hq" and d.arrival == nil then
			u.strength = math.max(40, math.floor(d.strength * ratio[side]))
		end
		u.key = string.format("h:%s:%d", side, i)
		units[i] = u
	end
	local ps = Battles.playerSide(s, b)
	local playerFaction = if factionSide[base.factions.player] == ps then base.factions.player else base.factions.enemy
	local enemyFaction = if playerFaction == base.factions.player then base.factions.enemy else base.factions.player
	return {
		id = b.battleId,
		name = base.name,
		map = base.map,
		briefing = base.briefing .. string.format(" (Grand campaign, %s: the historical order of battle, scaled to the armies present.)", EuropeData.dateOf(s.turn)),
		factions = { player = playerFaction, enemy = enemyFaction },
		factionNames = base.factionNames,
		units = units,
		timeLimit = base.timeLimit,
		date = base.date,
		year = base.year,
		summary = base.summary,
		difficultyNote = base.difficultyNote,
		weather = base.weather,
		weatherUntil = base.weatherUntil,
		moments = keptMoments(base, units),
	}
end

type Placed = { u: Unit, a: Army }

function Battles.scenario(s: State, battleId: string): Scenarios.Scenario?
	local b = Battles.pending(s, battleId)
	if not b then
		return nil
	end
	local battle = b :: Battle
	if battle.scenarioId then
		local base = Scenarios.get(battle.scenarioId)
		if base then
			return setPieceScenario(s, battle, base)
		end
	end
	local p = State.province(battle.provinceId)
	local mapId = Battles.mapId(p)
	local map = mapFor(mapId)
	local zk = Battles.zoneKeys(s, battle, map)
	local units: { Scenarios.UnitDef } = {}
	local names: { [string]: string } = {}
	for _, side in { "attackers", "defenders" } do
		local key = zk[side]
		local otherKey = zk[if side == "attackers" then "defenders" else "attackers"]
		names[key] = sideName(s, if side == "attackers" then battle.attackers else battle.defenders)
		local zone = map.deployZones[key]
		local ez = map.deployZones[otherKey]
		local cx, cz = (zone.x0 + zone.x1) / 2, (zone.z0 + zone.z1) / 2
		local dx, dz = (ez.x0 + ez.x1) / 2 - cx, (ez.z0 + ez.z1) / 2 - cz
		local len = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
		dx, dz = dx / len, dz / len
		local heading = math.atan2(dz, dx)
		local px, pz = -dz, dx
		local all: { Placed } = {}
		local hqArmy: Army? = nil
		for _, a in Battles.armies(s, battle, side) do
			for _, u in a.units do
				all[#all + 1] = { u = u, a = a }
			end
			if a.general and (hqArmy == nil or (hqArmy :: Army).general == nil or (a.general :: State.General).rating > ((hqArmy :: Army).general :: State.General).rating) then
				hqArmy = a
			end
		end
		table.sort(all, function(x: Placed, y: Placed): boolean
			local px_, py_ = State.unitPower(x.u), State.unitPower(y.u)
			if px_ ~= py_ then
				return px_ > py_
			end
			return x.u.key < y.u.key
		end)
		local line: { Placed } = {}
		for i = 1, math.min(#all, Battles.MAX_UNITS_PER_SIDE) do
			line[i] = all[i]
		end
		local perRow = 8
		local rows = math.max(1, math.ceil(#line / perRow))
		for i, pair in line do
			local row = math.floor((i - 1) / perRow)
			local inRow = math.min(perRow, #line - row * perRow)
			local col = (i - 1) % perRow
			local along, back = (col - (inRow - 1) / 2) * 90, (row - (rows - 1) / 2) * 70
			local x, z = clampTo(zone, cx + px * along - dx * back, cz + pz * along - dz * back)
			local c = EuropeData.UnitClasses[pair.u.type]
			units[#units + 1] = {
				name = pair.u.name,
				class = c.class,
				type = c.sim,
				corps = pair.a.name,
				strength = pair.u.strength,
				experience = pair.u.experience,
				pos = { x = x, z = z },
				heading = heading,
				faction = key,
				colour = EuropeData.Nations[pair.a.nation].colour,
				key = pair.u.key,
			}
		end
		local leadNation = if side == "attackers" then battle.attacker else battle.defender
		local hq = hqArmy
		local x, z = clampTo(zone, cx - dx * (rows * 35 + 60), cz - dz * (rows * 35 + 60))
		units[#units + 1] = {
			name = if hq and hq.general then hq.general.name .. " — HQ" else State.nationName(leadNation) .. " — HQ",
			class = "hq",
			corps = if hq then hq.name else "HQ",
			strength = 120,
			experience = if hq and hq.general then math.min(3, hq.general.rating - 1) else 1,
			pos = { x = x, z = z },
			heading = heading,
			faction = key,
			colour = EuropeData.Nations[if hq then hq.nation else leadNation].colour,
			commander = true,
			key = "hq:" .. side,
		}
	end
	local ps = Battles.playerSide(s, battle)
	local enemySide = if ps == "attackers" then "defenders" else "attackers"
	return {
		id = battle.battleId,
		name = "Battle of " .. p.name,
		map = mapId,
		briefing = string.format("%s. %s attacks %s in %s. Break the enemy army or drive it from the field.", EuropeData.dateOf(s.turn), sideName(s, battle.attackers), sideName(s, battle.defenders), p.name),
		factions = { player = zk[ps], enemy = zk[enemySide] },
		factionNames = names,
		units = units,
		timeLimit = nil,
		date = EuropeData.dateOf(s.turn),
		year = EuropeData.StartYear + ((s.turn - 1) * 2) // 12,
	}
end

return Battles
