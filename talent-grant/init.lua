-- Talent Grant — a testing tool.
--
-- A modded talent can only be checked by playing until the game happens to
-- offer it. This hands it over at the start of every run instead, through the
-- engine's own tier setter (R.talent.grant), so each test is one launch.
--
-- The log lists every talent the hero has with the name it resolved, before
-- granting. If a grant is refused, that list is what to read: it shows the
-- names the match was tried against.

local R = require "rsmm"

local RARITY = { common = 0, rare = 1, epic = 2, legendary = 3 }

local cfg = {
    talent    = R.config.get("talent", "Quick Bombs"),
    tier      = RARITY[R.config.get("rarity", "common")] or 0,
    grant_all = R.config.get("grant_all", false),
}

local granted = false

-- Skill controllers register as they activate, which can trail the hero
-- capture, so poll until they are there and grant exactly once per run.
local function try_grant()
    if granted or not R.entity.ready() then return end
    if #R.talent.controllers() == 0 then return end
    granted = true
    R.talent.dump()
    if cfg.grant_all then
        R.talent.grant_all()
    else
        R.talent.grant(cfg.talent, cfg.tier)
    end
end

R.on("run:start", function() granted = false end)
R.schedule.every(3, try_grant)
