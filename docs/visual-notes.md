# Visual reference analysis

**Reference:** two frames from the Epic History Jena video (`docs/reference/epic-history-jena-1.jpg`,
`-2.jpg`), supplied after Gate 0. They show the whole battlefield at corps scale; the game
shows regiment/battalion scale, so counts differ while the visual language is kept.
The video itself was not watched (unreachable from this environment).

## Observed in the images

| # | Observation | Game interpretation |
| --- | --- | --- |
| 1 | High oblique view, ~50–55° below horizontal, looking across the field; tops and shaded sides of terrain visible | Default camera pitch 52°, yaw free, height 220–900 studs |
| 2 | Terrain is a sculpted relief model: olive-gold on lit plateaus, darker olive/brown in shadow, pronounced valley shading; no flat parchment | Terrain voxels from the heightmap, relief exaggerated; `Grass` recoloured olive-gold, `Ground` darker on slopes; low sun from the south-east so north/west slopes read dark |
| 3 | Woods: dense dark-green clusters of individual rounded crowns with a dark base, irregular outlines | Tree clusters from `MapGen` woods blobs; 2–3 stacked spheres per crown; a dark disc under each cluster |
| 4 | Villages: tight clusters of many small dark-brown pitched roofs aligned to the roads; towns (Jena, Apolda, Zwätzen) are larger clusters | Village prop generator: box + wedge roof, roofs dark brown, walls muted; counts per village in `MapGen` |
| 5 | Rivers blue-violet with pale banks (Saale east, Ilm west, brooks); roads thin pale lines; bridges visible as small spans | Water voxels tinted blue-violet, `Sand` bank strip, roads `Cobblestone` 6 studs wide, stone bridge parts |
| 6 | Units are flat rectangular slabs with a lighter top face and dark edge: French deep cobalt, Prussian near-black charcoal; infantry corps shown as 2–4 parallel slabs | Far LOD: one slab per rank; colours `Palette.France` / `Palette.Prussia`; near LOD: figures |
| 7 | Cavalry = same slab with two white diagonal stripes; artillery = small dark gun silhouettes | Cavalry far LOD: slab + white diagonal stripes (not a wedge); artillery: barrel + two wheels |
| 8 | Commander markers: thin pole, white/ivory plate with thin dark frame and dark serif capitals ("LANNES / V CORPS"), square flag below (French tricolour eagle standards, Prussian black-and-white); Napoleon's marker taller with a portrait plate | Pole + framed `SurfaceGui` plate + flag part; HQ marker 1.5× taller with a gold-bordered wide plate (no portrait asset) |
| 9 | Settlement names: pale cream serif, mixed case, lying on the terrain, modest size | Flat ground labels, Garamond, cream, 40 % transparency, scale with camera height |
| 10 | The field dominates; no HUD in the reference | Thin top bar + bottom command bar + small roster; centre clear |

Place names visible in the frames (for the condensed map): Jena area — Closewitz, Lützeroda,
Vierzehnheiligen, Isserstedt, Cospeda; north — Stroba, Rödingen, Hermstedt, Gross-Romstedt,
Kapellendorf, Apolda, Niedertrebra, Dornburg, Zwätzen; south — Kötschau. Our map keeps the
Jena-plateau set and uses Apolda, Kapellendorf, Dornburg and Zwätzen in the campaign graph.

## Measured colours (averaged 9×9 samples from frame 2; JPEG-compressed video, approximate)

See the table printed in `docs/reference/colours.txt`. They are darker and more desaturated
than the palette below because of the video's vignette and compression; the palette keeps the
hue relationships (olive-gold ground, blue-violet water, cobalt vs charcoal units) and lifts
brightness so units stay readable in Roblox lighting.

## Adapted for interaction

- Selection ring (thin cream outline) and destination ghost (translucent faction-colour
  rectangle with a facing chevron) are additions the reference does not show.
- Unit slabs carry a strength bar and status word only when selected or hovered.
- Labels are deconflicted: HQ > selected > hovered > corps > others, hidden when overlapping.
- The reference labels corps; the game labels formations, so plates show the formation name
  with the corps on a second line, and only the corps HQ gets a tall marker.

## Artistic choices

- Figures are stylised 6-part bodies; 1 figure = 25 soldiers (`Config.Visual.SoldiersPerFigure`).
  Deaths remove figures in 25-man steps; the inspector shows the real strength.
- Palette lives in `Config.Visual.Palette`; faces and flags are built from parts and
  `SurfaceGui`s (no uploaded images).
- Fonts: Roblox `Garamond` for titles, plates and labels; `Gotham` for HUD data.
