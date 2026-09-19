-- MODIFIER PROOF — does selecting the CLONE change the run?
--
-- The clone of MoreExperience already reaches the challenge screen (2026-09-18).
-- The open question is whether selecting it does anything. A modifier def
-- takes effect by writing its value into the run's entity-value store, which
-- R.game reads by key. The clone carries the base's payload, so if the
-- engine applies it, the "More experience" toggle reads non-zero.
--
-- HOW TO RUN IT: start a run with ONLY "TEST Double XP" selected (not the
-- vanilla More Experience), then `rsmm log --grep modifier-proof`.
--
--   More experience != 0   -> the clone's effect was applied (PASS)
--   More experience == 0   -> selected but inert (FAIL) — unless a run with
--                             the VANILLA More Experience also reads 0, in
--                             which case the reader is what is broken.
--   nil                    -> unreadable; the reason is printed beside it.
local R = require "rsmm"

local TAG = "[modifier-proof]"
-- Run modifiers live in the GLOBAL scene-context value table (R.game, group
-- "New Game Plus"), not on the hero: the first version read the hero store
-- through R.modifier and got 0.0 for everything, including the global XP
-- multiplier, which cannot be real.
local KEYS = { "gamemodifier_more_experience", "global_xp_modifier",
               "difficulty_xp_modifier" }

local dumped = false
local function report(when)
    if not (R.game and R.game.get) then
        R.log(TAG .. " R.game missing on this SDK")
        return
    end
    local parts = {}
    for _, k in ipairs(KEYS) do
        local v = R.game.get(k)
        local shown = v == nil and ("nil (" .. tostring(R.game.why()) .. ")") or tostring(v)
        parts[#parts + 1] = ("%s=%s"):format(k, shown)
    end
    local on = R.game.get("gamemodifier_more_experience")
    local verdict
    if on == nil then
        verdict = "UNREADABLE"
    elseif on ~= 0 then
        verdict = "More experience ACTIVE — PASS if only the clone was selected"
    else
        verdict = "More experience OFF — FAIL if the clone was selected"
    end
    R.log(("%s %s: %s -> %s"):format(TAG, when, table.concat(parts, ", "), verdict))
    -- Layout evidence, once: the raw unions of the modifier keys beside a key
    -- that is not a modifier ("Current chapter"), so the next session can read
    -- the non-inline shape off the dump instead of guessing it.
    if not dumped and R.game.raw then
        dumped = true
        R.log(("%s current_chapter reads %s"):format(TAG, tostring(R.game.get("current_chapter"))))
        for _, k in ipairs(KEYS) do R.game.raw(k) end
        R.game.raw("current_chapter")
    end
end

R.on("run:start", function()
    R.schedule.after_main(20, function() report("run start +20s") end)
    R.schedule.after_main(60, function() report("run start +60s") end)
end)

R.log(TAG .. " armed — select ONLY 'TEST Double XP', start a run, then: "
      .. "rsmm log --grep modifier-proof")
