--!strict
-- Where the stains fall on an aged sheet. Pure numbers (no Roblox types) so the headless spec
-- can check it: every mark lies inside the unit square, and the same seed gives the same sheet.

local PaperLayout = {}

export type Mark = { x: number, y: number, w: number, h: number, alpha: number }
export type Sheet = {
	blotches: { Mark }, -- foxing spots: x, y, w, h in 0..1 of the panel, alpha = transparency
	ring: Mark?, -- one coffee ring on roughly a third of sheets
	crease: { y: number, rotation: number }, -- a fold across the sheet, y in 0..1
	chip: number, -- which corner is folded: 1 top-left, 2 top-right, 3 bottom-left, 4 bottom-right
}

-- FNV-1a over the bytes: a stable seed from the panel's name and size.
function PaperLayout.seed(key: string): number
	local h = 2166136261
	for i = 1, #key do
		h = bit32.band((bit32.bxor(h, string.byte(key, i)) * 16777619), 0xFFFFFFFF)
	end
	return h
end

function PaperLayout.sheet(seed: number): Sheet
	local state = seed % 2147483647
	if state == 0 then
		state = 1
	end
	local function rand(lo: number, hi: number): number
		state = (state * 48271) % 2147483647 -- Park-Miller
		return lo + (state / 2147483647) * (hi - lo)
	end
	local blotches: { Mark } = {}
	for _ = 1, 3 do
		local w = rand(0.06, 0.22)
		local h = w * rand(0.5, 1.1)
		table.insert(blotches, { x = rand(0, 1 - w), y = rand(0, 1 - h), w = w, h = h, alpha = rand(0.78, 0.9) })
	end
	local ring: Mark? = nil
	if rand(0, 1) < 0.4 then
		local d = rand(0.14, 0.24)
		ring = { x = rand(0.02, 1 - d - 0.02), y = rand(0.02, 1 - d - 0.02), w = d, h = d, alpha = rand(0.6, 0.75) }
	end
	return {
		blotches = blotches,
		ring = ring,
		crease = { y = rand(0.3, 0.75), rotation = rand(-2.5, 2.5) },
		chip = 1 + math.floor(rand(0, 3.999)),
	}
end

return PaperLayout
