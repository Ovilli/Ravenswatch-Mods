-- TESTING ONLY. Grants the 14 trigger test items at run start and logs every
-- trigger as it switches on and off. Trigger k (0-based, in this order) gives
-- 2^k x UNIT life on hit; the value itself says which are active (it is 0
-- without them), so each poll compares the active set with the last one. The raw value is logged every 5 s too, so a capped or frozen
-- one shows.
--
-- What a pass looks like, per trigger: "[Trig] ON  <name>" when you do the
-- thing (take damage, dash, use your ultimate, ...), then "[Trig] OFF <name>"
-- 5 s later by the log timestamps -- or later, if it fired again meanwhile.
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
local UNIT = 1 / 1024     -- binary: sums of these are exact in f32

-- Time is counted in polls (0.25 s each): mods have no wall clock.
local POLL = 0.25
local granted, since, last, polls = 0, {}, nil, 0
local function reset() granted, since, last, polls = 0, {}, nil, 0 end
for _, b in ipairs({ "run:start", "run:end", "menu:enter" }) do R.on(b, reset) end

-- The bits active right now, from the value itself: life on hit is 0 without
-- the test items (measured), so value * 1024 is exactly the sum of the active
-- triggers' bits. Decoding CHANGES instead misread one trigger switching on and
-- another off in the same poll as unrelated triggers (2026-10-20).
local function active_bits(v)
    local units = v / UNIT
    local n = math.floor(units + 0.5)
    if n < 0 or n >= (1 << #TRIGGERS) or math.abs(units - n) > 0.02 then return nil end
    return n
end

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
    local crit = R.stat.get("life_on_hit")
    if not crit then
        if polls % 20 == 0 then R.log("[Trig] life_on_hit unreadable") end
        return
    end
    if polls % 20 == 0 then R.log(("[Trig] life on hit now %.6f"):format(crit)) end
    if last == nil then
        last = 0
        R.log(("[Trig] life on hit at start %.6f"):format(crit))
    end
    local bits = active_bits(crit)
    if bits == nil then
        R.log(("[Trig] life on hit %.6f is not a sum of test bits (another source?)"):format(crit))
        last = crit
        return
    end
    local was = active_bits(last) or 0
    last = crit
    if bits == was then return end
    local now = polls * POLL
    for k, name in ipairs(TRIGGERS) do
        local on, before = (bits >> (k - 1)) & 1 == 1, (was >> (k - 1)) & 1 == 1
        if on and not before then
            since[name] = now
            R.log(("[Trig] ON  %s"):format(name))
        elseif before and not on then
            -- No duration here: every_main ticks slower than POLL, so a poll
            -- count undercounts (2.2 s printed for a 4.4 s window, 2026-10-20).
            -- The log line's own timestamp is the clock: OFF minus ON.
            R.log(("[Trig] OFF %s"):format(name))
            since[name] = nil
        end
    end
end)

R.on("ready", function() R.log(("[Trig] armed: %d triggers"):format(#TRIGGERS)) end)
