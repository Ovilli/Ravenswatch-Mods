-- Written Talent Test — TESTING auto-grant.
--
-- Hands Sun Wukong the five rebuilt talents at the start of every run:
-- Fiery Dragon (Trait Fire), Frost Tiger (Trait Frost), the beads card
-- (Special Beads Increase), Trait Longer Effects (game-event triggers) and
-- Trait Switch Timing (invulnerable for a moment).
-- On any other hero the grants are refused and nothing happens. Strip this
-- file before publishing.

local R = require "rsmm"

local RARITY = { common = 0, rare = 1, epic = 2, legendary = 3 }

local enabled = R.config.get("auto_grant", true)
local tier = RARITY[R.config.get("rarity", "legendary")] or 3

local TALENTS = { "Trait Fire", "Trait Frost", "Special Beads Increase", "Trait Longer Effects",
                  "Trait Switch Timing" }

local granted = false

-- Skill controllers register as they activate, which can trail the hero
-- capture, so poll until they are there and grant once per run.
local function try_grant()
    if granted or not enabled or not R.entity.ready() then return end
    if #R.talent.controllers() == 0 then return end
    granted = true
    for _, t in ipairs(TALENTS) do R.talent.grant(t, tier) end
end

R.on("run:start", function() granted = false end)
R.schedule.every(3, try_grant)
