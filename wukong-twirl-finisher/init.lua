-- Wukong: Talent Tweaks — testing grant.
--
-- Every change in this mod only shows once its talent is owned, and waiting for
-- the game to offer it turns every test into a lottery. This hands the talents
-- over at the start of each run: Stick Twirl, Celestial Pillar (how the two
-- interact is half the Twirl test), and Fiery Dragon / Frost Tiger for the TRAIT
-- cooldown reduction. Each optional one has a config toggle.
--
-- A controller's name resolves either as "Skill Controller Dash Attack" or as
-- its text key "Skill_Attack_After_Dash", so each talent is tried under both.
-- Nothing is granted unless the hero is Wukong: `Special Beads Increase` is a
-- Wukong-only controller, and other heroes may carry a "Dash Attack" of their own.

local R = require "rsmm"

local RARITY = { common = 0, rare = 1, epic = 2, legendary = 3 }

local cfg = {
    tier         = RARITY[R.config.get("rarity", "common")] or 0,
    grant_pillar = R.config.get("grant_pillar", true),
    grant_fire   = R.config.get("grant_fire", true),
    grant_frost  = R.config.get("grant_frost", true),
}

local TALENTS = {
    { label = "Stick Twirl",      queries = { "Skill Controller Dash Attack", "Attack After Dash" } },
    { label = "Celestial Pillar", queries = { "Skill Controller Attack Finisher", "Attack Finisher" },
      optional = "grant_pillar" },
    { label = "Fiery Dragon",     queries = { "Skill Controller Trait Fire", "Skill_Trait_Fire" },
      optional = "grant_fire" },
    { label = "Frost Tiger",      queries = { "Skill Controller Trait Frost", "Skill_Trait_Frost" },
      optional = "grant_frost" },
}

local done = false

local function resolve(queries)
    local why
    for _, q in ipairs(queries) do
        local e, reason = R.talent.find(q)
        if e then return q end
        why = reason
    end
    return nil, why
end

local function try_grant()
    if done or not R.entity.ready() then return end
    if #R.talent.controllers() == 0 then return end
    done = true

    if not (R.talent.find("Special Beads Increase") or R.talent.find("Special_Beads_Increase")) then
        R.log("[twirl-finisher] not Wukong, nothing granted")
        return
    end

    for _, t in ipairs(TALENTS) do
        if not t.optional or cfg[t.optional] then
            local q, why = resolve(t.queries)
            if q then
                R.talent.grant(q, cfg.tier)
                R.log("[twirl-finisher] granting " .. t.label .. " (" .. q .. ")")
            else
                R.talent.dump()
                R.log("[twirl-finisher] could not find " .. t.label .. ": " .. tostring(why))
            end
        end
    end
end

R.on("run:start", function() done = false end)
R.schedule.every(3, try_grant)
