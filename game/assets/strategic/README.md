# Strategic visual production assets

Production provenance for the logic-faithful irregular-boundary map pass. Runtime assets live in `game/assets/ui/strategic/` and `game/assets/maps/strategic/`; this directory records their contract and origin.

## Visual contract

- UI icons use a 32×32 view box, `#D7AE5B` copper-gold strokes, transparent backgrounds, and no embedded text.
- Map overview assets use high-coverage silhouettes at their contract sizes: city 12×12 px, capital 18×18 px, terrain 12×12 px, soldier 6×12 px. The city, capital, and terrain source view boxes now match their final pixel boxes to avoid losing thin detail during rasterization.
- `terrain_base_parchment.png` is a low-contrast, full-bleed 1254×1254 mother texture (the built-in generator's actual saved dimensions). It contains no roads, buildings, armies, resources, rivers, borders, grid, text, or country colors. It is a texture input, not a game screenshot.
- Terrain patterns are transparent 64×64 SVG overlays. They are stable motifs to clip inside real province geometry and tint below the game-state overlays.
- Nothing in this pack encodes a province count, owner, capital location, road, army count, or simulation state.

## Provenance

- Raster mother texture: generated once with the built-in OpenAI image generation tool on 2026-09-15. The full prompt and source output location are recorded in `manifest.json`.
- All SVG files, preview markup, and documentation: original project-local work created for this task; no external icon set, font, screenshot, or traced artwork was used.
- The concept image at `docs/assets/ui/2026-09-05-strategic-command-ui-concept.png` was used only as a style reference for restrained hand-painted earth and copper-gold linework. It is not embedded or used as a map background.

## Preview evidence

- `preview.html` shows UI icons both enlarged and at exact 32×32 px, plus map icons at inspection scale and exact final-size rasterization targets.
- `preview.png` is produced from that page with headless Chrome at 1400×1600. It is an asset contact sheet only, not a Godot/gameplay acceptance screenshot.
- Small-size rows intentionally render with CSS `image-rendering:auto`; they demonstrate normal vector rasterization at 12 px, 18 px, and 6×12 px.

## Integration notes

- Import SVGs with filtering enabled. Do not enlarge the logical icon ratios; the renderer supplies the contract pixel rectangle.
- Apply national colors and unit ownership badges in code, not in these neutral assets.
- Multiply the raster base at low opacity beneath terrain motifs. Avoid interpreting texture density as gameplay data.
- The generated mother texture is low contrast but is not certified seamless: measured opposite-edge mean RGB differences are about 27.6 horizontally and 28.3 vertically. Prefer one continuous world-space sample across the full map; if tiling is required, inspect seams in a real Godot render before adoption.
- The soldier asset represents one real army object. Repeat it only according to the existing 3-column slot rules.
- During Godot integration, `soldier_overview.svg` received a final native-size legibility pass: the broad dark body and diagonal firearm remain inside the same 6×12 view box. The renderer supplies the narrow owner-color badge and a separate high-contrast overflow counter; neither changes the one-icon-per-army meaning.

## SVG maintenance

- SVGs are plain project-local XML and can be edited directly in a text editor or vector editor without external source files. Preserve each `viewBox`, transparent background, listed safe padding, palette role, and logical display size from `manifest.json`.
- UI icons use stroked 32×32 geometry. Map overview icons use compact filled silhouettes designed for their exact final-size row. After edits, regenerate `preview.png` and inspect both the enlarged and exact-size rows with normal filtered scaling.
