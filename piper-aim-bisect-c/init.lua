-- Piper aim bisect — TESTING auto-grant of Horde.
--
-- Grants Horde (Trait More Controllable Pets) at run start on Piper.

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
    R.talent.grant("Trait More Controllable Pets", tier)
end

R.on("run:start", function() granted = false end)
R.schedule.every(3, try_grant)
