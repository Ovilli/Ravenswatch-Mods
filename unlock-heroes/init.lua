local R = require "rsmm"

R.health.checkpoint("per_mod:unlock-heroes")

-- `R.hero.unlock_progression` hooks the progression, rank, story and challenge
-- unlock conditions and answers true for each. The ownership condition rides
-- the same vftable slot and is deliberately NOT reachable from here, so a hero
-- locked because it was never bought stays locked.
R.on("ready", function()
    local opened = R.hero.unlock_progression()
    if opened == 0 then
        R.log("[unlock-heroes] no gates opened — the unlock symbols are "
              .. "unresolved on this game build, so nothing was hooked")
    end
end)
