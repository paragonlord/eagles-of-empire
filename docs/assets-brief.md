# Asset brief: meshes and textures for Eagles of Empire

The game builds everything from Roblox primitive parts today. Every item below has a named slot
in `src/shared/Assets.luau`; put an asset id in the slot and the game uses the mesh instead of the
parts. Empty slots keep the part version, so you can fill them one at a time.

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
  +Y up, facing **+Z** forward (Roblox default).
- **One material per mesh**, one PNG texture 512² (props) or 1024² (hero objects), no transparency
  except tree canopies (alpha-cutout allowed).
- **Triangle budgets** are per mesh. Roblox caps a MeshPart at 10k; aim far lower.
- **Low poly, hand-painted or flat-shaded** reads better at our camera height than photo-real.
  Reference look: Napoleon: Total War at mid zoom; Epic History TV's Jena maps for the palette
  (olive-gold ground, dark-green woods, red-brown roofs, cobalt vs charcoal units).
- Name files exactly as the slot keys so nothing gets mixed up.

## Figures (slot keys in `Assets.figures`)

Height of a man is **2.8 studs** (figures are 1 : 25 men). Rigged is NOT needed: the game poses
parts itself. Supply each figure as separate meshes so they can animate:

| key | what | tris | notes |
| --- | --- | --- | --- |
| `infTorso` | coat with crossbelts, no arms/head | ≤ 600 | one texture atlas per nation set below |
| `infHead` | head + shako (peak, pompon, plate) | ≤ 400 | French, Prussian, Austrian, Russian, British variants: `infHead_fr` etc. |
| `infHeadBearskin` | Old Guard / grenadier bearskin | ≤ 400 | |
| `infArmL`, `infArmR` | arms in sleeve, hand closed | ≤ 150 each | |
| `infLegL`, `infLegR` | breeches + gaiter + shoe | ≤ 150 each | |
| `musket` | musket with bayonet | ≤ 200 | 1.5 studs long |
| `backpack` | pack with rolled greatcoat | ≤ 150 | |
| `drum`, `eagle`, `flag` | colour party | ≤ 300 | flag as a flat quad is fine |
| `horse` | horse body (no legs, no head) | ≤ 800 | |
| `horseHead`, `horseLeg` | separate | ≤ 300 / 150 | |
| `cavTorso` | rider torso with cuirass variant `cavTorsoCuirass` | ≤ 600 | |
| `cavHeadHelmet`, `cavHeadShako`, `cavHeadColpack` | | ≤ 400 | |
| `sabre`, `lance` | | ≤ 120 | lance 3 studs with pennon quad |
| `gunBarrel` | 6-pdr barrel with trunnions and cascabel | ≤ 400 | 2.2 studs |
| `gunCarriage` | cheeks + trail + axle | ≤ 500 | |
| `wheel` | 8-spoke wheel, 1.4 studs diameter | ≤ 300 | shared with limber and carts |
| `limber` | limber box | ≤ 300 | |

Textures: one 1024² atlas per nation (`uniform_fr.png`, `uniform_pr.png`, `uniform_at.png`,
`uniform_ru.png`, `uniform_gb.png`) covering torso, arms, legs, head; the game recolours facings by
regiment through vertex colour, so leave the lapels/cuffs a mid-grey where the regiment colour goes.

## World props (slot keys in `Assets.world`)

Sizes are the bounding boxes the game expects (W × H × D in studs); the mesh is scaled to fit.

| key | what | size | tris |
| --- | --- | --- | --- |
| `treeOak` | broad oak, visible trunk | 14 × 16 × 14 | ≤ 1200 |
| `treeBeech` | taller, smoother | 10 × 18 × 10 | ≤ 1000 |
| `treePine` | conifer | 8 × 20 × 8 | ≤ 800 |
| `treePoplar` | Lombardy poplar | 4 × 22 × 4 | ≤ 500 |
| `treeWillow` | weeping, for river banks | 12 × 12 × 12 | ≤ 1000 |
| `treeFruit` | orchard apple/pear | 7 × 7 × 7 | ≤ 500 |
| `hedge` | 8-stud hedge segment, tileable ends | 8 × 2 × 1.5 | ≤ 300 |
| `wallStone` | dry-stone wall segment | 8 × 1.6 × 0.8 | ≤ 300 |
| `fenceRail` | post-and-rail segment | 8 × 1.4 × 0.3 | ≤ 150 |
| `houseA` | whitewashed, steep red tile roof, chimney | 10 × 9 × 8 | ≤ 1500 |
| `houseB` | timber-framed, two storeys | 11 × 11 × 8 | ≤ 1800 |
| `houseC` | brick, lean-to | 9 × 8 × 9 | ≤ 1500 |
| `barn` | long timber barn, big doors | 18 × 10 × 9 | ≤ 1500 |
| `church` | nave + spire | 14 × 28 × 24 | ≤ 3000 |
| `churchOnion` | nave + onion-dome tower (Austerlitz) | 14 × 26 × 24 | ≤ 3000 |
| `windmill` | post mill with four sails | 10 × 22 × 10 | ≤ 2000 |
| `watermill` | mill house + wheel | 12 × 10 × 10 | ≤ 2000 |
| `well` | stone well with roof | 2.5 × 3 × 2.5 | ≤ 300 |
| `cart` | farm cart | 4 × 2.5 × 2 | ≤ 500 |
| `haystack`, `stook` | | 4 × 3 × 4 / 1.2 × 1.6 × 1.2 | ≤ 300 / 100 |
| `shrine` | wayside cross/shrine | 1.2 × 3 × 1.2 | ≤ 300 |
| `bridgeStone` | 3-arch stone bridge, tileable span | 10 × 5 × 28 | ≤ 2000 |
| `bridgeTimber` | timber bridge with railings | 8 × 3 × 20 | ≤ 800 |
| `reeds` | reed clump, alpha cutout | 3 × 2 × 3 | ≤ 100 |

Textures (tileable, 1024², PNG): `bark`, `roofTile`, `thatch`, `wallStone`, `wallWhitewash`,
`timberFrame`, `cobbles`, `dirtRoad`, `wheat`, `plough`, `grass`, `paper` (already set).

## UI (slot keys in `Assets.ui`)

`paper` (set), `wax` (red seal, 256² with alpha), `brass` (brushed brass tile, 256²),
`ornament` (a horizontal rule ornament, 512 × 64 with alpha), `stamp` (circular dépôt stamp, 512²
with alpha, red ink), `eagleEmblem` (imperial eagle, 512² alpha, for the menu).

## Priority order

1. `treeOak`, `treeBeech`, `treePine`, `treePoplar`, `bark`, `roofTile` (biggest visible change)
2. `houseA`, `houseB`, `barn`, `church`, `windmill`
3. the infantry set for one nation (`infTorso`, `infHead_fr`, arms, legs, `musket`) + `uniform_fr`
4. `horse` set, `gun` set
5. everything else
