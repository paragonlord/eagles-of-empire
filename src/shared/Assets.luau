--!strict
-- Named slots for Creator Store assets (no ids are checked in). A slot with a mesh id makes
-- the client build that object as one Part with a SpecialMesh (FileMesh) instead of the part
-- assembly; an empty slot keeps the procedural build. Fill `mesh`/`texture` with
-- "rbxassetid://<id>" and set `scale` so the mesh fits the figure's studs (the Studio session
-- does this from the asset's native size). Add keys only; both the figures (Soldiers) and
-- the world (Props/WorldGen) read this table.

export type Slot = {
	mesh: string, -- "rbxassetid://..." or ""
	texture: string,
	scale: { number }, -- SpecialMesh.Scale (x, y, z)
	offset: { number }, -- SpecialMesh.Offset (x, y, z), studs
}

local function slot(): Slot
	return { mesh = "", texture = "", scale = { 1, 1, 1 }, offset = { 0, 0, 0 } }
end

local Assets = {}

-- Figures (Soldiers.luau): one mesh per figure, origin on the ground, facing +X, sized in studs.
Assets.slots = {
	soldierInfantry = slot(), -- a standing musketeer ~3.2 studs tall
	soldierCavalry = slot(), -- horse and rider ~4 studs tall, 3.6 long
	horse = slot(), -- a horse alone (limber teams)
	gun = slot(), -- field gun on its carriage, muzzle toward +X
	limber = slot(), -- limber with its chest
	shako = slot(), -- headgear swaps, worn on top of the procedural head
	bearskin = slot(),
	helmet = slot(),
	-- World (WorldGen): one mesh per object, origin on the ground, facing +X (the road side),
	-- scaled to the procedural object's bounds given in WorldGen's meshObject calls.
	treeOak = slot(), -- broad oak ~r 5: 12 wide, 13 tall
	treeBeech = slot(),
	treePine = slot(),
	treePoplar = slot(), -- narrow spindle ~16 tall
	treeWillow = slot(),
	houseA = slot(), -- cottage ~5 x 5 footprint, 2.6 eaves, gable ridge along +X
	houseB = slot(),
	houseC = slot(),
	barn = slot(),
	church = slot(), -- nave 13 long with a west tower, ~22 tall
	windmill = slot(), -- post mill ~20 tall
	bridgeStone = slot(), -- deck along +X, length = the span given
	bridgeTimber = slot(),
	-- World textures (Texture instances on part faces; `texture` only, mesh stays "")
	bark = slot(),
	roofTile = slot(),
	wall = slot(),
	thatch = slot(),
}

-- A texture id for a slot, or nil when the slot has none.
function Assets.textureOf(key: string): string?
	local s = (Assets.slots :: { [string]: Slot })[key]
	if s and s.texture ~= "" then
		return s.texture
	end
	return nil
end

function Assets.get(key: string): Slot?
	local s = (Assets.slots :: { [string]: Slot })[key]
	if s and s.mesh ~= "" then
		return s
	end
	return nil
end

return Assets
