#!/usr/bin/env python3
"""
Deactivation hook for seeded-runs.

While enabled, init.lua writes the engine's own GameOptions singleton on
every `ready`: "Forced seed" = the configured seed, and "Dev" = true (the
engine only honours a forced seed while Dev is true). The game persists
those to <game>/_Save/GameSettings.ini under `[Debug]`.

The mod only runs while it is enabled, so it cannot unpin them itself —
the ini lines outlive the mod, and the symptom is a run seed that will
not change no matter how thoroughly the mod is removed. `rsmm apply`
fires this hook when the mod flips enabled -> disabled, and uninstall
fires it before deleting the folder (see apply_mods.run_uninstall_hook).

Env contract (set by the caller):

    RSMM_GAME_DIR  — Ravenswatch install directory
    RSMM_MOD_DIR   — this mod's root

Idempotent: missing line / missing file / missing section -> no-op.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

SEED_KEY_RE = re.compile(r"^\s*(Forced\s+seed|Dev)\s*=", re.IGNORECASE)


def main() -> int:
    game = os.environ.get("RSMM_GAME_DIR")
    if not game:
        print("RSMM_GAME_DIR not set; refusing to guess", file=sys.stderr)
        return 1
    ini = Path(game) / "_Save" / "GameSettings.ini"
    if not ini.is_file():
        print(f"no GameSettings.ini at {ini} — nothing to clear")
        return 0

    text = ini.read_text(encoding="utf-8", errors="replace")
    kept: list[str] = []
    removed = 0
    for line in text.splitlines(keepends=True):
        if SEED_KEY_RE.match(line):
            removed += 1
            continue
        kept.append(line)

    if removed == 0:
        print("no `Forced seed=` / `Dev=` line present; ini already clean")
        return 0

    ini.write_text("".join(kept), encoding="utf-8")
    print(f"cleared {removed} `Forced seed=` / `Dev=` line(s) from {ini}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
