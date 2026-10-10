-- TESTING ONLY. Steps through R.melody.remove in both states its handler
-- (0x140399150) treats differently, then the two stagger senders — one step
-- per ability use. R.revive.add_token is proven (2026-10-10) and no longer here.
--
-- REMOVE_MELODY finds the hero's instance of the melody: if it is still
-- COLLECTING (state 1) it resets the hero's note counters, then sets state 3;
-- if the melody is active it also fires the melody's trigger.
local R = require "rsmm"

local TAG = "[revive-melody-stagger-test] "
local MELODY = "Reveal_Map"
local step, queued, last = 0, false, -10

R.on("run:start", function() step, last = 0, -10 end)

local function notes(n)
    local got = 0
    for _ = 1, n do if R.ingredient.add("Note", 1) then got = got + 1 end end
    return got
end

local STEPS = {
    -- collecting path: a part-filled counter that remove() should empty
    function()
        return "choose(" .. MELODY .. "): " .. tostring(R.melody.choose(MELODY))
            .. ", Note x3: " .. notes(3) .. " sent — the note counter should show 3"
    end,
    function()
        return "remove(" .. MELODY .. ") while collecting: " .. tostring(R.melody.remove(MELODY))
            .. " — the counter should drop back to 0"
    end,
    -- completed path: the proven choose + notes, then remove the active melody
    function()
        return "choose(" .. MELODY .. "): " .. tostring(R.melody.choose(MELODY))
            .. ", Note x10: " .. notes(10) .. " sent — the map reveals only if choose() forced Reveal_Map; a different melody = the game's random pick won"
    end,
    function()
        return "remove(" .. MELODY .. ") once active: " .. tostring(R.melody.remove(MELODY))
            .. " — the melody should leave your melody list"
    end,
    function()
        return "status.clear_stagger(): " .. tostring(R.status.clear_stagger())
            .. ", reset_stagger_resilience(): " .. tostring(R.status.reset_stagger_resilience())
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

R.log(TAG .. "loaded; R.melody.remove " .. (R.melody and R.melody.remove and "present" or "MISSING")
    .. ", R.status " .. (R.status and "present" or "MISSING"))
