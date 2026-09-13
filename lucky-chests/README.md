# Lucky Chests

Chests sometimes pay out twice. A configurable chance on every chest to duplicate one of the magical objects you already carry.

- **Scope:** `local-only`
- **Version:** 1.0.0

## Install

```
rsmm enable lucky-chests
rsmm apply
```

Settings live in `config.toml` (or the Settings panel in the desktop app);
the available fields and their ranges are declared in `config_schema.toml`.

## Settings

- `chance_percent`
- `rarity`
- `pity_after`
- `max_per_run`

## How it works

This mod is pure event logic — it ships no assets and patches no game files, so
enabling and disabling it costs nothing and cannot corrupt an install. It
subscribes to the engine's own gameplay event bus through the `R.*` SDK.
