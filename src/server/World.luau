--!strict
-- Builds the battlefield once per map on the server: terrain voxels and the structure tier of
-- WorldGen's props (ground, fields, bridges, houses, trees, walls, hedges) under
-- workspace.EoEWorld, which replicates to every client. The root folder carries attributes:
--   MapId      the map being built (set before the first part)
--   WorldReady the number of parts, set once every part is parented (clients gate on it)
-- Quality is capped at 2: phones hide the "<group>Q2" folders locally instead of rebuilding.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("EoE")
local WorldGen = require(Shared.WorldGen)
local WorldBuild = require(Shared.WorldBuild)

local World = {}

local ROOT = "EoEWorld"
local SERVER_Q = 2
local builtId: string? = nil
local wanted: any = nil
local scheduled = false
local token = 0

local function build(map: any)
	token += 1
	local my = token
	local function alive(): boolean
		return token == my
	end
	builtId = map.id
	local old = workspace:FindFirstChild(ROOT)
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder") :: Folder
	root.Name = ROOT
	root:SetAttribute("MapId", map.id)
	root.Parent = workspace
	local t0 = os.clock()
	local terrain = WorldGen.terrain(map)
	WorldBuild.applyPalette(map)
	workspace.Terrain:Clear()
	if not WorldBuild.writeVoxels(terrain, alive) then
		return
	end
	local specs = WorldGen.props(map, terrain, { maxQ = SERVER_Q, detail = false, yield = function()
		task.wait()
	end })
	if not alive() then
		return
	end
	local n = WorldBuild.spawn(specs, root, alive)
	if not n then
		return
	end
	root:SetAttribute("WorldReady", n)
	print(string.format("[EoE world] built %d parts for %s in %.1f s", n, map.id, os.clock() - t0))
	task.spawn(World.checkClip, root, alive)
end

-- Debug: raycasts down onto the terrain under the lowest points of every world part (parts
-- marked Buried are meant to sit in the ground) and reports how many sit more than 0.1 below
-- the surface. Spread over frames; prints "[EoE clip] world: N parts below ground" (expect 0).
function World.checkClip(root: Instance, alive: () -> boolean)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local below, checked = 0, 0
	local n = 0
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") and not p:GetAttribute("Buried") and (p :: BasePart).Transparency < 1 then
			local bp = p :: BasePart
			-- the part's true shape: a sphere's lowest point, a cylinder's end circles, a box's corners
			local kind: WorldGen.ShapeKind = "box"
			if bp:IsA("Part") then
				local shape = (bp :: Part).Shape
				if shape == Enum.PartType.Ball or bp:FindFirstChildOfClass("SpecialMesh") then
					kind = "ellipsoid"
				elseif shape == Enum.PartType.Cylinder then
					kind = "cylinder"
				end
			end
			local worst = false
			for _, q in WorldGen.lowPoints(bp.CFrame, bp.Size, kind) do
				local hit = workspace:Raycast(q + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), params)
				if hit and hit.Position.Y > q.Y + 0.1 then
					worst = true
					break
				end
			end
			if worst then
				below += 1
			end
			checked += 1
			n += 1
			if n % 400 == 0 then
				task.wait()
				if not alive() then
					return
				end
			end
		end
	end
	root:SetAttribute("ClipBelowGround", below)
	print(string.format("[EoE clip] world: %d parts below ground (%d checked)", below, checked))
end

-- Makes sure `map` is the built world; a different map replaces the current one. Deferred so
-- a destroy/create pair in one frame builds once; the build itself yields every batch.
function World.ensure(map: any)
	wanted = map
	if scheduled then
		return
	end
	scheduled = true
	task.defer(function()
		scheduled = false
		if wanted and wanted.id ~= builtId then
			build(wanted)
		end
	end)
end

function World.clear()
	token += 1
	builtId = nil
	wanted = nil
	local old = workspace:FindFirstChild(ROOT)
	if old then
		old:Destroy()
	end
end

return World
