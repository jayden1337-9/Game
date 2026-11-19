# Forgotten World — visual asset sources

The art direction is **storybook medieval fantasy**: warm parchment, muted forest greens, weathered stone, dark walnut wood, brass details and readable pixel art. Keep one consistent palette and pixel scale; do not mix unrelated art packs in the same scene.

## Licence-first asset shortlist

These are source pages/catalogues, not assets copied into this repository. Download only the individual packs whose included licence and source notes match the intended use, and keep their original licence files.

| Area | Source | Intended use |
|---|---|---|
| Characters and villagers | https://github.com/Tiddybub/2d-assets | Browse the characters and fantasy collections; each pack includes a SOURCE.md with author and licence details. |
| Terrain, trees and world tiles | https://assethoard.com/free-game-assets/tilesets | Filter for CC0 2D tilesets; look for the Kenney map / roguelike packs and 0x72 fantasy tiles. |
| Medieval buildings and props | https://assethoard.com/free-game-assets/cc0 | Browse CC0 environment and prop packs; prefer matching top-down or side-view assets. |
| Menus, inventory frames and buttons | https://assethoard.com/free-game-assets/cc0 | The catalogue lists Foozle's RPG UI Set 1 as hand-drawn UI and CC0. |
| Typography | https://github.com/google/fonts/tree/main/ofl/imfellenglish | IM Fell English is an old-style serif from Google Fonts under the SIL Open Font License; use it for headings and pair it with a plain readable body font. |
| Creatures and ambient effects | https://github.com/Tiddybub/2d-assets | Browse fantasy, characters and effects; preserve each pack's attribution/licence file even where attribution is not required. |
| Additional medieval pixel-art sets | https://itch.io/game-assets/free/tag-cc0/tag-pixel-art/tag-tileset | Filter by CC0, pixel art and tileset; inspect each pack's own licence before importing. |

## Import rules

1. Prefer CC0 assets. If a pack uses CC-BY or another licence, retain its required attribution and comply with its terms.
2. Do not copy random Google Images or assets with unclear ownership into the game.
3. Keep original downloads in a staging folder, then copy only the required PNG, WAV/OGG, font and metadata files into `game/assets/`.
4. Keep a `LICENSES.md` or the original `SOURCE.md` beside each imported pack.
5. Use nearest-neighbour filtering for pixel art; avoid blur, resampling and mixing different pixel scales.
6. For this 2D side-view project, reject isometric-only packs unless they include compatible side-view sprites.

## Visual implementation status

The current game pass uses a parchment HUD, warm terrain palette, layered sky and distant foliage, and framed crafting, journal, equipment and hotbar panels. These are code-drawn placeholders. The external art packs above still need to be downloaded, reviewed and imported; this document does not claim that third-party images are already bundled.
