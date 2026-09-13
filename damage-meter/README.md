# Damage Meter

Per-player damage tracking for co-op: who is carrying the run.

Every few seconds the meter writes a scoreboard to the loader log and persists
a snapshot the CLI can render:

```
[damage-meter] 1. You            48210 dmg   57.3%    612.4 dps    381 hits      1220 taken  <- you
[damage-meter] 2. Akaza          31904 dmg   37.9%    402.1 dps    290 hits          - taken
[damage-meter] 3. Brig            4055 dmg    4.8%     51.7 dps     44 hits          - taken  ?31 unclassified
```

Three ways to read it:

```sh
rsmm overlay damage-meter            # print the current board
rsmm overlay damage-meter --watch    # live, e.g. on a second monitor
```

...or the desktop app's always-on-top overlay window (Settings → Overlays;
drag the bottom-right corner to resize, **Ctrl+Alt+O** un-pins click-through),
which draws the `[overlay]` block this mod declares in its manifest and fills
it with the rows the mod publishes once a second.

## What it counts

| Column | Meaning |
|---|---|
| `dmg`   | total damage dealt to non-hero targets this run |
| `%`     | share of the team's damage — the "carrying" number |
| `dps`   | rolling average over the configured window (`window_seconds`) |
| `hits`  | number of damaged targets (an AoE hitting four enemies is four) |
| `taken` | damage that landed on that player — **your row only**; `-` means this machine cannot observe it (see below) |

Two columns are deliberately allowed to say "I don't know", because a confident
zero in either place reads as a wrong number rather than a missing one:

* `-` under `taken` means no source ever reported a hit on that player — the
  normal state for an ally, and not the same claim as "was never hit".
* `?N unclassified` counts hits whose victim the enemy/prop test could not read.
  Those hits **are** counted (damage is never dropped on a bad read), so a large
  `?N` beside a small damage total is prop chip damage inflating `hits` and
  `dps`, not carry damage.

Damage between heroes is never counted as carry damage; it becomes the victim's
`taken`. Enemies never appear on the board.

### Fences, jars and other furniture

Destructible props and mission objects are damageable entities like any other,
and the **game itself** counts damage dealt to them — its end-of-run total does.
This meter does not, by default: a prop takes a flat **1.0 per hit**, so
counting it inflates hit counts and DPS far more than it inflates damage, and
the board stops answering "who is carrying the fight".

The prop damage is not thrown away — it is reported as `(+1234 into props)` on
the row. Set `ignore_scenery = false` to rank everything the game counts and
match the end-of-run screen instead.

Enemies are told apart by the components they carry (`EnemyController`,
`CharacterController`); a prop carries none. A target the meter cannot read at
all is **counted**, never dropped — and reported as `?N unclassified` so that
assumption is visible instead of silently shaping the board.

The test is remembered per victim **type** (its settings object), not just per
victim, because instances of one prop family share it: one readable jar
classifies every other jar, including the ones whose own component map cannot
be read. Without that, a 2026-08-18 co-op run put one player at 11,612 hits for
613k damage (59 per hit, against 353 for the top row) — thousands of flat-1.0
prop hits arriving as carry damage.

## How allies are tracked

The board is not limited to you. The meter hooks the engine's own per-hero
damage bookkeeping, which runs for **every** hero — the game simply declines to
*total* anything for a hero that is not the local player, which is why the
end-of-run screen only ever shows your own numbers. Reading that hook gives each
ally's damage, split by ability type.

Two more sources fill the gaps: the local attack resolver (damage taken, and
solo play) and the replicated damage event (what other machines tell yours).
The three views are unified per player, so nobody is counted twice and nobody
appears twice.

## Multiplayer, honestly

A peer can only count what its own machine applies or is told about.

* Your own damage is always counted correctly, on any peer.
* The **host** owns the enemies, so the host's board is the most complete one.
* On a client you see your own damage plus whatever the owner replicates to you,
  which may leave another client's damage under-counted.
* `taken` is filled for **you** only. A hit on an ally is applied on the ally's
  own machine, so their meter counts it and yours never sees it — their row
  shows `-`, not `0`.

Nothing is networked or synchronised by this mod, and it changes no game state:
the underlying `R.damage` hook replays the engine's own attack resolution with
the arguments it was given and returns the engine's own result. Running it does
not affect other players, and other players do not need it.

## Names

Your own row shows your real Steam name, and allies show their real names too —
they arrive from the lobby's own attribute blob, which carries a `PlayerName`
per member. A row keeps a `Player N` placeholder only until that roster lands.

Allies are matched to rows in **join order**, so with three or more players the
name-to-row mapping is a best guess rather than a fact. Set `player_2 = "Ada"`
etc. below to pin them yourself.

## Settings

Edit `config.toml` next to this README (it ships with every key spelled out and
commented), or use the desktop app's mod settings panel. `rsmm install-loader`
copies `config.toml` into the game; the loader reads only that file, so a key
you delete falls back to the mod's built-in default, not to the schema's.

| Key | Default | Meaning |
|---|---|---|
| `report_seconds` | 15 | seconds between scoreboard reports in the log (0 = never) |
| `snapshot_seconds` | 1 | how often the live snapshot for the overlay is rewritten (0 = off) |
| `window_seconds` | 10 | rolling window behind the DPS figure |
| `quiet_when_idle` | true | skip a report when nothing changed since the last one |
| `ignore_scenery` | true | count only damage dealt to enemies (skip fences, jars, props) |
| `probe_victims` | false | log what the first 12 distinct targets were — for debugging the enemy test after a game patch |
| `log_hits` | false | log every individual hit (very noisy; debugging only) |
| `player_1..4` | "" | fixed names by join order, e.g. `player_2 = "Ada"` |

## Requirements

The loader (`rsmm install-loader`) with the gameplay bus armed — the default.
Nothing else; no assets are touched, so `rsmm restore --all` removes it cleanly.
