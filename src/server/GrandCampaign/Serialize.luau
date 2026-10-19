--!strict
-- Profile format for the grand campaign (DataStore-safe: string keys, arrays, finite numbers).
-- `deserialize` validates everything it reads and returns nil rather than a half-valid state.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local RNG = require(Shared.RNG)
local EuropeData = require(Shared.EuropeData)
local State = require(script.Parent.State)

type State = State.State

local Serialize = {}

Serialize.VERSION = 1

local FIELDS = { "provinces", "nations", "relations", "wars", "alliances", "truces", "peaces", "armies", "recruitment", "flags", "fired", "inbox", "offers", "counters", "log", "pendingBattles", "appliedBattles", "usedSetPieces" }

function Serialize.serialize(s: State): { [string]: any }
	local p: { [string]: any } = {
		version = Serialize.VERSION,
		kind = "grand",
		revision = s.revision,
		campaignId = s.campaignId,
		seed = s.seed,
		rngState = s.rng.state,
		turn = s.turn,
		phase = s.phase,
		playerNation = s.playerNation,
		abdicatedTo = State.copy(s.abdicatedTo),
		victory = State.copy(s.victory),
		nextId = s.nextId,
	}
	for _, f in FIELDS do
		p[f] = State.copy((s :: any)[f])
	end
	return p
end

local isNum = State.isNum
local function isStr(v: any): boolean
	return type(v) == "string" and #v <= 200
end
local function nationOk(v: any): boolean
	return type(v) == "string" and EuropeData.Nations[v] ~= nil
end
local function provinceOk(v: any): boolean
	return type(v) == "string" and EuropeData.province(v) ~= nil
end

local function validArmy(a: any): boolean
	if type(a) ~= "table" or not isStr(a.id) or not nationOk(a.nation) or not isStr(a.name) or not provinceOk(a.provinceId) or not isNum(a.movesLeft) or type(a.units) ~= "table" or #a.units > State.MAX_UNITS then
		return false
	end
	if a.general ~= nil and (type(a.general) ~= "table" or not isStr(a.general.name) or not isNum(a.general.rating)) then
		return false
	end
	if a.forced ~= nil and type(a.forced) ~= "boolean" then
		return false
	end
	if a.path ~= nil then
		if type(a.path) ~= "table" or #a.path > 8 then
			return false
		end
		for _, id in a.path do
			if not provinceOk(id) then
				return false
			end
		end
	end
	for _, u in a.units do
		if type(u) ~= "table" or not isStr(u.key) or EuropeData.UnitClasses[u.type] == nil or not isStr(u.name) or not isNum(u.strength) or not isNum(u.maxStrength) or not isNum(u.experience) then
			return false
		end
		if u.strength < 0 or u.strength > u.maxStrength or u.experience < 0 or u.experience > 3 then
			return false
		end
		if u.honours ~= nil then
			if type(u.honours) ~= "table" or #u.honours > State.MAX_HONOURS then
				return false
			end
			local n = 0
			for _, h in u.honours do
				n += 1
				if type(h) ~= "string" or #h > State.HONOUR_LEN or n > State.MAX_HONOURS then
					return false
				end
			end
		end
	end
	return true
end

local function validBattle(b: any): boolean
	if type(b) ~= "table" or not isStr(b.battleId) or not provinceOk(b.provinceId) or not isNum(b.turn) or not nationOk(b.attacker) or not nationOk(b.defender) or type(b.player) ~= "boolean" then
		return false
	end
	if type(b.attackers) ~= "table" or type(b.defenders) ~= "table" or (b.scenarioId ~= nil and not isStr(b.scenarioId)) then
		return false
	end
	local r = b.reinforcements
	if r ~= nil then
		if type(r) ~= "table" or type(r.attackers) ~= "table" or type(r.defenders) ~= "table" then
			return false
		end
		for _, side in { r.attackers, r.defenders } do
			for _, id in side do
				if not isStr(id) then
					return false
				end
			end
		end
	end
	for _, n in b.attackers do
		if not nationOk(n) then
			return false
		end
	end
	for _, n in b.defenders do
		if not nationOk(n) then
			return false
		end
	end
	return true
end

