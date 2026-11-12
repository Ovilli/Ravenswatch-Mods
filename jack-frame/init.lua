-- Jack (from scratch): button freeze bisection, TEMPORARY (v0.5.1).
--
-- His ability states switch off in the frame they start (2026-11-08 probe),
-- so his clips never play and his timers stall. Each button is built a
-- different way this time (manifest `variant`):
--   ATTACK   (left click)  as before -- the control
--   POWER                  Geppetto's shape: released flag, aim on entry, no end-timer switch
--   SPECIAL                + the input-released flag and tester
--   DEFENSE                aim on entry only
--   TRAIT                  the end timer does not switch the state off
--   ULTIMATE 1             no move-inertia hand-over
--   ULTIMATE 2             Hero_Common's own dash state (button-side check)
--
-- Once his hero is live this logs, for three minutes, every on/off of each
-- ability state (byte +0x64, bit 0x08 = on), sampled every frame. Press each
-- button once, a few seconds apart, then quit and send the log. Remove this
-- file once the buttons work.

local R = require "rsmm"

local TAG = "[jack-probe]"
local started = false

R.on_match("^gameplay:", function(_, name)
    if not started then return end
    local ev = name:sub(10)
    if ev:find("ABILIT") or ev:find("ATTACK") or ev:find("EXIT") then
        R.log(TAG, "event " .. ev)
    end
end)

R.schedule.every(1.0, function()
    if started or not (R.entity and R.entity.ready and R.entity.ready()) then return end
    started = true
    if not (R.debug and R.debug.watch_components) then
        R.log(TAG, "this loader has no R.debug.watch_components -- run `rsmm install-loader`")
        return
    end
    R.log(TAG, "hero live: press DASH, ATTACK, POWER, SPECIAL, DEFENSE, TRAIT, a few s apart")
    R.debug.watch_components("^State %a+%d? Ability$",
        { label = "states", seconds = 180, from = 0x64, len = 1, every = 0.001, baseline = 1 })
end)
