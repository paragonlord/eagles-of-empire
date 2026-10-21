--!strict
-- Authoritative terrain grid: heights, terrain classes and clearance at Config.Map.CellSize.
-- Used by the server for navigation / LOS / placement and by the client to build visuals.
-- Flat arrays, 0-based cell coordinates, index = cz * cols + cx + 1.

local Config = require(script.Parent.Config)
local Vec = require(script.Parent.Vec)

type Vec = Vec.Vec

export type Grid = {
	cols: number,
	rows: number,
	cell: number,
	width: number,
	depth: number,
	height: { number },
	class: { number },
	clearance: { number }, -- studs to nearest impassable cell / map edge
	water: { [number]: number }?, -- river cells: the water surface there (MapGen)
}

local Grid = {}

local IDS = Config.TerrainIds
local TERRAIN = Config.Terrain

function Grid.new(cols: number, rows: number, cell: number): Grid
	local n = cols * rows
	local height = table.create(n, 0)
	local class = table.create(n, IDS.open)
	local clearance = table.create(n, 0)
	return {
		cols = cols,
		rows = rows,
		cell = cell,
		width = cols * cell,
		depth = rows * cell,
		height = height,
		class = class,
		clearance = clearance,
	}
end

function Grid.index(g: Grid, cx: number, cz: number): number
	return cz * g.cols + cx + 1
end

-- Cell containing world point, clamped to the grid.
function Grid.cellOf(g: Grid, x: number, z: number): (number, number)
	local cx = math.clamp(math.floor(x / g.cell), 0, g.cols - 1)
	local cz = math.clamp(math.floor(z / g.cell), 0, g.rows - 1)
	return cx, cz
end

function Grid.cellCenter(g: Grid, cx: number, cz: number): Vec
	return { x = (cx + 0.5) * g.cell, z = (cz + 0.5) * g.cell }
end

function Grid.inBounds(g: Grid, x: number, z: number): boolean
	return x >= 0 and z >= 0 and x < g.width and z < g.depth
end

function Grid.classAt(g: Grid, x: number, z: number): number
	local cx, cz = Grid.cellOf(g, x, z)
	return g.class[cz * g.cols + cx + 1]
end

function Grid.terrainAt(g: Grid, x: number, z: number)
	return TERRAIN[Grid.classAt(g, x, z)]
end

-- Bilinear height between cell centres.
function Grid.heightAt(g: Grid, x: number, z: number): number
	local fx = math.clamp(x / g.cell - 0.5, 0, g.cols - 1)
	local fz = math.clamp(z / g.cell - 0.5, 0, g.rows - 1)
	local x0 = math.floor(fx)
	local z0 = math.floor(fz)
	local x1 = math.min(x0 + 1, g.cols - 1)
	local z1 = math.min(z0 + 1, g.rows - 1)
	local tx = fx - x0
	local tz = fz - z0
	local h = g.height
	local c = g.cols
	local h00 = h[z0 * c + x0 + 1]
	local h10 = h[z0 * c + x1 + 1]
	local h01 = h[z1 * c + x0 + 1]
	local h11 = h[z1 * c + x1 + 1]
	local a = h00 + (h10 - h00) * tx
	local b = h01 + (h11 - h01) * tx
	return a + (b - a) * tz
end

-- Rise per stud along x and z (central differences over one cell).
function Grid.gradient(g: Grid, x: number, z: number): (number, number)
	local d = g.cell
	local gx = (Grid.heightAt(g, x + d, z) - Grid.heightAt(g, x - d, z)) / (2 * d)
	local gz = (Grid.heightAt(g, x, z + d) - Grid.heightAt(g, x, z - d)) / (2 * d)
	return gx, gz
end

function Grid.slopeMagnitude(g: Grid, x: number, z: number): number
	local gx, gz = Grid.gradient(g, x, z)
	return math.sqrt(gx * gx + gz * gz)
end

-- Signed rise per stud when moving in direction dir (unit vector). Positive = uphill.
function Grid.slopeAlong(g: Grid, x: number, z: number, dir: Vec): number
	local gx, gz = Grid.gradient(g, x, z)
	return gx * dir.x + gz * dir.z
end

