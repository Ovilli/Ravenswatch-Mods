-- TESTING ONLY. Steps through R.melody, R.control and R.run, one step per
-- ability use. Step 5 ends the run.
local R = require "rsmm"

local TAG = "[flow-test] "
local MELODY = "Reveal_Map"
local step, queued, last = 0, false, -10

local STEPS = {
    function()
        return "melodies loaded: " .. table.concat(R.melody.names(), ", ")
            .. "; choose(" .. MELODY .. "): " .. tostring(R.melody.choose(MELODY))
    end,
    function() return "remove(" .. MELODY .. "): " .. tostring(R.melody.remove(MELODY)) end,
    function()
        local ok = R.control.lock()
        R.schedule.after_main(3, function()
            R.log(TAG .. "release after 3 s: " .. tostring(R.control.release()) .. " unlock(s)")
        end)
        return "control.lock(): " .. tostring(ok) .. " (held " .. R.control.held() .. ")"
    end,
    function()
        return "world ready: " .. tostring(R.run.world_ready())
            .. "; next_chapter(): " .. tostring(R.run.next_chapter())
    end,
    function()
        return "world ready: " .. tostring(R.run.world_ready()) .. "; win(): " .. tostring(R.run.win())
    end,
}

-- ABILITY_EXIT fires from inside the engine's own dispatch; act on the next
-- main-thread tick instead.
R.on("gameplay:ABILITY_EXIT", function()
    if queued or step >= #STEPS or os.clock() - last < 5 then return end
    queued = true
    R.schedule.next_main(function()
        queued, last = false, os.clock()
        step = step + 1
        R.log(TAG .. ("step %d/%d: %s"):format(step, #STEPS, STEPS[step]()))
    end)
end)

R.log(TAG .. "loaded; R.melody.choose " .. (R.melody.choose and "present" or "MISSING")
    .. ", R.control " .. (R.control and "present" or "MISSING")
    .. ", R.run.next_chapter " .. (R.run.next_chapter and "present" or "MISSING"))
