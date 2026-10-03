# Beowulf Fireball Test

TEST mod for the in-place `ability` kind: it edits Beowulf himself (no extra hero).

What changes (the Fireball, Beowulf's ultimate-2 talent, "Ultimate 2 Fireball Dash"):

| Part (file `Hero_Beowulf_Ultimate_2_Fireball`) | Was | Now |
|---|---|---|
| Stagger Power Selector (entry 1) | 50 | 5000 |
| Stun Duration Selector (entry 1) | 1 | 10 |
| Spawner Scale Value | 2 | 6 |
| Splash Radius Value | 7 | 20 |

`init.lua` grants the talent at the start of a run (testing only; delete before sharing).

Play Beowulf, use ultimate 2 and throw the Fireball: it should be a much bigger
fireball and everything it hits should be staggered and stunned for a long time.
