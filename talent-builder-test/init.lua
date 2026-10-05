-- TEST: Talent builder — TESTING auto-grant.
--
-- Hands Aladdin the rebuilt "Counter Dive" (row "Attack Dive") at the start of
-- every run, so it can be tried at once. Remove this file (and
-- config_schema.toml) before publishing: from the store it is a free talent.
--
-- Only Aladdin has a talent row named "Attack Dive" here, so on any other hero
-- the grant is refused and nothing happens.

local R = require "rsmm"

local RARITY = { common = 0, rare = 1, epic = 2, legendary = 3 }

local enabled = R.config.get("auto_grant", true)
local tier = RARITY[R.config.get("rarity", "legendary")] or 3

local granted = false

-- Skill controllers register as they activate, which can trail the hero
-- capture, so poll until they are there and grant once per run.
local function try_grant()
    if granted or not enabled or not R.entity.ready() then return end
    if #R.talent.controllers() == 0 then return end
    granted = true
    R.talent.grant("Attack Dive", tier)
    R.log("talent-builder-test: granted Counter Dive (Attack Dive), tier " .. tier)
end

R.on("run:start", function() granted = false end)
R.schedule.every(3, try_grant)

-- The test itself: Aladdin can't ATTACK during DEFENSE once the dive is gone,
-- so the "during" bonus is read off the stat instead of felt in a fight. Every
-- change of "Attack power basic" is logged; hold DEFENSE and it should rise by
-- the card's number, then fall back when DEFENSE ends.
--   rsmm log | grep talent-builder-test
local last
R.schedule.every(0.1, function()
    if not granted then return end
    local v = R.stat.get("attack_power_basic")
    if v ~= nil and v ~= last then
        R.log(string.format("talent-builder-test: Attack power basic = %.3f%s", v,
            last and string.format(" (was %.3f)", last) or ""))
        last = v
    end
end)
