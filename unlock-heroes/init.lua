local R = require "rsmm"

R.health.checkpoint("per_mod:unlock-heroes")

-- `R.hero.unlock_progression` hooks the progression, rank, story, challenge AND
-- ownership (DLC) unlock conditions and answers true for each. A deliberate
-- choice: paid DLC heroes such as Merlin unlock for everyone running this mod.
R.on("ready", function()
    local opened = R.hero.unlock_progression()
    if opened == 0 then
        R.log("[unlock-heroes] no gates opened — the unlock symbols are "
              .. "unresolved on this game build, so nothing was hooked")
    end
end)
