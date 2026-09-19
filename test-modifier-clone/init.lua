-- MODIFIER PROOF — does selecting the CLONE change the run?
--
-- The clone of MoreExperience already reaches the challenge screen (2026-09-18).
-- The open question is whether selecting it does anything. A modifier def
-- takes effect by writing its value into the run's entity-value store, which
-- R.modifier reads by key. The clone carries the base's payload, so if the
-- engine applies it, the "More experience" toggle reads non-zero.
--
-- HOW TO RUN IT: start a run with ONLY "TEST Double XP" selected (not the
-- vanilla More Experience), then `rsmm log --grep modifier-proof`.
--
--   More experience != 0   -> the clone's effect was applied (PASS)
--   More experience == 0   -> selected but inert (FAIL), or R.modifier cannot
--                             read this build's store: compare one run with the
--                             VANILLA More Experience selected — if that also
--                             reads 0, the reader is what is broken.
--
-- XP is logged every 30 s as a second, independent reading.
local R = require "rsmm"

local TAG = "[modifier-proof]"
local KEYS = { "More experience", "Global Xp Modifier", "Difficulty Xp Modifier" }

local function report(when)
    if not R.modifier then
        R.log(TAG .. " R.modifier missing on this SDK")
        return
    end
    local parts = {}
    for _, k in ipairs(KEYS) do
        parts[#parts + 1] = ("%s=%s"):format(k, tostring(R.modifier.value(k)))
    end
    local on = R.modifier.active("More experience")
    R.log(("%s %s: %s -> %s"):format(TAG, when, table.concat(parts, ", "),
        on and "More experience ACTIVE (PASS if only the clone was selected)"
           or "More experience off"))
end

local ticker
R.on("run:start", function()
    R.schedule.after(5, function() report("run start +5s") end)
    if not ticker and R.xp then
        ticker = R.schedule.every(30, function()
            R.log(("%s xp: level=%s xp=%s"):format(TAG,
                tostring(R.xp.level()), tostring(R.xp.xp())))
        end)
    end
end)

R.log(TAG .. " armed — select ONLY 'TEST Double XP', start a run, then: "
      .. "rsmm log --grep modifier-proof")
