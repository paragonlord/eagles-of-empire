-- World pipeline: WorldGen determinism and tiers, the client readiness gate.
local Shared = game:GetService("ReplicatedStorage").EoE
local Client = game:GetService("StarterPlayer").StarterPlayerScripts.EoEClient
local MapGen = require(Shared.MapGen)
local WorldGen = require(Shared.WorldGen)
local Ready = require(Client.World.Ready)

local MAP = MapGen.generate("jena")

local function fingerprint(specs)
	local parts = {}
	for i, s in specs do
		local x, y, z, a, b, c, d, e, f, g, h, k = s.cframe:GetComponents()
		parts[i] = string.format("%s|%s|%d|%s|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f|%.4f,%.4f,%.4f|%s|%s",
			s.group, s.class, s.q, s.tier, s.size.X, s.size.Y, s.size.Z, x, y, z, a, b, c, d, e, f, g, h, k, s.color.R, s.color.G, s.color.B, tostring(s.transparency), tostring(s.castShadow))
	end
	return table.concat(parts, "\n")
end

test("WorldGen: same map and seed give the identical spec list", function()
	local t1 = WorldGen.terrain(MAP)
	local s1 = WorldGen.props(MAP, t1)
	local t2 = WorldGen.terrain(MapGen.generate("jena"))
	local s2 = WorldGen.props(MapGen.generate("jena"), t2)
	assertTrue(#s1 > 10000, "jena has over ten thousand specs")
	assertEq(#s2, #s1, "count")
	assertEq(fingerprint(s2), fingerprint(s1), "specs")
	-- the terrain model is deterministic too
	for _, c in { { 10, 10 }, { 200, 150 }, { -100, 400 }, { 500, -50 } } do
		local h1, m1, w1 = t1.column(c[1], c[2])
		local h2, m2, w2 = t2.column(c[1], c[2])
		assertEq(h2, h1, "height")
		assertEq(m2, m1, "material")
		assertEq(w2, w1, "water")
	end
end)

test("WorldGen: tiers and quality filters", function()
	local t = WorldGen.terrain(MAP)
	local all = WorldGen.props(MAP, t)
	local server = WorldGen.props(MAP, t, { maxQ = 2, detail = false })
	local detail = WorldGen.props(MAP, t, { structure = false })
	local phone = WorldGen.props(MAP, t, { maxQ = 1, detail = false })
	assertEq(#server + #detail, #all, "structure + detail = everything (nothing needs quality 3)")
	for _, s in server do
		assertEq(s.tier, "s", "server tier")
		assertTrue(s.q <= 2, "server cap")
	end
	local groups = {}
	for _, s in detail do
		assertEq(s.tier, "d", "detail tier")
		groups[s.group] = true
	end
	assertTrue(groups.Smoke and groups.GroundFog, "detail = hearth smoke and valley fog")
	assertTrue(#phone < #server, "quality 1 shows fewer parts")
	for _, s in phone do
		assertEq(s.q, 1, "quality 1 specs")
	end
	local n1 = 0
	for _, s in server do
		if s.q == 1 then
			n1 += 1
		end
	end
	assertEq(#phone, n1, "quality 1 is exactly the q1 subset of the server tier")
	local tally = WorldGen.tally(server)
	assertTrue(tally["Part/Grass"] > 5000, "crown lobes are Grass parts")
	assertTrue(tally["WedgePart/Slate"] > 500, "roofs are Slate wedges")
	print(string.format("  jena: server %d (q1 %d), detail %d", #server, n1, #detail))
end)

test("WorldGen: no part sits below the terrain at its corners, on every map", function()
	for _, id in { "jena", "auerstedt", "austerlitz", "waterloo" } do
		local map = MapGen.generate(id)
		local t = WorldGen.terrain(map)
		local specs = WorldGen.props(map, t)
		local bad, worst = 0, 0
		for _, s in specs do
			if not s.buried then
				local sf = WorldGen.shortfall(s, t)
				if sf > 0.05 then
					bad += 1
					worst = math.max(worst, sf)
				end
			end
		end
		assertEq(bad, 0, string.format("%s: parts below ground (worst %.2f)", id, worst))
	end
end)

local function run(samples, settleCap, replicateCap)
	local st = Ready.new(settleCap, replicateCap)
	local ready = false
	for _, s in samples do
		ready = Ready.step(st, s)
		if ready then
			break
		end
	end
	return ready, st
end

test("Ready gate: needs replication, three settled checks and two quiet frames", function()
	local good = { dt = 0.016, replicated = true, frameMs = 10 }
	-- quiet frames alone, no raycast check: not ready
	assertEq((run({ good, good, good, good })), false, "no checks")
	-- three hits then two quiet frames: ready
	local hit = { dt = 0.016, replicated = true, allHit = true, frameMs = 10 }
	assertEq((run({ hit, hit, hit, good, good })), true, "settled + frames")
	-- the frames must come after settling: frames before the third hit do not count
	assertEq((run({ good, good, hit, hit, hit })), false, "the third hit's frame is only the first quiet one")
	assertEq((run({ good, good, hit, hit, hit, good })), true, "one more quiet frame")
	assertEq((run({ good, good, hit, hit, good, good })), false, "two hits only")
	-- a miss resets the run of hits
	local miss = { dt = 0.016, replicated = true, allHit = false, frameMs = 10 }
	assertEq((run({ hit, hit, miss, hit, good, good })), false, "miss resets")
	assertEq((run({ hit, hit, miss, hit, hit, hit, good })), true, "recovers after a miss")
	-- a slow frame resets the quiet-frame run
	local slow = { dt = 0.05, replicated = true, frameMs = 50 }
	assertEq((run({ hit, hit, hit, slow, good })), false, "slow frame resets")
	assertEq((run({ hit, hit, hit, slow, good, good })), true, "two quiet after the slow one")
	-- not replicated: never ready however settled
	local unrep = { dt = 0.016, replicated = false, allHit = true, frameMs = 10 }
	assertEq((run({ unrep, unrep, unrep, unrep, unrep })), false, "unreplicated")
end)

test("Ready gate: caps on settling and replication", function()
	local miss = { dt = 0.2, replicated = true, allHit = false, frameMs = 10 }
	local samples = {}
	for _ = 1, 110 do
		table.insert(samples, miss) -- 22 s of raycasts missing
	end
	local ready, st = run(samples, 20)
	assertEq(ready, true, "settles by the cap even when rays keep missing")
	assertTrue(st.t >= 20, "cap reached")
	assertEq((run({ miss, miss, miss, miss, miss }, 20)), false, "before the cap")
	-- a missing world (offline menu) stops blocking after the replication cap
	local unrep = { dt = 1, replicated = false, allHit = true, frameMs = 10 }
	local s2 = {}
	for _ = 1, 95 do
		table.insert(s2, unrep)
	end
	assertEq((run(s2, 20, 90)), true, "replication cap")
	assertEq((run({ unrep, unrep, unrep, unrep }, 20, 90)), false, "before the cap")
	-- a device that never runs under the frame budget opens after FRAME_CAP, not never
	local hit = { dt = 0.016, replicated = true, allHit = true, frameMs = 60 }
	local slow = { dt = 0.06, replicated = true, frameMs = 60 }
	local s3 = { hit, hit, hit }
	for _ = 1, math.ceil(Ready.FRAME_CAP / 0.06) + 1 do
		table.insert(s3, slow)
	end
	assertEq((run(s3)), true, "frame cap")
	assertEq((run({ hit, hit, hit, slow, slow, slow })), false, "before the frame cap")
end)
