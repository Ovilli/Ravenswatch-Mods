-- REWARD PROOF — does the engine hold OUR Dark Hills camp reward def?
--
-- The manifest drops the three astrolabs from Camp_Rewards_Dark_Hills_Update5,
-- which turns its astrolab type (min 0, max 1, 3 items) into (0, 0, 0). Seeing
-- no astrolab in a run proves nothing: vanilla already allows zero. So this
-- reads every LIVE reward def's type shape and looks for ours:
--
--   (1,2,2)(3,4,3)(0,0,0)(1,3,1)   ours    -> the override is what got loaded
--   (1,2,2)(3,4,3)(0,1,3)(1,3,1)   vanilla -> the override was not loaded
--
-- Reward defs load with the level, so it reports at run start and again a
-- little later, once the level's reward roll has run.
local R = require "rsmm"

local OURS    = "(1,2,2)(3,4,3)(0,0,0)(1,3,1)"
local VANILLA = "(1,2,2)(3,4,3)(0,1,3)(1,3,1)"
local TAG = "[reward-proof]"

if not R.rewards then
    R.log(TAG .. " R.rewards missing on this SDK — cannot measure")
    return
end

local function verdict(when)
    local ours = R.rewards.report(OURS, TAG)
    local vanilla = 0
    for _, e in ipairs(R.rewards.defs()) do
        if R.rewards.format(e.shape) == VANILLA then vanilla = vanilla + 1 end
    end
    local v
    if ours > 0 and vanilla == 0 then
        v = "PASS — the live Dark Hills camp def is our override"
    elseif vanilla > 0 and ours == 0 then
        v = "FAIL — the live def is still vanilla"
    elseif ours > 0 and vanilla > 0 then
        v = "MIXED — both shapes live; another def may share the vanilla shape"
    else
        v = "NOT FOUND — neither shape live (not in Dark Hills yet, or offsets moved)"
    end
    R.log(("%s %s: ours=%d vanilla=%d -> %s"):format(TAG, when, ours, vanilla, v))
end

R.on("run:start", function()
    verdict("run start")
    R.schedule.after(20, function() verdict("run start +20s") end)
end)

R.log(TAG .. " armed — start a Dark Hills run, then: rsmm log --grep reward-proof")
