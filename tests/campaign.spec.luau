-- Campaign rules and persistence. Deterministic, no Roblox needed.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local CampaignData = require(Shared.CampaignData)
local Campaign = require(Server.Campaign)
local ProfileStore = require(Server.Persist.ProfileStore)
local MapGen = require(Shared.MapGen)
local Sim = require(Server.Sim)

local function deepEq(a, b, path)
	path = path or ""
	if type(a) ~= type(b) then
		return false, path .. ": " .. type(a) .. " vs " .. type(b)
	end
	if type(a) ~= "table" then
		return a == b, path .. ": " .. tostring(a) .. " vs " .. tostring(b)
	end
	for k, v in a do
		local ok, why = deepEq(v, b[k], path .. "." .. tostring(k))
		if not ok then
			return false, why
		end
	end
	for k in b do
		if a[k] == nil then
			return false, path .. "." .. tostring(k) .. " missing"
		end
	end
	return true
end

local function assertDeepEq(a, b, msg)
	local ok, why = deepEq(a, b)
	assertTrue(ok, (msg or "deepEq") .. ": " .. tostring(why))
end

local function army(state, id)
	for _, a in state.armies do
		if a.id == id then
			return a
		end
	end
	return nil
end

local function removeArmy(state, id)
	for i, a in state.armies do
		if a.id == id then
			table.remove(state.armies, i)
			return
		end
	end
end

local function results(outcome)
	return { outcome = outcome, reason = "test", clock = 0, objectives = {}, sides = {}, feedback = {}, log = {} }
end

-- Starting layout: army 1 (France, HQ) at kahla, 2 (France) at gera, 3 (Prussia, HQ) at jena, 4 (Prussia) at weimar.

