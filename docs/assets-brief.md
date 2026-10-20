# Asset brief: meshes and textures for Eagles of Empire

The game builds everything from Roblox primitive parts today. Every item below has a named slot
in `src/shared/Assets.luau` (`Assets.slots.<key>`); put an asset id in the slot and the game uses
the mesh instead of the parts. Empty slots keep the part version, so you can fill them one at a
time. **The key names and sizes in `Assets.luau` are the truth; this brief follows them.**

A slot is `{ mesh = "rbxassetid://…", texture = "rbxassetid://…", scale = {x, y, z}, offset = {x, y, z} }`.
`native` is the mesh's own size in studs as Studio shows it on import (e.g. `{12, 13, 12}`):
with it set, the game fits the mesh to every object's box, so one oak mesh serves small and
large oaks alike. `scale` is then only a final tweak (leave `{1, 1, 1}`); `offset` nudges the
mesh if its pivot is not on the ground. World meshes stand on the centre of their base.

Already filled by the local Studio session: `bark`, `roofTile`, `wall` textures.

## How to get an id into the game

1. Make or find the model (see the list). Export as **FBX** (or OBJ) with the texture as a PNG.
2. Roblox Studio → **Asset Manager → Bulk Import** (or the 3D Importer). Studio uploads it and
   gives it an asset id. Accept the default scale; the game scales each mesh to its slot's size.
3. Open the imported MeshPart in Explorer, copy its **MeshId** and **TextureID** (both look like
   `rbxassetid://123456789`). Image textures on their own: Asset Manager → Images → the id.
4. Paste them into the matching slot in `src/shared/Assets.luau`, run `tools/check.sh`, commit.

Creator Store (Toolbox in Studio, filter "Free") works the same way: insert the model, read the
MeshId/TextureID from the MeshPart. The decal id a store page shows is not the image id;
`game:GetObjects("rbxassetid://<decal>")[1].Texture` gives the image id (noted in docs/qa.md).

Any generator works (Meshy, Tripo, Sloyd, ChatGPT-driven pipelines, Blender). Stay inside the
triangle budgets below or the game stutters at the budgets it runs at (10–20k parts per map).

## Common rules

- **Units**: 1 stud = 1 unit in the file. Pivot at the **base centre** (feet / ground contact),
  +Y up, facing **+X** forward (the game's heading axis: a soldier looks along +X, a house's
  ridge runs along +X, a bridge deck runs along +X).
- **One material per mesh**, one PNG texture 512² (props) or 1024² (hero objects), no transparency
  except tree canopies (alpha-cutout allowed).
- **Triangle budgets** are per mesh. Roblox caps a MeshPart at 10k; aim far lower.
- **Look: painterly realistic** (art direction since the graphics pass, 2026-10-20). Napoleon:
  Total War at mid zoom is the reference: real uniform colours and kit, muted natural ground
  (olive-gold fields, dark woods, red-brown roofs), white powder smoke that hangs. Figures read
  like painted 28 mm wargame miniatures: adult proportions, small heads, textures painted on.
- **Triangle budgets** (whole object): infantry kit 2,000; mid-range figure 600; horse 3,000;
  gun 2,500; building 4,000; tree 1,500.
- Name files exactly as the slot keys so nothing gets mixed up.

## Figures: generated kits (`Assets.kits`)

Soldiers are **kits**: one generated figure split into pieces (torso, head, headgear, left arm,
right arm, left leg, right leg, musket), each a textured mesh. The game poses the pieces with
the same animation codes as the part-built figure, so kits march, reload, level and thrust.

