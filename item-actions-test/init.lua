-- TESTING ONLY. Grants the item-actions test items once per run; what each
-- should do is listed in manifest.toml. Look for "[Act] grant ... ok" in the
-- rsmm log, then check each effect in game.
local R = require "rsmm"

local ITEMS = {
    "Test_Action_Dash_Reset",
    "Test_Action_All_Reset",
    "Test_Action_Upgrade",
    "Test_Action_Consumables",
    "Test_Action_Duplicate",
}

local granted = false
for _, b in ipairs({ "run:start", "run:end", "menu:enter" }) do
    R.on(b, function() granted = false end)
end

-- Grants build entities: main thread only.
R.schedule.every_main(0.5, function()
    if granted or not R.give.ready() then return end
    granted = true
    for _, id in ipairs(ITEMS) do
        local ok = R.give.by_name(id)
        R.log(("[Act] grant %s: %s"):format(id, ok and "ok" or "NOT LOADED"))
    end
end)
