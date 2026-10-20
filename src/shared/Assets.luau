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
	tint: { number }?, -- SpecialMesh.VertexColor over the texture (r, g, b multipliers)
}

-- A generated figure kit (tools/kit_import.luau): one textured mesh per body piece, placed in the
-- figure frame (+X forward, +Y up, +Z right, ground at 0). Soldiers poses the pieces with the
-- part-built figure's anim codes, so the kit marches, reloads and charges like it.
export type Piece = {
	mesh: string,
	texture: string,
	size: { number }, -- carrier part, studs
	scale: { number }, -- SpecialMesh.Scale
	cf: { number }, -- x, y, z, then XYZ Euler angles (radians)
}
export type Kit = { [string]: Piece }

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
		tint = { 0.8, 0.85, 0.75 }, -- the generated greens read lime against the palette (qa rounds 27-28)
	},
	treeBeech = { -- original 600-triangle beech; native bounds confirmed in Studio
		mesh = "rbxassetid://112134639390683",
		texture = "rbxassetid://107894282230802",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 10, 16, 10 },
		tint = { 0.8, 0.85, 0.75 }, -- the generated greens read lime against the palette (qa rounds 27-28)
	},
	treePine = { -- original 444-triangle pine; native bounds confirmed in Studio
		mesh = "rbxassetid://82857667018871",
		texture = "rbxassetid://130754173408547",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 8, 18, 8 },
		tint = { 0.8, 0.85, 0.75 }, -- the generated greens read lime against the palette (qa rounds 27-28)
	},
	treePoplar = { -- original 200-triangle poplar; native bounds confirmed in Studio
		mesh = "rbxassetid://140076983958671",
		texture = "rbxassetid://130600435597827",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 4, 16, 4 },
		tint = { 0.8, 0.85, 0.75 }, -- the generated greens read lime against the palette (qa rounds 27-28)
	},
	treeWillow = { -- generated weeping willow (graphics pass); native bounds read in Studio
		mesh = "rbxassetid://122959187552284",
		texture = "rbxassetid://109222457137290",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 9.71, 11, 8.97 },
		tint = { 0.85, 0.88, 0.8 },
	},
	houseA = { -- original 788-triangle whitewashed cottage; ridge along +X
		mesh = "rbxassetid://91534964288834",
		texture = "rbxassetid://84033137999917",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 5.6, 5.4, 4.5 }, -- measured in Studio (round 29): it now fills its plot like its neighbours
		tint = { 0.9, 0.84, 0.8 }, -- tones the bright orange roof down to the tinted part-built roofs
	},
	houseB = { -- original 1652-triangle timber-framed house; ridge along +X
		mesh = "rbxassetid://106845158633872",
		texture = "rbxassetid://84033137999917",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 8, 8, 6 },
	},
	houseC = slot(),
	barn = { -- original 440-triangle timber barn; ridge along +X
		mesh = "rbxassetid://110230662589871",
		texture = "rbxassetid://84033137999917",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 13, 7, 6 },
	},
	church = { -- original 1490-triangle church; nave +X, tower at the -X end
		mesh = "rbxassetid://136170488950314",
		texture = "rbxassetid://84909055465369",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 22, 22, 7.4 },
	},
	windmill = { -- original 908-triangle post mill; bounds include all four sails
		mesh = "rbxassetid://127694156629914",
		texture = "rbxassetid://84909055465369",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 20, 20, 20 },
	},
	bridgeStone = { -- generated stone arch bridge; deck along +X, length = the span given
		mesh = "rbxassetid://75690320300014",
		texture = "rbxassetid://85086594158546",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 12.4, 6, 4.77 },
	},
	bridgeTimber = { -- generated trestle bridge; deck along +X
		mesh = "rbxassetid://116235833337035",
		texture = "rbxassetid://77191135426847",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 5.6, 4, 3.32 },
	},
	hedge = { -- generated hedgerow section, long along Z (the border's length)
		mesh = "rbxassetid://109481830924513",
		texture = "rbxassetid://91535360470320",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 1.75, 2.88, 10 },
	},
	stoneWall = { -- generated dry-stone field wall with an end pillar each side, long along Z
		mesh = "rbxassetid://127916614194194",
		texture = "rbxassetid://85059598017560",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 0.81, 1.6, 4.98 },
	},
	reeds = { -- generated clump of river reeds and cattails on a muddy tuft
		mesh = "rbxassetid://129739908545802",
		texture = "rbxassetid://135174526017932",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 2.15, 2.6, 2.02 },
	},
	ship = { -- generated 74-gun ship of the line (campaign fleet token), keel along Z
		mesh = "rbxassetid://123365547551398",
		texture = "rbxassetid://82494823051177",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 3, 5.46, 6.53 },
	},
	cart = { -- generated two-wheeled farm cart, shafts along Z
		mesh = "rbxassetid://112271944313587",
		texture = "rbxassetid://121727660050649",
		scale = { 1, 1, 1 },
		offset = { 0, 0, 0 },
		native = { 2.15, 2.2, 2.99 },
	},
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

