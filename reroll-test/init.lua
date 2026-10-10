-- TESTING ONLY. Grants 3 offer rerolls once per run so R.reroll.add can be
-- checked in game. Delete before sharing: from the store it is free rerolls.
local R = require "rsmm"

local GRANT = 3
local TAG = "[reroll-test] "

local granted, pending, waited = false, false, 0
R.on("run:start", function() granted, pending, waited = false, false, 0 end)

-- The grant needs the hero's event dispatcher, which the SDK captures from the
-- hero's own gameplay events (an attack or ability), so poll until it is ready.
R.schedule.every(2, function()
    if granted or pending then return end
    if not R.give.ready() then
        waited = waited + 1
        if waited % 15 == 1 then R.log(TAG .. "waiting for the hero to act once (attack or use an ability)") end
        return
    end
    pending = true
    R.schedule.next_main(function()
        pending = false
        local before = R.reroll.get()
        local ok = R.reroll.add(GRANT)
        granted = ok and true or false
        R.log(TAG .. ("R.reroll.add(%d): %s; rerolls %s -> %s"):format(
            GRANT, ok and "dispatched" or "refused", tostring(before), tostring(R.reroll.get())))
    end)
end)
