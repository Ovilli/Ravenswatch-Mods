-- Aladdin: Jinn Charge — TESTING auto-grant.
--
-- Hands Aladdin the talent at the start of every run so it can be tried at
-- once instead of waiting for a level-up card. Remove this file (and
-- config_schema.toml) before publishing: from the store it is a free talent.
--
-- The controller keeps Cyclonic Appearance's name, and only Aladdin has one
-- called that, so on any other hero the grant is refused and nothing happens.

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
    R.talent.grant("Power Start AOE", tier)
end

R.on("run:start", function() granted = false end)
R.schedule.every(3, try_grant)
