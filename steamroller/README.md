# Steamroller

A **test harness**, not a content mod. Chapter-load crashes can only be
reproduced by getting to the load, and playing chapter one honestly costs six
minutes a try. This pins the offensive stats high and keeps you alive so a
chapter takes a couple of minutes.

- **Scope:** `local-only` — writes go to your own hero's value store. Nothing
  is networked, but a peer sees the results, so keep it out of other people's
  lobbies.
- **Delete it once the question it was made for is answered.**

## Use

```
rsmm enable steamroller && rsmm apply
```

Needs hero capture, like every stat mod: `RSMM_ENABLE_HERO_CAPTURE=1` before
`%command%` in the Steam launch options, or the desktop app's flags panel. The
pins land the first time the hero acts in a run, not at boot.

## Settings

- `attack_power` — displayed attack power to pin (default 4000)
- `move_speed` — move speed multiplier (default 1.6)
- `godmode` — top health back up when it drops (default on)
- `heal_below` — health fraction that triggers a top-up (default 0.5)

## Two things worth knowing if you edit it

- **`R.stat` works in store units — displayed value / 100.** Passing the
  displayed number straight through asks for 100× what you meant.
- **`stick`, not `set`.** The engine rebuilds every stat from base+modifiers on
  the next recompute (a level-up, an item pickup), which silently wipes a plain
  `set()`. `stick` re-asserts after each recompute. Health goes through
  `R.combat` for the same reason: it is the engine's own committed path, where
  poking the HP field only edits a cache.
- **The health top-up requires a landed stat pin.** `R.entity.hp()` is a
  page-guarded read at a fixed offset with no check that the object is a hero,
  so on a wrong capture it returns plausible floats and `hp_frac()` comes out
  under the threshold — after which `R.combat` hands that pointer to
  `Entity_ModifyHealth` and the engine owns the deref. Session 8c4f did
  exactly that and crashed at `Entity_ModifyHealth+0x45`. The value-store
  lookup is the one gate that told the truth, so the heal is gated on it.
- Both writes run only under `ev.source == "gameplay"` — that is the game's
  main thread. Calling them from `tick` (the loader's background thread) is the
  documented way to crash the game.
