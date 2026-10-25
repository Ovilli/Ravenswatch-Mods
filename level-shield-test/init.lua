-- TESTING ONLY. Grants Test_Level_Shield once the game is ready.
local R = require "rsmm"

local ITEM = "Test_Level_Shield"
local granted = false

for _, event in ipairs({ "run:start", "run:end", "menu:enter" }) do
    R.on(event, function() granted = false end)
end

R.schedule.every_main(0.25, function()
    if granted or not R.give.ready() then return end
    local ok = R.give.by_name(ITEM)
    R.log(("[Level shield test] grant: %s"):format(ok and "ok" or "NOT LOADED"))
    granted = ok
end)