-- The first ids (2026-10-20), picked without listening: each one measured in Studio through an
-- AudioAnalyzer (length, loudness envelope, low-frequency share) to match its slot. Licensed
-- (APM, Pro Sound Effects) where the libraries had one; the gunfire, cannon and hooves are public
-- Creator Store uploads (Cannon_Explode is Roblox's own). docs/assets-brief.md lists each.
local function ids(list: { number }): { string }
	local out = {}
	for _, n in list do
		table.insert(out, "rbxassetid://" .. n)
	end
	return out
end
local S = Assets.sounds
S.musketVolley.id = ids({ 9103981709, 9103982167, 9103982507 }) -- "Musket Fire 1-3": 1 s cracks
S.musketScatter.id = ids({ 129944384098631, 9104013729 }) -- a distant single shot, a quieter one
S.cannonFire.id = ids({ 3149249837, 138726661215326, 72411732778781 }) -- 4 s booms, 90 % low end
S.cannonBounce.id = ids({ 136353799660868 }) -- "Cannon Impact": a 2 s thud
S.canister.id = ids({ 72411732778781 }) -- a cannon shot pitched up into a sharper blast
S.canister.pitch = { 1.18, 1.3 }
S.cavalryCharge.id = ids({ 113726319971995, 108771044697744 }) -- 4-5 s of gallop
S.drumsMarchFr.id = ids({ 1842279455 }) -- APM "Tenor Drum Sounds (b)", every nation for now
S.drumsMarchPr.id = S.drumsMarchFr.id
S.drumsMarchAt.id = S.drumsMarchFr.id
S.drumsMarchRu.id = S.drumsMarchFr.id
S.drumsMarchGb.id = S.drumsMarchFr.id
S.ambienceField.id = ids({ 9112832288 }) -- Pro Sound Effects "Mountain Birds 1", a quiet recording
S.ambienceField.volume = 1
S.menuMusic.id = ids({ 1847601287 }) -- APM "War History"
S.battleMusicCalm.id = ids({ 1840899246 }) -- APM "Military Approach"
S.battleMusicTense.id = ids({ 1840899338 }) -- APM "The Regiment"
S.campaignMusic.id = ids({ 9046678026 }) -- APM "Army Soldiers March"
S.victory.id = ids({ 1838608860 }) -- APM "Homecoming Of The Victorious (30s)"
S.uiClick.id = ids({ 9125655352 }) -- PSE "Mechanism Wooden Jerks Single Clicks": a dry 0.6 s click
S.uiPaper.id = ids({ 9125723307 }) -- PSE "Paper Movement ... Flips": a sheet handled, quiet
S.uiPaper.volume = 0.9
S.ambienceRain.id = ids({ 9112853422 }) -- PSE "Rain Heavy Rainfall Grass Wooden Roof 1", 46 s loop

-- Kits by nation (Look.nation), each kind from one generated figure retextured per uniform.
-- infantry_*: torso, head, headgear (the nation's line headgear), armL, armR, legL, legR, musket.
-- cavalry_*: horse body, neck, four legs (legFL ...), rider and riderHead (helmet and sabre),
-- 3.9 studs tall. A nation with no kit keeps the part-built figure.
Assets.kits = {
	infantry_france = {
		torso = { mesh = "rbxassetid://72447424433783", texture = "rbxassetid://76009995950013", size = { 0.910, 1.681, 0.760 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.023, 1.777, 0.011, 0, -1.571, 0 } },
		head = { mesh = "rbxassetid://115740877823408", texture = "rbxassetid://73188983304116", size = { 0.385, 0.540, 0.481 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.075, 2.685, 0.014, 0, -1.571, 0 } },
		headgear = { mesh = "rbxassetid://107169635745358", texture = "rbxassetid://138854108381670", size = { 0.450, 0.519, 0.520 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.073, 2.941, 0.009, 0, -1.571, 0 } },
		armL = { mesh = "rbxassetid://121594989973603", texture = "rbxassetid://137137930547812", size = { 0.501, 1.454, 0.422 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.011, 1.884, -0.352, 0, -1.571, 0 } },
		armR = { mesh = "rbxassetid://111440529891696", texture = "rbxassetid://100399824521086", size = { 0.580, 1.018, 0.781 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.187, 2.102, 0.383, 0, -1.571, 0 } },
		legL = { mesh = "rbxassetid://96888915771832", texture = "rbxassetid://123963383821382", size = { 0.619, 1.769, 0.536 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.001, 0.886, -0.178, 0, -1.571, 0 } },
		legR = { mesh = "rbxassetid://97071635557023", texture = "rbxassetid://87912861052007", size = { 0.622, 1.788, 0.527 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.001, 0.894, 0.178, 0, -1.571, 0 } },
		musket = { mesh = "rbxassetid://130456209273865", texture = "rbxassetid://95977280465596", size = { 0.287, 3.136, 0.154 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.482, 1.592, 0.592, 0, -1.571, 0 } },
	},
	infantry_prussia = {
		torso = { mesh = "rbxassetid://100340254732697", texture = "rbxassetid://86434840880705", size = { 0.910, 1.681, 0.760 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.023, 1.777, 0.011, 0, -1.571, 0 } },
		head = { mesh = "rbxassetid://91903684493092", texture = "rbxassetid://70709158942177", size = { 0.385, 0.540, 0.481 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.075, 2.685, 0.014, 0, -1.571, 0 } },
		headgear = { mesh = "rbxassetid://87704916367887", texture = "rbxassetid://103951449579693", size = { 0.450, 0.519, 0.520 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.073, 2.941, 0.009, 0, -1.571, 0 } },
		armL = { mesh = "rbxassetid://89534756824826", texture = "rbxassetid://79840849952658", size = { 0.501, 1.454, 0.422 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.011, 1.884, -0.352, 0, -1.571, 0 } },
		armR = { mesh = "rbxassetid://73999327676912", texture = "rbxassetid://130531744331411", size = { 0.580, 1.018, 0.781 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.187, 2.102, 0.383, 0, -1.571, 0 } },
		legL = { mesh = "rbxassetid://75999870250590", texture = "rbxassetid://90788648929694", size = { 0.619, 1.769, 0.536 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.001, 0.886, -0.178, 0, -1.571, 0 } },
		legR = { mesh = "rbxassetid://115989188416001", texture = "rbxassetid://134421712320133", size = { 0.622, 1.788, 0.527 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.001, 0.894, 0.178, 0, -1.571, 0 } },
		musket = { mesh = "rbxassetid://78667426847451", texture = "rbxassetid://97155862407087", size = { 0.287, 3.136, 0.154 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.482, 1.592, 0.592, 0, -1.571, 0 } },
	},
	infantry_austria = {
		torso = { mesh = "rbxassetid://126063052168951", texture = "rbxassetid://107479516027570", size = { 0.910, 1.681, 0.760 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.023, 1.777, 0.011, 0, -1.571, 0 } },
		head = { mesh = "rbxassetid://89464617975261", texture = "rbxassetid://105227040308491", size = { 0.385, 0.540, 0.481 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.075, 2.685, 0.014, 0, -1.571, 0 } },
		headgear = { mesh = "rbxassetid://87704916367887", texture = "rbxassetid://76756090875089", size = { 0.450, 0.519, 0.520 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.073, 2.941, 0.009, 0, -1.571, 0 } },
		armL = { mesh = "rbxassetid://134899576134687", texture = "rbxassetid://130100051785342", size = { 0.501, 1.454, 0.422 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.011, 1.884, -0.352, 0, -1.571, 0 } },
		armR = { mesh = "rbxassetid://73999327676912", texture = "rbxassetid://106069557452960", size = { 0.580, 1.018, 0.781 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.187, 2.102, 0.383, 0, -1.571, 0 } },
		legL = { mesh = "rbxassetid://75999870250590", texture = "rbxassetid://87754351395901", size = { 0.619, 1.769, 0.536 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.001, 0.886, -0.178, 0, -1.571, 0 } },
		legR = { mesh = "rbxassetid://76701290095774", texture = "rbxassetid://106508536091446", size = { 0.622, 1.788, 0.527 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.001, 0.894, 0.178, 0, -1.571, 0 } },
		musket = { mesh = "rbxassetid://133213331850745", texture = "rbxassetid://115096728123059", size = { 0.287, 3.136, 0.154 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.482, 1.592, 0.592, 0, -1.571, 0 } },
	},
	infantry_russia = {
		torso = { mesh = "rbxassetid://100307931846787", texture = "rbxassetid://121846545707287", size = { 0.910, 1.681, 0.760 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.023, 1.777, 0.011, 0, -1.571, 0 } },
		head = { mesh = "rbxassetid://91903684493092", texture = "rbxassetid://129929602202542", size = { 0.385, 0.540, 0.481 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.075, 2.685, 0.014, 0, -1.571, 0 } },
		headgear = { mesh = "rbxassetid://87704916367887", texture = "rbxassetid://123890667837311", size = { 0.450, 0.519, 0.520 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.073, 2.941, 0.009, 0, -1.571, 0 } },
		armL = { mesh = "rbxassetid://130012504213142", texture = "rbxassetid://134631179173911", size = { 0.501, 1.454, 0.422 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.011, 1.884, -0.352, 0, -1.571, 0 } },
		armR = { mesh = "rbxassetid://135381172107540", texture = "rbxassetid://116385866069807", size = { 0.580, 1.018, 0.781 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.187, 2.102, 0.383, 0, -1.571, 0 } },
		legL = { mesh = "rbxassetid://75999870250590", texture = "rbxassetid://107149799289347", size = { 0.619, 1.769, 0.536 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.001, 0.886, -0.178, 0, -1.571, 0 } },
		legR = { mesh = "rbxassetid://76701290095774", texture = "rbxassetid://90495551040836", size = { 0.622, 1.788, 0.527 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.001, 0.894, 0.178, 0, -1.571, 0 } },
		musket = { mesh = "rbxassetid://91878694098089", texture = "rbxassetid://118861877060416", size = { 0.287, 3.136, 0.154 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.482, 1.592, 0.592, 0, -1.571, 0 } },
	},
	infantry_britain = {
		torso = { mesh = "rbxassetid://129183344218951", texture = "rbxassetid://103941331179810", size = { 0.910, 1.681, 0.760 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.023, 1.777, 0.011, 0, -1.571, 0 } },
		head = { mesh = "rbxassetid://91903684493092", texture = "rbxassetid://118685226239707", size = { 0.385, 0.540, 0.481 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.075, 2.685, 0.014, 0, -1.571, 0 } },
		headgear = { mesh = "rbxassetid://87704916367887", texture = "rbxassetid://123760337615564", size = { 0.450, 0.519, 0.520 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.073, 2.941, 0.009, 0, -1.571, 0 } },
		armL = { mesh = "rbxassetid://90122556834763", texture = "rbxassetid://73663532939296", size = { 0.501, 1.454, 0.422 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.011, 1.884, -0.352, 0, -1.571, 0 } },
		armR = { mesh = "rbxassetid://107730648252390", texture = "rbxassetid://129771445221741", size = { 0.580, 1.018, 0.781 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.187, 2.102, 0.383, 0, -1.571, 0 } },
		legL = { mesh = "rbxassetid://75999870250590", texture = "rbxassetid://72617049022748", size = { 0.619, 1.769, 0.536 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.001, 0.886, -0.178, 0, -1.571, 0 } },
		legR = { mesh = "rbxassetid://77142277884567", texture = "rbxassetid://91284207331557", size = { 0.622, 1.788, 0.527 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.001, 0.894, 0.178, 0, -1.571, 0 } },
		musket = { mesh = "rbxassetid://78667426847451", texture = "rbxassetid://131218067439061", size = { 0.287, 3.136, 0.154 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.482, 1.592, 0.592, 0, -1.571, 0 } },
	},
	infantry_saxony = {
		torso = { mesh = "rbxassetid://129183344218951", texture = "rbxassetid://81398696499863", size = { 0.910, 1.681, 0.760 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.023, 1.777, 0.011, 0, -1.571, 0 } },
		head = { mesh = "rbxassetid://91903684493092", texture = "rbxassetid://129975501176486", size = { 0.385, 0.540, 0.481 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.075, 2.685, 0.014, 0, -1.571, 0 } },
		headgear = { mesh = "rbxassetid://87704916367887", texture = "rbxassetid://81578671947679", size = { 0.450, 0.519, 0.520 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.073, 2.941, 0.009, 0, -1.571, 0 } },
		armL = { mesh = "rbxassetid://90122556834763", texture = "rbxassetid://73390537946974", size = { 0.501, 1.454, 0.422 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.011, 1.884, -0.352, 0, -1.571, 0 } },
		armR = { mesh = "rbxassetid://107730648252390", texture = "rbxassetid://94562223647464", size = { 0.580, 1.018, 0.781 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.187, 2.102, 0.383, 0, -1.571, 0 } },
		legL = { mesh = "rbxassetid://75999870250590", texture = "rbxassetid://90233699217808", size = { 0.619, 1.769, 0.536 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.001, 0.886, -0.178, 0, -1.571, 0 } },
		legR = { mesh = "rbxassetid://76701290095774", texture = "rbxassetid://140664416298924", size = { 0.622, 1.788, 0.527 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.001, 0.894, 0.178, 0, -1.571, 0 } },
		musket = { mesh = "rbxassetid://78667426847451", texture = "rbxassetid://103961039376190", size = { 0.287, 3.136, 0.154 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.482, 1.592, 0.592, 0, -1.571, 0 } },
	},
	infantry_netherlands = {
		torso = { mesh = "rbxassetid://129183344218951", texture = "rbxassetid://121043910384796", size = { 0.910, 1.681, 0.760 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.023, 1.777, 0.011, 0, -1.571, 0 } },
		head = { mesh = "rbxassetid://91903684493092", texture = "rbxassetid://95654127317878", size = { 0.385, 0.540, 0.481 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.075, 2.685, 0.014, 0, -1.571, 0 } },
		headgear = { mesh = "rbxassetid://87704916367887", texture = "rbxassetid://103692339740816", size = { 0.450, 0.519, 0.520 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.073, 2.941, 0.009, 0, -1.571, 0 } },
		armL = { mesh = "rbxassetid://90122556834763", texture = "rbxassetid://122082390175976", size = { 0.501, 1.454, 0.422 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.011, 1.884, -0.352, 0, -1.571, 0 } },
		armR = { mesh = "rbxassetid://135381172107540", texture = "rbxassetid://98137796365664", size = { 0.580, 1.018, 0.781 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.187, 2.102, 0.383, 0, -1.571, 0 } },
		legL = { mesh = "rbxassetid://75999870250590", texture = "rbxassetid://73839047365298", size = { 0.619, 1.769, 0.536 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.001, 0.886, -0.178, 0, -1.571, 0 } },
		legR = { mesh = "rbxassetid://76701290095774", texture = "rbxassetid://134020398034292", size = { 0.622, 1.788, 0.527 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.001, 0.894, 0.178, 0, -1.571, 0 } },
		musket = { mesh = "rbxassetid://78667426847451", texture = "rbxassetid://116241276421749", size = { 0.287, 3.136, 0.154 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.482, 1.592, 0.592, 0, -1.571, 0 } },
	},
	infantry_bavaria = {
		torso = { mesh = "rbxassetid://129183344218951", texture = "rbxassetid://93330769644288", size = { 0.910, 1.681, 0.760 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.023, 1.777, 0.011, 0, -1.571, 0 } },
		head = { mesh = "rbxassetid://115995662052450", texture = "rbxassetid://93426260340941", size = { 0.385, 0.540, 0.481 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.075, 2.685, 0.014, 0, -1.571, 0 } },
		headgear = { mesh = "rbxassetid://93468585124691", texture = "rbxassetid://130574658518085", size = { 0.450, 0.519, 0.520 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.073, 2.941, 0.009, 0, -1.571, 0 } },
		armL = { mesh = "rbxassetid://90122556834763", texture = "rbxassetid://91749711042022", size = { 0.501, 1.454, 0.422 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.011, 1.884, -0.352, 0, -1.571, 0 } },
		armR = { mesh = "rbxassetid://107730648252390", texture = "rbxassetid://124450630139133", size = { 0.580, 1.018, 0.781 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.187, 2.102, 0.383, 0, -1.571, 0 } },
		legL = { mesh = "rbxassetid://75999870250590", texture = "rbxassetid://120917923814018", size = { 0.619, 1.769, 0.536 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.001, 0.886, -0.178, 0, -1.571, 0 } },
		legR = { mesh = "rbxassetid://77142277884567", texture = "rbxassetid://107696127085071", size = { 0.622, 1.788, 0.527 }, scale = { 1.337, 1.337, 1.337 }, cf = { -0.001, 0.894, 0.178, 0, -1.571, 0 } },
		musket = { mesh = "rbxassetid://117599744605645", texture = "rbxassetid://90018048390884", size = { 0.287, 3.136, 0.154 }, scale = { 1.337, 1.337, 1.337 }, cf = { 0.482, 1.592, 0.592, 0, -1.571, 0 } },
	},
	cavalry_france = {
		body = { mesh = "rbxassetid://101209066546460", texture = "rbxassetid://135331797219533", size = { 1.045, 1.804, 3.064 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.195, 1.553, -0.003, 0, -1.571, 0 } },
		neck = { mesh = "rbxassetid://95314629656435", texture = "rbxassetid://99922572574292", size = { 0.602, 1.138, 1.323 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.254, 2.413, 0.003, 0, -1.571, 0 } },
		rider = { mesh = "rbxassetid://96275282726194", texture = "rbxassetid://117170299366500", size = { 1.272, 2.563, 0.944 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.235, 2.618, 0.001, 0, -1.571, 0 } },
		riderHead = { mesh = "rbxassetid://94832972494815", texture = "rbxassetid://131954730851579", size = { 0.716, 1.789, 1.182 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.105, 2.979, 0.039, 0, -1.571, 0 } },
		legFL = { mesh = "rbxassetid://73085611638906", texture = "rbxassetid://119698898981922", size = { 0.442, 1.658, 0.503 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.901, 0.830, -0.210, 0, -1.571, 0 } },
		legFR = { mesh = "rbxassetid://79084536683650", texture = "rbxassetid://107739209709240", size = { 0.435, 1.658, 0.496 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.903, 0.829, 0.220, 0, -1.571, 0 } },
		legBL = { mesh = "rbxassetid://97228754256621", texture = "rbxassetid://119121153923312", size = { 0.449, 1.594, 0.690 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.798, -0.243, 0, -1.571, 0 } },
		legBR = { mesh = "rbxassetid://116188909619161", texture = "rbxassetid://111264749434518", size = { 0.474, 1.585, 0.698 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.793, 0.233, 0, -1.571, 0 } },
	},
	cavalry_prussia = {
		body = { mesh = "rbxassetid://126980995434593", texture = "rbxassetid://105356024757049", size = { 1.045, 1.804, 3.064 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.195, 1.553, -0.003, 0, -1.571, 0 } },
		neck = { mesh = "rbxassetid://104804374875586", texture = "rbxassetid://140647944335623", size = { 0.602, 1.138, 1.323 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.254, 2.413, 0.003, 0, -1.571, 0 } },
		rider = { mesh = "rbxassetid://100731151188144", texture = "rbxassetid://131481807512125", size = { 1.272, 2.563, 0.944 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.235, 2.618, 0.001, 0, -1.571, 0 } },
		riderHead = { mesh = "rbxassetid://70918914869313", texture = "rbxassetid://72999112208405", size = { 0.716, 1.789, 1.182 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.105, 2.979, 0.039, 0, -1.571, 0 } },
		legFL = { mesh = "rbxassetid://90666174572538", texture = "rbxassetid://124493348520639", size = { 0.442, 1.658, 0.503 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.901, 0.830, -0.210, 0, -1.571, 0 } },
		legFR = { mesh = "rbxassetid://93454033435597", texture = "rbxassetid://92778571420128", size = { 0.435, 1.658, 0.496 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.903, 0.829, 0.220, 0, -1.571, 0 } },
		legBL = { mesh = "rbxassetid://115652056463517", texture = "rbxassetid://71329329511247", size = { 0.449, 1.594, 0.690 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.798, -0.243, 0, -1.571, 0 } },
		legBR = { mesh = "rbxassetid://107408663248265", texture = "rbxassetid://129083245291610", size = { 0.474, 1.585, 0.698 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.793, 0.233, 0, -1.571, 0 } },
	},
	cavalry_austria = {
		body = { mesh = "rbxassetid://126980995434593", texture = "rbxassetid://86132092363876", size = { 1.045, 1.804, 3.064 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.195, 1.553, -0.003, 0, -1.571, 0 } },
		neck = { mesh = "rbxassetid://104804374875586", texture = "rbxassetid://106657063708168", size = { 0.602, 1.138, 1.323 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.254, 2.413, 0.003, 0, -1.571, 0 } },
		rider = { mesh = "rbxassetid://72223682665238", texture = "rbxassetid://126829823237199", size = { 1.272, 2.563, 0.944 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.235, 2.618, 0.001, 0, -1.571, 0 } },
		riderHead = { mesh = "rbxassetid://72184720023128", texture = "rbxassetid://136769917169436", size = { 0.716, 1.789, 1.182 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.105, 2.979, 0.039, 0, -1.571, 0 } },
		legFL = { mesh = "rbxassetid://70783407002482", texture = "rbxassetid://93392678083101", size = { 0.442, 1.658, 0.503 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.901, 0.830, -0.210, 0, -1.571, 0 } },
		legFR = { mesh = "rbxassetid://125265575406381", texture = "rbxassetid://128727272432428", size = { 0.435, 1.658, 0.496 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.903, 0.829, 0.220, 0, -1.571, 0 } },
		legBL = { mesh = "rbxassetid://135167894328595", texture = "rbxassetid://134725499345479", size = { 0.449, 1.594, 0.690 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.798, -0.243, 0, -1.571, 0 } },
		legBR = { mesh = "rbxassetid://77513473129021", texture = "rbxassetid://102455605558394", size = { 0.474, 1.585, 0.698 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.793, 0.233, 0, -1.571, 0 } },
	},
	cavalry_russia = {
		body = { mesh = "rbxassetid://122914315147108", texture = "rbxassetid://73259070832816", size = { 1.045, 1.804, 3.064 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.195, 1.553, -0.003, 0, -1.571, 0 } },
		neck = { mesh = "rbxassetid://108744649704930", texture = "rbxassetid://109698653027019", size = { 0.602, 1.138, 1.323 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.254, 2.413, 0.003, 0, -1.571, 0 } },
		rider = { mesh = "rbxassetid://72223682665238", texture = "rbxassetid://125179309308962", size = { 1.272, 2.563, 0.944 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.235, 2.618, 0.001, 0, -1.571, 0 } },
		riderHead = { mesh = "rbxassetid://83027753552191", texture = "rbxassetid://109622183143346", size = { 0.716, 1.789, 1.182 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.105, 2.979, 0.039, 0, -1.571, 0 } },
		legFL = { mesh = "rbxassetid://70783407002482", texture = "rbxassetid://124062250720190", size = { 0.442, 1.658, 0.503 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.901, 0.830, -0.210, 0, -1.571, 0 } },
		legFR = { mesh = "rbxassetid://104955681348224", texture = "rbxassetid://132449992515390", size = { 0.435, 1.658, 0.496 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.903, 0.829, 0.220, 0, -1.571, 0 } },
		legBL = { mesh = "rbxassetid://103297166522723", texture = "rbxassetid://126829224207393", size = { 0.449, 1.594, 0.690 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.798, -0.243, 0, -1.571, 0 } },
		legBR = { mesh = "rbxassetid://107646498701188", texture = "rbxassetid://126708628288394", size = { 0.474, 1.585, 0.698 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.793, 0.233, 0, -1.571, 0 } },
	},
	cavalry_britain = {
		body = { mesh = "rbxassetid://122914315147108", texture = "rbxassetid://116022173856999", size = { 1.045, 1.804, 3.064 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.195, 1.553, -0.003, 0, -1.571, 0 } },
		neck = { mesh = "rbxassetid://135826896533041", texture = "rbxassetid://88488895964205", size = { 0.602, 1.138, 1.323 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.254, 2.413, 0.003, 0, -1.571, 0 } },
		rider = { mesh = "rbxassetid://73042617453852", texture = "rbxassetid://85980232866263", size = { 1.272, 2.563, 0.944 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.235, 2.618, 0.001, 0, -1.571, 0 } },
		riderHead = { mesh = "rbxassetid://72184720023128", texture = "rbxassetid://101518959169225", size = { 0.716, 1.789, 1.182 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.105, 2.979, 0.039, 0, -1.571, 0 } },
		legFL = { mesh = "rbxassetid://128255260241006", texture = "rbxassetid://115928205004848", size = { 0.442, 1.658, 0.503 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.901, 0.830, -0.210, 0, -1.571, 0 } },
		legFR = { mesh = "rbxassetid://104955681348224", texture = "rbxassetid://137283276385545", size = { 0.435, 1.658, 0.496 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.903, 0.829, 0.220, 0, -1.571, 0 } },
		legBL = { mesh = "rbxassetid://103297166522723", texture = "rbxassetid://112917349089077", size = { 0.449, 1.594, 0.690 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.798, -0.243, 0, -1.571, 0 } },
		legBR = { mesh = "rbxassetid://107646498701188", texture = "rbxassetid://123062050570215", size = { 0.474, 1.585, 0.698 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.793, 0.233, 0, -1.571, 0 } },
	},
	cavalry_saxony = {
		body = { mesh = "rbxassetid://119102249427555", texture = "rbxassetid://90004683328021", size = { 1.045, 1.804, 3.064 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.195, 1.553, -0.003, 0, -1.571, 0 } },
		neck = { mesh = "rbxassetid://93037243702051", texture = "rbxassetid://117824422992487", size = { 0.602, 1.138, 1.323 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.254, 2.413, 0.003, 0, -1.571, 0 } },
		rider = { mesh = "rbxassetid://72223682665238", texture = "rbxassetid://138570423124000", size = { 1.272, 2.563, 0.944 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.235, 2.618, 0.001, 0, -1.571, 0 } },
		riderHead = { mesh = "rbxassetid://88269720329818", texture = "rbxassetid://81533158544797", size = { 0.716, 1.789, 1.182 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.105, 2.979, 0.039, 0, -1.571, 0 } },
		legFL = { mesh = "rbxassetid://111102222738325", texture = "rbxassetid://115335064804579", size = { 0.442, 1.658, 0.503 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.901, 0.830, -0.210, 0, -1.571, 0 } },
		legFR = { mesh = "rbxassetid://125265575406381", texture = "rbxassetid://78136041454769", size = { 0.435, 1.658, 0.496 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.903, 0.829, 0.220, 0, -1.571, 0 } },
		legBL = { mesh = "rbxassetid://135167894328595", texture = "rbxassetid://81914521336965", size = { 0.449, 1.594, 0.690 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.798, -0.243, 0, -1.571, 0 } },
		legBR = { mesh = "rbxassetid://77513473129021", texture = "rbxassetid://110431775089464", size = { 0.474, 1.585, 0.698 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.793, 0.233, 0, -1.571, 0 } },
	},
	cavalry_netherlands = {
		body = { mesh = "rbxassetid://126980995434593", texture = "rbxassetid://107801186516172", size = { 1.045, 1.804, 3.064 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.195, 1.553, -0.003, 0, -1.571, 0 } },
		neck = { mesh = "rbxassetid://104804374875586", texture = "rbxassetid://109504271356800", size = { 0.602, 1.138, 1.323 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.254, 2.413, 0.003, 0, -1.571, 0 } },
		rider = { mesh = "rbxassetid://72223682665238", texture = "rbxassetid://101871281153258", size = { 1.272, 2.563, 0.944 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.235, 2.618, 0.001, 0, -1.571, 0 } },
		riderHead = { mesh = "rbxassetid://83027753552191", texture = "rbxassetid://131414450845679", size = { 0.716, 1.789, 1.182 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.105, 2.979, 0.039, 0, -1.571, 0 } },
		legFL = { mesh = "rbxassetid://111102222738325", texture = "rbxassetid://138825892487951", size = { 0.442, 1.658, 0.503 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.901, 0.830, -0.210, 0, -1.571, 0 } },
		legFR = { mesh = "rbxassetid://125265575406381", texture = "rbxassetid://83311613055208", size = { 0.435, 1.658, 0.496 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.903, 0.829, 0.220, 0, -1.571, 0 } },
		legBL = { mesh = "rbxassetid://135167894328595", texture = "rbxassetid://74726164781330", size = { 0.449, 1.594, 0.690 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.798, -0.243, 0, -1.571, 0 } },
		legBR = { mesh = "rbxassetid://125030104198826", texture = "rbxassetid://110135495802951", size = { 0.474, 1.585, 0.698 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.793, 0.233, 0, -1.571, 0 } },
	},
	cavalry_bavaria = {
		body = { mesh = "rbxassetid://122914315147108", texture = "rbxassetid://115607948742721", size = { 1.045, 1.804, 3.064 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.195, 1.553, -0.003, 0, -1.571, 0 } },
		neck = { mesh = "rbxassetid://104804374875586", texture = "rbxassetid://113631942679996", size = { 0.602, 1.138, 1.323 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.254, 2.413, 0.003, 0, -1.571, 0 } },
		rider = { mesh = "rbxassetid://72223682665238", texture = "rbxassetid://105551710540828", size = { 1.272, 2.563, 0.944 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.235, 2.618, 0.001, 0, -1.571, 0 } },
		riderHead = { mesh = "rbxassetid://83027753552191", texture = "rbxassetid://121942413923895", size = { 0.716, 1.789, 1.182 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.105, 2.979, 0.039, 0, -1.571, 0 } },
		legFL = { mesh = "rbxassetid://111102222738325", texture = "rbxassetid://82949309365561", size = { 0.442, 1.658, 0.503 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.901, 0.830, -0.210, 0, -1.571, 0 } },
		legFR = { mesh = "rbxassetid://125265575406381", texture = "rbxassetid://111456254734864", size = { 0.435, 1.658, 0.496 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.903, 0.829, 0.220, 0, -1.571, 0 } },
		legBL = { mesh = "rbxassetid://103340490040183", texture = "rbxassetid://137924320187544", size = { 0.449, 1.594, 0.690 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.798, -0.243, 0, -1.571, 0 } },
		legBR = { mesh = "rbxassetid://107646498701188", texture = "rbxassetid://91755086531963", size = { 0.474, 1.585, 0.698 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.793, 0.233, 0, -1.571, 0 } },
	},
	-- headgear swaps worn on a kit's head (head_<Look.head>): stand on the head top, front to +X
	head_bearskin = { headgear = { mesh = "rbxassetid://76596095858373", texture = "rbxassetid://75179736797078", size = { 0.370, 0.800, 0.561 }, scale = { 0.935, 0.935, 0.935 }, cf = { 0, 0, 0, 0, -1.571, 0 } } },
	head_bicorne = { headgear = { mesh = "rbxassetid://129696614120605", texture = "rbxassetid://104357746964512", size = { 0.768, 0.360, 0.420 }, scale = { 1.536, 1.536, 1.536 }, cf = { 0, 0, 0, 0, -1.571, 0 } } },
	head_crested = { headgear = { mesh = "rbxassetid://119676080371945", texture = "rbxassetid://85213909999178", size = { 0.325, 0.620, 0.436 }, scale = { 1.033, 1.033, 1.033 }, cf = { 0, 0, 0, 0, -1.571, 0 } } },
	-- the Austrian helmet sits 0.08 lower than its box: its chin strap hangs below the brim
	head_kaskett = { headgear = { mesh = "rbxassetid://88414765373172", texture = "rbxassetid://129616501674009", size = { 0.450, 0.736, 0.519 }, scale = { 1.339, 1.339, 1.339 }, cf = { 0, -0.08, 0, 0, -1.571, 0 } } },
	head_bonnet = { headgear = { mesh = "rbxassetid://101140967079858", texture = "rbxassetid://121301412148902", size = { 0.527, 0.780, 0.528 }, scale = { 1.040, 1.040, 1.040 }, cf = { 0, 0, 0, 0, -1.571, 0 } } },
	-- gun_*: barrel, carriage, wheelL, wheelR; muzzle to +X, axle over the origin, 2 studs tall
	gun_france = {
		barrel = { mesh = "rbxassetid://104670291301066", texture = "rbxassetid://82829453107788", size = { 0.829, 0.933, 2.325 }, scale = { 1.000, 1.000, 1.000 }, cf = { 0.423, 1.534, -0.001, 0, -1.571, 0 } },
		carriage = { mesh = "rbxassetid://131963666798321", texture = "rbxassetid://84427755863901", size = { 1.556, 1.303, 1.523 }, scale = { 1.000, 1.000, 1.000 }, cf = { 0.007, 0.774, -0.001, 0, -1.571, 0 } },
		wheelL = { mesh = "rbxassetid://107119790762274", texture = "rbxassetid://140684159418792", size = { 0.412, 1.410, 1.420 }, scale = { 1.000, 1.000, 1.000 }, cf = { -0.001, 0.705, -0.841, 0, -1.571, 0 } },
		wheelR = { mesh = "rbxassetid://129908926252251", texture = "rbxassetid://131213773238798", size = { 0.420, 1.404, 1.421 }, scale = { 1.000, 1.000, 1.000 }, cf = { 0.001, 0.708, 0.841, 0, -1.571, 0 } },
	},
	gun_austria = {
		barrel = { mesh = "rbxassetid://126576605817440", texture = "rbxassetid://96904922973636", size = { 0.829, 0.933, 2.325 }, scale = { 1.000, 1.000, 1.000 }, cf = { 0.423, 1.534, -0.001, 0, -1.571, 0 } },
		carriage = { mesh = "rbxassetid://117480650559983", texture = "rbxassetid://75095711954068", size = { 1.556, 1.303, 1.523 }, scale = { 1.000, 1.000, 1.000 }, cf = { 0.007, 0.774, -0.001, 0, -1.571, 0 } },
		wheelL = { mesh = "rbxassetid://73299283152527", texture = "rbxassetid://75290792192611", size = { 0.412, 1.410, 1.420 }, scale = { 1.000, 1.000, 1.000 }, cf = { -0.001, 0.705, -0.841, 0, -1.571, 0 } },
		wheelR = { mesh = "rbxassetid://117572760467346", texture = "rbxassetid://140703325449684", size = { 0.420, 1.404, 1.421 }, scale = { 1.000, 1.000, 1.000 }, cf = { 0.001, 0.708, 0.841, 0, -1.571, 0 } },
	},
	gun_britain = {
		barrel = { mesh = "rbxassetid://95291511847105", texture = "rbxassetid://138991677162116", size = { 0.829, 0.933, 2.325 }, scale = { 1.000, 1.000, 1.000 }, cf = { 0.423, 1.534, -0.001, 0, -1.571, 0 } },
		carriage = { mesh = "rbxassetid://117480650559983", texture = "rbxassetid://105786252723114", size = { 1.556, 1.303, 1.523 }, scale = { 1.000, 1.000, 1.000 }, cf = { 0.007, 0.774, -0.001, 0, -1.571, 0 } },
		wheelL = { mesh = "rbxassetid://73299283152527", texture = "rbxassetid://114631889756618", size = { 0.412, 1.410, 1.420 }, scale = { 1.000, 1.000, 1.000 }, cf = { -0.001, 0.705, -0.841, 0, -1.571, 0 } },
		wheelR = { mesh = "rbxassetid://81450504410703", texture = "rbxassetid://80872205674537", size = { 0.420, 1.404, 1.421 }, scale = { 1.000, 1.000, 1.000 }, cf = { 0.001, 0.708, 0.841, 0, -1.571, 0 } },
	},
	cavalry_emperor = { -- Napoleon: the Guard chasseur coat on a grey
		body = { mesh = "rbxassetid://129420610842126", texture = "rbxassetid://127466484525918", size = { 1.045, 1.804, 3.064 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.195, 1.553, -0.003, 0, -1.571, 0 } },
		neck = { mesh = "rbxassetid://97810334031536", texture = "rbxassetid://84838549504166", size = { 0.602, 1.138, 1.323 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.254, 2.413, 0.003, 0, -1.571, 0 } },
		rider = { mesh = "rbxassetid://136655313774729", texture = "rbxassetid://138865376002160", size = { 1.272, 2.563, 0.944 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.235, 2.618, 0.001, 0, -1.571, 0 } },
		riderHead = { mesh = "rbxassetid://93646707869151", texture = "rbxassetid://115100213114456", size = { 0.716, 1.789, 1.182 }, scale = { 1.060, 1.060, 1.060 }, cf = { 1.105, 2.979, 0.039, 0, -1.571, 0 } },
		legFL = { mesh = "rbxassetid://90666174572538", texture = "rbxassetid://84556248222313", size = { 0.442, 1.658, 0.503 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.901, 0.830, -0.210, 0, -1.571, 0 } },
		legFR = { mesh = "rbxassetid://125265575406381", texture = "rbxassetid://120345732090340", size = { 0.435, 1.658, 0.496 }, scale = { 1.060, 1.060, 1.060 }, cf = { 0.903, 0.829, 0.220, 0, -1.571, 0 } },
		legBL = { mesh = "rbxassetid://126705425320346", texture = "rbxassetid://87238983341073", size = { 0.449, 1.594, 0.690 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.798, -0.243, 0, -1.571, 0 } },
		legBR = { mesh = "rbxassetid://107646498701188", texture = "rbxassetid://75819985288111", size = { 0.474, 1.585, 0.698 }, scale = { 1.060, 1.060, 1.060 }, cf = { -0.902, 0.793, 0.233, 0, -1.571, 0 } },
	},
	limber_france = { limber = { mesh = "rbxassetid://79895136778232", texture = "rbxassetid://104087580561513", size = { 2.168, 1.528, 2.600 }, scale = { 1.355, 1.355, 1.355 }, cf = { 1.6, 0.764, 0, 0, -1.571, 0 } } },
} :: { [string]: Kit }

function Assets.kit(key: string): Kit?
	return Assets.kits[key]
end

-- Public-domain battle paintings (Wikimedia Commons; the painters died over a century ago),
-- cropped to sky, smoke and the lines above the fallen, 1024 wide, uploaded in Studio. Sources
-- in docs/assets-brief.md ("Paintings").
Assets.paintings = {
	menu = "rbxassetid://71478981929025", -- Philippoteaux, the cuirassiers' charge at Waterloo (1874)
	austerlitz = "rbxassetid://72324631406127", -- Gérard, La bataille d'Austerlitz (1810)
	jena = "rbxassetid://77495645476448", -- Vernet, Bataille d'Iéna (1836)
	waterloo = "rbxassetid://104564772834798", -- Sadler, The Battle of Waterloo (c. 1815)
	thuringia = "rbxassetid://115020031615909", -- the campaign map's parchment (tools/thuringia_map.py)
}

-- The rulers of 1805 for the grand campaign's nation picker (public-domain portraits, head and
-- shoulders, 256²): David, Ramsay, Amerling, Gebauer, Dawe.
Assets.rulers = {
	france = "rbxassetid://108823540029358", -- Napoleon I
	britain = "rbxassetid://89327521394091", -- George III
	austria = "rbxassetid://139154612819980", -- Francis II
	prussia = "rbxassetid://94214866043823", -- Frederick William III
	russia = "rbxassetid://134911391128710", -- Alexander I
} :: { [string]: string }

-- The painting for a battle map: its battle's, or the menu's for maps without one.
function Assets.paintingFor(mapId: string?): string
	local id = mapId or ""
	local battle = string.match(id, "^([a-z]+)") or ""
	if battle == "auerstedt" then
		battle = "jena" -- the same day, the same campaign
	end
	return (Assets.paintings :: { [string]: string })[battle] or Assets.paintings.menu
end

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
