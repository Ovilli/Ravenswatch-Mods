# Bounty Board

A live board of combat bounties that refreshes all run long. Each bounty is a
small goal on a timer. Meet it and it pays out on the spot; miss it and a new
one is posted a few seconds later.

| Bounty | Standard goal | Time | Pays |
|---|---|---|---|
| Slay N enemies | 20 | 2:00 | 40 shards |
| Kill N within 8 seconds | 6 | 3:00 | 60 shards + reroll |
| Kill N without getting hit | 10 (a hit resets it) | 4:00 | 60 shards + reroll |
| Open N chests | 2 | 5:00 | 40 shards |
| Gain N levels | 2 | 6:00 | 40 shards |
| Win a world event | 1 | 7:00 | 60 shards + reroll |

- **Streak:** three bounties completed in a row (no expiry in between) also pay
  a **mystery item**, a random magical object from the run's pool. It can be
  cursed.
- **Boss bounty:** every boss fight posts *Defeat the boss without falling*.
  It pays a talent upgrade and a revive token; going down once fails it.
- **Difficulty:** Relaxed (fewer kills, longer timers, smaller payouts),
  Standard, or Brutal (×1.5 goals, ×0.75 time, ×1.6 payouts and two rerolls).
  Switch it from the overlay; it applies to the next bounty posted.
- Clocks stop between chapters and during cinematics.

## Where the board shows

- The desktop app's overlay window (Settings → Overlays → Bounties).
- `rsmm overlay bounty-board --watch` in a terminal.
- `rsmm log -f --grep Bounty` for every posting, completion and payout.

## Co-op

Every player who runs the mod has their own board. Kills count for the whole
team, hits taken only for you, and payouts go to your own hero.

## Known limits

- *Win a world event* listens for `ACTIVITY_SUCCESS`, which has not been seen
  firing in a playtest yet. If it never completes, it simply expires; it is
  the rarest bounty for that reason.
- Payouts wait until your hero has acted once in the run (attacked or used an
  ability), because that is when the game exposes the hero's reward channel.
