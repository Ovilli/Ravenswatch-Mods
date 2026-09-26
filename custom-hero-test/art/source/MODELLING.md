# Modelling Nyx: a night witch on Piper's rig

Nyx plays every one of Piper's animations and abilities, so her body must be
rigged to **Piper's skeleton, unchanged**. Model anything you like on top of it,
inside the limits below.

## Open the kit

`art/source/nyx_starter.blend` holds:

- `Nyx_Rig`: Piper's armature (100 bones) with all 53 of her animations as
  actions. The idle plays on the timeline; pick others in the Action Editor to
  test your model in motion.
- `Nyx_Head`: the game's **head part** (head, hat, hair, feather, eyes).
- `Nyx_Body`: the game's **body part** (torso, arms, legs, dress, cape).
- `Flute_reference`: position reference only. It is not exported; her flute
  is a separate model (`art/flute.glb`).
- Text blocks: this file, and `nyx_export.py`.

Start from Piper's mesh or delete it and model fresh. Either way, keep the two
objects' **names**, and parent each to `Nyx_Rig` with an Armature modifier.

## The limits (the export script refuses to write past them)

| Limit | Value | Why |
|---|---|---|
| Bones | Piper's 100, same names; add none, rename none | weights bind by bone name; only existing bones are animated |
| Bones weighting one part | **63** per object | the game skins at most 63 bones per draw |
| Weights per vertex | **4** | the game's skin format |
| Vertices | **65,535** total, counted after export | above it the game crashes at load |
| Texture | one UV map, one **1024×1024** albedo shared by both parts | both parts use one material |
| Parts | exactly two: `Nyx_Head`, then `Nyx_Body` | they map onto the game's two submeshes, in order |

Piper's own budget, for scale: head part 42 bones, body part **63** (already
at the limit), about 27,000 vertices in total.

## Rigging a night witch

The bones you need already exist:

- **Tall pointed hat** → `Nyx_Head`. Weight the brim and cone to `DEF.Hat`,
  with the sides on `DEF.PHY.Hat.L`, `DEF.PHY.Hat.R` and the front on
  `DEF.PHY.HatF`. These swing with physics.
- **Floppy hat tip** → weight the bent tip along the feather chain
  `DEF.PHY.FeatherHat01 → 02 → 03`. It is a three-bone physics chain, so a
  crooked witch-hat tip will bob as she runs.
- **Hair** → `DEF.PHY.Hair.L` / `.R`.
- **Long cape** → `Nyx_Body`, on the dress bones she already has:
  `DEF.Dress.B` and `DEF.PHY.Dress.B` (back centre), `DEF.Dress01.B.L/R`,
  `DEF.Dress02.B.L/R` (back sides), with `DEF.PHY.*` variants for the swing.
  Because the body part is already at 63 bones, a cape must **reuse** these
  bones: moving weight from one bone to another is fine, adding a 64th is not.
- **Skirt or robe** → `DEF.PHY.Skirt.L/R` and `DEF.Dress03.F.L/R` (front).

Anything the head part carries counts against its 63, so there is room for 21
more bones there if the hat needs extra sway.

## Texture

Paint on one 1024×1024 sheet. `art/nyx_alb.png` (her current painted texture,
already on the material) is a good start if you keep Piper's UVs. With new UVs,
paint a new sheet and point the manifest's `albedo` at it.

## Export and try it

1. In the Text Editor, open `nyx_export.py` and press **Run Script**.
   It checks everything above. Lines marked `FIX` say what to change; nothing
   is written until they are all fixed. On success it writes `art/nyx.glb`.
2. `rsmm apply --dry-run`: the cooker's own check of the file.
3. `rsmm restore --all && rsmm apply && rsmm install-loader`, then play Nyx.

The outfits (Frost, Eclipse, and so on) use this body too, except Moss, which
has a body of its own. Repaint their textures if your new UVs differ from
Piper's.