How a kit is made (all in Studio through the MCP; the generator publishes every piece as an
asset on Bartosz's account):
1. `generate_mesh` with `segmentation = "explicit"` and those eight part names; prompt for a
   "realistic 28mm historical wargame miniature", adult proportions, arms down, musket upright
   in the right hand, **no base**, under 300 characters, at most 2,000 triangles.
2. For another nation, `generate_texture` (Fast) on a copy of the chosen figure: the same shape
   in that nation's uniform, so one layout fits every nation.
3. Paste `tools/kit_import.luau` into Studio with the model's name: it prints the kit entry
   (ids, sizes, places in the figure frame: +X forward, +Y up, ground at 0, 3.2 studs tall).
   The generator turns each model toward the camera; the importer reads the facing from the
   pieces, so no hand turning.
4. The kit goes into `Assets.kits` as `infantry_<nation>`. A nation without one keeps the part
   build. Headgear other than a shako is the part-built one on the kit's head until its own
   mesh slot is filled.

Height of a man is **3.2 studs** with his headgear (figures are 1 : 25 men).

| kit | prompt base | status |
| --- | --- | --- |
| `infantry_france` | French line fusilier 1806, shako, blue coat, white crossbelts, knapsack | filled |

## Figures: single-mesh slots (`Assets.slots`)

Older one-mesh slots, still read for horses, guns and headgear swaps until their kits exist.

| key | what | size W × H × D | tris |
| --- | --- | --- | --- |
| `soldierCavalry` | horse and rider, sabre at the carry | 1.4 × 4 × 3.6 | ≤ 1500 |
| `horse` | horse alone (limber teams) | 1.2 × 3.4 × 3.4 | ≤ 900 |
| `gun` | 6-pdr on its carriage, muzzle toward +X, 8-spoke wheels | 2.4 × 2 × 4.4 | ≤ 1200 |
| `limber` | limber with chest | 2 × 2 × 3 | ≤ 600 |
| `shako` | headgear only, worn on the procedural head | 0.6 × 0.7 × 0.6 | ≤ 200 |
| `bearskin`, `helmet` | same | 0.7 × 0.9 × 0.7 | ≤ 200 |

## World props (slot keys in `Assets.world`)

Sizes are the bounding boxes the game expects (W × H × D in studs); the mesh is scaled to fit.

| key | what | size | tris |
| --- | --- | --- | --- |
| `treeOak` | broad oak, visible trunk | 12 × 13 × 12 | ≤ 1200 |
| `treeBeech` | taller, smoother | 10 × 16 × 10 | ≤ 1000 |
| `treePine` | conifer | 8 × 18 × 8 | ≤ 800 |
| `treePoplar` | Lombardy poplar | 4 × 16 × 4 | ≤ 500 |
| `treeWillow` | weeping, for river banks | 12 × 12 × 12 | ≤ 1000 |
| `houseA` | whitewashed cottage, steep red tile roof, chimney; ridge along +X | 7 × 6 × 5 | ≤ 1500 |
| `houseB` | timber-framed, two storeys | 8 × 8 × 6 | ≤ 1800 |
| `houseC` | brick with lean-to | 7 × 6 × 6 | ≤ 1500 |
| `barn` | long timber barn, big doors | 13 × 7 × 6 | ≤ 1500 |
| `church` | nave 13 long with a west tower and spire; nave along +X | 22 × 22 × 7.4 | ≤ 3000 |
| `windmill` | post mill with four sails | 20 × 20 × 20 (sail span) | ≤ 2000 |
| `bridgeStone` | stone bridge with parapets, deck along +X; scaled to each span | 28 × 6 × 10 | ≤ 2000 |
| `bridgeTimber` | timber bridge with railings, deck along +X | 20 × 6 × 8 | ≤ 800 |

Textures (tileable, 1024², PNG) with slots today: `bark`, `roofTile`, `wall` (all set), `thatch`.
More texture slots (cobbles, dirt road, wheat, plough, timber frame) are added when a texture exists
for them; say which and the slot appears.

Not yet slotted (procedural only for now; ask and a slot is added): hedge, stone wall, fence, well,
cart, haystack, stook, shrine, reeds, fruit tree, onion-dome church, watermill.

## UI

UI images live in `src/client/UI/Kit.luau` (`Kit.paperTextureId`, set). Planned: `wax` (red seal, 256² with alpha), `brass` (brushed brass tile, 256²),
`ornament` (a horizontal rule ornament, 512 × 64 with alpha), `stamp` (circular dépôt stamp, 512²
with alpha, red ink), `eagleEmblem` (imperial eagle, 512² alpha, for the menu).

## Paintings (`Assets.paintings`)

Public-domain battle paintings from Wikimedia Commons (the painters died more than a century
ago; Commons treats faithful photos of 2D public-domain art as public domain). Each was cropped
to its upper band (sky, smoke, the lines) to leave out the fallen in the foreground, resized to
1024 wide with `sips`, and uploaded through Studio's `upload_image`. Used on the menu header,
the loading screen (per battle, `Assets.paintingFor`) and the results ribbon.

| key | painting | Commons file |
| --- | --- | --- |
| `menu` | Félix Philippoteaux, the cuirassiers' charge at Waterloo (1874) | `Charge_of_the_French_Cuirassiers_at_Waterloo.jpg` |
| `austerlitz` | François Gérard, *La bataille d'Austerlitz* (1810) | `La_bataille_d'Austerlitz._2_decembre_1805_(François_Gérard).jpg` |
| `jena` | Horace Vernet, *Bataille d'Iéna* (1836); also Auerstedt | `Bataille_d'Iéna,_14_octobre_1806_(Vernet).jpg` |
| `waterloo` | William Sadler, *The Battle of Waterloo* (c. 1815) | `Battle_of_Waterloo_1815.PNG` |

Rulers for the grand campaign's nation picker (`Assets.rulers`, head and shoulders, 256²):
David, *The Emperor Napoleon in His Study at the Tuileries* (1812); Ramsay, *George III in
coronation robes* (1761, cropped); Amerling, *Kaiser Franz I.* (1832); Gebauer, *Friedrich
Wilhelm III.*; Dawe, *Alexander I* (1826, Peterhof). The Thuringian campaign's parchment map is
drawn by `tools/thuringia_map.py` (`Assets.paintings.thuringia`).

## Generated assets (graphics pass, 2026-10-20)

All made with Studio's generators through the MCP and published to Bartosz's account:
- Figures: eight-piece infantry kits and cavalry kits for the eight nations, Napoleon's own
  kit, gun kits in three carriage colours, a limber, hats (bearskin, bicorne, crested helmet,
  Highland bonnet). Ids in `Assets.kits`.
- World: hedgerow, weeping willow, stone arch and trestle bridges, farm cart (`Assets.slots`);
  a ship of the line for the campaign fleets (`ship`).
- Ground: seven MaterialVariants (meadow, pasture, stubble, plough, track, cobbles, rock) in
  `default.project.json` under MaterialService, chosen from four candidates each.
- `head_kaskett` (2026-10-21, third attempt): mesh 88414765373172, texture 129616501674009, an
  1806 Austrian helmet with brass badge, black crest and chin strap; worn 0.08 below its box so
  the brim sits on the brow (`t3-austrian-helmet.jpg`).
- `reeds` (2026-10-21): mesh 129739908545802, texture 135174526017932, native 2.15 × 2.6 × 2.02, a
  clump of reeds and cattails on a muddy tuft; one per reed spot on the river banks, fitted 2.2-3.4
  tall (it replaces three flat green slabs).
- Tried and dropped: a post-and-rail
  fence (three attempts, the last as a single bay, each came out a flat sliver a fraction of the
  asked size); those stay part-built.
- `stoneWall` (2026-10-20, third attempt): mesh 127916614194194, texture 85059598017560, native
  0.81 × 1.6 × 4.98, a dry-stone section with a pillar at each end. Fitted to the 8.4-stud border
  pieces it stretches 1.7× along the wall; its pillars replace the part-built join pillars.

## Priority order (what is left)

1. A fence section (failed three times; see above).
2. Separate kit layouts for light infantry (no knapsack) and grenadiers if the hats are not
   enough to tell them apart.
3. `church` and `windmill` regenerated in the painterly look (today's are the earlier meshes).

## Sounds wired in (2026-10-20, measured, not yet heard by a person)

Each id was played in Studio through an AudioAnalyzer (muted output): length, loudness peak and
decay, and the share of energy in the lowest bins, to match the slot (a volley is a 1 s crack, a
cannon a 4 s boom with ~90 % low end). Listen once and swap any that sound wrong.

| Slot | Ids | Measured | Source |
| --- | --- | --- | --- |
| `musketVolley` | 9103981709, 9103982167, 9103982507 ("Musket Fire 1-3") | 1.0-1.1 s, sharp peak, gone by 0.2-0.7 s | Community (TheBritishEmpire1) |
| `musketScatter` | 129944384098631 ("Musket Single Shot Distant"), 9104013729 ("Musket Fire 4") | 1.3-3.4 s, quiet | Community |
| `cannonFire` | 3149249837 ("Cannon_Explode"), 138726661215326, 72411732778781 | 3.8-4.7 s, 87-95 % low end | Roblox; community |
| `cannonBounce` | 136353799660868 ("Cannon Impact") | 2.0 s thud, 98 % low end | Community |
| `canister` | 72411732778781 pitched ×1.18-1.3 | a sharper blast | Community |
| `cavalryCharge` | 113726319971995, 108771044697744 ("Horse Gallop") | 4.4-4.6 s | Community |
| `drumsMarch*` | 1842279455 ("Tenor Drum Sounds (b)"), all nations | 21 s loop | Licensed (APM) |
| `ambienceField` | 9112832288 ("Mountain Birds 1"), slot volume 1 (a quiet recording) | 31 s loop | Licensed (PSE) |
| `menuMusic` | 1847601287 ("War History") | 68 s | Licensed (APM) |
| `battleMusicCalm` | 1840899246 ("Military Approach") | 62 s | Licensed (APM) |
| `battleMusicTense` | 1840899338 ("The Regiment") | 63 s | Licensed (APM) |
| `campaignMusic` | 9046678026 ("Army Soldiers March") | 30 s | Licensed (APM) |
| `victory` | 1838608860 ("Homecoming Of The Victorious (30s)") | 30 s | Licensed (APM) |
| `uiClick` | 9125655352 ("Mechanism Wooden Jerks Single Clicks Smacks 2") | 0.6 s, no low end | Licensed (PSE) |
| `uiPaper` | 9125723307 ("Paper Movement Cu Handling Grabs Flips Waving 8"), slot volume 0.9 | 1.4 s, quiet | Licensed (PSE) |
| `ambienceRain` | 9112853422 ("Rain Heavy Rainfall Grass Wooden Roof 1") | 46 s loop | Licensed (PSE) |

Still empty: bugles (the libraries' only short one is a Chinese bugle), the defeat sting, rout
cries, melee (only single sword clashes, which loop badly), fog ambience, the wax seal. An empty
slot plays nothing.

## Sound candidates (to audition)

Found with the Studio Creator Store search on 2026-10-19. Not one has been listened to: open the
link, play it, and put the id you like into `Assets.sounds` (one commit per slot, then Settings →
debug audio). **Licensed** = Roblox's licensed libraries (Pro Sound Effects, APM Music), safe to
use. **Community** = a player's upload: its origin is unknown, so prefer a licensed one or your own
recording where one exists.

| Slot | Candidate | Source |
| --- | --- | --- |
| `drumsMarchFr` (and the other drum slots) | [Army Soldiers March (Promo Length)](https://create.roblox.com/store/asset/9046678026) · [Military Approach](https://create.roblox.com/store/asset/1840899246) · [The Regiment](https://create.roblox.com/store/asset/1840899338) · [Tenor Drum Sounds (b)](https://create.roblox.com/store/asset/1842279455) | Licensed (APM) |
| `menuMusic` | [Homecoming Of The Victorious (30s)](https://create.roblox.com/store/asset/1838608860) · [War History](https://create.roblox.com/store/asset/1847601287) · [Historical Intro](https://create.roblox.com/store/asset/1845278552) | Licensed (APM) |
| `bugleCharge` | [Three Fanfares](https://create.roblox.com/store/asset/1838225124) · [Four Short Fanfare Bridges 3](https://create.roblox.com/store/asset/1838583668) | Licensed (APM) |
| `ambienceField` | [Mountain Birds 1](https://create.roblox.com/store/asset/9112832288) | Licensed (PSE) |
| `uiClick` | [Hanger Wooded On Off 8](https://create.roblox.com/store/asset/9114775311) (a dry wooden click) | Licensed (PSE) |
| `musketVolley` | [Musket Fire 1](https://create.roblox.com/store/asset/9103981709) · [Flintlock Musket Fire 1](https://create.roblox.com/store/asset/119085773320119) · [Musket Firing](https://create.roblox.com/store/asset/99091571902207) | Community |
| `cannonFire` | [Cannon Fire](https://create.roblox.com/store/asset/138726661215326) · [Cannon Fire Shot](https://create.roblox.com/store/asset/72411732778781) | Community |
| `cavalryCharge` | [Horse Gallop](https://create.roblox.com/store/asset/108771044697744) · [Horse Trot Loopable](https://create.roblox.com/store/asset/92630369612488) | Community |

Skipped: uploads named after commercial games (their rights are doubtful).
