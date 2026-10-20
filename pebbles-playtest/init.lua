-- TESTING ONLY. Gives you Little Thumb Pebbles at the start of every run and
-- logs crit chance once a second, so the 5-second window shows in the log.
-- Delete this file before you share or publish the mod.
--
-- What a pass looks like: crit stays flat until you take a hit, jumps by 0.30,
-- drops back about 5 s later, and the next hit after that raises it again.
-- A fail: it never drops (the timer does not end the hit state), or it climbs
-- with every hit (the modifier is still permanent).
local R = require "rsmm"

local ITEM = "Increase_Crit_M"

local given = false
local last
local function reset() given, last = false, nil end
for _, boundary in ipairs({ "run:start", "run:end", "menu:enter" }) do
    R.on(boundary, reset)
end

-- Grants build the item's entity, which is main-thread only.
R.schedule.every_main(1, function()
    if not given and R.give.ready() then
        given = R.give.by_name(ITEM)
        R.log(("[Pebbles] grant %s: %s"):format(ITEM, given and "ok" or "not loaded yet"))
    end
    if not given then return end
    local crit = R.stat.get("crit_chance")
    if crit and crit ~= last then
        R.log(("[Pebbles] crit_chance %.2f -> %.2f"):format(last or crit, crit))
        last = crit
    end
end)

R.damage.on(function(hit)
    if hit.kind == "taken" and hit.is_local and given then
        R.log(("[Pebbles] hit taken (%.0f); crit should rise now"):format(hit.amount or 0))
    end
end)
