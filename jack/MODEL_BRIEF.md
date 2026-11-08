# Model brief: Jack, the Giant-Slayer

You are building the 3D model for a custom Ravenswatch hero, **Jack** (from
*Jack and the Beanstalk*). He is built on the hero **Beowulf**: he uses
Beowulf's skeleton and every one of his animations. You only replace the
**mesh and textures**. Nothing you deliver can change bones or animations.

## Art style: match Passtech Games, not generic "stylized"

Ravenswatch (Passtech Games) has a very specific look, and generic
stylized/PBR output does not match it. **Before modelling, open
`art/reference/passtech_style_sheet.png`.** It shows six shipped heroes
(Aladdin, Romeo, Beowulf, Kintaro, Piper, Geppetto) in front, ¾, side and
in-game camera views, rendered from the game's own meshes and maps. The single
views (`art/reference/<Hero>_<view>.png`) are larger. Beowulf is Jack's
skeleton; Romeo and Aladdin are the closest builds to Jack.

The numbers below were measured from those heroes' shipped files. Treat them
as targets.

### Shape and silhouette

- **Exaggerated proportions.** Passtech heroes have oversized hands, forearms
  and boots. Adults are about 7 heads tall with a small head (Beowulf,
  Romeo); young characters have a big head and are about 5 heads tall
  (Piper 4.8, Kintaro about 3.5).
