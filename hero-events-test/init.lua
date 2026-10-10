-- TESTING ONLY. Checks R.ability, R.shards.gain and R.ingredient in game.
-- Delete before sharing: from the store it is "no cooldowns + free shards".
local R = require "rsmm"

local TAG = "[hero-events-test] "

-- Level up at once so the ULTIMATE is unlocked and its cooldown can be checked.
R.xp.arm()
local granted, queued, last = false, false, 0

R.on("run:start", function() granted = false end)

-- Our own events, seen on the bus: proves they reached the dispatcher.
for _, name in ipairs({ "CLEAR_CD", "ADD_DASH_CHARGE", "GAIN_DREAM_SHARDS", "GAIN_INGREDIENT" }) do
    R.on("gameplay:" .. name, function(ev)
        R.log(TAG .. "bus " .. name .. " class=" .. tostring(ev.class)
            .. " dispatcher=" .. tostring(ev.dispatcher))
    end)
end

local function once_per_run()
    granted = true
    local before = R.shards.get and R.shards.get()
    R.log(TAG .. "add_charge(dash, 2): " .. tostring(R.ability.add_charge("dash", 2)))
    R.log(TAG .. "shards.gain(50): " .. tostring(R.shards.gain(50))
        .. "; shards " .. tostring(before) .. " -> " .. tostring(R.shards.get and R.shards.get()))
    R.log(TAG .. "ingredients loaded: " .. table.concat(R.ingredient.names(), ", "))
    R.log(TAG .. "ingredient.add(Key, 2): " .. tostring(R.ingredient.add("Key", 2)))
    R.stat.enable_writes()
    -- R.xp.set_level is new (XpComponent_SetLevel); fall back to a grant.
    local lv0 = R.xp.level()
    local ok = R.xp.set_level(10)
    R.log(TAG .. "xp.set_level(10): " .. tostring(ok) .. " (level " .. tostring(lv0) .. " -> " .. tostring(R.xp.level()) .. ")")
    if not ok then
        R.log(TAG .. "xp.grant(5000): " .. tostring(R.xp.grant(5000)) .. " (level " .. tostring(R.xp.level()) .. ")")
    end
end

-- ABILITY_EXIT fires from inside the engine's own dispatch; send ours on the
-- next main-thread tick instead, at most once a second.
R.on("gameplay:ABILITY_EXIT", function()
    if queued or not R.ability or os.clock() - last < 1 then return end
    queued = true
    R.schedule.next_main(function()
        queued, last = false, os.clock()
        local ok = R.ability.reset_cooldown()
        R.log(TAG .. "reset_cooldown(): " .. tostring(ok))
        if ok and not granted then once_per_run() end
    end)
end)

R.log(TAG .. "loaded; R.ability " .. (R.ability and "present" or "MISSING")
    .. ", R.shards.gain " .. (R.shards and R.shards.gain and "present" or "MISSING")
    .. ", R.ingredient " .. (R.ingredient and "present" or "MISSING"))
