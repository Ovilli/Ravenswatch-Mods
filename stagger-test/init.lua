-- TESTING ONLY. Proves R.status.clear_stagger from the log: the SDK's read-only
-- hook logs the stagger value before and after each clear.
local R = require "rsmm"

local TAG = "[stagger-test] "
local primed, queued, last_clear, last_seen = false, false, -10, 0

local function clear(why)
    queued = true
    R.schedule.next_main(function()
        queued, last_clear = false, os.clock()
        R.log(TAG .. why .. ": clear_stagger() " .. tostring(R.status.clear_stagger())
            .. ", reset_stagger_resilience() " .. tostring(R.status.reset_stagger_resilience()))
    end)
end

R.log(TAG .. "loaded; watch_stagger: " .. tostring(R.status.watch_stagger()))

-- Step 1: the first clear is what captures the hero's controller.
R.on("gameplay:ABILITY_EXIT", function()
    if primed or queued then return end
    primed = true
    clear("priming (captures the controller)")
end)

-- Step 2: watch the value; clear it whenever it is up.
R.schedule.every(0.25, function()
    local g, res = R.status.stagger()
    if g == nil then return end
    if math.abs(g - last_seen) > 0.01 then
        R.log(TAG .. ("stagger %.2f -> %.2f (resilience %s)"):format(last_seen, g, tostring(res)))
        last_seen = g
    end
    if g > 0 and not queued and os.clock() - last_clear >= 2 then
        clear(("stagger is %.2f"):format(g))
    end
end)
