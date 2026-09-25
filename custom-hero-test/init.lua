-- Gate 1: the herodef registered (13 live). The rest is your eyes.
-- To reach the ultimate (Rat King, 5 s cooldown) without a long run, the hero
-- gets XP at the start of every run.
local R = require "rsmm"

-- Arm the level capture NOW (before any run builds the level component).
R.xp.arm()

R.on("ready", function()
    R.schedule.after_main(12, function()
        local n = #(R.defs.instances("oCDtHeroDefinition") or {})
        R.log(("[custom-hero] %d hero defs live (vanilla 12) -> Nyx %s"):format(
            n, n > 12 and "REGISTERED" or "NOT registered"))
    end)
end)

local granted, xp_done = false, false
R.on("run:start", function() granted, xp_done = false, false end)
R.schedule.every(3, function()
    if granted or not R.entity.ready() then return end
    granted = true
    R.schedule.next_main(function()
        R.stat.enable_writes()
        local lvl = R.xp.level()
        local ok = R.xp.grant(5000)
        xp_done = ok
        R.log(("[custom-hero] R.xp.grant(5000): %s (level %s -> %s)"):format(
            ok and "OK" or "failed", tostring(lvl), tostring(R.xp.level())))
        -- Fallback: a durable XP-multiplier modifier on the hero (R.stat.set only
        -- pokes a cache the game recomputes, which wiped it in the 2026-09-25 run).
        local mok = R.stat.modify("xp_multiplier", 5000)
        R.log(("[custom-hero] XP multiplier modifier: %s (now %s)"):format(
            mok and "applied" or "REFUSED", tostring(R.stat.get("xp_multiplier"))))
    end)
end)

-- A grant that failed at run start (component not captured yet) retries after
-- the first XP the game hands out, which captures it through Hero_GainExperience.
R.schedule.every(5, function()
    if not granted or xp_done then return end
    R.schedule.next_main(function()
        if xp_done then return end
        if R.xp.level() then
            xp_done = R.xp.grant(5000)
            R.log(("[custom-hero] retry R.xp.grant(5000): %s (level now %s)"):format(
                xp_done and "OK" or "failed", tostring(R.xp.level())))
        end
    end)
end)
