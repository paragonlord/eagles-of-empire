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

-- Painted ground: the place's generated MaterialVariants (default.project.json, MaterialService)
-- stand in for the base materials the battle terrain and walls use. A place without them keeps
-- the stock look. The season tint (Terrain:SetMaterialColor) still applies over them.
local GROUND: { [EnumMaterial]: string } = {
	[Enum.Material.Grass] = "EoEMeadow",
	[Enum.Material.LeafyGrass] = "EoEPasture",
	[Enum.Material.Limestone] = "EoEStubble",
	[Enum.Material.Mud] = "EoEPlough",
	[Enum.Material.Ground] = "EoETrack",
	[Enum.Material.Cobblestone] = "EoECobble",
	[Enum.Material.Rock] = "EoERock",
}
function Terrain.paintGround()
	local ms = game:GetService("MaterialService")
	for base, name in GROUND do
		if ms:FindFirstChild(name) then
			pcall(function()
				ms:SetBaseMaterialOverride(base, name)
			end)
		end
	end
end

-- The folder holding the server's pick-plane tiles; raycast include lists take descendants.
function Terrain.pickPlane(): Instance?
	local root = workspace:FindFirstChild("EoEWorld")
	return if root then root:FindFirstChild("PickPlane") else nil
end

return Terrain