test("Campaign: fresh map has 8 regions, symmetric adjacency, all reachable, authored start", function()
	local state = Campaign.new(1)
	assertEq(#CampaignData.Regions, 8)
	local byId = {}
	for _, r in CampaignData.Regions do
		byId[r.id] = r
	end
	for _, r in CampaignData.Regions do
		for _, adj in r.adjacent do
			assertTrue(byId[adj], r.id .. " -> unknown " .. adj)
			assertTrue(table.find(byId[adj].adjacent, r.id), adj .. " does not link back to " .. r.id)
		end
	end
	local seen, stack = {}, { CampaignData.Regions[1].id }
	while #stack > 0 do
		local id = table.remove(stack)
		if not seen[id] then
			seen[id] = true
			for _, adj in byId[id].adjacent do
				stack[#stack + 1] = adj
			end
		end
	end
	local n = 0
	for _ in seen do
		n += 1
	end
	assertEq(n, 8, "every region reachable")
	local france, prussia = 0, 0
	for _, r in CampaignData.Regions do
		assertEq(state.owners[r.id], r.owner, r.id)
		if r.owner == "france" then
			france += 1
		else
			prussia += 1
		end
	end
	assertEq(france, 3)
	assertEq(prussia, 5)
	assertEq(state.factions.france.treasury, CampaignData.Economy.StartTreasury.france)
	assertEq(#state.armies, 4)
	assertEq(state.turn, 1)
	assertEq(state.phase, "player")
	local v = Campaign.view(state)
	assertEq(#v.regions, 8)
	assertEq(v.treasury, 800)
	assertTrue(v.victory == nil and v.pendingBattle == nil)
end)

test("Campaign: move rules (adjacent, own army, once per turn)", function()
	local state = Campaign.new(2)
	local ok, why = Campaign.command(state, { kind = "move", armyId = 1, regionId = "weimar" })
	assertTrue(not ok and why == "notAdjacent", "kahla-weimar not adjacent")
	ok, why = Campaign.command(state, { kind = "move", armyId = 3, regionId = "kahla" })
	assertTrue(not ok and why == "notYourArmy")
	ok, why = Campaign.command(state, { kind = "move", armyId = 99, regionId = "kahla" })
	assertTrue(not ok and why == "notYourArmy")
	assertTrue(Campaign.command(state, { kind = "move", armyId = 1, regionId = "jena" }))
	assertEq(army(state, 1).regionId, "jena")
	ok, why = Campaign.command(state, { kind = "move", armyId = 1, regionId = "kahla" })
	assertTrue(not ok and why == "alreadyMoved")
end)

test("Campaign: contacts produce one battle per army in stable region order; no army in two regions", function()
	local state = Campaign.new(3)
	army(state, 4).regionId = "gera" -- Prussian stack inside French-owned Gera (with French army 2)
	assertTrue(Campaign.command(state, { kind = "move", armyId = 1, regionId = "jena" }))
	local _, battles = Campaign.endTurn(state)
	assertEq(#battles, 2)
	assertEq(battles[1].regionId, "gera", "lowest region id first")
	assertEq(battles[2].regionId, "jena")
	assertEq(battles[1].attacker, "prussia")
	assertEq(battles[1].defender, "france")
	assertEq(battles[2].attacker, "france")
	assertTrue(battles[1].battleId ~= battles[2].battleId)
	assertEq(state.phase, "battle")
	local count = {}
	for _, r in Campaign.view(state).regions do
		for _, id in r.armies do
			count[id] = (count[id] or 0) + 1
		end
	end
	for _, a in state.armies do
		assertEq(count[a.id], 1, "army " .. a.id .. " in exactly one region")
	end
	assertTrue(not Campaign.command(state, { kind = "move", armyId = 2, regionId = "kahla" }), "no commands in battle phase")
end)

test("Campaign: empty enemy region is occupied at end of turn", function()
	local state = Campaign.new(4)
	assertTrue(Campaign.command(state, { kind = "move", armyId = 2, regionId = "naumburg" }))
	Campaign.endTurn(state)
	assertEq(state.owners.naumburg, "france")
	assertEq(state.phase, "player")
	assertEq(state.turn, 2)
	assertEq(army(state, 2).movesLeft, 1, "moves reset")
end)

test("Campaign: battle scenario carries keys; result applies once; survivors reconcile; retreat; experience cap", function()
	local state = Campaign.new(5)
	army(state, 1).units[2].experience = 3
	assertTrue(Campaign.command(state, { kind = "move", armyId = 1, regionId = "jena" }))
	local _, battles = Campaign.endTurn(state)
	assertEq(#battles, 1)
	local id = battles[1].battleId
	local sc = Campaign.battleScenario(state, id)
	assertEq(sc.map, "jena")
	assertEq(#sc.units, #army(state, 1).units + #army(state, 3).units)
	local keys = {}
	for _, u in sc.units do
		assertTrue(type(u.key) == "string" and not keys[u.key], "unique key")
		keys[u.key] = true
		assertTrue(u.pos.x >= 0 and u.pos.x <= 1600 and u.pos.z >= 0 and u.pos.z <= 1200, "inside map")
	end
	assertTrue(string.find(sc.briefing, "Jena", 1, true) and string.find(sc.briefing, "France attacks", 1, true), "briefing names region and attacker")
	local map = MapGen.generate(sc.map)
	for _, u in sc.units do
		assertTrue(MapGen.inZone(map, u.faction, u.pos), u.name .. " inside its deployment zone")
	end
	local sim = Sim.new({ matchId = id, scenario = sc, map = map, seed = 1 })
	assertEq(#sim.order, #sc.units, "the Sim builds one formation per campaign unit")
	assertEq(sim.formations[1].experience, sc.units[1].experience)
	assertEq(sim.formations[3].name, sc.units[3].name, "formation id i is scenario.units[i], whose key is the campaign unit")
	local survivors = {}
	for _, u in army(state, 1).units do
		survivors[u.key] = { strength = 500, experience = u.experience }
	end
	local pUnits = table.clone(army(state, 3).units)
	survivors[pUnits[2].key] = { strength = 0, experience = 1, destroyed = true }
	local destroyedKey = pUnits[2].key
	local thirdExp = pUnits[3].experience
	for i = 3, #pUnits do
		survivors[pUnits[i].key] = { strength = 300, experience = pUnits[i].experience }
	end
	local ok, why = Campaign.applyBattleResult(state, id, results("victory"), survivors)
	assertTrue(ok and why == nil, tostring(why))
	assertEq(state.owners.jena, "france")
	assertEq(state.phase, "player")
	local a1 = army(state, 1)
	assertEq(a1.regionId, "jena")
	assertEq(a1.units[1].strength, 40, "clamped to max strength")
	assertEq(a1.units[2].strength, 500)
	assertEq(a1.units[2].experience, 3, "capped at 3")
	assertEq(a1.units[3].experience, 2, "+1 for the winner")
	local a3 = army(state, 3)
	assertEq(a3.regionId, "apolda", "loser retreats to lowest adjacent friendly region")
	assertEq(#a3.units, #pUnits - 1)
	for _, u in a3.units do
		assertTrue(u.key ~= destroyedKey, "destroyed unit removed")
	end
	assertEq(a3.units[1].strength, 40, "unit missing from survivors is unchanged (HQ)")
	assertEq(a3.units[2].strength, 300)
	assertEq(a3.units[2].experience, thirdExp, "loser gains no experience")
	local before = Campaign.serialize(state)
	ok, why = Campaign.applyBattleResult(state, id, results("defeat"), {})
	assertTrue(ok and why == "alreadyApplied")
	assertDeepEq(Campaign.serialize(state), before, "second apply changes nothing")
	assertTrue(not Campaign.applyBattleResult(state, "nope", results("victory"), {}))
end)

test("Campaign: loser with no line of retreat is destroyed; defender wins a draw", function()
	local state = Campaign.new(6)
	removeArmy(state, 4)
	state.owners.apolda = "france"
	state.owners.weimar = "france"
	assertTrue(Campaign.command(state, { kind = "move", armyId = 1, regionId = "jena" }))
	local _, battles = Campaign.endTurn(state)
	assertEq(#battles, 1)
	assertTrue(Campaign.applyBattleResult(state, battles[1].battleId, results("victory"), {}))
	assertTrue(army(state, 3) == nil, "Prussian army destroyed")
	assertEq(state.owners.jena, "france")

	local s2 = Campaign.new(6)
	assertTrue(Campaign.command(s2, { kind = "move", armyId = 1, regionId = "jena" }))
	local _, b2 = Campaign.endTurn(s2)
	assertTrue(Campaign.applyBattleResult(s2, b2[1].battleId, results("draw"), {}))
	assertEq(s2.owners.jena, "prussia", "defender keeps the region on a draw")
	assertEq(army(s2, 1).regionId, "gera", "attacker falls back to the lowest-id friendly region")
end)

test("Campaign: auto-resolve is deterministic and leaves the state consistent", function()
	local function run()
		local s = Campaign.new(7)
		Campaign.command(s, { kind = "move", armyId = 1, regionId = "jena" })
		local _, b = Campaign.endTurn(s)
		assertTrue(Campaign.autoResolve(s, b[1].battleId))
		local ok, why = Campaign.autoResolve(s, b[1].battleId)
		assertTrue(ok and why == "alreadyApplied")
		return s
	end
	local a, b = run(), run()
	assertDeepEq(Campaign.serialize(a), Campaign.serialize(b))
	assertEq(a.phase, "player")
	for _, ar in a.armies do
		for _, u in ar.units do
			assertTrue(u.strength > 0 and u.strength <= u.maxStrength)
		end
	end
	assertEq(#a.pendingBattles, 0)
	assertEq(#a.appliedBattles, 1)
end)

test("Campaign: recruitment costs treasury, completes after N turns, cannot overdraw", function()
	local state = Campaign.new(8)
	local line = CampaignData.UnitTypes.line
	assertTrue(Campaign.command(state, { kind = "recruit", regionId = "kahla", unitType = "line" }))
	assertEq(state.factions.france.treasury, 800 - line.cost)
	local ok, why = Campaign.command(state, { kind = "recruit", regionId = "kahla", unitType = "cavalry" })
	assertTrue(not ok and why == "insufficientFunds")
	ok, why = Campaign.command(state, { kind = "recruit", regionId = "jena", unitType = "line" })
	assertTrue(not ok and why == "notYourRegion")
	assertTrue(Campaign.command(state, { kind = "recruit", regionId = "kahla", unitType = "line" }))
	ok, why = Campaign.command(state, { kind = "recruit", regionId = "kahla", unitType = "line" })
	assertTrue(not ok and why == "insufficientFunds", "third duplicate rejected")
	assertEq(state.factions.france.treasury, 0, "never negative")
	local v = Campaign.view(state)
	assertEq(#v.recruitment, 2)
	assertEq(v.recruitment[1].turnsLeft, line.turns)
	local before = #army(state, 1).units
	for _ = 1, line.turns do
		Campaign.endTurn(state)
		assertEq(state.phase, "player")
	end
	assertEq(#army(state, 1).units, before + 2, "recruits join the army in the region")
	local last = army(state, 1).units[#army(state, 1).units]
	assertEq(last.type, "line")
	assertEq(last.strength, line.strength)
	assertEq(last.experience, 0)
end)

test("Campaign: replenishment never exceeds max strength and consumes treasury + manpower", function()
	local state = Campaign.new(9)
	local a = army(state, 1)
	a.units[2].strength = 100
	assertTrue(Campaign.command(state, { kind = "replenish", armyId = 1 }))
	assertEq(a.units[2].strength, 600)
	assertEq(state.factions.france.treasury, 800 - 500 * CampaignData.Economy.ReplenishCostPerMan)
	assertEq(state.factions.france.manpower, 600 - 500)
	local ok, why = Campaign.command(state, { kind = "replenish", armyId = 1 })
	assertTrue(not ok and why == "nothingToReplenish")
	-- bounded by manpower
	a.units[2].strength = 100
	state.factions.france.manpower = 50
	assertTrue(Campaign.command(state, { kind = "replenish", armyId = 1 }))
	assertEq(a.units[2].strength, 150)
	assertEq(state.factions.france.manpower, 0)
end)

test("Campaign: upkeep shortage lowers supply, then attrition at supply 0", function()
	local state = Campaign.new(10)
	state.factions.france.treasury = 0
	Campaign.endTurn(state)
	assertEq(state.factions.france.supply, 100 - CampaignData.Economy.SupplyShortage)
	assertTrue(state.factions.france.treasury >= 0)
	state.factions.france.treasury = 0
	state.factions.france.supply = CampaignData.Economy.SupplyShortage
	Campaign.endTurn(state)
	assertEq(state.factions.france.supply, 0)
	assertEq(army(state, 1).units[2].strength, math.floor(600 * (1 - CampaignData.Economy.AttritionFraction)))
	assertEq(army(state, 1).supplied, false)
	-- paying again recovers
	state.factions.france.treasury = 5000
	Campaign.endTurn(state)
	assertEq(state.factions.france.supply, CampaignData.Economy.SupplyRecovery)
	assertEq(army(state, 1).supplied, true)
end)

test("Campaign: victory and defeat are both reachable", function()
	local state = Campaign.new(11)
	assertTrue(Campaign.victory(state) == nil)
	removeArmy(state, 3)
	removeArmy(state, 4)
	for _, id in CampaignData.Victory.Objectives do
		state.owners[id] = "france"
	end
	local v = Campaign.victory(state)
	assertTrue(v and v.outcome == "victory", "objectives + army => victory")
	Campaign.endTurn(state)
	assertEq(state.phase, "ended")
	assertEq(Campaign.view(state).victory.outcome, "victory")
	assertTrue(not Campaign.command(state, { kind = "endTurn" }), "no play after the end")

	local d = Campaign.new(11)
	d.turn = CampaignData.Victory.TurnLimit + 1
	assertEq(Campaign.victory(d).outcome, "defeat")

	local d2 = Campaign.new(11)
	d2.armies = {}
	d2.factions.france.treasury = 0
	assertEq(Campaign.victory(d2).outcome, "defeat")

	local d3 = Campaign.new(11)
	for id in d3.owners do
		d3.owners[id] = "prussia"
	end
	assertEq(Campaign.victory(d3).outcome, "defeat")

	assertTrue(Campaign.command(state, { kind = "restart" }))
	assertEq(state.turn, 1)
	assertEq(state.phase, "player")
	assertTrue(state.victory == nil)
	assertEq(#state.armies, 4)
end)

test("Campaign: serialize round-trips, rejects invalid profiles, continues deterministically", function()
	local a = Campaign.new(12)
	Campaign.command(a, { kind = "recruit", regionId = "gera", unitType = "cavalry" })
	Campaign.command(a, { kind = "move", armyId = 1, regionId = "jena" })
	Campaign.endTurn(a)
	local p = Campaign.serialize(a)
	assertEq(p.version, 1)
	assertTrue(type(p.rngState) == "number")
	local b = Campaign.deserialize(p)
	assertTrue(b ~= nil)
	assertDeepEq(Campaign.serialize(b), p, "round trip")
	assertTrue(Campaign.deserialize(nil) == nil)
	assertTrue(Campaign.deserialize({}) == nil)
	assertTrue(Campaign.deserialize({ version = 1, revision = 0 }) == nil, "lock-only profile is not a campaign")
	local bad = Campaign.serialize(a)
	bad.owners.jena = "austria"
	assertTrue(Campaign.deserialize(bad) == nil)
	bad = Campaign.serialize(a)
	bad.armies[1].units[1].strength = 10000
	assertTrue(Campaign.deserialize(bad) == nil)
	bad = Campaign.serialize(a)
	bad.version = 2
	assertTrue(Campaign.deserialize(bad) == nil)
	-- same seed, same AI turn, whether or not the state went through a profile
	local pending = a.pendingBattles[1].battleId
	assertTrue(Campaign.autoResolve(a, pending))
	assertTrue(Campaign.autoResolve(b, pending))
	Campaign.endTurn(a)
	Campaign.endTurn(b)
	assertDeepEq(Campaign.serialize(a), Campaign.serialize(b), "deterministic continuation")
	local c = Campaign.new(12)
	Campaign.command(c, { kind = "recruit", regionId = "gera", unitType = "cavalry" })
	Campaign.command(c, { kind = "move", armyId = 1, regionId = "jena" })
	Campaign.endTurn(c)
	assertDeepEq(Campaign.serialize(c), p, "same seed, same turn")
end)

test("ProfileStore: memory adapter is sessionOnly; update creates, bumps revision, rejects stale", function()
	local store = ProfileStore.new({ name = "eoe", scope = "dev", sleep = function() end })
	assertEq(store.sessionOnly, true)
	local p, status = store:load(1)
	assertTrue(p == nil and status == "empty")
	local ok, np = store:update(1, 0, function(old)
		assertTrue(old == nil)
		return { version = 1, revision = 0, x = 1 }
	end)
	assertTrue(ok)
	assertEq(np.revision, 1)
	p, status = store:load(1)
	assertEq(status, "ok")
	assertEq(p.x, 1)
	local ok2, _, why = store:update(1, 0, function(old)
		return old
	end)
	assertTrue(not ok2 and why == "stale")
	local ok3, np3 = store:update(1, 1, function(old)
		old.x = 2
		return old
	end)
	assertTrue(ok3 and np3.revision == 2 and np3.x == 2)
	local ok4, seen, why4 = store:update(1, nil, function(old)
		return nil, "cancelled"
	end)
	assertTrue(not ok4 and why4 == "cancelled" and seen.x == 2)
	assertEq(store:load(1).revision, 2, "cancelled update writes nothing")
	local ok5, _, why5 = store:update(2, nil, function()
		return { version = 1, revision = 0, fn = function() end }
	end)
	assertTrue(not ok5 and why5 == "error", "unserialisable profile rejected")
end)

test("ProfileStore: session claim with timeout", function()
	local store = ProfileStore.new({ name = "eoe", scope = "dev", sleep = function() end, sessionTimeout = 300 })
	assertTrue(store:claimSession(1, "s1", 100))
	local ok, why = store:claimSession(1, "s2", 200)
	assertTrue(not ok and why == "locked")
	assertTrue(store:claimSession(1, "s1", 250), "owner may renew")
	assertTrue(store:claimSession(1, "s2", 600), "expired lock can be taken")
	ok, why = store:releaseSession(1, "s1")
	assertTrue(not ok and why == "notOwner")
	assertTrue(store:releaseSession(1, "s2"))
	assertTrue(store:load(1).session == nil)
end)

test("ProfileStore: read errors report 'error' and never write defaults; throttling retries with backoff", function()
	local data = {}
	local failing = true
	local calls, sleeps = 0, {}
	local ds = {
		GetAsync = function(_, k)
			calls += 1
			if failing then
				error("503 Service Unavailable")
			end
			return data[k]
		end,
		UpdateAsync = function(_, k, fn)
			calls += 1
			if failing then
				error("throttled")
			end
			local new = fn(data[k])
			if new ~= nil then
				data[k] = new
			end
			return new
		end,
	}
	local svc = { GetDataStore = function()
		return ds
	end }
	local store = ProfileStore.new({ name = "eoe", scope = "live", dataStoreService = svc, sleep = function(t)
		sleeps[#sleeps + 1] = t
	end, maxRetries = 2, backoff = 1 })
	assertEq(store.sessionOnly, false)
	data.u1 = { version = 1, revision = 5, campaign = "precious" }
	local p, status = store:load(1)
	assertTrue(p == nil and status == "error")
	assertEq(calls, 3, "1 try + 2 retries")
	assertEq(#sleeps, 2)
	assertTrue(sleeps[2] > sleeps[1], "backoff grows")
	local ok, _, why = store:update(1, nil, function(old)
		return { version = 1, revision = 0 }
	end)
	assertTrue(not ok and why == "error")
	assertEq(data.u1.campaign, "precious", "stored profile untouched after failures")
	failing = false
	p, status = store:load(1)
	assertTrue(status == "ok" and p.campaign == "precious")
	local broken = ProfileStore.new({ name = "eoe", scope = "live", dataStoreService = { GetDataStore = function()
		error("no datastore")
	end } })
	assertEq(broken.sessionOnly, true, "GetDataStore failure falls back to memory")
end)

test("Campaign: checkpoint + commitBattle are atomic, idempotent, and reject stale sessions/revisions", function()
	local store = ProfileStore.new({ name = "eoe", scope = "dev", sleep = function() end })
	assertTrue(store:claimSession(7, "s1", 0))
	local profile = store:load(7)
	local state = Campaign.new(13)
	state.revision = profile.revision
	assertTrue(Campaign.checkpoint(store, 7, "s1", state))
	assertEq(state.revision, 2)
	assertTrue(Campaign.command(state, { kind = "move", armyId = 1, regionId = "jena" }))
	local _, battles = Campaign.endTurn(state)
	local id = battles[1].battleId
	assertTrue(Campaign.checkpoint(store, 7, "s1", state), "pre-battle checkpoint")
	local stored = Campaign.deserialize(store:load(7))
	assertEq(stored.phase, "battle")
	assertEq(stored.pendingBattles[1].battleId, id)
	local survivors = {}
	for _, u in army(state, 3).units do
		survivors[u.key] = { strength = 200, experience = u.experience }
	end
	local ok, newState, why = Campaign.commitBattle(store, 7, "s1", state, id, results("victory"), survivors)
	assertTrue(ok and why == nil, tostring(why))
	assertEq(newState.owners.jena, "france")
	assertEq(newState.phase, "player")
	assertEq(newState.revision, state.revision + 1)
	assertEq(store:load(7).session.id, "s1", "session preserved")
	-- retried request with the stale in-memory state returns the committed outcome, changes nothing
	local before = store:load(7)
	local ok2, again, why2 = Campaign.commitBattle(store, 7, "s1", state, id, results("defeat"), {})
	assertTrue(ok2 and why2 == "alreadyApplied")
	assertEq(again.owners.jena, "france")
	assertDeepEq(store:load(7), before)
	-- a stale session cannot write
	local ok3, _, why3 = Campaign.commitBattle(store, 7, "s2", newState, id, results("victory"), {})
	assertTrue(not ok3 and why3 == "notOwner")
	local ok4, why4 = Campaign.checkpoint(store, 7, "s2", newState)
	assertTrue(not ok4 and why4 == "notOwner")
	-- stale revision: someone else moved the profile on
	local ok5, why5 = Campaign.checkpoint(store, 7, "s1", state)
	assertTrue(not ok5 and why5 == "stale")
	-- unknown battle on the stored profile
	local ok6, _, why6 = Campaign.commitBattle(store, 7, "s1", newState, "ghost", results("victory"), {})
	assertTrue(not ok6 and why6 == "unknownBattle")
	assertTrue(store:releaseSession(7, "s1"))
end)

test("Campaign: full loop of auto-resolved turns ends in victory or defeat", function()
	local state = Campaign.new(14)
	local iterations = 0
	while Campaign.victory(state) == nil and iterations < 200 do
		iterations += 1
		if state.phase == "battle" then
			local ids = {}
			for _, b in state.pendingBattles do
				ids[#ids + 1] = b.battleId
			end
			for _, id in ids do
				assertTrue(Campaign.battleScenario(state, id) ~= nil)
				assertTrue(Campaign.autoResolve(state, id))
			end
		else
			for _, a in table.clone(state.armies) do
				if a.faction == "france" and a.movesLeft > 0 then
					local adj = table.clone(CampaignData.region(a.regionId).adjacent)
					table.sort(adj)
					for _, id in adj do
						if state.owners[id] == "prussia" then
							Campaign.command(state, { kind = "move", armyId = a.id, regionId = id })
							break
						end
					end
				end
			end
			Campaign.command(state, { kind = "recruit", regionId = "kahla", unitType = "line" })
			assertTrue(Campaign.command(state, { kind = "endTurn" }))
		end
		local count = {}
		for _, r in Campaign.view(state).regions do
			for _, id in r.armies do
				count[id] = (count[id] or 0) + 1
				assertEq(count[id], 1)
			end
		end
	end
	local v = Campaign.victory(state)
	assertTrue(v ~= nil, "campaign ended")
	assertTrue(v.outcome == "victory" or v.outcome == "defeat")
	assertEq(state.phase, "ended")
	assertTrue(state.turn <= CampaignData.Victory.TurnLimit + 1)
	assertTrue(Campaign.deserialize(Campaign.serialize(state)) ~= nil, "final state serializable")
	assertTrue(#Campaign.view(state).log <= 20)
end)
