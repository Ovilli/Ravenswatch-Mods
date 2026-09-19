-- BOSS PROOF — does the ghoul den spawn the crab?
--
-- The manifest repoints Boss_Marsh_Ghoul's entity_ref at the Storm Island
-- giant crab. The den selects its boss by the Boss_Marsh_Ghoul FLAG, so if the
-- swap holds, the thing standing in the den is a Boss_Crab entity.
--
-- Every 5 s this lists the enemies the scene spawner holds (R.spawn.enemies,
-- one row per template, named by resource path) and logs any boss template
-- the first time it appears — so the answer is in the log whether or not
-- anyone was looking at the screen.
--
--   "Boss_Crab"        seen -> PASS (the den fought the crab)
--   "Boss_Marsh_Ghoul" seen -> FAIL (the den still spawned the ghoul)
local R = require "rsmm"

local TAG = "[boss-proof]"
local seen = {}

local function scan()
    if not (R.spawn and R.spawn.enemies) then return end
    local ok, rows = pcall(R.spawn.enemies)
    if not ok or type(rows) ~= "table" then return end
    for _, r in ipairs(rows) do
        local n = r.name or ""
        if n:find("Boss_", 1, true) and not seen[n] then
            seen[n] = true
            local v = ""
            if n:find("Boss_Crab", 1, true) then
                v = " -> PASS if this is the Dark Hills ghoul den"
            elseif n:find("Boss_Marsh_Ghoul", 1, true) then
                v = " -> FAIL: the den still spawned the ghoul"
            end
            R.log(("%s boss in scene: %s (x%d)%s"):format(TAG, n, r.count or 1, v))
        end
    end
end

if not (R.spawn and R.spawn.enemies) then
    R.log(TAG .. " R.spawn missing on this SDK — watch the den by eye")
else
    R.schedule.every(5, scan)
    R.log(TAG .. " armed — enter the Dark Hills ghoul den, then: rsmm log --grep boss-proof")
end
