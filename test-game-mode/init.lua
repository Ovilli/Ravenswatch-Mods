-- GAME MODE PROOF — does the engine play a REPEATED chapter order?
--
-- The manifest rewrites All_Chapters in place to [0, 0, 1]: Dark Hills,
-- Dark Hills again, Storm Island. Override-in-place and skipping chapters are
-- proven; a repeated index is not. This logs the live chapter list, so the
-- data half is visible at boot, and counts run starts, so the log shows how
-- many chapters were entered. test-tilegen's probe logs every map generation
-- with its chapter, which is the second, independent reading:
--
--   tilegen-proof "Dark Hills" twice, then a non-Dark-Hills map -> PASS
local R = require "rsmm"

local TAG = "[mode-proof]"
local EXPECT = "0,0,1"

local function chapters(when)
    if not (R.maps and R.maps.chapters) then
        R.log(TAG .. " R.maps missing on this SDK")
        return
    end
    local rows, err = R.maps.chapters()
    if not rows then
        R.log(TAG .. " " .. when .. ": chapter list unreadable: " .. tostring(err))
        return
    end
    local b = {}
    for _, r in ipairs(rows) do b[#b + 1] = tostring(r.biome or (r.resref and "resref") or "?") end
    local got = table.concat(b, ",")
    R.log(("%s %s: live chapter list = [%s] (expected [%s]) -> %s"):format(TAG, when, got,
        EXPECT, got == EXPECT and "override live" or "NOT our order"))
end

local starts = 0
R.on("ready", function() R.schedule.after(10, function() chapters("boot") end) end)
R.on("run:start", function()
    starts = starts + 1
    R.log(("%s run start #%d"):format(TAG, starts))
    if starts == 1 then chapters("first run start") end
end)

R.log(TAG .. " armed — play past chapter 1, then: rsmm log --grep 'mode-proof\\|tilegen-proof'")
