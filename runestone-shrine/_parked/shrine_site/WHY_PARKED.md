Parked 2026-09-06 — this is where the 13 icons came from.

It edited the SHIPPED `6x6_Blocker_02` level in place, so the shrine appeared
in every placement of that tiledef, not just ours: the vanilla blocker tile
carries it too, and so does every clone pointing at that level. The probe
reported `1 of 141 placed tiles are ours` and was right — it matches tiles by
OUR names, and the vanilla blocker is not one of them, so the extra shrines
were invisible to the only counter we had.

`shrine_pool` now owns its level (`own_level = true`) and carries the swap
itself, so a shrine appears only in a tile this mod placed.
