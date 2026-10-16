# Visual reference analysis

**Status:** the brief's `image.png` was not attached to the upload (only the prompt file
arrived). The video is unreachable from this environment and was not watched. This analysis
works from the ten written characteristics in the brief and names what is observed there,
what is adapted for interaction, and what is an artistic choice. When the image arrives,
re-check items marked *(verify)*.

## Observed (from the brief's description)

| # | Description | Game interpretation |
| --- | --- | --- |
| 1 | Elevated oblique view, tops and sides of terrain visible | Default camera pitch ≈ 50° below horizontal, yaw free, height 220–900 studs. *(verify angle)* |
| 2 | Golden-brown / muted olive sculpted terrain with plateaus, valleys, ridges, pronounced shaded slopes | Terrain voxels from the heightmap; relief exaggerated ×1.6 against the real Landgrafenberg; `Grass` recoloured olive-gold, `Ground` warm brown on slopes, directional sun low in the south-east so slopes read. |
| 3 | Dense irregular woodland with individual crowns and dark depth beneath | Tree clusters from `MapGen` woods polygons: 2–3 stacked spheres per crown, dark green-olive, a flat dark disc under each cluster. |
| 4 | Settlements of many brown / reddish pitched-roof houses along roads | Village prop generator: 8–20 small boxes with wedge roofs (terracotta / brown), aligned to the road passing through. |
| 5 | Blue-violet winding waterways with pale banks, narrow roads, visible bridges | Water voxels tinted blue-violet, `Sand` bank strip, roads as `Cobblestone` 6 studs wide, bridge = stone parts with parapets. |
| 6 | Ordered cobalt-blue and charcoal rectangular troop blocks with light faces and shadows (solid miniatures) | Far LOD: one block per rank, cobalt (France) / charcoal (Prussia) with a lighter top face. Near LOD: figures. |
| 7 | Wedge-like cavalry symbols, small artillery silhouettes | Cavalry far LOD is a wedge part; artillery far LOD is a gun silhouette (barrel + two wheels). |
| 8 | Tall commander markers: pole, framed ivory nameplate with dark serif text, military flag beneath; Napoleon's HQ more prominent | `BillboardGui`-free: world-space `SurfaceGui` nameplate on a thin part atop a pole, flag part below; HQ marker 1.5× taller with a wider plate. Enemy markers obey visibility. |
| 9 | Large understated pale serif settlement names on the terrain | Flat `SurfaceGui` labels lying on the ground, serif, cream, 40 % transparency, scale with camera height. |
| 10 | Battlefield dominates; terrain, formation and labels carry the information | HUD is a thin top bar + bottom command bar + small right roster; nothing covers the centre. |

## Adapted for interaction

- Selection ring (thin cream outline) and destination ghost (translucent faction-colour
  rectangle with a facing chevron) are additions the reference does not show.
- Unit blocks carry a small strength bar and status word only when selected or hovered.
- Labels are deconflicted: HQ > selected > hovered > corps > others, hidden when overlapping.

## Artistic choices

- Figures are stylised: 6-part bodies (torso, head, shako, two legs as one block, musket),
  1 figure = 25 soldiers (`Config.Visual.SoldiersPerFigure`). Deaths remove figures in whole
  25-man steps; the inspector shows the real strength.
- Palette (all in `Config.Visual.Palette`): terrain olive-gold `#9A8A4E`, slope brown
  `#7A5C3A`, woods `#3E4E2A`, water `#5A5FA8`, roof `#8A4A32`, France cobalt `#2C4FA6`,
  Prussia charcoal `#3A3D42`, Saxony (Prussian ally) slate `#6C7180`, cream `#EDE4CC`,
  ink `#2A2420`. These are choices, not measurements.
- Fonts: `Enum.Font.Garamond`/`Fondamento`-free: Roblox `Garamond` for titles and labels,
  `Gotham` for HUD data (both ship with Roblox, no uploads).
