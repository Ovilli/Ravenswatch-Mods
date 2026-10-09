-- TEST: Virtuoso borrows Focused Strikes. TESTING auto-grant.
--
-- Hands Piper "Virtuoso" (row "Attack Move Speed") at the start of every run,
-- so the borrowed bonus can be checked at once. Remove this file (and
-- config_schema.toml) before publishing: from the store it is a free talent.
--
-- Only Piper has a talent row named "Attack Move Speed" here, so on any other
-- hero the grant is refused and nothing happens.

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
    R.talent.grant("Attack Move Speed", tier)
    R.log("piper-borrow-test: granted Virtuoso (Attack Move Speed), tier " .. tier)
end

R.on("run:start", function() granted = false end)
R.schedule.every(3, try_grant)

-- The test itself: Focused Strikes is a POWER damage bonus, so log every change
-- of "Attack power primary". It should rise by the card's number (0.24 at
-- Legendary) shortly after the grant.
--   rsmm log | grep piper-borrow-test
local last = {}
local WATCH = { attack_power_primary = "Attack power primary", move_speed = "Move speed" }
R.schedule.every(0.1, function()
    if not granted then return end
    for key, label in pairs(WATCH) do
        local v = R.stat.get(key)
        if v ~= nil and v ~= last[key] then
            R.log(string.format("piper-borrow-test: %s = %.3f%s", label, v,
                last[key] and string.format(" (was %.3f)", last[key]) or ""))
            last[key] = v
        end
    end
end)
