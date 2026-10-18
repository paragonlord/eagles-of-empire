--!strict
-- Rendered-ground sampler for everything cosmetic (figures, bodies, rings, ghosts, smoke).
-- The sim's heightmap (`Grid.heightAt`) is an approximation of the voxel terrain; the
-- figures must stand on what is actually drawn, so this casts rays down onto
-- workspace.Terrain plus the world's bridges (EoEWorld.Water*), caches one sample per
-- 2-stud grid node for 0.5 s, and interpolates bilinearly between nodes. Rays are capped
-- per frame; a node that cannot be refreshed keeps its last sample, and before the world is
-- ready the heightmap stands in.
--
-- `Ground.lift` is the pure four-corner rule: how far an upright (or pitched) body must
-- rise so no corner of its footprint sinks into the surface.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Grid = require(Shared.Grid)
local BattleState = require(script.Parent.BattleState)

local Ground = {}

local CELL = 2
local REFRESH = 0.5
local MAX_RAYS_PER_FRAME = 100 -- ~1 ms of raycasts at most; stale nodes keep their last sample
local CLEARANCE = 0.05

type Node = { y: number, t: number }
local cache: { [number]: Node } = {}
local params: RaycastParams? = nil
local worldRoot: Instance? = nil
local worldKey = ""
local raysThisFrame = 0
local rayTime = 0
local lastRays, lastMs = 0, 0

local function fallback(x: number, z: number): number
	local m = BattleState.map
	return if m then Grid.heightAt(m.grid, x, z) else 0
end

-- Terrain plus the world's bridge decks; rebuilt when the world folder is replaced.
local function filter(): RaycastParams
	local root = workspace:FindFirstChild("EoEWorld")
	local key = if root then tostring(root:GetAttribute("WorldReady") or "") else ""
	local p = params
	if p and root == worldRoot and key == worldKey then
		return p
	end
	worldRoot, worldKey = root, key
	p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.IgnoreWater = false -- a figure at the water's edge stands on the surface, never under it
	local list: { Instance } = { workspace.Terrain }
	if root then
		for _, name in { "Water", "WaterQ2" } do
			local f = root:FindFirstChild(name)
			if f then
				table.insert(list, f)
			end
		end
	end
	p.FilterDescendantsInstances = list
	params = p
	return p
end

local function nodeKey(ix: number, iz: number): number
	return ix * 1048576 + iz + 524288
end

-- Ground at a grid node (ix, iz), cached; one raycast per node per REFRESH.
local function node(ix: number, iz: number, now: number): number
	local key = nodeKey(ix, iz)
	local e = cache[key]
	if e and now - e.t < REFRESH then
		return e.y
	end
	local wx, wz = ix * CELL, iz * CELL
	if raysThisFrame >= MAX_RAYS_PER_FRAME then
		return if e then e.y else fallback(wx, wz)
	end
	raysThisFrame += 1
	local t0 = os.clock()
	local hit = workspace:Raycast(Vector3.new(wx, 1000, wz), Vector3.new(0, -1600, 0), filter())
	rayTime += os.clock() - t0
	local y = if hit then hit.Position.Y else fallback(wx, wz)
	if e then
		e.y, e.t = y, now
	else
		cache[key] = { y = y, t = now }
	end
	return y
end

-- Rendered ground height under (x, z): bilinear between the four surrounding nodes.
function Ground.heightAt(x: number, z: number): number
	local gx, gz = x / CELL, z / CELL
	local ix, iz = math.floor(gx), math.floor(gz)
	local fx, fz = gx - ix, gz - iz
	local now = os.clock()
	local y00 = node(ix, iz, now)
	local y10 = node(ix + 1, iz, now)
	local y01 = node(ix, iz + 1, now)
	local y11 = node(ix + 1, iz + 1, now)
	return (y00 * (1 - fx) + y10 * fx) * (1 - fz) + (y01 * (1 - fx) + y11 * fx) * fz
end

-- Four-corner lift (pure). `base` is the height the body stands at under its centre;
-- `corners` the ground under each footprint corner; `plane` (optional) the body's underside
-- at each corner when it is pitched to the slope (defaults to `base` everywhere). Returns
-- how far to raise the body so every corner clears the surface by CLEARANCE, or 0 when
-- nothing sinks.
function Ground.lift(base: number, corners: { number }, plane: { number }?): number
	local worst = 0
	for i, h in corners do
		local under = if plane then plane[i] else base
		local short = h - under
		if short > worst then
			worst = short
		end
	end
	return if worst > 0 then worst + CLEARANCE else 0
end

-- Lift for an upright body with a half-footprint (hx forward, hz right) at (x, z) facing
-- `heading`, standing at `base`. `slope` (rise per stud forward) describes a pitched body.
function Ground.liftAt(x: number, z: number, base: number, heading: number, hx: number, hz: number, slope: number?): number
	local fx, fz = math.cos(heading), math.sin(heading)
	local rx, rz = -fz, fx
	local corners: { number } = {}
	local plane: { number }? = if slope then {} else nil
	local i = 0
	for _, dx in { -hx, hx } do
		for _, dz in { -hz, hz } do
			i += 1
			corners[i] = Ground.heightAt(x + fx * dx + rx * dz, z + fz * dx + rz * dz)
			if plane and slope then
				plane[i] = base + slope * dx
			end
		end
	end
	return Ground.lift(base, corners, plane)
end

-- Per-frame bookkeeping: the ray cap and the cost of the last frame's rays.
function Ground.beginFrame()
	lastRays, lastMs = raysThisFrame, rayTime * 1000
	raysThisFrame = 0
	rayTime = 0
end

function Ground.stats(): (number, number)
	return lastRays, lastMs
end

function Ground.clear()
	table.clear(cache)
	params = nil
	worldRoot = nil
end

Ground.CLEARANCE = CLEARANCE

return Ground
