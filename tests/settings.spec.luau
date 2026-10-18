-- Viewer settings: typeface and place-name modes accept only their presets, so a stale value
-- in a saved profile can never leave the UI without a font or the field without a label mode.
local Client = game:GetService("StarterPlayer").StarterPlayerScripts.EoEClient
local Settings = require(Client.Settings)

test("Settings: typeface and placeNames take presets only", function()
	assertEq(Settings.get().typeface, "Garamond", "default typeface")
	assertEq(Settings.get().placeNames, "ground", "default place names")
	local fired = 0
	local c = Settings.changed:Connect(function()
		fired += 1
	end)
	Settings.set("typeface", "Comic")
	assertEq(Settings.get().typeface, "Garamond", "unknown preset refused")
	Settings.set("placeNames", "neon")
	assertEq(Settings.get().placeNames, "ground", "unknown mode refused")
	assertEq(fired, 0, "refused values fire nothing")
	for _, t in Settings.TYPEFACES do
		Settings.set("typeface", t)
		assertEq(Settings.get().typeface, t)
	end
	for _, m in Settings.PLACE_NAMES do
		Settings.set("placeNames", m)
		assertEq(Settings.get().placeNames, m)
	end
	assertEq(fired, 4 + 4 - 2, "each real change fires once (the first of each list was already set)")
	Settings.set("typeface", "Garamond")
	Settings.set("placeNames", "ground")
	c:Disconnect()
end)
