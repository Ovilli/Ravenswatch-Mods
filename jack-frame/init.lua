-- Jack (from scratch): button probe, TEMPORARY.
--
-- His buttons froze in one pose in the 2026-11-08 playtest. Once his hero is
-- live this logs which of his ability parts the game instantiated and, for
-- three minutes, every one whose state flips while you press buttons
-- (R.debug.watch_components). Press each button once, a second apart, then
-- send the loader log. Remove this file once the buttons work.

local R = require "rsmm"

local TAG = "[jack-probe]"
local started = false

R.schedule.every(1.0, function()
    if started or not (R.entity and R.entity.ready and R.entity.ready()) then return end
    if not (R.debug and R.debug.watch_components) then
        R.log(TAG, "this loader has no R.debug.watch_components -- run `rsmm install-loader`")
        started = true
        return
    end
    started = true
    R.log(TAG, "hero live: watching his ability parts for 180 s -- press each button once")
    R.debug.watch_components("Ability", { label = "jack", seconds = 180, len = 0x60 })
    R.debug.watch_components("Inertia", { label = "jack-move", seconds = 180, len = 0x60 })
end)
