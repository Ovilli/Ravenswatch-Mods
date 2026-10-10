-- TESTING ONLY. Proves R.status.clear_stagger / reset_stagger_resilience from
-- the log: the SDK's read-only hook logs the stagger values around each clear.
--
-- Two values on the hero: the stagger BAR (fills on staggering hits, decays
-- over time, drops to 0 the moment you are staggered) and RESILIENCE (grows by
-- a step every time you are actually staggered). A rising resilience is the
-- proof a stagger happened; the bar can fill and empty between two polls.
local R = require "rsmm"

local TAG = "[stagger-test] "
local primed, queued, last_clear = false, false, -10
local seen_g, seen_r, peak_g, staggers = 0, 0, 0, 0

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

-- Step 2: watch both values every 0.1 s; clear whenever either is up.
R.schedule.every(0.1, function()
    local g, res = R.status.stagger()
    if g == nil then return end
    if g > peak_g then peak_g = g end
    if math.abs(g - seen_g) > 0.01 then
        R.log(TAG .. ("bar %.2f -> %.2f"):format(seen_g, g))
        seen_g = g
    end
    if math.abs(res - seen_r) > 0.001 then
        if res > seen_r then staggers = staggers + 1 end
        R.log(TAG .. ("resilience %.3f -> %.3f%s"):format(seen_r, res,
            res > seen_r and "  <- you were STAGGERED" or ""))
        seen_r = res
    end
    if (g > 0 or res > 0) and not queued and os.clock() - last_clear >= 2 then
        clear(("bar %.2f, resilience %.3f"):format(g, res))
    end
end)

-- Heartbeat: proves the poll is alive even when nothing changes.
R.schedule.every(30, function()
    local g, res = R.status.stagger()
    R.log(TAG .. ("heartbeat: bar %s, resilience %s, peak bar %.2f, staggers seen %d"):format(
        tostring(g), tostring(res), peak_g, staggers))
end)
