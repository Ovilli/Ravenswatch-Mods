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

-- Names come from R.interact.name (the entity's own template name, proven on
-- live entities); R.spawn.enemies' string-walk named nothing on this build.
local names = {}
local function scan()
    if not (R.spawn and R.spawn.entities and R.interact and R.interact.name) then return end
    local ok, rows = pcall(R.spawn.entities)
    if not ok or type(rows) ~= "table" then return end
    local counts = {}
    for _, row in ipairs(rows) do
        local n = names[row.template]
        if n == nil then
            n = R.interact.name(row.entity) or false
            names[row.template] = n
        end
        if n then counts[n] = (counts[n] or 0) + 1 end
    end
    -- The chapter, from names: the edit only matters in Dark Hills, where a
    -- Boss_Crab can only be the swapped ghoul den (the real crab lives on
    -- Storm Island). The den's boss is on this list from level start.
    local dh = false
    for n in pairs(counts) do
        if n:find("Dark_Hills", 1, true) then dh = true break end
    end
    for n, c in pairs(counts) do
        if n:find("Boss_", 1, true) and not seen[n] then
            seen[n] = true
            local v = ""
            if dh and n == "Boss_Crab" then
                v = " -> PASS: a crab boss in Dark Hills is the swapped ghoul den"
            elseif dh and (n == "Boss_Marsh_Ghoul" or n == "Boss_White_Lady") then
                v = " -> FAIL: the arena still spawned its own boss"
            end
            R.log(("%s %s boss in scene: %s (x%d)%s"):format(TAG,
                dh and "[Dark Hills]" or "[other chapter]", n, c, v))
        end
    end
end

-- Each chapter is a new scene; report its bosses afresh.
R.on("run:start", function() seen = {} end)

if not (R.spawn and R.spawn.entities and R.interact and R.interact.name) then
    R.log(TAG .. " R.spawn missing on this SDK — watch the den by eye")
else
    R.schedule.every(5, scan)
    R.log(TAG .. " armed — enter the Dark Hills ghoul den, then: rsmm log --grep boss-proof")
end
