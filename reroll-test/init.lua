-- TESTING ONLY. Grants 3 offer rerolls once per run so R.reroll.add can be
-- checked in game. Delete before sharing: from the store it is free rerolls.
local R = require "rsmm"

local GRANT = 3
local TAG = "[reroll-test] "

local granted, pending, waited = false, false, 0

local function game_count()
    return R.game and R.game.ready and R.game.ready() and R.game.get("reroll_count") or nil
end

-- Every GAIN_REROLL that goes through the bus, ours and the game's own: shows
-- whether our event reached dispatch and what a genuine one looks like.
R.on("gameplay:GAIN_REROLL", function(ev)
    local parts = {}
    for k, v in pairs(ev) do parts[#parts + 1] = k .. "=" .. tostring(v) end
    table.sort(parts)
    R.log(TAG .. "bus GAIN_REROLL " .. table.concat(parts, " ") .. " game reroll_count=" .. tostring(game_count()))
end)
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
        local before, gbefore = R.reroll.get(), game_count()
        local ok = R.reroll.add(GRANT)
        granted = ok and true or false
        R.log(TAG .. ("R.reroll.add(%d): %s; rerolls %s -> %s; game reroll_count %s -> %s"):format(
            GRANT, ok and "dispatched" or "refused", tostring(before), tostring(R.reroll.get()),
            tostring(gbefore), tostring(game_count())))
    end)
end)
