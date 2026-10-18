--!strict
-- Client side of the terrain: the voxels, palette and pick planes are built by the server
-- (src/server/World.luau) and replicate; this keeps only the per-client bits.

local Terrain = {}

-- Grass decoration (the blades Terrain draws on Grass and LeafyGrass) costs GPU; on by quality.
function Terrain.setDecoration(on: boolean)
	pcall(function()
		(workspace.Terrain :: any).Decoration = on
	end)
end

-- The folder holding the server's pick-plane tiles; raycast include lists take descendants.
function Terrain.pickPlane(): Instance?
	local root = workspace:FindFirstChild("EoEWorld")
	return if root then root:FindFirstChild("PickPlane") else nil
end

return Terrain
