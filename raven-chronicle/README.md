# Raven Chronicle

A career log that survives between sessions: kills, bosses, chests, melodies, deaths and runs. Read-only — it watches, it never touches the game.

- **Scope:** `cosmetic`
- **Version:** 1.0.0

## Install

```
rsmm enable raven-chronicle
rsmm apply
```

Settings live in `config.toml` (or the Settings panel in the desktop app);
the available fields and their ranges are declared in `config_schema.toml`.

## Settings

- `report_on_menu`
- `report_on_run_end`

## How it works

This mod is pure event logic — it ships no assets and patches no game files, so
enabling and disabling it costs nothing and cannot corrupt an install. It
subscribes to the engine's own gameplay event bus through the `R.*` SDK.
