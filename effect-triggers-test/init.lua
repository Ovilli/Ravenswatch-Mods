-- TESTING ONLY. Grants the 14 trigger test items at run start and logs every
-- trigger as it switches on and off. Trigger k (0-based, in this order) gives
-- 2^k crit chance (a whole number), so the whole part of the crit value says
-- exactly which are active; the hero's own crit is a fraction and drops out.
--
-- What a pass looks like, per trigger: "[Trig] ON  <name>" when you do the
-- thing (take damage, dash, use your ultimate, ...), then "[Trig] OFF <name>
-- after 5.0 s" -- or later, if the same trigger fired again meanwhile.
-- A trigger that never logs ON did not fire; one that logs ON but never OFF
-- is stuck (the bug Pebbles had).
local R = require "rsmm"

local TRIGGERS = {
    "damage_taken",
    "hit",
    "dash",
    "special",
    "defense",
    "ultimate",
    "power",
    "day_start",
    "night_start",
    "talent_picked",
    "item_picked_up",
    "dream_shards_gained",
    "sandman_purchase",
    "reroll"
}

-- Time is counted in polls (0.25 s each): mods have no wall clock.
local POLL = 0.25
local granted, active, since, last, polls = 0, {}, {}, nil, 0
local function reset() granted, active, since, last, polls = 0, {}, {}, nil, 0 end
for _, b in ipairs({ "run:start", "run:end", "menu:enter" }) do R.on(b, reset) end

-- Grants build entities: main thread only.
R.schedule.every_main(POLL, function()
    polls = polls + 1
    if granted < #TRIGGERS and R.give.ready() then
        for k = granted + 1, #TRIGGERS do
            local id = "Test_Trigger_" .. TRIGGERS[k]
            local ok = R.give.by_name(id)
            R.log(("[Trig] grant %s: %s"):format(id, ok and "ok" or "NOT LOADED"))
            granted = k
        end
    end
    if granted < #TRIGGERS then return end
    local crit = R.stat.get("crit_chance")
    if not crit then return end
    local bits = math.floor(crit + 1e-6)
    if bits == last then return end
    last = bits
    local now = polls * POLL
    for k, name in ipairs(TRIGGERS) do
        local on = (bits >> (k - 1)) & 1 == 1
        if on and not active[name] then
            active[name], since[name] = true, now
            R.log(("[Trig] ON  %s"):format(name))
        elseif not on and active[name] then
            active[name] = nil
            R.log(("[Trig] OFF %s after %.1f s"):format(name, now - (since[name] or now)))
        end
    end
end)

R.on("ready", function() R.log(("[Trig] armed: %d triggers"):format(#TRIGGERS)) end)
