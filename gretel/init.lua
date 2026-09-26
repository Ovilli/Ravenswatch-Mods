-- Gretel — TESTING auto-grant. Remove this file and config_schema.toml before
-- publishing: from the store it is free XP and free talents.
--
-- Every run: 5000 XP (so her ultimates unlock at once) and her three reworked
-- talents, so each change can be seen in one launch. Gretel shares Beowulf's
-- controller names and events, so the loader cannot tell the two apart: this
-- also fires when you play Beowulf. Turn it off in the mod's config.

local R = require "rsmm"

local RARITY = { common = 0, rare = 1, epic = 2, legendary = 3 }
local enabled = R.config.get("auto_grant", true)
local tier = RARITY[R.config.get("rarity", "legendary")] or 3

-- Slam the Door, Hunter's Pursuit, Siblings' Oath (by controller name).
local TALENTS = { "Attack Flurry", "Dash Attack", "Trait Battlecry" }

R.xp.arm()

local talents_done, xp_done = false, false
R.on("run:start", function() talents_done, xp_done = false, false end)

-- Skill controllers register as they activate, which can trail the hero
-- capture, so poll until they are there and grant once per run.
R.schedule.every(3, function()
    if not enabled or not R.entity.ready() then return end
    if not xp_done then
        R.schedule.next_main(function()
            if xp_done then return end
            R.stat.enable_writes()
            xp_done = R.xp.grant(5000)
            R.log(("[gretel] R.xp.grant(5000): %s (level %s)"):format(
                xp_done and "OK" or "failed, retrying", tostring(R.xp.level())))
        end)
    end
    if not talents_done and #R.talent.controllers() > 0 then
        talents_done = true
        for _, name in ipairs(TALENTS) do
            R.talent.grant(name, tier)
        end
    end
end)
