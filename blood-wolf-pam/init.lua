local R = require "rsmm"
R.on("gameplay:COMBO_LINK", function(ev)
    R.log("[blood-wolf-diag] COMBO_LINK fired")
end)
R.on("gameplay:ABILITY_EXIT", function(ev)
    R.log("[blood-wolf-diag] ABILITY_EXIT fired")
end)

-- TESTING ONLY (local playtest, not Pam's): 5000 XP once per run on Blood
-- Wolf, so the ultimates unlock at once. Same pattern as mods/gretel. Remove
-- before sending the mod back: from a store it is free XP.
local XP, XP_TRIES = 20000, 5
R.xp.arm()                       -- capture the level component before the run builds it

local done, pending, tries, who, polls = false, false, 0, nil, 0
R.on("run:start", function() done, pending, tries, who, polls = false, false, 0, nil, 0 end)

local function is_blood_wolf()
    if who == nil and R.hero.entity then
        polls = polls + 1
        if R.hero.entity() then
            who = R.hero.entity_is("Hero_BloodWolf") and "yes" or "no"
            R.log("[blood-wolf-test] hero " .. tostring(R.hero.entity()) .. " -> " .. who)
        elseif polls >= 6 then
            who = "yes"          -- name unreadable: grant anyway, and say so
            R.log("[blood-wolf-test] hero name unreadable; granting XP anyway")
        end
    end
    return who == "yes"
end

R.schedule.every(5, function()
    if done or pending or tries >= XP_TRIES or not R.entity.ready() then return end
    if not is_blood_wolf() then return end
    if tries > 0 and not R.xp.level() then return end
    pending = true
    R.schedule.next_main(function()       -- engine-mutating: main thread only
        pending, tries = false, tries + 1
        R.stat.enable_writes()
        done = R.xp.grant(XP) and true or false
        R.log(("[blood-wolf-test] R.xp.grant(%d) try %d/%d: %s (level %s)"):format(
            XP, tries, XP_TRIES, done and "OK" or "failed", tostring(R.xp.level())))
    end)
end)
