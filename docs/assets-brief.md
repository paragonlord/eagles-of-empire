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
- **Low poly, hand-painted or flat-shaded** reads better at our camera height than photo-real.
  Reference look: Napoleon: Total War at mid zoom; Epic History TV's Jena maps for the palette
  (olive-gold ground, dark-green woods, red-brown roofs, cobalt vs charcoal units).
- Name files exactly as the slot keys so nothing gets mixed up.

## Figures (slot keys in `Assets.slots`)

One mesh per figure, static pose, origin on the ground, facing +X. The game animates by
swapping/offsetting whole figures, so no rig and no separate limbs are needed. Height of a man is
**3.2 studs** (figures are 1 : 25 men).

| key | what | size W × H × D | tris |
| --- | --- | --- | --- |
| `soldierInfantry` | standing musketeer at the shoulder-arms carry, shako, pack | 1 × 3.2 × 1 | ≤ 900 |
| `soldierCavalry` | horse and rider, sabre at the carry | 1.4 × 4 × 3.6 | ≤ 1500 |
| `horse` | horse alone (limber teams) | 1.2 × 3.4 × 3.4 | ≤ 900 |
| `gun` | 6-pdr on its carriage, muzzle toward +X, 8-spoke wheels | 2.4 × 2 × 4.4 | ≤ 1200 |
| `limber` | limber with chest | 2 × 2 × 3 | ≤ 600 |
| `shako` | headgear only, worn on the procedural head | 0.6 × 0.7 × 0.6 | ≤ 200 |
| `bearskin`, `helmet` | same | 0.7 × 0.9 × 0.7 | ≤ 200 |

Textures: one 1024² atlas per nation per figure (`soldierInfantry_fr.png` …); the game tints
coats by faction when the texture is grey where the coat is, so paint the coat a mid-grey and the
facings, belts, breeches and metal in their true colours. Separate nation meshes can come later as
`soldierInfantry_pr` etc.; one French set first.

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
