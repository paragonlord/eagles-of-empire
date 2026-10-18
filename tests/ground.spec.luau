-- Ground: the pure four-corner lift that keeps figures, blocks and bodies out of the hillside.
local Client = game:GetService("StarterPlayer").StarterPlayerScripts.EoEClient
local Ground = require(Client.Ground)

test("Ground.lift: raises a body by the worst sunk corner plus the clearance, never lowers it", function()
	assertEq(Ground.lift(10, { 9, 9.5, 8, 10 }), 0, "every corner at or below the feet: no lift")
	assertNear(Ground.lift(10, { 10.4, 9, 11.2, 10 }), 1.2 + Ground.CLEARANCE, 1e-9, "the highest corner decides")
	assertNear(Ground.lift(0, { 0.001, -5, -5, -5 }), 0.001 + Ground.CLEARANCE, 1e-9, "any sinking at all is lifted")
	assertEq(Ground.lift(3, {}), 0, "no corners, no lift")
end)

test("Ground.lift: a pitched body is measured against its own underside at each corner", function()
	-- a horse on a 30 % slope, pitched to it: the plane follows the ground, so nothing sinks
	local plane = { 10 - 0.48, 10 - 0.48, 10 + 0.48, 10 + 0.48 }
	assertEq(Ground.lift(10, { 9.52, 9.52, 10.48, 10.48 }, plane), 0, "pitched to the slope: clear")
	-- the same ground under an upright body sinks the uphill corners
	assertNear(Ground.lift(10, { 9.52, 9.52, 10.48, 10.48 }), 0.48 + Ground.CLEARANCE, 1e-9, "upright: lifted by the uphill rise")
	-- a bump under one corner of the pitched body still lifts it
	assertNear(Ground.lift(10, { 9.52, 9.9, 10.48, 10.48 }, plane), 0.38 + Ground.CLEARANCE, 1e-9, "a rock under one hoof")
end)
