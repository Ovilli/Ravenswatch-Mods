# Saga

Meta-progression Ravenswatch does not ship: a global XP bar that grows across
every run you ever play, ranks you climb, feats that unlock once and stay
unlocked, a rotating set of objectives that hand out XP when you finish them,
and a weighted challenge generator that rolls a tiered run ruleset and tracks
the rules it can actually verify.

- **Scope:** `deterministic-shared`. As shipped it is observation only — it
  subscribes to the event bus, keeps score in its own key-value store, and
  never calls into the engine. One setting reaches further: `challenge_apply`
  writes game-modifier state, which is a stat tweak and must match on every
  peer. That setting is off by default.
- **Version:** 1.4.0

## Install

```
rsmm enable saga
rsmm apply
```

Open the HUD with `rsmm overlay saga --watch`, or from the desktop app's
Overlays panel.

## What it tracks

| Layer | What it is | Where it lives |
|-------|-----------|----------------|
| **XP + rank** | One bar for your whole account. Every tracked event pays XP; the rank is derived from the total, so it never resets. | `xp` |
| **Feats** | 18 one-time unlocks against lifetime totals — *First Blood*, *Giant-Slayer*, *Untouched* (win a run without going down), *Tide of Iron* (10 000 kills). | `feat.<id>` |
| **Objectives** | Three (configurable) active at a time, drawn from a pool of 20. Run-scoped ones ("kill 400 in one run") reset with the run; lifetime ones ("open 60 chests") carry over and retire when finished. Finishing one pays XP and draws a replacement. | `slot<n>.id` |
| **Records** | Your best single run for kills, bosses, chests, objects, melodies and chapters. | `best_<metric>` |
| **Winrate** | Wins / defeats / abandons per hero, split solo vs co-op. Printed at the main menu. | `hero.<Hero>.<mode>.<result>` |
| **Challenges** | A weighted, seeded ruleset rolled per run from a 107-entry pool (83 written out, plus the 24 Forced cursed permutations), scored against a tier band. Kept sets pay their score as XP. | `challenges_kept` / `challenges_broken` |

Rank titles: Stranger → Wanderer (5) → Watcher (10) → Sentinel (15) →
Nightwarden (20) → Ravenswatch (30) → Legend (45) → Myth (60).

The curve costs `750 × level` XP to leave a level. A won run pays roughly
2500–3000 XP, so it is about three levels on your first evening and a fraction
of one by level 20.

## Co-op attribution

The gameplay bus is not yours alone: a replicated event is dispatched on every
machine in the party, so an unfiltered counter records the whole party's kills
as your own — and *flawless* quietly comes to mean "nobody went down" rather
than "I didn't".

Events are attributed by `ev.dispatcher`, the dispatcher the event was
delivered to, which for a hero-anchored event is that hero's own.
`R.hero.handle()` is the local hero's. Allies are learned rather than assumed:
any dispatcher that fires a hero-anchored event belongs to *some* hero, and the
ones that are not yours are theirs.

It **fails open**. An event is dropped only when it was positively identified as
another player's hero — an unknown dispatcher, a world-anchored event, or a
session where your hero has not acted yet all count exactly as before, so solo
cannot regress. Turn it off with `attribute_to_me = false`.

Which events this actually reaches is a playtest question, not a static one: an
event anchored on the world rather than on a hero belongs to nobody and stays
party-wide. The mod logs one line per event the first time it decides:

```
[Saga] attribution: GAIN_DREAM_SHARDS -> mine
[Saga] attribution: ENEMY_KILLED -> unattributed
```

Read that before assuming a given counter is now personal.

## Challenges

Off by default. Set `challenge_tier` and Saga rolls a ruleset at the start of
every run, prints it, and tracks the rules it can verify.

A set is drawn from three sub-pools that share one schema:

| Sub-pool | What it is | Weight |
|----------|-----------|--------|
| **malus** | An in-game Custom Mode negative (Corruption, Inflation, Shadowy Fog). | positive |
| **boon** | An in-game positive (Light Feet, Quick Learner, Explorer). | **negative** — a boon reduces the set's score |
| **self** | A rule you hold yourself to (No Melodies, Straight to the Nightmare, Forced cursed). | positive |

The set's score is the sum, with the boons' combined discount capped at 500.
Each tier is a score band plus a count range per sub-pool, and every tier rolls
at least one self-imposed rule:

| Tier | Band | malus | boons | self |
|------|------|-------|-------|------|
| FLAVOR | 150–300 | 0 | 0–2 | 1–3 |
| LIGHT | 301–650 | 1 | 0–2 | 1–3 |
| STANDARD | 651–1000 | 2 | 0–1 | 1–4 |
| HARD | 1001–1500 | 3–5 | 0 | 1–3 |
| BRUTAL | 1501–2200 | 4–5 | 0 | 1–5 |
| IMPOSSIBLE | 2201+ | 5 | 0 | 2–5 |

`weekly_a` and `weekly_b` roll a tier from the weekly lists (FLAVOR and
IMPOSSIBLE never appear in a weekly) and seed from the ISO week, so everyone
who sets the same one gets the same challenge without passing anything around.
Any other tier seeds from the date. Set `challenge_seed` to pin it.

The draw honours conflicts (made symmetric — the spec lists most pairs once),
`requires` (Level 8 in Chapter 1 only rolls alongside Quick Learner), frequency
flags, draw boosts, hero gating (Aladdin-only rules), the co-op toggle, and the
HARD-and-above floor on Trigger the Super Effect. Because draw probability *is*
difficulty here, a tight band overshoots on the last pick, so an over-budget set
is trimmed of its heaviest droppable entry until it fits.