function Grid.isPassableCell(g: Grid, cx: number, cz: number): boolean
	if cx < 0 or cz < 0 or cx >= g.cols or cz >= g.rows then
		return false
	end
	return TERRAIN[g.class[cz * g.cols + cx + 1]].passable
end

function Grid.clearanceAt(g: Grid, x: number, z: number): number
	if not Grid.inBounds(g, x, z) then
		return 0
	end
	local cx, cz = Grid.cellOf(g, x, z)
	return g.clearance[cz * g.cols + cx + 1]
end

-- A footprint of the given half-width fits at (x, z).
function Grid.fits(g: Grid, x: number, z: number, halfWidth: number): boolean
	return Grid.clearanceAt(g, x, z) >= halfWidth
end

-- Multi-source BFS (8-neighbour, Chebyshev) from impassable cells and the map border.
-- clearance = cells * cell size; an impassable cell has clearance 0.
function Grid.computeClearance(g: Grid)
	local cols, rows = g.cols, g.rows
	local n = cols * rows
	local dist = table.create(n, -1)
	local queue = table.create(n, 0)
	local head, tail = 1, 0
	local class = g.class
	for i = 1, n do
		local cx = (i - 1) % cols
		local cz = (i - 1) // cols
		local border = cx == 0 or cz == 0 or cx == cols - 1 or cz == rows - 1
		if not TERRAIN[class[i]].passable then
			dist[i] = 0
			tail += 1
			queue[tail] = i
		elseif border then
			dist[i] = 1
			tail += 1
			queue[tail] = i
		end
	end
	while head <= tail do
		local i = queue[head]
		head += 1
		local cx = (i - 1) % cols
		local cz = (i - 1) // cols
		local d = dist[i] + 1
		for dz = -1, 1 do
			local nz = cz + dz
			if nz >= 0 and nz < rows then
				for dx = -1, 1 do
					local nx = cx + dx
					if nx >= 0 and nx < cols then
						local j = nz * cols + nx + 1
						if dist[j] < 0 then
							dist[j] = d
							tail += 1
							queue[tail] = j
						end
					end
				end
			end
		end
	end
	local clearance = g.clearance
	local cell = g.cell
	for i = 1, n do
		clearance[i] = math.max(dist[i], 0) * cell
	end
end

-- Line of sight between two ground points. Intermediate samples use terrain height plus the
-- class sightHeight (woods/village block). Samples within `skip` studs of either end are
-- ignored so a unit at a wood's edge can see out; spotting units *inside* cover is handled by
-- Config.Vision.WoodsReveal in the visibility module.
-- The village or wood an end stands in does not block its own line within OWN_COVER studs: men in
-- houses or among trees look and fire out of them, and are seen and fired on there (the terrain's
-- cover counts instead). A village, wood or crest between the two still blocks. Without this every
-- line into or out of a village was blocked and village fights stood still.
local OWN_COVER = 80
function Grid.lineOfSight(g: Grid, a: Vec, b: Vec, eyeA: number?, eyeB: number?): boolean
	local ea = (eyeA or Config.Vision.EyeHeight)
	local eb = (eyeB or Config.Vision.EyeHeight)
	local ha = Grid.heightAt(g, a.x, a.z) + ea
	local hb = Grid.heightAt(g, b.x, b.z) + eb
	local dx, dz = b.x - a.x, b.z - a.z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < g.cell then
		return true
	end
	local clsA, clsB = Grid.classAt(g, a.x, a.z), Grid.classAt(g, b.x, b.z)
	local step = g.cell
	local skip = 8
	local steps = math.floor(len / step)
	for i = 1, steps - 1 do
		local t = i / steps
		local s = t * len
		if s > skip and s < len - skip then
			local x = a.x + dx * t
			local z = a.z + dz * t
			local cx, cz = Grid.cellOf(g, x, z)
			local cls = g.class[cz * g.cols + cx + 1]
			local own = (cls == clsA and s <= OWN_COVER) or (cls == clsB and len - s <= OWN_COVER)
			local terrainH = Grid.heightAt(g, x, z) + (if own then 0 else TERRAIN[cls].sightHeight)
			local lineH = ha + (hb - ha) * t
			if terrainH > lineH + Config.Vision.SightTolerance then
				return false
			end
		end
	end
	return true
end

Grid.Ids = IDS

return Grid
