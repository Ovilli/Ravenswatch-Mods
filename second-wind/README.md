# Second Wind

Go down once per run and you get back up swinging: a handful of dream shards and a short surge of attack power. After that you are on your own.

- **Scope:** `local-only`
- **Version:** 1.0.0

## Install

```
rsmm enable second-wind
rsmm apply
```

Settings live in `config.toml` (or the Settings panel in the desktop app);
the available fields and their ranges are declared in `config_schema.toml`.

## Requires hero capture

This mod changes the hero (dream shards / stat modifiers), so the loader has to have
captured them. That is opt-in — launch the game with `RSMM_ENABLE_HERO_CAPTURE=1`
in the Steam launch options, or enable it in the desktop app's flags panel.
Without it the mod loads, logs a note, and does nothing.

## How it works

This mod is pure event logic — it ships no assets and patches no game files, so
enabling and disabling it costs nothing and cannot corrupt an install. It
subscribes to the engine's own gameplay event bus through the `R.*` SDK.
