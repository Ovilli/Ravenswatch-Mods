-- TEST: Shapeshifter keeps the instant bomb — TESTING auto-grant.
--
-- Hands Scarlet Shapeshifter (row "Trait Active") at the start of every run so
-- the included Short Wick bomb can be tried at once. Remove this file (and
-- config_schema.toml) before publishing: from the store it is a free talent.

local R = require "rsmm"

local RARITY = { common = 0, rare = 1, epic = 2, legendary = 3 }

local enabled = R.config.get("auto_grant", true)
local tier = RARITY[R.config.get("rarity", "legendary")] or 3

local granted = false

local function try_grant()
    if granted or not enabled or not R.entity.ready() then return end
    if #R.talent.controllers() == 0 then return end
    granted = true
    R.talent.grant("Trait Active", tier)
    R.log("red-shapeshifter-wick: granted Shapeshifter (Trait Active), tier " .. tier)
end

R.on("run:start", function() granted = false end)
R.schedule.every(3, try_grant)

-- Short Wick's other half comes along at its Common value: log SPECIAL's
-- cooldown reduction so the number can be checked, not guessed. Found by its
-- engine key ("CD reduce secondary"): the loader's hand-written per-slot
-- cooldown names are shifted by one against the engine catalog, so
-- "cooldown_reduction_secondary" reads "CD reduce basic".
local CD_SPECIAL = 0x15b45d86
local cd_name
for name, spec in pairs(R.stat.keys) do
    if spec.key == CD_SPECIAL then cd_name = name end
end
local last
R.schedule.every(0.5, function()
    if not granted or not cd_name then return end
    local v = R.stat.get(cd_name)
    if v ~= nil and v ~= last then
        R.log(string.format("red-shapeshifter-wick: SPECIAL cooldown reduction = %.3f", v))
        last = v
    end
end)
