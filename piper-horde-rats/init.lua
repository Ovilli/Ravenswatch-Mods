-- Piper: Horde of Rats — testing grant.
--
-- The rewire only does anything once Horde is owned, so hand it over at the
-- start of each run instead of waiting for a level-up card. Horde's controller
-- exists only on Piper, so on any other hero the lookup simply finds nothing.

local R = require "rsmm"

local RARITY = { common = 0, rare = 1, epic = 2, legendary = 3 }
local tier = RARITY[R.config.get("rarity", "common")] or 0
local QUERIES = { "Skill Controller Trait More Controllable Pets", "Trait More Controllable Pets" }

local done = false

local function try_grant()
    if done or not R.entity.ready() then return end
    if #R.talent.controllers() == 0 then return end
    done = true

    for _, q in ipairs(QUERIES) do
        if R.talent.find(q) then
            R.talent.grant(q, tier)
            R.log("[horde-rats] granting Horde (" .. q .. ")")
            return
        end
    end
    R.log("[horde-rats] Horde not found on this hero, nothing granted")
end

R.on("run:start", function() done = false end)
R.schedule.every(3, try_grant)
