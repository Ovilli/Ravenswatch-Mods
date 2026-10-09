-- TEST: talent charges, Strength, Regeneration. TESTING auto-grant.
--
-- Hands Melusine "Wisp Surge" (row "Attack Speed") at the start of every run.
-- Remove this file (and config_schema.toml) before publishing: from the store
-- it is a free talent. On any other hero the talent is never found, so nothing
-- happens.

local R = require "rsmm"

local RARITY = { common = 0, rare = 1, epic = 2, legendary = 3 }

local enabled = R.config.get("auto_grant", true)
local tier = RARITY[R.config.get("rarity", "legendary")] or 3

local granted = false

-- Wait for THIS talent's controller, not just any: a grant tried before it
-- registers is refused and never retried.
local function try_grant()
    if granted or not enabled or not R.entity.ready() then return end
    if #R.talent.controllers() == 0 or not R.talent.find("Attack Speed") then return end
    granted = true
    R.talent.grant("Attack Speed", tier)
    R.log("melusine-talent-stats-test: granted Wisp Surge (Attack Speed), tier " .. tier)
end

R.on("run:start", function() granted = false end)
R.schedule.every(3, try_grant)

-- Strength and Regeneration are status stacks: log every change.
local last = {}
local WATCH = { status_strength = "Strength", status_regen = "Regeneration" }
R.schedule.every(0.5, function()
    if not granted then return end
    for key, label in pairs(WATCH) do
        local v = R.stat.get(key)
        if v ~= nil and v ~= last[key] then
            R.log(string.format("melusine-talent-stats-test: %s = %s%s", label, tostring(v),
                last[key] and (" (was " .. tostring(last[key]) .. ")") or ""))
            last[key] = v
        end
    end
end)
