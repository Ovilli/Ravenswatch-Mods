-- TESTING ONLY. Steps through the talent event senders, one step per ability
-- use, so each change can be seen on the talent list.
local R = require "rsmm"

local TAG = "[talents-test] "
local step, queued, last = 0, false, -10

R.xp.arm()
R.on("run:start", function() step, last = 0, -10 end)

local STEPS = {
    function()
        R.stat.enable_writes()
        return "xp.set_level(8): " .. tostring(R.xp.set_level(8)) .. " — pick your talents now"
    end,
    function() return "upgrade(1): " .. tostring(R.talent.upgrade(1)) end,
    function() return "upgrade_random(2): " .. tostring(R.talent.upgrade_random(2)) end,
    function() return "upgrade_lowest(to legendary): " .. tostring(R.talent.upgrade_lowest(true)) end,
    function() return "add_random_ultimate(): " .. tostring(R.talent.add_random_ultimate()) end,
    function()
        return "status.clear(): " .. tostring(R.status.clear())
            .. ", clear_stagger(): " .. tostring(R.status.clear_stagger())
    end,
    function() return "reset(): " .. tostring(R.talent.reset()) end,
}

-- ABILITY_EXIT fires from inside the engine's own dispatch; act on the next
-- main-thread tick instead.
R.on("gameplay:ABILITY_EXIT", function()
    if queued or step >= #STEPS or os.clock() - last < 5 then return end
    queued = true
    R.schedule.next_main(function()
        queued, last = false, os.clock()
        step = step + 1
        local before = R.talent.owned()
        local what = STEPS[step]()
        R.log(TAG .. ("step %d/%d: %s (talents owned %s -> %s)"):format(
            step, #STEPS, what, tostring(before), tostring(R.talent.owned())))
    end)
end)

R.log(TAG .. "loaded; R.talent.upgrade " .. (R.talent.upgrade and "present" or "MISSING")
    .. ", R.status " .. (R.status and "present" or "MISSING"))
