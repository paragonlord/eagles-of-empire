-- AI-vs-AI balance driver. Bundled by tools/balance.py as a test with the jobs table substituted
-- (a Luau table of { scenario, difficulty, seed, minutes }); prints one "BAL\t..." line per run.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local Config = require(Shared.Config)
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)
local Sim = require(Server.Sim)
local AI = require(Server.AI)

local JOBS = __JOBS__

local maps = {}
local function mapFor(id)
	if not maps[id] then
		maps[id] = MapGen.generate(id)
	end
	return maps[id]
end

local function play(job)
	local sc = assert(Scenarios.get(job.scenario), "no scenario " .. job.scenario)
	local sim = Sim.new({ matchId = "b", scenario = sc, map = mapFor(sc.map), seed = job.seed, difficulty = job.difficulty, timeLimit = job.minutes * 60 })
	local a = AI.new(sim, sc.factions.player, job.difficulty)
	local b = AI.new(sim, sc.factions.enemy, job.difficulty)
	sim.aiStep = function()
		AI.step(a)
		AI.step(b)
	end
	sim:start()
	local firstContact, cannon, cavCharges, flips, contested = nil, 0, 0, 0, false
	local maxTicks = job.minutes * 60 * Config.Sim.TickRate
	for _ = 1, maxTicks do
		sim:step()
		for _, ev in sim.events do
			if ev.kind == "volley" or ev.kind == "cannon" or ev.kind == "charge" then
				firstContact = firstContact or sim.clock
			end
			if ev.kind == "cannon" then
				cannon += 1
			elseif ev.kind == "charge" and ev.text ~= "bayonet" then
				cavCharges += 1
			elseif ev.kind == "capture" then
				flips += 1
			end
		end
		sim:clearEvents()
		for _, o in sim.objectives do
			contested = contested or o.contested
		end
		if sim.state ~= "running" then
			break
		end
	end
	local r = sim.result or sim:buildResults("draw", "timeout")
	local winner = sim.winner or "draw"
	local cols = { job.scenario, job.difficulty, job.seed, winner, r.reason, string.format("%.0f", sim.clock), firstContact and string.format("%.0f", firstContact) or "", cannon, cavCharges, flips, contested and 1 or 0 }
	for _, faction in { sc.factions.player, sc.factions.enemy } do
		local s = r.sides[faction]
		table.insert(cols, string.format("%s:%d/%d/%d/%d/%d/%d", faction, s.deployed, s.casualties, s.formations, s.routEvents, s.shattered, s.destroyed + s.exited))
	end
	print("BAL\t" .. table.concat(cols, "\t"))
end

test("[slow] balance harness", function()
	for _, job in JOBS do
		play(job)
	end
end)
