-- Jack (from scratch): button probe, TEMPORARY (v0.6.0).
--
-- v0.5.1 showed every one of his ability states switching off within a frame
-- whatever its shape, while the dash's lived. v0.6.0 writes his files with one
-- run per component class (as every shipped entity) and his fans through a
-- yaw value. This logs, for three minutes, every on/off of each ability state
-- (byte +0x64, bit 0x08 = on). Press DASH, ATTACK, POWER, SPECIAL, DEFENSE and
-- TRAIT a few seconds apart, then quit. Remove once the buttons work.

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
