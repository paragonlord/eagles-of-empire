--!strict
-- Real time → logical ticks. Speed scales the accumulator, never the step. Work per frame is
-- bounded; sustained overload shows up as simLag instead of a giant step.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)

export type Clock = {
	speed: number,
	paused: boolean,
	accumulator: number,
	simLag: number, -- seconds of simulation owed but not yet run
}

local MatchClock = {}

local DT = Config.Sim.DT
local MAX_TICKS = Config.Sim.MaxTicksPerFrame
local MAX_DEBT = 2.0 -- seconds; beyond this we drop time rather than spiral

function MatchClock.new(): Clock
	return { speed = 1, paused = false, accumulator = 0, simLag = 0 }
end

function MatchClock.setSpeed(clock: Clock, speed: number): boolean
	for _, s in Config.Sim.Speeds do
		if s == speed then
			clock.speed = speed
			return true
		end
	end
	return false
end

-- Advance by realDt seconds; calls step() for each logical tick run. Returns ticks run.
function MatchClock.advance(clock: Clock, realDt: number, step: () -> ()): number
	if clock.paused then
		clock.accumulator = 0
		return 0
	end
	clock.accumulator += math.max(0, realDt) * clock.speed
	if clock.accumulator > MAX_DEBT then
		clock.accumulator = MAX_DEBT
	end
	local ticks = math.floor(clock.accumulator / DT)
	if ticks > MAX_TICKS then
		ticks = MAX_TICKS
	end
	for _ = 1, ticks do
		step()
	end
	clock.accumulator -= ticks * DT
	clock.simLag = math.max(0, clock.accumulator - DT)
	return ticks
end

return MatchClock
