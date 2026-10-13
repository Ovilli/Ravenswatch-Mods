# Kintaro Clone (Brakk)

A 13th hero, cloned from Kintaro. With only `base = "Kintaro"` he plays exactly
like Kintaro, so this is a clean starting point.

Change him in `manifest.toml` under `[[content]]`:
`name`/`description` for the select screen, `albedo`/`portrait`/`outfits` for art,
`values` for numbers, `abilities` and `attacks` for moves. Field reference:
`src/rsmm/sdk/kinds/heros.py`.

After each edit: `rsmm lint kintaro-clone`, then `rsmm restore --all && rsmm apply`.

Note: the hero's first run may need `unlock-heroes` enabled to be selectable.
