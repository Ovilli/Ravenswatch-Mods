-- Gretel — TESTING auto-grant. Remove this file and config_schema.toml before
-- publishing: from the store it is free XP and free talents.
--
-- Every run: 5000 XP (so her ultimates unlock at once) and her three reworked
-- talents, so each change can be seen in one launch. Gretel shares Beowulf's
-- controller names and events; R.hero.entity() reads the live hero's entity
-- name (Hero_Gretel_*), so on Beowulf nothing is granted. If that name cannot
-- be read, it grants anyway and says so in the log.

local R = require "rsmm"

local RARITY = { common = 0, rare = 1, epic = 2, legendary = 3 }
local enabled = R.config.get("auto_grant", true)
local tier = RARITY[R.config.get("rarity", "legendary")] or 3

-- Slam the Door, Hunter's Pursuit, Siblings' Oath (by controller name).
local TALENTS = { "Attack Flurry", "Dash Attack", "Trait Battlecry" }
local XP_TRIES = 5

-- Arm the level capture now, before any run builds the level component.
R.xp.arm()

local talents_done, xp_done, xp_tries = false, false, 0
R.on("run:start", function() talents_done, xp_done, xp_tries = false, false, 0 end)

-- XP: once at run start, then only once the level component is known (the
-- game's first XP gain captures it), at most XP_TRIES times, one at a time.
local xp_pending = false
local function try_xp()
    if xp_done or xp_pending or xp_tries >= XP_TRIES then return end
    if xp_tries > 0 and not R.xp.level() then return end
    xp_pending = true
    R.schedule.next_main(function()
        xp_pending = false
        xp_tries = xp_tries + 1
        R.stat.enable_writes()
        xp_done = R.xp.grant(5000) and true or false
        R.log(("[gretel] R.xp.grant(5000) try %d/%d: %s (level %s)"):format(
            xp_tries, XP_TRIES, xp_done and "OK" or "failed", tostring(R.xp.level())))
    end)
end

-- Skill controllers register as they activate, which can trail the hero
-- capture, so poll until they are there and grant once per run.
-- Gretel, Beowulf, or unknown (nil): the name is read once per run.
local who, polls = nil, 0
R.on("run:start", function() who, polls = nil, 0 end)
local function is_gretel()
    if who == nil and R.hero.entity then
        local n = R.hero.entity()
        polls = polls + 1
        if n then
            who = R.hero.entity_is("Hero_Gretel") and "gretel" or "other"
            R.log(("[gretel] hero entity %s -> %s"):format(n, who))
        elseif polls >= 6 then
            who = "unknown"
            R.log("[gretel] hero entity name unreadable; granting as before")
        end
    end
    return who == "gretel" or who == "unknown"
end

R.schedule.every(5, function()
    if not enabled or not R.entity.ready() then return end
    if not is_gretel() then return end
    try_xp()
    if not talents_done and #R.talent.controllers() > 0 then
        talents_done = true
        for _, name in ipairs(TALENTS) do
            R.talent.grant(name, tier)
        end
    end
end)