- **Jack is a BOY (about 13), not a man.** He uses Beowulf's skeleton, which
  fixes only where the JOINTS are (shoulders, elbows, hips, knees: the dots
  on the template), not how thick the body around them is. The game scales
  the whole of Jack to **0.8** (`Character Mesh Scale` in the manifest), so
  he stands a head shorter than Beowulf. Inside those joints, make him a boy:
  - a **big head** (about 5 heads tall at Beowulf's height) and a young face;
  - **thin arms and legs** around the same bones, a slim chest and waist;
  - **oversized hand-me-down clothes** that bridge the gap to Beowulf's wide
    shoulder joints: a baggy shirt with dropped shoulders and rolled
    sleeves, a too-big sash and belt, wide trouser legs, boots a size too
    big. That is the poor widow's son of the tale, and it reads as a kid
    on a grown man's frame;
  - big hands and feet are fine (the Passtech "puppy" look).
- **Hard, angular planes.** Cloth is cut in flat, faceted panels with sharp
  folds, not soft simulated drapery. Hems end in **jagged sawtooth points**
  (Piper's cape and leg wraps, Romeo's knee spikes), and leather straps and
  wraps are chunky bands.
- **Readable from above.** The game camera looks down at about 55°
  (`*_gamecam.png`). The head, hair, shoulders and back prop carry the
  silhouette, so make the hair, the sash and the pot lid on his back bold
  shapes.
- **Faces:** angular and graphic. A sharp nose, heavy brow, simple almond eyes
  with a dark painted lid line, and a strong jaw. No realistic skin detail.

### Geometry budget

- **Body: 13,000–16,500 triangles** (every shipped hero sits in this range;
  Beowulf has 15,249). Weapon about 400–1,000; the lid about 1,000.
- Low-poly with clean silhouettes. Detail goes in the paint, not the mesh.
  Do **not** ship a dense sculpt or a raw AI-generated mesh: retopologise.

### Textures (this is where AI output usually goes wrong)

- **Hand-painted, with the lighting painted in.** The albedo carries its own
  shading: soft top-down gradients, darker undersides, painted highlights on
  edges. The game adds little lighting on top. Average albedo brightness is
  only **0.26–0.39** (on a 0–1 scale), so these are dark, rich colours, not
  pastel.
- **Dark ink line work** is painted into the albedo along seams, folds,
  stitches and panel edges, and as a few crack/scratch strokes (2–12% of the
  texels are near-black). Look at `art/jack_body_alb.png` (Beowulf's map
  recoloured to Jack's palette) for exactly how the lines sit.
- **Palette:** earthy and muted (average saturation 0.31–0.39), with **one or
  two accent colours** (Piper purple, Romeo orange-red). Jack: moss green and
  brown, with an ochre sash and copper as the accents.
- **No photo textures, no noise, no fabric weave, no tiling materials.**
  Surfaces are flat paint with brush-stroke gradients.
- **MRA map:** almost no metal (0–3% of texels; only real metal such as the
  axe head and lid rim go to 1). Roughness is high (0.75–1.0, matte), and AO is
  near white (the shadows are already in the albedo).
- **Normal map: mostly flat.** 60–85% of the texels are perfectly flat; use it
  only for big bevels, folds and a few chiselled edges. No sculpted
  micro-detail.

### If you use an image- or text-to-3D generator

Generators default to realistic PBR with sculpted noise. Generate a **concept
image first**, using `passtech_style_sheet.png` as the style reference, then
build from that, and expect to retopologise and repaint. A starting prompt:

> Stylized 3D game hero in the style of Ravenswatch by Passtech Games,
> hand-painted textures with painted-in lighting and dark ink outlines, dark
> fairy-tale mood, exaggerated proportions with oversized hands, forearms and
> boots, angular faceted cloth with jagged sawtooth hems, low-poly game asset.
> Jack from Jack and the Beanstalk: a scrawny 13-year-old farm boy, big head, messy straw-blond
> hair, freckles, sly grin, patched moss-green wool tunic, brown trousers,
> ochre sash, chunky leather straps and boots, seed pouch and dried bean pods
> on the belt, a woodcutter's felling axe, a dented copper pot lid slung on
> his back. Full body, A-pose, neutral grey background.

Avoid: realistic, photorealistic, PBR metal, glossy, subsurface skin, sculpted
detail, fabric texture, anime, chibi, Pixar/Disney soft look, cel-shading
with a flat outline shader (the outlines are *painted*, not a shader).

### Concept reviews: v1 and v2 (`art/reference/concept_v1.png`, `concept_v2.png`)

- **v1** (`concept_v1_vs_beowulf_romeo.png`): a slim teen with the right
  outfit and palette, but its joints did not sit on Beowulf's skeleton, it
  had a comic/anime face, fine scratchy paint and arms hanging down.
- **v2** (`concept_v2_vs_template.png`): joints on the skeleton and the axe
  and lid added, but it overshot into a **big muscular man**. That was this
  brief's fault (it asked for "broad, top-heavy, thick forearms").

**Keep from v2:** the outfit, palette, axe, copper pot lid on a strap, the
sawtooth hems and the boots. **v3 target:** v2's design on a BOY's body (see
"Shape and silhouette"): big head, young face, thin limbs, baggy oversized
clothes, joints still on the template's dots, in an A-pose. Generate a
**turnaround sheet** (front, side, back, same scale), because image-to-3D
builds far better geometry from several views. Feed `concept_v2.png` as the
design reference, `beowulf_bindpose_front_silhouette.png` as the pose
reference and `passtech_style_sheet.png` as the style reference:

> Character turnaround sheet, front view, side view and back view, same
> scale, A-pose with arms 45 degrees out, legs straight. Same outfit, colours
> and props as the design reference, but the character is a scrawny
> 13-year-old boy, not a man: big head (about 5 heads tall), young face, thin
> arms and legs, slim chest, wearing hand-me-down clothes that are too big
> for him (baggy dropped-shoulder shirt, rolled sleeves, oversized belt and
> sash, wide trousers, boots a size too big). Stylized game hero in the style
> of Ravenswatch by Passtech Games: angular graphic face, sharp nose,
> cheeky closed-mouth smirk, freckles, straw-blond hair in a few big chunky
> clumps, oversized hands and boots. Hand-painted look with large flat colour
> areas, smooth gradients and a few bold dark ink lines, no speckled grime
> or noise. Woodcutter's felling axe standing beside him, dented copper pot
> lid on his back. Neutral grey background.

**Short prompt (809 characters, for tools capped at 1024):**

> Stylized 3D game hero in the style of Ravenswatch by Passtech Games. Jack from Jack and the Beanstalk: a scrawny 13-year-old farm boy, big head, young angular face, sharp nose, freckles, cheeky smirk, messy straw-blond hair in big chunky clumps. Cream sheepskin collar, patched moss-green tunic with short sleeves and a jagged sawtooth hem, ochre sash across the chest and waist with a rope belt, seed pouch and bean pods, brown knee shorts, leather bracers, chunky tan boots a size too big. Thin arms and legs, oversized hands and boots. Hand-painted textures with painted-in lighting and a few dark ink lines, muted earthy colours, flat angular cloth panels. Low-poly game asset. Full body, A-pose, arms 45 degrees out, grey background. No realism, no glossy PBR, no sculpted noise, no anime, no Pixar look.

### Check before delivering

Render your model with flat or unlit shading (texture only) next to
`art/reference/Beowulf_front.png` and `Romeo_front.png` at the same size. It
should look like it belongs in the same row of the sheet.

## The character

A farm boy of about 13 (see "Shape and silhouette": a boy's body on Beowulf's
joints, scaled to 0.8 in game). He should read as poor, quick and cheeky.

- **Clothes:** patched moss-green wool tunic, brown trousers, ochre sash, worn
  leather boots and belt, rolled sleeves. Maybe a few dried bean pods and a
  small seed pouch hanging off the belt.
- **Head:** messy straw-blond hair, no beard (Beowulf has one, so remove it),
  freckles, a sly grin.
- **Weapon (right hand):** a woodcutter's felling axe, single-bladed, with a
  long wooden haft and a nicked steel head. It replaces Beowulf's sword.
- **Back:** the giant's **copper pot lid**, round, dented, with a handle. It
  replaces Beowulf's round shield and sits on the same bone.

## What to deliver (put the files in `mods/jack/art/`)

| File | What | Rig / anchor |
| --- | --- | --- |
| `jack.glb` | body mesh, skinned | Beowulf's skeleton (113 bones) |
| `jack_body_alb.png`, `jack_body_mra.png`, `jack_body_nrm.png` | 1024×1024 body maps | – |
| `jack_axe.glb` | the axe, unskinned | origin on the grip, modelled where the sword sits on `DEF.Weapon.Sword` |
| `jack_lid.glb` | the pot lid, unskinned | modelled where the shield sits on `DEF.PHY.Weapon.Shield` |
| `jack_acc_alb.png` (+ `_mra`, `_nrm` if you can) | one shared 1024 map for the axe and the lid | – |

The MRA map packs R = metalness, G = roughness, B = ambient occlusion. A map
you skip keeps Beowulf's map; the albedo matters most.

## Start file

`mods/jack/art/source/beowulf_starter.glb` is Beowulf's rig with his sword
and shields placed on their bones, and his idle animation. Its body mesh has
**three material slots, and they map one to one onto the game's**:

| Slot | Vertices | Atlas | What |
| --- | --- | --- | --- |
| 0 | 2,196 | body (`jack_body_*`) | Beowulf's head / upper part |
| 1 | 5,471 | body (`jack_body_*`) | the rest of his body |
| 2 | 1,904 | accessories (`jack_acc_*`) | **the Wyrm**: the companion lives inside the body mesh, weighted to its own bones of the same skeleton (in rest pose it lies at Beowulf's feet) |

Model Jack over slots 0 and 1. The proportions must match Beowulf's, because
his animations drive Jack's body unchanged. Mismatched limb lengths or
shoulder widths clip and stretch.

**Proportion template:** `art/reference/beowulf_bindpose_front_silhouette.png`
and `..._side_silhouette.png` show Beowulf's rest (A-)pose silhouette with
the joints marked (head, neck, shoulders, elbows, hips, knees). Jack's
shoulders, elbows, hips and knees must sit on those dots. Use the image as
the pose/shape guide for a concept generator (image reference, ControlNet
pose or depth). `..._textured.png` is the same pose in colour.

To regenerate it: `rsmm export-character Beowulf -o beowulf_starter.glb`
(add `--clips ''` for the mesh only, or leave `--clips` out for every
animation, which is good for testing deformation).

## Hard rules (the importer refuses or breaks otherwise)

1. **Bones bind by name.** Weight only to bones that already exist in the
   starter rig. Do not add, rename or delete bones. Keep the armature as
   exported.
2. **Exactly three material slots, in the starter's order:** Jack's head /
   upper part, the rest of Jack, then the Hen (or the untouched Wyrm). They
   land on the game's slots by position. A missing third slot loses the
   companion, and a fourth is merged into the third (the Hen's material).
   **Each slot may use 63 bones or fewer.**
3. **Each vertex has 4 bone weights or fewer**, normalised.
4. **65,535 vertices or fewer per submesh after export** (split normals and
   UV seams count). Aim for 8–15k in total, like the original.
5. **One UV set.** Slots 0 and 1 share one 1024 atlas (`jack_body_*`).
   Slot 2 (the Hen) uses the accessories atlas (`jack_acc_*`), shared with
   the axe and the lid.
6. **The axe and the lid are static meshes**, not skinned and with no
   armature. Keep their authored scale and orientation: they are fitted to
   the bone as modelled. Model them in place over the starter's sword and
   shield, then export each one on its own.
7. Y-up glTF binary (`.glb`), metres, the same scale as the starter.

## Testing

Once the files are in `mods/jack/art/`, add these lines to
`mods/jack/manifest.toml` in the `[[content]]` block and run
`rsmm apply --dry-run`. It cooks everything and reports any rule above that
was broken:

```toml
model  = "art/jack.glb"
albedo = "art/jack_body_alb.png"
mra    = "art/jack_body_mra.png"
normal = "art/jack_body_nrm.png"

[content.weapons."Weapon In Right Hand Mesh"]
model  = "art/jack_axe.glb"
albedo = "art/jack_acc_alb.png"

[content.weapons."Weapon Shield Back Mesh"]
model  = "art/jack_lid.glb"
albedo = "art/jack_acc_alb.png"
```

(`Weapon In Right Hand Mesh` already has an entry in the manifest. Merge into
it rather than adding a second one.)

## The Golden Hen (optional, in the body file)

Beowulf's dragon is Jack's **Golden Hen**. She is slot 2 of the body mesh,
skinned to the Wyrm's own bones in the same skeleton (wings, tail, jaw), so
a hen model goes into `jack.glb` as the third material slot and needs no
extra wiring. Until then, keep the starter's Wyrm in slot 2 untouched (it is
already recoloured gold by `art/jack_acc_alb.png`).

A hen in Passtech's style: a plump, fierce, slightly menacing barnyard hen
(not cute), with chunky faceted feathers in sawtooth layers, a golden body
with brown wing-tips, a red comb, and an ember glow at the beak (she breathes
fire). Keep the Wyrm's size and pivots: her wings follow the Wyrm's wing
bones, her neck and head the jaw/neck chain, and her tail the tail bones.
Weight only to the Wyrm's bones, with 63 or fewer in that slot.
