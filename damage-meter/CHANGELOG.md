# Changelog

All notable changes to **Damage Meter**.

Entries before 1.2.0 are reconstructed from the code and its comments — `mods/`
is not tracked in git, so there is no commit history to read them out of.

## 1.2.4 — 2026-08-24

Needs game-loader v8 (`rsmm update-loader`). Every fix below lives in the SDK,
not in this mod's own files, so an older loader will not have them.

There is no 1.2.3. That version was published with a package whose manifest
still said 1.2.2, so installing it never changed the installed version and the
launcher went on offering the same update — the store now refuses a mismatch
like that at publish time.

### Fixed

- **The stutter, at its root.** The identity probes read memory one value at a
  time, and every one of those reads asks the operating system whether the page
  is readable first — 20,000 and 24,000 of them per tick, so ~44,000 syscalls a
  second. Under Proton each goes through Wine's memory manager and takes the
  process lock the game's own thread needs, which is why a player with no other
  mods installed still felt it. They read a page at a time now: measured on the
  same sweep, 12,382 guarded reads became 7.
- **An ally's transform is no longer a second player.** Rows are joined on the
  owner identity the engine itself stamps into every hit it resolves
  (`netcomp -> +0xb8 -> +0x100 -> +0x28`), so a swapped hero object lands on the
  row it belongs to — for allies too, which no join on this build could do
  before. Refuses to merge two heroes that are both alive.
- **The board matches the end-of-run screen.** The engine gates all of its own
  damage accounting on a flag this meter ignored, so hits the game discards were
  being counted. Now gated — and the gate samples before it filters, retiring
  itself if the flag stops behaving, because filtering everything would empty
  the board silently.
- **Kills** are counted per row, and discarded hits are reported rather than
  vanishing.
- **A forked board no longer guesses names.** With more rows than players at
  least one guess is wrong by construction; placeholders are the honest answer.

## 1.2.2 — 2026-08-24

Fixes for a player report of stuttering that got worse once ultimates unlocked
and when Sun Wukong transformed, and that continued with the meter switched
off. All three causes were in the SDK the mod sits on, so this arrives through
`rsmm update-loader` — no new mod files.

### Fixed

- **A transform no longer counts as a new player.** An ability that swaps the
  hero object — Sun Wukong's transform, and a respawn — handed the meter a
  pointer it had never seen and it boarded a second row for the same person.
  The local player is now recognised through the swap (the engine's own
  is-local flag), so the row and its damage survive. An ally still forks: no
  field on this build identifies an ally through a swap, and a wrong merge
  would move one player's damage onto another's row.
- **A forked board no longer keeps the name scan running.** A duplicate row can
  never be named (its name is already held by the row it duplicates), and the
  scan's "is anyone still unnamed?" gate read exactly that — so it swept the
  address space for the rest of the run. That is the stutter. The scan now
  stands down when the board has more rows than the lobby has players, keeping
  the names it already proved.
- **The hero-id scan no longer restarts on every new row.** A new row is a
  bigger sample and worth restarting for, but a board that forks rows threw a
  ~900,000-probe scan back to the start as fast as rows appeared, so it never
  finished. Restarts are now coalesced to one per 30 seconds.
- **`disable` now really stops the meter.** Turning metering off stopped the
  counting, but the once-a-second background tick — the memory scans, the
  per-row probes — kept running for the rest of the session, because nothing
  in it checked whether the meter was on. It does now. (Detours stay installed
  by design: removing a hook another mod may be using is worse than an early
  return in a callback.)

## 1.2.1 — 2026-08-19

### Fixed

- **The identity scan no longer stutters the game.** Locating a player's id
  walks the whole address space, and the meter was doing every player at once,
  every time the lobby changed — including for boards where nobody was left to
  identify. It now does one player per tick, only searches the network id (not
  the gamertag, which appears in chat and every piece of UI text), and does not
  scan at all when every row is already named.
- **Names now appear on the first sweep instead of minutes in.** The meter
  was searching every row's memory for a name, ~264k reads per player, which
  took longer than some runs last. It now asks the process where each player's
  id is stored — one scan per player — and then only has to check which row
  points at it. Same evidence, a fraction of the work. An id that more than one
  row can reach still names nobody: that is a shared table, not an owner.
- **Ally names now come from the player's network id.** Four sessions of
  sweeping for gamertags and hero ids on the hero controller found nothing;
  the id the netcode addresses players by is right there, one pointer deep
  through the entity, and the lobby blob hands it over for free. Two of four
  rows were named on the first run with it. Every chain that hits is
  remembered and tried on later rows, because the offset is not the same for
  every player; and a row whose object was not yet populated when it first
  dealt damage is swept again instead of keeping a placeholder for the run.
- **The lobby hook can no longer name a row at all, and that is deliberate.**
  Decompiling the engine settled it: the attribute parser is handed a stack
  local, and the lobby members it iterates are freshly allocated copies freed
  in the same call. Session 5636 showed the consequence live — one address
  arriving as `tyki07` and later as `Ovili`. Every sweep built on that pairing
  has been removed rather than tuned, along with the hundreds of log lines per
  tick it produced.
