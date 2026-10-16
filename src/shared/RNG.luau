--!strict
-- Deterministic xorshift32 RNG with a serializable integer state. All simulation randomness
-- goes through one instance owned by the sim; cosmetic randomness uses separate instances.

local RNG = {}
RNG.__index = RNG

export type RNG = typeof(setmetatable({} :: { state: number }, RNG))

function RNG.new(seed: number): RNG
	local s = bit32.band(math.floor(seed), 0xFFFFFFFF)
	if s == 0 then
		s = 0x9E3779B9
	end
	return setmetatable({ state = s }, RNG)
end

function RNG.fromState(state: number): RNG
	return RNG.new(state)
end

function RNG.nextU32(self: RNG): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

-- [0, 1)
function RNG.float(self: RNG): number
	return RNG.nextU32(self) / 4294967296
end

-- integer in [lo, hi]
function RNG.int(self: RNG, lo: number, hi: number): number
	return lo + RNG.nextU32(self) % (hi - lo + 1)
end

-- float in [lo, hi)
function RNG.range(self: RNG, lo: number, hi: number): number
	return lo + RNG.float(self) * (hi - lo)
end

function RNG.chance(self: RNG, p: number): boolean
	return RNG.float(self) < p
end

function RNG.serialize(self: RNG): number
	return self.state
end

-- 32-bit multiply without exceeding 2^53 in intermediates (keeps results exact everywhere).
local function mul32(a: number, b: number): number
	local lo = bit32.band(a, 0xFFFF) * b
	local hi = (bit32.rshift(a, 16) * b) % 4294967296
	return (lo + bit32.lshift(hi, 16)) % 4294967296
end

-- Stateless hash in [0,1) for keyed event randomness and noise (no RNG state needed).
-- Inputs are floored and reduced mod 2^32; typical callers pass small integers.
function RNG.hash(a: number, b: number, c: number): number
	local h = (math.floor(a) % 4294967296 * 73856093 + math.floor(b) % 4294967296 * 19349663 + math.floor(c) % 4294967296 * 83492791) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0x5bd1e995)
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = mul32(h, 0x27d4eb2f)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

return RNG
