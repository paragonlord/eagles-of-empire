-- World pipeline: WorldGen determinism and tiers, the client readiness gate.
local Shared = game:GetService("ReplicatedStorage").EoE
local Client = game:GetService("StarterPlayer").StarterPlayerScripts.EoEClient
local MapGen = require(Shared.MapGen)
local WorldGen = require(Shared.WorldGen)
local Ready = require(Client.World.Ready)
local Assets = require(Shared.Assets)

local MAP = MapGen.generate("jena")

-- The procedural pipeline is tested with every mesh slot empty (a filled slot replaces whole
-- objects with one mesh part); the mesh path has its own test below.
local savedMeshes: { [string]: string } = {}
for key, slot in Assets.slots do
	savedMeshes[key] = slot.mesh
end
local function setMeshes(on: boolean)
	for key, slot in Assets.slots do
		slot.mesh = if on then savedMeshes[key] else ""
	end
end
setMeshes(false)

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
	-- the authored fields and one province field of each archetype the generator draws
	for _, id in { "jena", "auerstedt", "austerlitz", "waterloo", "province:rhineland", "province:vienna", "province:moravia" } do
		local map = MapGen.generate(id)
		local t = WorldGen.terrain(map)
		local specs = WorldGen.props(map, t)
		assertTrue(#specs > 500, id .. ": a world was built")
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

test("WorldGen: filled tree and house slots turn each object into one mesh part standing on the ground", function()
	for _, key in { "treeOak", "houseA" } do
	local slot = Assets.slots[key]
	slot.mesh = "rbxassetid://1"
	local ok, err = pcall(function()
		for _, id in { "jena", "austerlitz" } do
			local map = MapGen.generate(id)
			local t = WorldGen.terrain(map)
			local specs = WorldGen.props(map, t)
			local meshes, bad = 0, 0
			for _, s in specs do
				if s.fileMesh == key then
					meshes += 1
					if WorldGen.shortfall(s, t) > 0.05 then
						bad += 1
					end
				end
			end
			assertTrue(meshes > 10, id .. " has " .. key .. " meshes")
			assertEq(bad, 0, id .. ": " .. key .. " bases below ground")
		end
	end)
	slot.mesh = ""
	assertTrue(ok, tostring(err))
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

test("Figures: muskets are reloaded upright and fired levelled; bayonets thrust in melee", function()
	local Soldiers = require(Client.World.Soldiers)
	local origin = CFrame.new()
	local shouldered = Soldiers.partCFrame(3, origin, 0, 0, false)
	local levelled = Soldiers.partCFrame(3, origin, 0, 0, true)
	-- reloading: most of the cycle the butt stands on the ground in front, the rest levelled to fire
	local ram = Soldiers.partCFrame(3, origin, 0, 0, true, "reload", 0.2)
	local butt = ram * Vector3.new(0, -0.85, 0) -- the part-built musket is 1.7 long, posed at its middle
	assertTrue(butt.Y > -0.1 and butt.Y < 0.3 and butt.X > 0.3, "butt grounded in front: " .. tostring(butt))
	assertTrue((Soldiers.partCFrame(3, origin, 0, 0, true, "reload", 0.9).Position - levelled.Position).Magnitude < 1e-6, "then levelled")
	-- the right arm works the ramrod: it moves through the cycle
	local a1 = Soldiers.partCFrame(13, origin, 0, 0, true, "reload", 0.1)
	local a2 = Soldiers.partCFrame(13, origin, 0, 0, true, "reload", 0.16)
	assertTrue((a1.LookVector - a2.LookVector).Magnitude > 0.05 or (a1.UpVector - a2.UpVector).Magnitude > 0.05, "the ramrod arm moves")
	-- melee: the levelled musket drives forward and back
	local out = Soldiers.partCFrame(3, origin, 0, 0, true, "thrust", 0.25)
	local back = Soldiers.partCFrame(3, origin, 0, 0, true, "thrust", 0.75)
	assertTrue(out.Position.X > levelled.Position.X + 0.2, "a thrust")
	assertTrue(math.abs(back.Position.X - levelled.Position.X) < 1e-6, "and back")
	local _ = shouldered
	-- the hands follow the musket: forward of the chest when levelled, at the muzzle when ramming
	local leftHand, rightHand = CFrame.new(0.26, -0.9, 0), CFrame.new(0.42, -0.62, 0)
	assertTrue(Soldiers.partCFrame(12, leftHand, 0, 0, true).Position.X > 0.4, "left hand forward under the barrel")
	assertTrue(Soldiers.partCFrame(13, rightHand, 0, 0, true).Position.X > 0.3, "right hand forward at the lock")
	local muzzle = ram * Vector3.new(0, 0.85, 0)
	for _, beat in { 0.1, 0.16, 0.3 } do
		local h = Soldiers.partCFrame(13, rightHand, 0, 0, true, "reload", beat).Position
		assertTrue(h.X > 0.2 and math.abs(h.Y - muzzle.Y) < 0.6, "ramming hand at the muzzle: " .. tostring(h) .. " muzzle " .. tostring(muzzle))
	end
	assertTrue(Soldiers.partCFrame(12, leftHand, 0, 0, true, "reload", 0.2).Position.X > 0.3, "left hand on the barrel in front")
end)

test("Figures: a generated kit stands as generated at rest and moves on the part-built anim codes", function()
	local Soldiers = require(Client.World.Soldiers)
	local Assets = require(game:GetService("ReplicatedStorage").EoE.Assets)
	local kit = Assets.kit("infantry_france") :: any
	assertTrue(kit ~= nil, "the French kit is filled")
	local layout = Soldiers.kitLayout(kit)
	local seen = {}
	for _, e in layout do
		seen[e.key] = e
		local p = kit[e.key].cf
		local want = CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(p[4], p[5], p[6])
		local rest = Soldiers.partCFrame(e.anim, e.lc, e.pivot, 0, false)
		if e.key ~= "musket" then
			assertTrue((rest.Position - want.Position).Magnitude < 1e-4, e.key .. " at rest where generated: " .. tostring(rest.Position))
			assertTrue((rest.LookVector - want.LookVector).Magnitude < 1e-4, e.key .. " faces as generated")
		end
	end
	for _, k in { "torso", "head", "legL", "legR", "armL", "armR", "musket" } do
		assertTrue(seen[k] ~= nil, "piece " .. k)
	end
	assertEq(seen.legL.anim, 1)
	assertEq(seen.legR.anim, 2)
	assertEq(seen.armL.anim, 12)
	assertEq(seen.armR.anim, 13)
	assertEq(seen.musket.anim, 3)
	-- marching swings a leg about the hip and keeps the mesh turned the kit's way
	local step = Soldiers.partCFrame(1, seen.legL.lc, seen.legL.pivot, 0.4, false)
	assertTrue(math.abs(step.Position.X - seen.legL.lc.Position.X) > 0.1, "the leg swings")
	assertTrue(math.abs(step.LookVector.Y) < 0.5, "and stays upright-facing")
	-- levelled: the arms reach forward and the musket points ahead at shoulder height, butt at the shoulder
	local arm = Soldiers.partCFrame(12, seen.armL.lc, seen.armL.pivot, 0, true)
	local armRest = Soldiers.partCFrame(12, seen.armL.lc, seen.armL.pivot, 0, false)
	assertTrue(arm.Position.X > armRest.Position.X + 0.2, "the left arm reaches forward")
	local gun = Soldiers.partCFrame(3, seen.musket.lc, seen.musket.pivot, 0, true)
	assertTrue(gun.Position.Y > 2.0 and gun.Position.Y < 2.6, "musket at shoulder height: " .. tostring(gun.Position))
	local half = kit.musket.size[2] / 2
	local butt = gun * Vector3.new(0, -half, 0)
	assertTrue(butt.X > -0.4 and butt.X < 0.3, "butt in the shoulder: " .. tostring(butt))
	-- reloading, the long kit musket also stands on its butt
	local ram = Soldiers.partCFrame(3, seen.musket.lc, seen.musket.pivot, 0, true, "reload", 0.2)
	local foot = ram * Vector3.new(0, -half, 0)
	assertTrue(foot.Y > -0.1 and foot.Y < 0.3, "kit butt grounded while ramming: " .. tostring(foot))
end)

test("Assets: every generated kit has all its pieces with ids, sizes and places", function()
	local Assets = require(game:GetService("ReplicatedStorage").EoE.Assets)
	local want = {
		infantry = { "torso", "head", "headgear", "armL", "armR", "legL", "legR", "musket" },
		cavalry = { "body", "neck", "rider", "riderHead", "legFL", "legFR", "legBL", "legBR" },
		head = { "headgear" },
		gun = { "barrel", "carriage", "wheelL", "wheelR" },
	}
	local count = 0
	for name, kit in Assets.kits do
		local kind = string.match(name, "^(%a+)_")
		local keys = want[kind]
		assertTrue(keys ~= nil, "known kit kind: " .. name)
		for _, k in keys do
			local p = kit[k]
			assertTrue(p ~= nil, name .. " has " .. k)
			assertTrue(string.match(p.mesh, "^rbxassetid://%d+$") ~= nil and string.match(p.texture, "^rbxassetid://%d+$") ~= nil, name .. "." .. k .. " ids")
			assertEq(#p.size, 3, name .. "." .. k .. " size")
			assertEq(#p.scale, 3, name .. "." .. k .. " scale")
			assertEq(#p.cf, 6, name .. "." .. k .. " cf")
		end
		count += 1
	end
	for _, nation in { "france", "prussia", "austria", "russia", "britain", "saxony", "netherlands", "bavaria" } do
		assertTrue(Assets.kit("infantry_" .. nation) ~= nil and Assets.kit("cavalry_" .. nation) ~= nil, "kits for " .. nation)
	end
	assertTrue(count >= 20, "kits: " .. count)
end)

test("Figures: the default camera sees men, not blocks, at every quality; farther at higher quality", function()
	local Config = require(game:GetService("ReplicatedStorage").EoE.Config)
	local far = Config.Visual.FarLodDistance
	assertEq(typeof(far), "table", "one distance per quality level")
	-- the default view: 420 high, pitched 52 degrees less the low-camera tilt (~48), sees the
	-- ground it looks at ~565 studs away
	local defaultDist = 420 / math.sin(math.rad(48))
	for q = 1, 3 do
		assertTrue(far[q] > defaultDist, "quality " .. q .. " shows men at the default view: " .. far[q])
	end
	assertTrue(far[1] < far[2] and far[2] < far[3], "higher quality draws men farther")
end)

test("Props: place names on the ground stay off the fighting up close and modest from above", function()
	local Props = require(Client.World.Props)
	local k, alpha = Props.groundLabelLook(120)
	assertEq(alpha, 1, "hidden among the troops")
	k, alpha = Props.groundLabelLook(260)
	assertTrue(alpha > 0.12 and alpha < 1, "fading in: " .. alpha)
	k, alpha = Props.groundLabelLook(420)
	assertTrue(alpha <= 0.15, "readable at the default view")
	assertTrue(k <= 1.0, "no bigger than before at the default view: " .. k)
	local kTop = Props.groundLabelLook(900)
	assertTrue(kTop <= 1.5, "capped from high up: " .. kTop)
end)
