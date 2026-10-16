--!strict
-- Formation navigation on a coarse grid derived from the terrain grid.
-- Nodes are Config.Map.NavCellSize studs; a node is walkable when its clearance allows at
-- least a travel column (half-width 8). Cost = distance / infantry terrain speed.
-- A* with a binary heap, then string-pulling that keeps the path inside walkable, clear ground.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Vec = require(Shared.Vec)

type Vec = Vec.Vec
type Grid = Grid.Grid

export type NavGrid = {
	cols: number,
	rows: number,
	size: number,
	walk: { boolean },
	cost: { number }, -- per-node traversal cost multiplier (1 / speed)
	clear: { number }, -- min clearance in the node (studs)
	grid: Grid,
	cache: { [string]: { Vec }? },
}

local Nav = {}

local TRAVEL_HALF = 8
local SQRT2 = math.sqrt(2)

function Nav.build(grid: Grid): NavGrid
	local size = Config.Map.NavCellSize
	local cols = grid.width // size
	local rows = grid.depth // size
	local n = cols * rows
	local walk = table.create(n, false)
	local cost = table.create(n, 1)
	local clear = table.create(n, 0)
	local sub = size // grid.cell
	for nz = 0, rows - 1 do
		for nx = 0, cols - 1 do
			local maxClear = 0
			local speedSum = 0
			local count = 0
			local passable = true
			for sz = 0, sub - 1 do
				for sx = 0, sub - 1 do
					local cx = nx * sub + sx
					local cz = nz * sub + sz
					local idx = cz * grid.cols + cx + 1
					local t = Config.Terrain[grid.class[idx]]
					if not t.passable then
						passable = false
					end
					speedSum += t.speed
					count += 1
					if grid.clearance[idx] > maxClear then
						maxClear = grid.clearance[idx]
					end
				end
			end
			local i = nz * cols + nx + 1
			-- Some cell in the node must leave room for a travel column (bridges, defiles).
			walk[i] = passable or maxClear >= TRAVEL_HALF
			clear[i] = maxClear
			local avg = speedSum / count
			cost[i] = if avg > 0.05 then 1 / avg else 20
		end
	end
	return { cols = cols, rows = rows, size = size, walk = walk, cost = cost, clear = clear, grid = grid, cache = {} }
end

local function nodeOf(nav: NavGrid, p: Vec): (number, number)
	return math.clamp(math.floor(p.x / nav.size), 0, nav.cols - 1), math.clamp(math.floor(p.z / nav.size), 0, nav.rows - 1)
end

local function centre(nav: NavGrid, nx: number, nz: number): Vec
	return { x = (nx + 0.5) * nav.size, z = (nz + 0.5) * nav.size }
end

