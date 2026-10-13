-- TESTING ONLY. Validates the typed `level_up` hook by logging it next to the
-- two other level-up signals. PASS = each level-up logs exactly one
-- `typed level_up level=N` whose N matches the HUD and the analytics value.
local R = require "rsmm"

local TAG = "[level-up-test] "
local count = { typed = 0, analytics = 0, gameplay = 0 }

R.on("level_up", function(ev)
    count.typed = count.typed + 1
    R.log(TAG .. "typed level_up level=" .. tostring(ev and ev.level)
          .. " seq=" .. tostring(ev and ev.seq))
end)

R.on("levelup_run", function(ev)c
    count.analytics = count.analytics + 1
    R.log(TAG .. "analytics levelup_run level_up_reach="
          .. tostring(ev and ev.level_up_reach))
end)

R.on("gameplay:HERO_XP_LEVEL_UP", function()
    count.gameplay = count.gameplay + 1
    R.log(TAG .. "gameplay HERO_XP_LEVEL_UP")
end)

R.on("ready", function()
    R.log(TAG .. "armed; level up in a run and compare the three lines")
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
