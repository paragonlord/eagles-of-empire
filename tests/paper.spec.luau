-- Aged-paper layout (UI/PaperLayout): seeded, repeatable, and every mark stays on the sheet so
-- an auto-sized panel never grows to fit a stain.
local Client = game:GetService("StarterPlayer").StarterPlayerScripts.EoEClient
local PaperLayout = require(Client.UI.PaperLayout)

local function inside(m)
	return m.x >= 0 and m.y >= 0 and m.x + m.w <= 1 and m.y + m.h <= 1 and m.w > 0 and m.h > 0
end

test("Paper: same seed, same sheet; different seeds differ", function()
	local a, b = PaperLayout.sheet(PaperLayout.seed("EoEDeploy:420:-96")), PaperLayout.sheet(PaperLayout.seed("EoEDeploy:420:-96"))
	assertEq(a.blotches[1].x, b.blotches[1].x, "repeatable")
	assertEq(a.crease.y, b.crease.y, "repeatable crease")
	assertEq(a.chip, b.chip, "repeatable chip")
	local c = PaperLayout.sheet(PaperLayout.seed("EoEResults:760:640"))
	assertTrue(a.blotches[1].x ~= c.blotches[1].x, "seeds differ")
	assertTrue(PaperLayout.seed("a") ~= PaperLayout.seed("b"), "hash differs")
end)

test("Paper: every mark lies inside the sheet; rings on some sheets only", function()
	local rings = 0
	for s = 1, 200 do
		local sheet = PaperLayout.sheet(s * 7919)
		assertEq(#sheet.blotches, 3, "three spots")
		for _, m in sheet.blotches do
			assertTrue(inside(m), "blotch inside")
			assertTrue(m.alpha > 0.5 and m.alpha < 1, "blotch faint")
		end
		if sheet.ring then
			rings += 1
			assertTrue(inside(sheet.ring), "ring inside")
		end
		assertTrue(sheet.crease.y > 0 and sheet.crease.y < 1, "crease on sheet")
		assertTrue(sheet.chip >= 1 and sheet.chip <= 4, "chip corner")
	end
	assertTrue(rings > 30 and rings < 130, "some sheets carry a ring, not all: " .. rings)
	-- seed 0 must not lock the generator
	assertTrue(inside(PaperLayout.sheet(0).blotches[1]), "seed 0")
end)