### What is actually tracked

Three states, and the difference is stated rather than implied:

- **auto** — a bus event proves it. Fountains Sealed, No Revive, No Defense
  Input, No Melodies, Level 7/8 in Chapter 1, Level 15, Max Level, Hoarder's
  Gate, Legendary by 4, Double Legendary by 7.
- **partial** — the closest available signal, with a known blind spot named in
  the code. Combat Dashless (only named boss/tumor fights count as combat),
  Glass Frame (max-HP *loss* reads the same as a gain), Level 6 Before Overtime
  (uses the boss activating as "Overtime"), Forced cursed (a hero ability that
  spends no charge fires nothing).
- **honour system** — everything else. Shown and scored, never checked. Routing
  rules, shop rules, build rules and the narration ones have no signal on the
  bus at all.

Nothing fails a rule it has seen no evidence for, and a broken rule stays
broken. A run that breaks nothing pays the set's score as XP.

If a game patch renames a tracked event the subscription still succeeds and
simply never fires, which would silently demote a rule to honour system — so
the mod checks its watch list against the event catalog at load and logs any
name the catalog does not know.

### Auto-apply

`challenge_apply` writes the rolled modifiers into the game instead of printing
them. It is **off by default and experimental**, and it reaches less far than it
sounds:

- Only 11 of the 33 in-game entries map to a modifier key this SDK can write.
  The rest are printed as a checklist to tick in the Custom Mode screen.
- Of those 11, the ones consumed at map generation — Single Chapter, Eternal
  Sun, Solar Eclipse, Blind Hero — cannot be switched on after a run has begun.
- It flips the state key the behaviour is gated on, not the UI. The
  challenge-select screen still shows nothing selected.
- Whether run modifiers live in the hero's value store at all has never been
  proven in-game. A wrong store reads 0 and writes nowhere.

## Settings

- `quest_slots` — how many objectives are active at once (1–6, default 3)
- `xp_multiplier` — scale all XP gain (0.1–10, default 1.0)
- `show_overlay` — publish the objectives HUD
- `report_on_run_end` — print a run summary when a run ends
- `report_on_menu` — print your rank and totals at the main menu
- `attribute_to_me` — in co-op, only count what you did (default on)
- `challenge_tier` — off / flavor / light / standard / hard / brutal /
  impossible / weekly_a / weekly_b / random (default off)
- `challenge_seed` — pin the roll; blank means the date, or the ISO week for a
  weekly
- `challenge_coop` — include the co-op-only rules in the draw
- `challenge_apply` — experimental: write the rolled modifiers (default off)
- `challenge_hero` — the hero you will play, which gates the Aladdin-only rules
- `challenge_preset` — use a hand-designed set instead of rolling

## How it works

Pure event logic — no assets, no patched game files, so enabling and disabling
it costs nothing and cannot corrupt an install. It subscribes to the engine's
gameplay event bus through the `R.*` SDK and writes only to its own
`.rsmm_state` store via `R.kv`.

The XP weights, the feat table and the objective pool are plain Lua tables at
the top of `init.lua`. Adding a feat or an objective is a row, not code.

## Winrate

A run ends in one of three ways, and they are kept apart:

- **win** — `GAME_END_SUCCESS`
- **defeat** — `GAME_END_FAILED` / `ALL_PLAYER_DEAD`, i.e. running out of feathers
- **abandon** — anything else that ends a run: quitting to the menu, or the
  analytics boundary closing a run the gameplay bus never reported on

Only wins and defeats are in the percentage. A run you walked away from is not
a loss, and counting it as one makes the number say something nobody asked it —
it is reported alongside instead.

Each result is filed under the hero you played and whether the lobby had anyone
else in it. The hero comes from the lobby member record's `RequestedHero`, which
is the only source that names a hero without guessing. **In a solo session the
lobby attributes may never be parsed at all** — that books as `Unknown` / solo
rather than inventing a hero, with `R.hero.name()` (signature-based, and only
seeded for heroes catalogued on this machine) as the fallback.

Three details worth knowing if you edit it:

- **Run boundaries are doubled up on purpose.** `run:start` / `run:end` ride the
  analytics firehose, which a session can legitimately be missing; `GAME_START`
  and the `GAME_END_*` gameplay events are the second opinion, and
  `menu:enter` is the backstop for a run abandoned from the pause menu. All
  three paths are idempotent through one `finalized` flag.
- **`GAME_END_SUCCESS` is a CHAPTER clear, not a won run.** Measured in session
  e304: the Dark Hills boss died at 19:40:43, `GAME_END_SUCCESS` landed at :44
  and `GAME_END_NEXT_CHAPTER` at :46, and the run carried on. Acting on the
  success booked a win and unlocked *Dawn At Last* at the end of chapter one.
- **No boundary is acted on where it fires.** The two buses are independent and
  nothing orders them, so whichever arrived first used to win outright. Each
  boundary instead *claims* an outcome; the claim is settled only on leaving
  the run (`run:end`, `menu:enter`, the next run, or shutdown), and
  `GAME_END_NEXT_CHAPTER` withdraws a claimed win. A claim can be upgraded
  until you leave; only leaving is final. `tests/lua/mods_spec.lua` fires the
  boundaries in the hostile order deliberately.
- **A run objective's baseline is deliberately not persisted.** It is
  meaningless once the run is over — storing it is how a slot handed out at 150
  kills ends up silently asking for 150 *more* in the next run.
