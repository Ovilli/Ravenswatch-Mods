-- TEST: Rising Tide (bigger POWER). TESTING auto-grant.
--
-- Hands Melusine "Rising Tide" (row "Trait Armor") at the start of every run, so
-- POWER's bigger area can be seen at once. Remove this file (and
-- config_schema.toml) before publishing: from the store it is a free talent.
--
-- Only Melusine has a talent row named "Trait Armor" here, so on any other hero
-- the grant is refused and nothing happens.

local R = require "rsmm"

local RARITY = { common = 0, rare = 1, epic = 2, legendary = 3 }

local enabled = R.config.get("auto_grant", true)
local tier = RARITY[R.config.get("rarity", "legendary")] or 3

local granted = false

-- Skill controllers register as they activate, which can trail the hero
-- capture, so poll until they are there and grant once per run.
-- Wait for THIS talent's controller, not just any: the first controllers to
-- register can be shared ones, and a grant tried before Melusine's own are up is
-- refused and never retried (run of 2026-10-09 14:55).
local tries = 0
local function try_grant()
    if granted or not enabled or not R.entity.ready() then return end
    if #R.talent.controllers() == 0 then return end
    local found, why = R.talent.find("Trait Armor")
    if not found then
        tries = tries + 1
        if tries == 10 then
            local names = {}
            for _, e in ipairs(R.talent.controllers()) do names[#names + 1] = tostring(e.name) end
            R.log("melusine-bigger-power-test: still no Trait Armor after 30 s (" .. tostring(why)
                .. "); controllers: " .. table.concat(names, ", "))
        end
        return
    end
    granted = true
    -- Which talents this run registered: 7 of Melusine's 31 were missing on
    -- 2026-10-09 15:03 with all of them unlocked. Same list every run, or not?
    local names = {}
    for _, e in ipairs(R.talent.controllers()) do
        names[#names + 1] = tostring(e.name):gsub("^Skill Controller ", "")
    end
    table.sort(names)
    R.log("melusine-bigger-power-test: " .. #names .. " talents registered: "
        .. table.concat(names, ", "))
    R.talent.grant("Trait Armor", tier)
    R.log("melusine-bigger-power-test: granted Rising Tide (Trait Armor), tier " .. tier)
end

R.on("run:start", function() granted = false; tries = 0 end)
R.schedule.every(3, try_grant)
