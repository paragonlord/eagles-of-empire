local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)
local Sim = require(Server.Sim)
local AI = require(Server.AI)
test("dbg fight", function()
	local sim = Sim.new({ matchId = "m", scenario = Scenarios.jena, map = MapGen.generate("jena"), seed = 9 })
	sim:start()
	local st = AI.new(sim, "prussia", "normal")
	local aiTime, n = 0, 0
	Sim.aiStep = function() local t0 = os.clock(); AI.step(st); aiTime += os.clock() - t0; n += 1 end
	local inf, cav = {}, {}
	for id = 1, 17 do local f = sim.formations[id]; if f.class == "infantry" then inf[#inf+1] = id elseif f.class == "cavalry" then cav[#cav+1] = id end end
	local kinds = {}
	local orig = sim.queueCommand
	sim.queueCommand = function(self, cmd, faction) if faction == "prussia" then kinds[cmd.kind] = (kinds[cmd.kind] or 0) + 1 end return orig(self, cmd, faction) end
	for t = 1, 20 * 600 do
		if t == 20 * 10 then
			sim:queueCommand({ matchId = "m", requestId = "a", kind = "AttackMove", ids = inf, data = { pos = { x = 900, z = 600 }, heading = math.pi / 2 } }, "france")
			sim:queueCommand({ matchId = "m", requestId = "b", kind = "Move", ids = cav, data = { pos = { x = 1100, z = 560 }, heading = math.pi / 2 } }, "france")
		end
		if t == 20 * 150 then
			sim:queueCommand({ matchId = "m", requestId = "c", kind = "Charge", ids = cav, data = { pos = { x = 980, z = 560 } } }, "france")
		end
		sim:step()
		if sim.state ~= "running" then break end
		if t % (20 * 120) == 0 then
			print("--- t=" .. sim.clock, st.posture)
			for _, v in AI.debugView(st) do
				local f = sim.formations[v.id]
				print(string.format("%2d %-24s %-9s %-16s %5.0f,%5.0f %-10s %-8s %4d m%3.0f %s", v.id, f.name:sub(1,24), f.class, v.goal, f.pos.x, f.pos.z, f.state, f.shape, f.strength, f.morale, v.reason))
			end
		end
	end
	print("ended", sim.state, sim.winner, sim.clock, "ai ms/step", aiTime / n * 1000, "steps", n)
	for k, c in kinds do print(k, c) end
	for _, l in sim.logLines do print(l) end
end)
