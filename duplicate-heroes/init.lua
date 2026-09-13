local R = require "rsmm"

R.health.checkpoint("per_mod:duplicate-heroes")

-- The hero slot the LOBBY is told you picked. It has to be one nobody else is
-- on; you still select whoever you actually want.
local DECOY_SLOT = 9

R.on("ready", function()
    if not R.hero.broadcast_decoy(DECOY_SLOT) then
        R.log("[duplicate-heroes] not armed — see the [rsmm.hero] line above")
    end
end)