function Serialize.deserialize(p: any): State?
	if type(p) ~= "table" or p.version ~= Serialize.VERSION or p.kind ~= "grand" or not isStr(p.campaignId) or not isNum(p.seed) or not isNum(p.rngState) or not isNum(p.turn) or not isNum(p.nextId) then
		return nil
	end
	if p.phase ~= "player" and p.phase ~= "battle" and p.phase ~= "ended" then
		return nil
	end
	if not nationOk(p.playerNation) or not EuropeData.Nations[p.playerNation].playable then
		return nil
	end
	for _, f in FIELDS do
		if type(p[f]) ~= "table" then
			return nil
		end
	end
	for _, id in EuropeData.ProvinceIds do
		local ps = p.provinces[id]
		if type(ps) ~= "table" or not nationOk(ps.owner) or (ps.occupiedBy ~= nil and not nationOk(ps.occupiedBy)) or not isNum(ps.occupiedTurns) then
			return nil
		end
		if ps.siege ~= nil and (type(ps.siege) ~= "table" or not nationOk(ps.siege.by) or not isNum(ps.siege.turnsLeft)) then
			return nil
		end
		if ps.buildings == nil then
			ps.buildings = EuropeData.startBuildings(State.province(id)) -- a save from before buildings
		elseif type(ps.buildings) ~= "table" then
			return nil
		else
			for chain, level in ps.buildings do
				if EuropeData.Buildings[chain] == nil or not isNum(level) or level < 0 or level > EuropeData.BuildingMax then
					return nil
				end
			end
		end
		local c = ps.construction
		if c ~= nil and (type(c) ~= "table" or EuropeData.Buildings[c.chain] == nil or not isNum(c.turnsLeft)) then
			return nil
		end
		if (ps.unrestTurns ~= nil and not isNum(ps.unrestTurns)) or (ps.revolt ~= nil and type(ps.revolt) ~= "boolean") then
			return nil
		end
	end
	for _, id in EuropeData.NationOrder do
		local ns = p.nations[id]
		if type(ns) ~= "table" or not isNum(ns.treasury) or not isNum(ns.manpower) then
			return nil
		end
		if ns.tax ~= nil and (not isNum(ns.tax) or ns.tax < 1 or ns.tax > 4 or ns.tax ~= math.floor(ns.tax)) then
			return nil
		end
		if ns.techs == nil then
			-- a save from before technology: what the nation knew in 1805
			ns.techs = {}
			for _, t in EuropeData.StartTechs[id] or {} do
				ns.techs[t] = true
			end
		elseif type(ns.techs) ~= "table" then
			return nil
		else
			for t, v in ns.techs do
				if EuropeData.TechById[t] == nil or v ~= true then
					return nil
				end
			end
		end
		if (ns.research ~= nil and EuropeData.TechById[ns.research] == nil) or (ns.progress ~= nil and not isNum(ns.progress)) then
			return nil
		end
	end
	for _, w in p.wars do
		if type(w) ~= "table" or not nationOk(w.a) or not nationOk(w.b) or not isNum(w.score) or not isNum(w.since) then
			return nil
		end
	end
	for _, v in p.relations do
		if not isNum(v) then
			return nil
		end
	end
	for _, v in p.truces do
		if not isNum(v) then
			return nil
		end
	end
	for _, pe in p.peaces do
		if type(pe) ~= "table" or type(pe.winner) ~= "string" or type(pe.dictated) ~= "boolean" or not isNum(pe.turn) then
			return nil
		end
	end
	if #p.armies > State.MAX_ARMIES * #EuropeData.NationOrder or #p.recruitment > 200 or #p.pendingBattles > #EuropeData.Provinces or #p.appliedBattles > State.APPLIED_MAX or #p.log > State.LOG_MAX * 2 then
		return nil
	end
	for _, a in p.armies do
		if not validArmy(a) then
			return nil
		end
	end
	for _, q in p.recruitment do
		if type(q) ~= "table" or not nationOk(q.nation) or not provinceOk(q.provinceId) or EuropeData.UnitClasses[q.unitType] == nil or not isNum(q.turnsLeft) then
			return nil
		end
	end
	for _, b in p.pendingBattles do
		if not validBattle(b) then
			return nil
		end
	end
	for _, b in p.appliedBattles do
		if type(b) ~= "table" or not isStr(b.battleId) or type(b.winner) ~= "string" or not isNum(b.turn) then
			return nil
		end
	end
	for _, o in p.offers do
		if type(o) ~= "table" or not isStr(o.id) or not nationOk(o.from) or not nationOk(o.to) or not isStr(o.kind) or type(o.terms) ~= "table" or not isNum(o.turn) then
			return nil
		end
	end
	for _, e in p.inbox do
		if type(e) ~= "table" or not isStr(e.id) or type(e.title) ~= "string" or type(e.text) ~= "string" or not isNum(e.turn) then
			return nil
		end
	end
	for _, l in p.log do
		if type(l) ~= "string" then
			return nil
		end
	end
	local v = p.victory
	if v ~= nil and (type(v) ~= "table" or (v.outcome ~= "victory" and v.outcome ~= "defeat" and v.outcome ~= "draw") or type(v.reason) ~= "string") then
		return nil
	end
	if p.abdicatedTo ~= nil and type(p.abdicatedTo) ~= "table" then
		return nil
	end
	local s: any = {
		campaignId = p.campaignId,
		seed = p.seed,
		revision = if isNum(p.revision) then p.revision else 0,
		rng = RNG.fromState(p.rngState),
		turn = p.turn,
		phase = p.phase,
		playerNation = p.playerNation,
		abdicatedTo = State.copy(p.abdicatedTo),
		victory = State.copy(p.victory),
		nextId = p.nextId,
	}
	for _, f in FIELDS do
		s[f] = State.copy(p[f])
	end
	return s :: State
end

return Serialize
