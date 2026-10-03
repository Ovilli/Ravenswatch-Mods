-- TESTING ONLY. Levels Beowulf up and gives him the Fireball talent as soon as the
-- game lets him hold it, so the change can be seen at once. Delete this file
-- before you share or publish the mod: from the store it is free XP and talents.
--
-- Why not just grant at run start: the log of 2026-10-03 showed 24 controllers on
-- Beowulf and none of them the Fireball. An ultimate's upgrade controller does not
-- exist until the ultimate is unlocked, so this grants XP first and then waits for
-- the controller to appear.
local R = require "rsmm"

-- The Fireball is the controller "Ultimate 2 Upgrade 2" (its card key is
-- Skill_Ultimate_2_Upgrade_Fireball_Dash; the dump of 2026-10-03 listed it under that
-- row name, never as "fireball"). Matched against each controller's name, ignoring case.
local WANT = "ultimate 2 upgrade 2"
local RARITY = 0             -- 0 Common, 1 Rare, 2 Epic, 3 Legendary
local XP = 60000                  -- 5000 only reached level 4 (2026-10-03 log); the upgrades come at level 10
local XP_TRIES = 5
local TAG = "[beowulf-fireball-test] "

R.xp.arm()                   -- before the run builds the level component

local done, tries, seen = false, 0, -1
local xp_done, xp_tries, xp_pending = false, 0, false
R.on("run:start", function()
    done, tries, seen = false, 0, -1
    xp_done, xp_tries, xp_pending = false, 0, false
end)

-- XP once the hero exists; the level component is known after the first gain.
local function try_xp()
    if xp_done or xp_pending or xp_tries >= XP_TRIES then return end
    if xp_tries > 0 and not R.xp.level() then return end
    xp_pending = true
    R.schedule.next_main(function()
        xp_pending = false
        xp_tries = xp_tries + 1
        R.stat.enable_writes()
        xp_done = R.xp.grant(XP) and true or false
        R.log(TAG .. ("R.xp.grant(%d) try %d/%d: %s (level %s)"):format(
            XP, xp_tries, XP_TRIES, xp_done and "OK" or "failed", tostring(R.xp.level())))
    end)
end

R.schedule.every(3, function()
    if done or not R.entity.ready() then return end
    tries = tries + 1
    try_xp()
    local list = R.talent.controllers()
    if #list == 0 then
        if tries % 10 == 1 then R.log(TAG .. "waiting for the hero's skill controllers (try " .. tries .. ")") end
        return
    end
    -- Controllers register as they activate: list them again whenever the count moves.
    if #list ~= seen then
        seen = #list
        R.talent.dump()
    end
    for _, c in ipairs(list) do
        if c.name and c.name:lower():find(WANT, 1, true) then
            done = true
            R.log(TAG .. "granting " .. c.name .. " at tier " .. RARITY)
            R.talent.grant(c.name, RARITY)
            return
        end
    end
    if tries % 20 == 0 then
        R.log(TAG .. "still no controller with '" .. WANT .. "' in its name among " .. #list
            .. " (level " .. tostring(R.xp.level()) .. "); pick Ultimate 2 in game, or look at the dump")
    end
end)
