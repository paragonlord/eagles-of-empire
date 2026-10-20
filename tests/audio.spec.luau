-- Audio (client): the pure parts of the mixer. Tension decays over its window with hysteresis
-- on the mood, the gate holds a cooldown and a cap per key, the roll-off grows and the volume
-- and treble fall with camera height. No Sound instances: ids are empty, nothing is created.
local Client = game:GetService("StarterPlayer").StarterPlayerScripts.EoEClient
local Audio = require(Client.Audio)
local Assets = require(game:GetService("ReplicatedStorage").EoE.Assets)

test("Audio: tension score decays over the window and the mood has hysteresis", function()
	local W = Audio.TENSION_WINDOW
	local list = { { t = 0, w = 4 }, { t = 10, w = 2 } }
	assertEq(Audio.tension({}, 5, W), 0, "no events")
	assertEq(Audio.tension(list, 10, W), 4 * 0.5 + 2, "half-faded rout plus a fresh melee")
	assertEq(Audio.tension(list, 30, W), 0, "all outside the window")
	assertEq(Audio.tension({ { t = 50, w = 9 } }, 10, W), 0, "future events ignored")
	assertEq(Audio.mood(Audio.TENSE_ON - 0.1, false), false, "below the on threshold: calm")
	assertEq(Audio.mood(Audio.TENSE_ON, false), true, "at the threshold: tense")
	assertEq(Audio.mood(Audio.TENSE_OFF + 1, true), true, "tense holds between the thresholds")
	assertEq(Audio.mood(Audio.TENSE_OFF, true), false, "calm again under the off threshold")
end)

test("Audio: the gate holds a cooldown and a cap of live instances per key", function()
	local g = { last = -math.huge, live = 0 }
	assert(Audio.gate(g, 0, 0.1, 2), "first play")
	assert(not Audio.gate(g, 0.05, 0.1, 2), "inside the cooldown")
	assert(Audio.gate(g, 0.1, 0.1, 2), "cooldown over")
	assertEq(g.live, 2)
	assert(not Audio.gate(g, 1, 0.1, 2), "cap reached")
	Audio.release(g)
	assert(Audio.gate(g, 2, 0.1, 2), "a release frees a slot")
	Audio.release(g)
	Audio.release(g)
	Audio.release(g)
	assertEq(g.live, 0, "never below zero")
end)

test("Audio: roll-off reaches further, quieter and duller from a high camera", function()
	local lowReach, lowScale, lowCut = Audio.rolloff(55)
	local highReach, highScale, highCut = Audio.rolloff(900)
	assert(highReach > lowReach, "a high camera hears further")
	assertEq(lowScale, 1, "full volume from low")
	assertEq(lowCut, 0, "no treble cut from low")
	assert(highScale < lowScale and highScale >= 0.4, "quieter from high, never below the floor")
	assert(highCut < -6 and highCut >= -12, "muffled from high")
	local _, s2 = Audio.rolloff(3000)
	assertEq(s2, 0.4, "the floor holds")
	assertEq(Audio.nearLevel(0), 1, "a source under the camera is at full level")
	assertEq(Audio.nearLevel(400), 0, "and gone at the edge")
	assert(Audio.nearLevel(200) > 0 and Audio.nearLevel(200) < 1, "fading between")
end)

test("Audio: every slot is well formed, the battle sounds are in, an empty slot plays nothing", function()
	assert(not Audio.isSilent(), "ids checked in")
	for key, slot in Assets.sounds do
		local list = if type(slot.id) == "table" then slot.id else { slot.id }
		for _, id in list :: { string } do
			assert(id == "" or string.match(id, "^rbxassetid://%d+$") ~= nil, key .. " id " .. tostring(id))
		end
		assert(slot.volume > 0 and slot.volume <= 1, key .. " volume")
		assert(slot.pitch[1] <= slot.pitch[2], key .. " pitch range")
		assert(slot.variants >= 1, key .. " variants")
	end
	for _, key in { "musketVolley", "cannonFire", "cavalryCharge", "menuMusic", "battleMusicCalm" } do
		assert(type(Assets.sounds[key].id) == "table" and #(Assets.sounds[key].id :: { string }) > 0, key .. " has a sound")
	end
	assertEq(Assets.sounds.bugleCharge.id, "", "a slot still waiting for its sound")
	Audio.play("bugleCharge", 100, 100) -- no init, no id: a no-op
	Audio.onEvent({ kind = "volley", x = 1, z = 1 })
end)
