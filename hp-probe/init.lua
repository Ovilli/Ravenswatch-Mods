-- Proof for R.hp (static RE 2026-09-18). Pass: the logged cur/max match the
-- health bar, cur drops when you take a hit, and a kill heals 25.
local R = require "rsmm"

R.schedule.every(5, function()
    local cur, mx = R.hp.get(), R.hp.max()
    if cur then
        R.log(("[hp-probe] hp %.1f / %.1f (%.0f%%)  shards %s")
            :format(cur, mx or 0, (R.hp.frac() or 0) * 100, tostring(R.shards.get())))
    else
        R.log("[hp-probe] no verified HitPoint component yet")
    end
end)

-- Gameplay events run on the main thread, the only place a setter is safe.
R.on("gameplay:ENEMY_KILLED", function()
    local before = R.hp.get()
    if before and R.hp.heal(25) then
        R.log(("[hp-probe] kill: heal 25, %.1f -> %.1f"):format(before, R.hp.get() or -1))
    end
end)
