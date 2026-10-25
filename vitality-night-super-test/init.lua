-- TESTING ONLY. Grants Test_Vitality_Night_Super three times so the Epic
-- super effect is active. At nightfall, cached vitality should rise by 15
-- points, then return after 5 seconds. The cache stores the value as a ratio,
-- so multiply it by 100 for the same units shown in game.
local R = require "rsmm"

local ITEM = "Test_Vitality_Night_Super"
local COPIES = 3
local POLL = 0.25

local granted, last = 0, nil
local function reset()
    granted, last = 0, nil
end

for _, event in ipairs({ "run:start", "run:end", "menu:enter" }) do
    R.on(event, reset)
end

R.schedule.every_main(POLL, function()
    if not R.give.ready() then return end
    if granted < COPIES then
        local ok = R.give.by_name(ITEM)
        R.log(("[Vitality test] grant %d/%d: %s"):format(
            granted + 1, COPIES, ok and "ok" or "NOT LOADED"))
        if not ok then return end
        granted = granted + 1
    end
    if granted < COPIES then return end

    local raw = R.stat.cached("max_health")
    if raw == nil then return end
    local points = raw * 100
    if last == nil then
        R.log(("[Vitality test] starting vitality: %.2f"):format(points))
    elseif math.abs(points - last) >= 0.01 then
        R.log(("[Vitality test] vitality %.2f -> %.2f (delta %+.2f)"):format(
            last, points, points - last))
    end
    last = points
end)

R.on("ready", function()
    R.log("[Vitality test] armed; grant occurs when the game is ready")
end)