-- Binary heap keyed on f-score.
local function heapPush(heap: { number }, keys: { number }, node: number)
	heap[#heap + 1] = node
	local i = #heap
	while i > 1 do
		local parent = i // 2
		if keys[heap[parent]] <= keys[heap[i]] then
			break
		end
		heap[parent], heap[i] = heap[i], heap[parent]
		i = parent
	end
end

local function heapPop(heap: { number }, keys: { number }): number
	local top = heap[1]
	local last = table.remove(heap)
	if #heap > 0 and last then
		heap[1] = last
		local i = 1
		local n = #heap
		while true do
			local l, r = i * 2, i * 2 + 1
			local m = i
			if l <= n and keys[heap[l]] < keys[heap[m]] then
				m = l
			end
			if r <= n and keys[heap[r]] < keys[heap[m]] then
				m = r
			end
			if m == i then
				break
			end
			heap[m], heap[i] = heap[i], heap[m]
			i = m
		end
	end
	return top
end

-- Nearest walkable node to p (spiral search), or nil.
function Nav.nearestWalkable(nav: NavGrid, p: Vec, maxRadius: number?): Vec?
	local nx, nz = nodeOf(nav, p)
	local r = 0
	local limit = maxRadius or 6
	while r <= limit do
		for dz = -r, r do
			for dx = -r, r do
				if math.abs(dx) == r or math.abs(dz) == r then
					local x, z = nx + dx, nz + dz
					if x >= 0 and z >= 0 and x < nav.cols and z < nav.rows and nav.walk[z * nav.cols + x + 1] then
						return centre(nav, x, z)
					end
				end
			end
		end
		r += 1
	end
	return nil
end

function Nav.isWalkable(nav: NavGrid, p: Vec): boolean
	if not Grid.inBounds(nav.grid, p.x, p.z) then
		return false
	end
	local nx, nz = nodeOf(nav, p)
	return nav.walk[nz * nav.cols + nx + 1]
end

-- Straight segment stays on walkable nodes with clearance >= halfWidth (sampled every 4 studs).
local function segmentClear(nav: NavGrid, a: Vec, b: Vec, halfWidth: number): boolean
	local d = Vec.dist(a, b)
	local steps = math.max(1, math.ceil(d / 4))
	for i = 0, steps do
		local t = i / steps
		local x = a.x + (b.x - a.x) * t
		local z = a.z + (b.z - a.z) * t
		if not Grid.inBounds(nav.grid, x, z) then
			return false
		end
		local nx, nz = nodeOf(nav, { x = x, z = z })
		local idx = nz * nav.cols + nx + 1
		if not nav.walk[idx] then
			return false
		end
		if Grid.clearanceAt(nav.grid, x, z) < halfWidth then
			return false
		end
	end
	return true
end

-- A* from a to b. Returns a list of waypoints (excluding a, ending at b or the nearest
-- reachable point), or nil when no route exists. halfWidth only affects smoothing.
function Nav.findPath(nav: NavGrid, a: Vec, b: Vec, halfWidth: number): { Vec }?
	local cols, rows = nav.cols, nav.rows
	local sx, sz = nodeOf(nav, a)
	local gx, gz = nodeOf(nav, b)
	local start = sz * cols + sx + 1
	local goal = gz * cols + gx + 1
	if not nav.walk[goal] then
		local alt = Nav.nearestWalkable(nav, b, 4)
		if not alt then
			return nil
		end
		gx, gz = nodeOf(nav, alt)
		goal = gz * cols + gx + 1
		b = alt
	end
	if not nav.walk[start] then
		local alt = Nav.nearestWalkable(nav, a, 4)
		if not alt then
			return nil
		end
		sx, sz = nodeOf(nav, alt)
		start = sz * cols + sx + 1
	end
	local key = start .. ":" .. goal
	local cached = nav.cache[key]
	if cached ~= nil then
		return Nav.smooth(nav, a, cached, halfWidth)
	end

	local gScore: { [number]: number } = { [start] = 0 }
	local fScore: { number } = {}
	local came: { [number]: number } = {}
	local closed: { [number]: boolean } = {}
	local heap: { number } = {}
	local function h(i: number): number
		local x = (i - 1) % cols
		local z = (i - 1) // cols
		local dx, dz = math.abs(x - gx), math.abs(z - gz)
		return (math.max(dx, dz) + (SQRT2 - 1) * math.min(dx, dz)) * 0.7 -- admissible (min cost 1/1.3)
	end
	fScore[start] = h(start)
	heapPush(heap, fScore, start)
	local found = false
	local expanded = 0
	while #heap > 0 do
		local cur = heapPop(heap, fScore)
		if cur == goal then
			found = true
			break
		end
		if not closed[cur] then
			closed[cur] = true
			expanded += 1
			if expanded > 20000 then
				break
			end
			local cx = (cur - 1) % cols
			local cz = (cur - 1) // cols
			for dz = -1, 1 do
				for dx = -1, 1 do
					if dx ~= 0 or dz ~= 0 then
						local nx, nz = cx + dx, cz + dz
						if nx >= 0 and nz >= 0 and nx < cols and nz < rows then
							local ni = nz * cols + nx + 1
							if nav.walk[ni] and not closed[ni] then
								-- no corner cutting past blocked nodes
								local okDiag = true
								if dx ~= 0 and dz ~= 0 then
									okDiag = nav.walk[cz * cols + nx + 1] and nav.walk[nz * cols + cx + 1]
								end
								if okDiag then
									local stepCost = (if dx ~= 0 and dz ~= 0 then SQRT2 else 1) * (nav.cost[cur] + nav.cost[ni]) * 0.5
									local tentative = gScore[cur] + stepCost
									if gScore[ni] == nil or tentative < gScore[ni] then
										gScore[ni] = tentative
										came[ni] = cur
										fScore[ni] = tentative + h(ni)
										heapPush(heap, fScore, ni)
									end
								end
							end
						end
					end
				end
			end
		end
	end
	if not found then
		nav.cache[key] = nil
		return nil
	end
	local nodes: { Vec } = {}
	local cur = goal
	while cur ~= start do
		local x = (cur - 1) % cols
		local z = (cur - 1) // cols
		table.insert(nodes, 1, centre(nav, x, z))
		cur = came[cur]
	end
	nodes[#nodes] = b -- end exactly at the requested point
	nav.cache[key] = nodes
	return Nav.smooth(nav, a, nodes, halfWidth)
end

-- String pulling: from the current point, jump to the farthest waypoint reachable in a
-- straight clear line. Falls back to a column-width check so narrow passages are kept.
function Nav.smooth(nav: NavGrid, from: Vec, nodes: { Vec }, halfWidth: number): { Vec }
	local out: { Vec } = {}
	local cur = from
	local i = 1
	local n = #nodes
	while i <= n do
		local best = i
		for j = n, i + 1, -1 do
			if segmentClear(nav, cur, nodes[j], halfWidth) or segmentClear(nav, cur, nodes[j], TRAVEL_HALF) and j - i <= 2 then
				best = j
				break
			end
		end
		out[#out + 1] = nodes[best]
		cur = nodes[best]
		i = best + 1
	end
	return out
end

-- Minimum clearance along the next segment of a path from p (sampled), used to decide
-- whether the formation must adopt a travel column.
function Nav.segmentMinClearance(nav: NavGrid, a: Vec, b: Vec): number
	local d = Vec.dist(a, b)
	local steps = math.max(1, math.ceil(d / 8))
	local minC = math.huge
	for i = 0, steps do
		local t = i / steps
		local c = Grid.clearanceAt(nav.grid, a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t)
		if c < minC then
			minC = c
		end
	end
	return minC
end

return Nav
