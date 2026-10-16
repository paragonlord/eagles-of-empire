-- Simulation cost on the stress fixture (24 v 24). Not a Roblox measurement: the Luau CLI
-- runs without native codegen, so Roblox server time per tick should be lower.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local Config = require(Shared.Config)
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)
local Sim = require(Server.Sim)

test("Stress fixture: 60 s of simulation with everyone attack-moving stays under 25 ms/tick", function()
	local map = MapGen.generate("jena")
	local sim = Sim.new({ matchId = "b", scenario = Scenarios.stress, map = map, seed = 99 })
	sim:start()
	local ids = {}
	for _, id in sim.order do
		local f = sim.formations[id]
		if f.faction == "france" and f.class ~= "artillery" then
			ids[#ids + 1] = id
		end
	end
	sim:queueCommand({ matchId = "b", requestId = "all", kind = "AttackMove", ids = { table.unpack(ids, 1, math.min(#ids, Config.Net.MaxBatch)) }, data = { pos = { x = 800, z = 760 }, heading = math.pi / 2 } }, "france")
	local ticks = 60 * Config.Sim.TickRate
	local t0 = os.clock()
	for _ = 1, ticks do
		sim:step()
		sim:clearEvents()
	end
	local msPerTick = (os.clock() - t0) * 1000 / ticks
	local snap = sim:snapshot("france", true)
	print(string.format("   stress: %.2f ms/tick, %d formations in full snapshot", msPerTick, #snap.formations))
	assertTrue(msPerTick < 25, string.format("%.2f ms/tick", msPerTick))
end)
