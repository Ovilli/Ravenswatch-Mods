-- TESTING ONLY. Steps through give / duplicate / remove / remove-all, one step
-- per ability use, so each change can be seen on the item bar.
local R = require "rsmm"

local TAG = "[items-test] "
local step, queued, last = 0, false, -10

R.on("run:start", function() step, last = 0, -10 end)

local STEPS = {
    function()
        local got = {}
        for i = 1, 3 do got[i] = tostring(R.give.random()) end
        return "gave 3 random items: " .. table.concat(got, ", ")
    end,
    function() return "duplicate_random(): " .. tostring(R.give.duplicate_random()) end,
    function() return "remove_random(): " .. tostring(R.give.remove_random()) end,
    function() return "remove_all(): " .. tostring(R.give.remove_all()) end,
}

-- ABILITY_EXIT fires from inside the engine's own dispatch; act on the next
-- main-thread tick instead.
R.on("gameplay:ABILITY_EXIT", function()
    if queued or step >= #STEPS or os.clock() - last < 5 then return end
    queued = true
    R.schedule.next_main(function()
        queued, last = false, os.clock()
        step = step + 1
        R.log(TAG .. "step " .. step .. "/" .. #STEPS .. ": " .. STEPS[step]())
    end)
end)

R.log(TAG .. "loaded; R.give.remove_random " .. (R.give.remove_random and "present" or "MISSING"))