- **Rows are now identified one pointer deep.** The controller holds a pointer
  to the hero definition and the hero id is a field of the definition, which is
  why four sessions reported "no offset distinguishes the rows" for the field
  on the controller itself. The deep scan is budgeted across background ticks
  and reports once, when it finishes, instead of repeating the same dead end
  every tick.
- **A stack frame is no longer mistaken for a lobby member.** Session 6136
  named the local row `Timattttttt` while Ovili was at the keyboard. The
  reverse member link — "a member object holding a pointer to a hero controller
  names that controller" — was being fed addresses like `0x11e538` and
  `0x11f400`, which are not member records at all but the game thread's STACK,
  handed to the parse detour as `param_1`. A stack is full of live controller
  pointers, so the link matched one by coincidence and stamped the row with
  whatever name last passed through that slot. Three independent defences now:
  an address parsed under two different names is blacklisted for the session; a
  link offset must be corroborated by two different members reaching two
  different rows before anything is claimed through it (the six false hits in
  6136 were at six different offsets, the two real ones both at `+0x210`); and
  a claim that would rename the LOCAL row is refused outright, because Steam
  already said who is at this keyboard.
- **A wrong claim used to cost two rows, not one.** The bad claim on the local
  row set its `player`, which consumed a real player's name — the row that
  actually owned it was then refused it as a duplicate and finished the run as
  `Player 3`.
- **The local player is no longer pruned from the roster mid-run.** 6136
  dropped `Ovili` with "last parsed 123s before the newest member": a run in
  progress re-parses the OTHER members as they move through lobby state and
  never re-parses us, so pure recency ages the local player out. Losing that
  entry costs more than a roster line — it is what tells every identity sweep
  which row must not be renamed.
- **Ally rows no longer carry the wrong player's name.** Reported from a
  four-player session: the local row was right and every ally row showed
  someone else's name against its damage. Names were matched to rows by
  *position* — `allies[rank]`, rank being the order allies first dealt damage,
  which is unrelated to the order the lobby lists members in. The join is the
  hero id now (each lobby member carries its `RequestedHero`); when that is not
  available the row keeps its `Player N` placeholder instead of borrowing a
  name, and the one case that is still exact by counting — a single unnamed row
  facing a single unclaimed name — is marked `?` on the board and the overlay.
  The fix is in the SDK (`rsmm.lua`), so it reaches players through the next
  loader-channel publish (`rsmm update-loader`); on an older loader the mod
  still runs and still shows the positional names.

### Added

- **Rows are identified by the player's own name, read out of their own hero
  object.** A four-player playtest proved the hero-id join cannot fire on this
  build (`no offset distinguishes the rows` — the lobby's `RequestedHero` is not
  a dword on the hero controller), which left every ally on a placeholder. The
  meter now sweeps each controller and its entity, inline and one pointer deep,
  for a name the lobby knows; a gamertag found inside a player's own object is
  identity with nothing to guess about. The sweep is budgeted per background
  tick, and the first hit teaches an offset chain that names every later row in
  two reads. If it finds nothing it says so once, with the roster it searched.
- **`InLobby` is not membership** (fixed the same day it shipped). It means
  "sitting in the lobby menu" and goes false for everyone the moment a run
  starts, so reading it as "left" pruned all four real players of session ea68 —
  every one of them on the end-of-run scoreboard — and left only a name from a
  lobby abandoned minutes earlier, which elimination then pinned on another
  player's 3.5k damage. The roster now prunes on recency alone, plus the game's
  own four-seat cap (the fifth-most-recently-parsed member cannot be in the
  run), and never evicts the local player.
- **Three independent identity sweeps**, because the first one came back empty
  on a real run: the hero-id field sweep now tries **byte and word** widths as
  well as dword (a hero id is 2/4/5/6 — exactly what an engine keeps in a byte,
  and a dword read over a byte field sees the neighbouring garbage); the
  owner-name sweep reaches deeper through pointers (0x400, enough for the HUD
  mirror and the stats block); and a new **member-link** sweep runs the other
  direction — a lobby member object that points at a hero controller names that
  row outright.
- **The lobby roster is the CURRENT lobby.** It was append-only, so a session
  that backed out of matchmaking and searched again kept every candidate
  teammate it had ever seen — a four-player run listed six members, two of whom
  never entered it. Members are now dropped when the lobby reports them out
  (`InLobby=false`) or when the engine stops refreshing them, measured against
  the newest parse rather than the clock so a run in progress (which parses
  nobody) keeps its whole roster. `RequestedHero: -1` is read as "has not picked
  a hero" instead of as hero id -1. Departures are logged.
- **`guess_names`** (default `false`) — hand the leftover lobby names to the
  leftover rows in join order anyway. Those rows print with a trailing `?`.
