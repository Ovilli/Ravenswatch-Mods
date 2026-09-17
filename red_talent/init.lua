-- TESTING ONLY. Gives you the talent at the start of every run.
-- Delete this file before you share or publish the mod.
local R = require "rsmm"

local TALENT = "Trait Active"   -- the "Search word" from the lookup page
local RARITY = 0                  -- 0 Common, 1 Rare, 2 Epic, 3 Legendary

local done = false
R.on("run:start", function() done = false end)
R.schedule.every(3, function()
    if done or not R.entity.ready() then return end
    if #R.talent.controllers() == 0 then return end
    done = true
    R.talent.dump()
    R.talent.grant(TALENT, RARITY)
end)