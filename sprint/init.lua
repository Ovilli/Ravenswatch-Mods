-- Multiply hero move speed, for crossing a generated map quickly while testing.
--
-- Uses R.stat.modify, not R.stat.set: set() pokes the cached value and the
-- engine's next recompute (item pickup, level up, new chapter) wipes it, so it
-- works until your first pickup and then quietly stops. modify() inserts a
-- real engine modifier that composes with the game's own and, with no
-- duration, is permanent -- so this applies once per hero instead of fighting
-- the recompute on a timer.
--
-- Move speed is a RATIO (vanilla 1.0), so the modifier is multiplier - 1.

local R = require "rsmm"

local BONUS = (R.config.get("multiplier") or 3.0) - 1.0
local _armed_for = nil          -- hero pointer the modifier is applied to

-- Waiting on the hero is normal for the first seconds of a run, but waiting
-- FOREVER is a bug in hero capture, not in this mod -- and it used to look
-- identical from the log (init OK, then silence). Say so once, late enough
-- that a normal load doesn't trip it.
local _waits = 0

local function arm()
    local hero = R.entity and R.entity.hero and R.entity.hero()
    if not hero then
        _waits = _waits + 1
        if _waits == 15 then       -- ~30s of main-thread ticks
            R.log("[sprint] still no hero after ~30s — hero capture is not "
                .. "producing a hero, so move speed cannot be applied "
                .. "(check the [rsmm.entity] REJECTED lines above)")
        end
        return
    end
    if hero == _armed_for then return end       -- already done for this hero
    if R.stat.modify("move_speed", BONUS, nil) then
        _armed_for = hero
        R.log(("[sprint] move speed x%.2f applied"):format(BONUS + 1.0))
    end
end

R.on("ready", function()
    if BONUS <= 0 then
        R.log("[sprint] multiplier <= 1.0 = disabled")
        return
    end
    R.stat.enable_writes()
    -- Poll rather than fire once: the hero is captured only after it acts, and
    -- a new run means a new hero entity that needs the modifier again.
    R.schedule.every_main(2.0, arm)
    R.log(("[sprint] waiting for a hero to apply x%.2f move speed"):format(BONUS + 1.0))
end)
