# Runestone Shrine

A structure that is not in Ravenswatch: a rune-carved pillar on a stepped
plinth, with a faceted crystal floating above it.

It **generates on the Dark Hills map**, standing alone at the centre of a
clearing of its own. It is **marked on the minimap** with its own icon, and you
can **interact with it**.
The mesh, its three texture maps and the icon are all authored by this mod, from
scratch — no game bytes are copied into the pixels or the vertices.

## Install

```
rsmm enable runestone-shrine
rsmm apply
```

`rsmm restore --all` puts everything back.

## What you will see

A bare grass clearing with the pillar at its centre and open floor all round.

One of the Dark Hills chapter's three crystal clearings is this mod's, so expect
roughly one shrine a run. **That clearing has no crystal in it** — the pillar
stands where the crystal would have, which is the price of the tile existing at
all. A generated map has a fixed number of slots and anything added takes one.

Crystal is the cheapest family to spend: not progression like Key, not traversal
like Teleporter, and crystals drop from other sources. Of the 77 tiles the
chapter pools, the only ones with an empty floor are single-resource clearings;
every Blocker tile, which would have cost nothing, is full of rubble with no
clear centre.

## What it changes

Nothing the game ships is overwritten. The mesh, the material, all three
textures, the prop entity, the tile, its prefab, its level and the icon are all
names the game has never seen.

The only shipped files it touches are the chapter's map definition and its
resource cache, which it has to extend to get its tile into the pool. The
vanilla pool goes from 77 entries to 78 and every vanilla entry survives.

## The art

`tools/make_shrine_assets.py` authors all of it. Run it to change the shrine:

```
python tools/make_shrine_assets.py
rsmm apply
```

| file | what it is |
|---|---|
| `model.glb` | stepped plinth, tapered runed pillar, floating crystal |
| `albedo.png` | layered value noise for stone, carved rune bands, climbing moss |
| `mra.png` | metal / roughness / ambient occlusion |
| `normal.png` | the same detail as surface relief |
| `icon.png` | 48x48 minimap icon, used for both the tiledef slot and the marker |

The pillar is 7.00 units tall and 2.20 across, in a clearing that runs to about
2.9 from the centre — 1.8 units of floor on every side.

⚠ **Width is what constrains it, not height.** An earlier version was 4.20
across and there was no tile in the chapter it fitted in: the healing fountain
alone is 5.05 wide, and every Blocker tile is full of rubble. If you widen the
mesh in the authoring tool, re-check it against the clearing before shipping.

## Tuning it

Everything is in `pois/shrine/poi.toml`.

| want | change |
|---|---|
| more shrines | `copies` (1 today, the SDK caps at 16 and warns past a sensible share) |
| no shrines, without uninstalling | `copies = 0` |
| a different slot family | `base` and `kinds` together — a tile's flags constrain which slots accept it, so move the donor with the kind |
| a different size | `transform.scale`. It is the only scale in the file, and for a reason: it was once set in two places that multiply |
| icon visible only up close | `[marker] reveal_radius`, 20000 today so it shows from the start |

⚠ Every TOML table header (`[slots]`, `[marker]`) has to stay below the plain
keys. A key written after `[slots]` is read as `slots.<key>`, and nothing warns.

## Multiplayer

Map generation is part of the seeded run state, so every peer needs this mod at
the same version. It is marked `deterministic-shared` for that reason.

## Status

The additive chain this rests on is proven in-game as of 2026-09-12: a mod-owned
tiledef pooled and placed, a mod-owned level built, a mod-owned entity
instantiated and drawn, and a mod-owned minimap marker rendering this mod's own
icon.

The **interaction** on a mod-owned host is the one part never confirmed. That is
why the `poi` kind is still rated experimental and why the mod declares
`experimental = true`.
