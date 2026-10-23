-- TESTING ONLY. Grants Test_Super_Effect 3 times, one per tick: an Epic
-- item's super effect switches on at 3 COPIES of that item (the model compares
-- the item's own amount with its rarity's target: Common 5, Rare 4, Epic 3).
-- Different Epic items do not count (2026-10-24: the item + Raven Wing + Raven
-- Claw left it off). Logs every change of Life on hit in units of 1/1024
-- (0 without the item).
--
-- What a pass looks like:
--   "[Super] grant 1/3 ... 3/3: ok", life_on_hit "nil -> 1", then "-> 3"
--     once the third copy lands (the super effect switched on; the card's
--     super text should replace "???")
--   dash: "3 -> 7", and about 5 s later "7 -> 3"
-- A fail: stays at 1 after 3/3 (a repeat grant does not stack copies, or the
-- super never switches on), or 7 never drops (timer stuck).
local R = require "rsmm"

local ITEM = "Test_Super_Effect"
local COPIES = 3
-- No poll counting for timing: every_main ticks slower than asked.
local POLL = 0.25

local granted, last = 0, nil
local function reset() granted, last = 0, nil end
for _, b in ipairs({ "run:start", "run:end", "menu:enter" }) do R.on(b, reset) end

-- Grants build entities: main thread only.
R.schedule.every_main(POLL, function()
    if not R.give.ready() then return end
    if granted < COPIES then
        local ok = R.give.by_name(ITEM)
        R.log(("[Super] grant %d/%d %s: %s"):format(granted + 1, COPIES, ITEM,
            ok and "ok" or "NOT LOADED"))
        if not ok then return end
        granted = granted + 1
    end
    local v = R.stat.get("life_on_hit")
    if not v then return end
    local units = math.floor(v * 1024 + 0.5)
    if units ~= last then
        R.log(("[Super] life_on_hit %s -> %d units (raw %.6f)"):format(tostring(last), units, v))
        last = units
    end
end)
