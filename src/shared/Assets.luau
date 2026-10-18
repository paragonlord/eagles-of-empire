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
	native: { number }?, -- the mesh's own size in studs (Studio shows it on import); world meshes are
	-- then fitted to each object's box, so one oak mesh serves every oak size
}

local function slot(texture: string?): Slot
	return { mesh = "", texture = texture or "", scale = { 1, 1, 1 }, offset = { 0, 0, 0 } }
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
	treeOak = { -- original 848-triangle oak; native bounds 12 x 13 x 12 studs
		mesh = "rbxassetid://73559467519799",
		texture = "rbxassetid://139915483990126",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 12, 13, 12 },
	},
	treeBeech = { -- original 600-triangle beech; native bounds confirmed in Studio
		mesh = "rbxassetid://112134639390683",
		texture = "rbxassetid://107894282230802",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 10, 16, 10 },
	},
	treePine = { -- original 444-triangle pine; native bounds confirmed in Studio
		mesh = "rbxassetid://82857667018871",
		texture = "rbxassetid://130754173408547",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 8, 18, 8 },
	},
	treePoplar = { -- original 200-triangle poplar; native bounds confirmed in Studio
		mesh = "rbxassetid://140076983958671",
		texture = "rbxassetid://130600435597827",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 4, 16, 4 },
	},
	treeWillow = slot(),
	houseA = { -- original 788-triangle whitewashed cottage; ridge along +X
		mesh = "rbxassetid://91534964288834",
		texture = "rbxassetid://84033137999917",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 7, 6, 5 },
	},
	houseB = slot(),
	houseC = slot(),
	barn = slot(),
	church = slot(), -- nave 13 long with a west tower, ~22 tall
	windmill = slot(), -- post mill ~20 tall
	bridgeStone = slot(), -- deck along +X, length = the span given
	bridgeTimber = slot(),
	-- World textures (Texture instances on part faces; `texture` only, mesh stays "")
	-- image ids (not the store's decal ids), free on the Creator Store, picked in Studio (qa round 22)
	bark = slot("rbxassetid://6490108541"), -- "TexturesCom_PineBark2_512_albedo", DarthRevan404
	roofTile = slot("rbxassetid://18708362091"), -- "roof_tile_texture4127", Phatgamingsk2
	wall = slot("rbxassetid://762795527"), -- "Seamless wall white paint stucco plaster", yumahap
	thatch = slot("rbxassetid://4125863236"), -- "Seamless Hay Texture", DjordyKK (tried on Austerlitz)
}

-- Sounds (client Audio.luau). `id` is "rbxassetid://<id>" or, for a slot with `variants` > 1, a
-- list of them (`id = { "rbxassetid://a", "rbxassetid://b" }`); a single id still gets pitch
-- variation. `pitch` is the PlaybackSpeed range rolled per play, `volume` the slot's level before
-- the buses. An empty id plays nothing and creates nothing. Keep keys; fill ids in Studio
-- (docs/vision.md, Audio).
export type Sound = { id: string | { string }, volume: number, pitch: { number }, variants: number, loop: boolean? }

local function sound(volume: number, pitch: { number }, variants: number?, loop: boolean?): Sound
	return { id = "", volume = volume, pitch = pitch, variants = variants or 1, loop = loop }
end

Assets.sounds = {
	-- battle, positional (anchored at the event, rolled off by camera height)
	musketVolley = sound(0.8, { 0.92, 1.08 }, 3), -- a battalion's volley, ~1 s of crackle
	musketScatter = sound(0.5, { 0.9, 1.1 }), -- scattered skirmish fire
	cannonFire = sound(1, { 0.9, 1.05 }, 3),
	cannonBounce = sound(0.6, { 0.9, 1.1 }), -- roundshot graze / earth
	canister = sound(0.9, { 0.95, 1.05 }), -- the shotgun blast of a canister round
	cavalryCharge = sound(0.8, { 0.95, 1.05 }), -- hooves at the gallop, ~4 s
	cavalryImpact = sound(0.9, { 0.95, 1.05 }), -- horses into a line
	meleeClash = sound(0.6, { 1, 1 }, 1, true), -- steel and shouting, loop
	drumsMarchFr = sound(0.5, { 1, 1 }, 1, true), -- pas de charge, loop per faction
	drumsMarchPr = sound(0.5, { 1, 1 }, 1, true),
	drumsMarchAt = sound(0.5, { 1, 1 }, 1, true),
	drumsMarchRu = sound(0.5, { 1, 1 }, 1, true),
	drumsMarchGb = sound(0.5, { 1, 1 }, 1, true),
	fifeMarch = sound(0.4, { 1, 1 }, 1, true),
	bugleCharge = sound(0.7, { 0.97, 1.03 }),
	bugleRally = sound(0.6, { 0.97, 1.03 }),
	rout = sound(0.6, { 0.95, 1.05 }), -- cries, a line breaking
	unitDestroyed = sound(0.6, { 0.95, 1.05 }),
	-- battle, 2D
	capture = sound(0.7, { 1, 1 }),
	objectiveLost = sound(0.7, { 1, 1 }),
	victory = sound(0.9, { 1, 1 }),
	defeat = sound(0.9, { 1, 1 }),
	momentSting = sound(0.8, { 1, 1 }), -- under a moment card; music ducks
	ping = sound(0.6, { 1, 1 }), -- co-op map ping
	-- interface
	uiClick = sound(0.5, { 0.97, 1.03 }),
	uiHover = sound(0.25, { 0.97, 1.03 }),
	uiPaper = sound(0.5, { 0.95, 1.05 }), -- a sheet laid on the desk
	uiSeal = sound(0.5, { 0.97, 1.03 }), -- wax seal / stamp
	-- ambience loops by weather grade
	ambienceField = sound(0.5, { 1, 1 }, 1, true), -- wind and birds
	ambienceRain = sound(0.6, { 1, 1 }, 1, true),
	ambienceFog = sound(0.4, { 1, 1 }, 1, true), -- muffled, close
	-- music (loops, crossfaded by the state machine)
	menuMusic = sound(0.6, { 1, 1 }, 1, true),
	battleMusicCalm = sound(0.5, { 1, 1 }, 1, true),
	battleMusicTense = sound(0.6, { 1, 1 }, 1, true),
	campaignMusic = sound(0.5, { 1, 1 }, 1, true),
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
