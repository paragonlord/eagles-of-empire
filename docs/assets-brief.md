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

## Priority order

1. `treeOak`, `treeBeech`, `treePine`, `treePoplar` (biggest visible change; textures are done)
2. `houseA`, `houseB`, `barn`, `church`, `windmill`
3. `soldierInfantry` (French) with its atlas
4. `soldierCavalry`, `gun`, `limber`, `horse`
5. everything else

First test: import one oak, paste its mesh id into `Assets.slots.treeOak.mesh`, set `scale` so
it is ~12 × 13 × 12, run `tools/check.sh`, play Jena. Every oak on the map becomes that mesh.

## Sound candidates (to audition; none wired in yet)

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