- `player_1`..`player_4` still override everything, by join order: slot N is the
  row the board prints as `Player N`, so a minute of play tells you which is
  which and the names stick for the rest of the run.

## 1.2.0 — 2026-08-18

Fixes for four problems visible in a 4-player co-op log. Needs the SDK shipped
in **loader channel v3** (`rsmm update-loader`); on an older loader the mod
still runs, it just prints the board it printed in 1.1.0.

### Fixed

- **Destructible props no longer land on the board as carry damage.** The
  enemy-vs-prop test asked each victim individually, and a victim it could not
  read was *counted* (a bad read must never delete a player's damage) — so a
  whole prop family arriving unreadable was ranked as damage. In the 2026-08-18
  log that put one player at **11,612 hits for 613k damage** — 59 per hit,
  against 353 for the top row — with long runs of exactly `1.0` (the flat
  per-hit prop value) and a frozen `(+N into props)` column while their hit
  count kept climbing. The answer is now remembered per victim **type**, so one
  readable jar classifies every unreadable jar of that family.
- **`taken` no longer claims 0 for allies.** The engine's damage-received
  bookkeeping only fires for heroes this machine owns, so every ally read
  exactly 0 for a 55-minute run — a wrong number, not a missing one. Ally rows
  print `-` now, meaning "not observable from here".
- **The board no longer double-prefixes the log.** Every line read
  `[damage-meter] [damage-meter] …`; the loader already prefixes the mod id.
- **`window_seconds` now defaults to 15, matching `report_seconds`.** A 10s
  window under a 15s report has a 5s blind gap, so a player who stopped
  attacking 11s ago printed `0.0 dps` on the same line that showed their damage
  rising. The mod logs a note at startup if you set the window lower again.

### Added

- **`?N unclassified`** on a row: how many of its hits were counted against a
  victim the prop test could not read. A large `?N` beside a small damage total
  is prop chip damage inflating `hits` and `dps`, not carry damage.
- The overlay receives `unknown_hits` and `taken_known` too, so the HUD is not
  the one place still printing a confident zero.
- The board (`R.damage.board()`) exposes `unknown`, `unknown_hits`,
  `taken_known` and `dps_window` for any other consumer.

### Notes

- Two fixes in the same release landed in the **SDK**, not in this mod, and
  benefit every mod that captures the hero: the hero-candidate ring now prefers
  this machine's player over an ally, and a chapter change retires the previous
  chapter's hero instead of leaving every write going into freed memory.
- `log_hits` is still shipped as `true` in `config.toml`. It writes a line per
  hit — thousands per run — and buries every other mod's output. Set it to
  `false` unless you are debugging.

## 1.1.0

### Added

- **The scenery filter** (`ignore_scenery`, default on): rank damage dealt to
  enemies only, and report what the furniture absorbed separately as
  `(+N into props)` rather than dropping it. Enemies are told apart by the
  `EnemyController` component they carry; a prop carries none. Confirmed in a
  5-player run, 2026-08-17.
- **Real ally names from the lobby**, replacing `Player N`. They arrive from the
  lobby's own attribute blob, which carries a `PlayerName` per member. Rows are
  still matched to names in join order, so with 3+ players the pairing is a
  guess and says so.
- **The desktop overlay**: an `[overlay]` block in the manifest declares the
  HUD's shape (columns, sorting, highlight) and the mod publishes live rows into
  it once a second. No mod-specific code in the desktop app.
- `probe_victims`, a diagnostic that logs what the first few victims were and
  which components each carried — for when a game patch makes the board look
  wrong.

### Fixed

- **A chapter change no longer forks the board.** The engine rebuilds every hero
  controller when a chapter loads, so rows keyed by that pointer split in two:
  a 4-player lobby produced seven rows, one player listed twice with both halves
  marked as the local player, placeholder labels running to `Player 7`, and the
  abandoned rows frozen at 0.0 dps. Rows now carry a hero identity that survives
  the transition, and a row is only re-adopted when its old controller cannot
  still be alive — refusing costs a visible duplicate, while merging silently
  deletes a player.

## 1.0.0

### Added

- Per-player damage tracking for co-op: damage dealt, share of the team total,
  rolling DPS, hit count and damage taken, boarding every hero the engine
  attributes damage to — not just you.
- Ally damage read from the engine's own per-hero bookkeeping, which runs for
  every hero even though the game only ever *totals* it for the local player.
  Two more sources fill the gaps (the local attack resolver for solo play and
  damage taken, and the replicated damage event), unified per player so nobody
  is counted or listed twice.
- Three places to read the board: the loader log, `rsmm overlay damage-meter
  --watch`, and the desktop app's always-on-top overlay window.
- Per-ability breakdown, biggest single hit, and per-run reset on run
  boundaries.
- Observation only. The meter replays the engine's attack resolution with the
  arguments it was given and returns the engine's own result, so no damage
  number, target list or event is altered. Nothing is networked; each peer
  counts what its own machine sees, and no other player needs the mod.
