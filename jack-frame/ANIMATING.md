# Animating Jack

Jack moves on the rig's skeleton (Kintaro's bones, 157 of them). His clips are
his own files: a Blender action cooked into `Hero_JackSelf_<name>.fbx`.

## Start file

`art/anims/jack_rig_kintaro_clips.glb` — the rig with Jack's body and 40
on-foot clips as Blender actions. Import it (File > Import > glTF 2.0).

## Make a clip

1. Duplicate the closest action (e.g. `Kintaro_Power_Out`) and rename it
   (e.g. `Jack_Timber`), or animate from scratch on the same armature.
2. Keep the bone names. Do not add, rename or delete bones: a bone the
   skeleton does not have is refused when cooking.
3. Export glTF binary (.glb) with only that action
   (Animation > "Export animations" / active action), Y-up, no mesh needed.
   Put it in `art/anims/`.

Bones you leave unanimated hold the template's first pose.

## Use it

```toml
[content.frame.animations.Timber]
source   = "art/anims/jack_timber.glb"
clip     = "Jack_Timber"                 # the action's name in the glb
template = "Kintaro_Power_Out"           # any rig clip: bone order + format

[content.frame.abilities.power]
clip = "anim:Timber"                     # length comes from the clip
```

Any shared slot takes one the same way, e.g.
`[content.frame.slots."Default Idle Anim"] clip = "anim:Idle"`.

## Getting motion fast

Free motion libraries (e.g. Mixamo axe/attack clips) retargeted onto this
armature in Blender (Rokoko Retargeting, Auto-Rig Pro) give real new moves.
Retarget onto the `DEF.*` bones, then export as above.
