-- TESTING ONLY. Validates the typed `level_up` hook by logging it next to the
-- two other level-up signals. PASS = each level-up logs exactly one
-- `typed level_up level=N` whose N matches the HUD and the analytics value.
--
-- It also LEVELS YOU UP ITSELF: once the hero is captured in a run it grants
-- XP through the engine's own gain-experience routine (R.xp.grant), the same
-- path a kill takes, so the level-up loop and its events fire for real.
local R = require "rsmm"

local TAG = "[level-up-test] "
local GRANT_XP    = 1000   -- per grant; enough for at least one level early on
local GRANTS      = 3      -- how many self level-ups to attempt
local GRANT_EVERY = 15     -- seconds between grants

local count = { typed = 0, analytics = 0, gameplay = 0 }

R.stat.enable_writes()     -- R.xp.grant is gated behind this opt-in
R.xp.arm()                 -- capture must be live before the run builds it

R.on("level_up", function(ev)
    count.typed = count.typed + 1
    R.log(TAG .. "typed level_up level=" .. tostring(ev and ev.level)
          .. " seq=" .. tostring(ev and ev.seq))
end)

R.on("levelup_run", function(ev)
    count.analytics = count.analytics + 1
    R.log(TAG .. "analytics levelup_run level_up_reach="
          .. tostring(ev and ev.level_up_reach))
end)

R.on("gameplay:HERO_XP_LEVEL_UP", function()
    count.gameplay = count.gameplay + 1
    R.log(TAG .. "gameplay HERO_XP_LEVEL_UP")
end)

R.on("ready", function()
    R.log(TAG .. "armed; will grant " .. GRANT_XP .. " XP x" .. GRANTS
          .. " once a run starts")
end)

-- Self level-up. Engine-mutating, so the grant itself runs on the MAIN thread.
local granted, waiting = 0, false
R.schedule.every(GRANT_EVERY, function()
    if granted >= GRANTS or waiting then return end
    if not R.entity.hero() then return end          -- not in a run yet
    waiting = true
    R.schedule.next_main(function()
        waiting = false
        local before = R.xp.level()
        local ok = R.xp.grant(GRANT_XP)
        granted = granted + 1
        R.log(string.format("%sgrant #%d: %d XP -> %s (level %s -> %s)",
              TAG, granted, GRANT_XP, ok and "ok" or "REFUSED",
              tostring(before), tostring(R.xp.level())))
    end)
end)

R.schedule.every(60, function()
    local verdict
    if count.analytics == 0 and count.gameplay == 0 then
        verdict = "no level-up yet"
    elseif count.typed == 0 then
        verdict = "FAIL: game levelled up but typed level_up never fired (check loader log for Event_LevelUp)"
    elseif count.typed > math.max(count.analytics, count.gameplay) then
        verdict = "FAIL: typed level_up fires more often than the game levels up"
    elseif count.typed < math.max(count.analytics, count.gameplay) then
        verdict = "FAIL: typed level_up missed some level-ups"
    else
        verdict = "PASS so far"
    end
    R.log(string.format("%styped=%d analytics=%d gameplay=%d -> %s",
          TAG, count.typed, count.analytics, count.gameplay, verdict))
end)
