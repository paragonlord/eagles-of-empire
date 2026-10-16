-- Networking helpers: request gate, match clock (pause / speed / bounded work).
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local Config = require(Shared.Config)
local Protocol = require(Shared.Protocol)
local CommandGate = require(Server.Net.CommandGate)
local MatchClock = require(Server.Net.MatchClock)

test("CommandGate rejects duplicates and bursts over the rate limit", function()
	local g = CommandGate.new()
	assertTrue(CommandGate.check(g, 1, "a", 0))
	local ok, reason = CommandGate.check(g, 1, "a", 0.1)
	assertTrue(not ok and reason == Protocol.Reasons.duplicate)
	for i = 1, Config.Net.RequestsPerSecond - 1 do
		assertTrue(CommandGate.check(g, 1, "b" .. i, 0.2), "within limit " .. i)
	end
	local ok2, reason2 = CommandGate.check(g, 1, "over", 0.3)
	assertTrue(not ok2 and reason2 == Protocol.Reasons.rateLimited)
	assertTrue(CommandGate.check(g, 2, "a", 0.3), "other player unaffected")
	assertTrue(CommandGate.check(g, 1, "later", 1.5), "window slides")
end)

test("MatchClock: pause freezes ticks, speed scales, work per frame is bounded", function()
	local c = MatchClock.new()
	local ticks = 0
	local function step()
		ticks += 1
	end
	MatchClock.advance(c, 0.1, step)
	assertEq(ticks, 2)
	c.paused = true
	MatchClock.advance(c, 1.0, step)
	assertEq(ticks, 2, "paused")
	c.paused = false
	assertTrue(MatchClock.setSpeed(c, 4))
	assertTrue(not MatchClock.setSpeed(c, 3))
	MatchClock.advance(c, 0.05, step)
	assertEq(ticks, 6, "x4 speed runs 4 ticks per 50 ms")
	MatchClock.setSpeed(c, 1)
	local before = ticks
	MatchClock.advance(c, 5, step)
	assertEq(ticks - before, Config.Sim.MaxTicksPerFrame, "bounded per frame")
	assertTrue(c.simLag > 0, "lag reported")
end)

test("Different render rates run the same number of ticks over the same real time", function()
	local function runAt(frameDt)
		local c = MatchClock.new()
		local ticks = 0
		local t = 0
		while t < 10 do
			MatchClock.advance(c, frameDt, function()
				ticks += 1
			end)
			t += frameDt
		end
		return ticks
	end
	local a, b = runAt(1 / 60), runAt(1 / 24)
	assertTrue(math.abs(a - b) <= 2, string.format("60fps %d vs 24fps %d", a, b))
end)
