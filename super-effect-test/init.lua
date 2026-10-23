-- TESTING ONLY. Grants Test_Super_Effect at run start, then 2 shipped Epic
-- items 10 s later so the Epic collection (3) completes, and logs every change
-- of Life on hit in units of 1/1024 (0 without the item, measured on
-- effect-triggers-test).
--
-- What a pass looks like:
--   "[Super] grant Test_Super_Effect: ok"          then "life_on_hit 0 -> 1"
--   "[Super] grant Reduce_Dash_CD / Reduce_Primary_CD: ok" then "1 -> 3"
--     (the super effect switched on; the card's super text should light up)
--   dash: "3 -> 7", and about 5 s later "7 -> 3"
-- A fail: stays at 1 after the fillers (super never switched on), or 7 never
-- drops (timer stuck), or a dash before the fillers already gives +4 (the
-- timed super ran outside the super state).
local R = require "rsmm"

local ITEM = "Test_Super_Effect"
local FILLERS = { "Reduce_Dash_CD", "Reduce_Primary_CD" }
local UNIT = 1 / 1024
local POLL = 0.25
local FILL_AFTER = 40          -- polls (10 s): see the 1-unit state first

local stage, polls, last = 0, 0, nil
local function reset() stage, polls, last = 0, 0, nil end
for _, b in ipairs({ "run:start", "run:end", "menu:enter" }) do R.on(b, reset) end

local function grant(id)
    local ok = R.give.by_name(id)
    R.log(("[Super] grant %s: %s"):format(id, ok and "ok" or "NOT LOADED"))
    return ok
end

-- Grants build entities: main thread only.
R.schedule.every_main(POLL, function()
    if not R.give.ready() then return end
    polls = polls + 1
    if stage == 0 then
        if grant(ITEM) then stage, polls = 1, 0 end
    elseif stage == 1 and polls >= FILL_AFTER then
        for _, id in ipairs(FILLERS) do grant(id) end
        stage = 2
    end
    if stage == 0 then return end
    local v = R.stat.get("life_on_hit")
    if not v then return end
    local units = math.floor(v / UNIT + 0.5)
    if units ~= last then
        R.log(("[Super] life_on_hit %s -> %d units (raw %.6f)"):format(tostring(last), units, v))
        last = units
    end
end)
