-- The grand campaign board's geography (src/shared/Relief.luau over EuropeGeo): real coasts,
-- relief from the mountain chains, provinces on the land, rivers.
local Shared = game:GetService("ReplicatedStorage").EoE
local Relief = require(Shared.Relief)
local Europe = require(Shared.EuropeData)

test("Relief: every province's centre stands on land and is that province", function()
	for _, p in Europe.Provinces do
		local c = p.centre
		assertTrue(Relief.isLand(c.x, c.z), p.id .. " centre on land")
		assertEq(Relief.provinceAt(c.x, c.z), p.id, p.id .. " owns its centre")
	end
end)

test("Relief: seas are water, the Alps stand high and the plains low", function()
	-- Bay of Biscay, the Tyrrhenian Sea, the Black Sea
	for _, ll in { { -5, 45.5 }, { 11.5, 39.5 }, { 34, 43 } } do
		local x, z = (ll[1] + 10) * 40, (ll[2] - 36) * 62.5
		assertTrue(not Relief.isLand(x, z), "water at " .. ll[1] .. "," .. ll[2])
	end
	local alps = Relief.height(840, 675) -- Swiss Alps on the chain
	local plain = Relief.height((12 + 10) * 40, (52.5 - 36) * 62.5) -- the North German plain
	assertTrue(alps > plain + 5, "alps " .. alps .. " over plain " .. plain)
	assertTrue(Relief.snow(840, 675), "snow on the Alps")
	assertTrue(not Relief.snow((12 + 10) * 40, (52.5 - 36) * 62.5), "no snow on the plain")
	-- caps on the peaks, rock between: a band of unbroken snow along the spine read as a white worm
	local snowy, along = 0, 0
	for t = 0, 1, 0.01 do
		local x, z = 700 + (990 - 700) * t, 625 + (705 - 625) * t -- the Alps' spine
		along += 1
		if Relief.snow(x, z) then
			snowy += 1
		end
	end
	assertTrue(snowy > along * 0.3 and snowy < along * 0.85, string.format("the spine is %d of %d snow", snowy, along))
end)

test("Relief: rivers are polylines inside the map", function()
	local n = 0
	for _, r in Relief.rivers() do
		assertTrue(#r.pts >= 2, r.name)
		for _, p in r.pts do
			assertTrue(p.x >= 0 and p.x <= 2000 and p.z >= 0 and p.z <= 1500, r.name .. " inside")
		end
		n += 1
	end
	assertTrue(n >= 20, "rivers: " .. n)
end)
