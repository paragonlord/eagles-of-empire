-- Full Jena battle with a scripted, sensible French plan against the AI. Slow (~1 min CLI):
-- runs only with `tools/test.py -k battle`. Produces pacing evidence for docs/qa.md.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local Config = require(Shared.Config)
local MapGen = require(Shared.MapGen)
local Scenarios = require(Shared.Scenarios)
local Sim = require(Server.Sim)
local AI = require(Server.AI)

local function playJena(difficulty, seed)
	local map = MapGen.generate("jena")
	local sim = Sim.new({ matchId = "j", scenario = Scenarios.jena, map = map, seed = seed, difficulty = difficulty })
	local ai = AI.new(sim, "prussia", difficulty)
	sim.aiStep = function()
		AI.step(ai)
	end
	sim:start()
	local n = 0
	local function order(kind, ids, data)
		n += 1
		sim:queueCommand({ matchId = "j", requestId = "p" .. n, kind = kind, ids = ids, data = data }, "france")
	end
	local inf, cav, art, hq = {}, {}, {}, nil
	for _, id in sim.order do
		local f = sim.formations[id]
		if f.faction == "france" then
			if f.class == "infantry" then
				inf[#inf + 1] = id
			elseif f.class == "cavalry" then
				cav[#cav + 1] = id
			elseif f.class == "artillery" then
				art[#art + 1] = id
			else
				hq = id
			end
		end
	end
	-- Plan: guns to the plateau edge and unlimber; infantry advances in column to the slope
	-- foot, deploys into line and attack-moves on Vierzehnheiligen / Closewitz; cavalry waits.
	order("Move", art, { pos = { x = 820, z = 360 }, heading = math.pi / 2 })
	order("Shape", inf, { shape = "column" })
	order("Move", inf, { pos = { x = 800, z = 470 }, heading = math.pi / 2 })
	order("Move", { hq }, { pos = { x = 800, z = 400 }, heading = math.pi / 2 })
	local phase = 1
	local ended = nil
	local events = { volleys = 0, charges = 0, routs = 0 }
	for tick = 1, 25 * 60 * Config.Sim.TickRate do
		sim:step()
		for _, ev in sim.events do
			if ev.kind == "volley" then
				events.volleys += 1
			elseif ev.kind == "charge" then
				events.charges += 1
			elseif ev.kind == "rout" then
				events.routs += 1
			end
		end
		sim:clearEvents()
		local t = sim.clock
		if phase == 1 and t > 60 then
			phase = 2
			order("Limber", art, { limbered = false })
		elseif phase == 2 and t > 110 then
			phase = 3
			order("Shape", inf, { shape = "line" })
		elseif phase == 3 and t > 140 then
			phase = 4
			local left, right = {}, {}
			for i, id in inf do
				if i % 2 == 0 then
					left[#left + 1] = id
				else
					right[#right + 1] = id
				end
			end
			order("AttackMove", left, { pos = { x = 760, z = 740 }, heading = math.pi / 2 })
			order("AttackMove", right, { pos = { x = 1000, z = 520 }, heading = math.pi / 2 })
			order("Move", cav, { pos = { x = 1100, z = 420 }, heading = math.pi / 2 })
		elseif phase == 4 and t > 420 then
			phase = 5
			-- cavalry: charge any visible enemy artillery or routing unit, else hold
			for _, id in sim.order do
				local e = sim.formations[id]
				if e.faction == "prussia" and sim:isVisibleTo("france", id) and (e.class == "artillery" or e.state == "routing") then
					order("Charge", cav, { targetId = id })
					break
				end
			end
		end
		if sim.state == "ended" then
			ended = t
			break
		end
		-- invariants every 10 s
		if tick % 200 == 0 then
			for _, id in sim.order do
				local f = sim.formations[id]
				assertTrue(f.pos.x == f.pos.x and f.pos.z == f.pos.z, "finite position " .. f.name)
				assertTrue(f.strength >= 0 and f.strength <= f.startStrength, "strength in range " .. f.name)
				assertTrue(f.morale >= 0 and f.morale <= 100, "morale in range")
			end
		end
	end
	local r = sim.result or sim:buildResults("draw", "timeout")
	return sim, r, ended, events
end

test("[slow] Scripted French plan vs normal AI: battle completes with plausible pacing and reconciled totals", function()
	local sim, r, ended, events = playJena("normal", 20261014)
	print(string.format("   ended at %s, outcome %s (%s); volleys %d, charges %d, routs %d", if ended then string.format("%d:%02d", ended // 60, ended % 60) else "timeout", r.outcome, r.reason, events.volleys, events.charges, events.routs))
	for faction, side in r.sides do
		print(string.format("   %s: deployed %d, casualties %d, remaining %d, routed %d, shattered %d, destroyed %d, exited %d", faction, side.deployed, side.casualties, side.remaining, side.routed, side.shattered, side.destroyed, side.exited))
		assertEq(side.deployed, side.remaining + side.casualties, faction .. " totals reconcile")
	end
	assertTrue(events.volleys > 50, "a real firefight happened")
	assertTrue(r.sides.france.casualties > 0 and r.sides.prussia.casualties > 0, "both sides bled")
	assertTrue(ended == nil or ended > 4 * 60, "did not end within 4 minutes")
end)
