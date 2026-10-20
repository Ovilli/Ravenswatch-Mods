-- TESTING ONLY. Grants the 14 trigger test items at run start and logs every
-- trigger as it switches on and off. Trigger k (0-based, in this order) gives
-- 2^k x UNIT life on hit; each change of it is decoded: +2^k units means
-- trigger k switched on, -2^k units that it switched off. A change that is not a
-- whole number of units is something else moving it (a talent, an item) and is
-- reported as such. The raw value is logged every 5 s too, so a capped or frozen
-- one shows.
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
local UNIT = 1 / 1024     -- binary: sums of these are exact in f32

-- Time is counted in polls (0.25 s each): mods have no wall clock.
local POLL = 0.25
local granted, since, last, polls = 0, {}, nil, 0
local function reset() granted, since, last, polls = 0, {}, nil, 0 end
for _, b in ipairs({ "run:start", "run:end", "menu:enter" }) do R.on(b, reset) end

local function decode(delta)
    local units = delta / UNIT
    local n = math.floor(math.abs(units) + 0.5)
    if n == 0 or n >= (1 << #TRIGGERS) or math.abs(math.abs(units) - n) > 0.02 then
        return nil
    end
    local names = {}
    for k, name in ipairs(TRIGGERS) do
        if (n >> (k - 1)) & 1 == 1 then names[#names + 1] = name end
    end
    return names, units > 0
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
        last = crit
        R.log(("[Trig] life on hit at start %.6f"):format(crit))
        return
    end
    local delta = crit - last
    if math.abs(delta) < UNIT / 4 then return end
    last = crit
    local names, on = decode(delta)
    if not names then
        R.log(("[Trig] life on hit changed by %+.6f, not a test item: now %.6f")
            :format(delta, crit))
        return
    end
    local now = polls * POLL
    for _, name in ipairs(names) do
        if on then
            since[name] = now
            R.log(("[Trig] ON  %s"):format(name))
        else
            R.log(("[Trig] OFF %s after %.1f s"):format(name, now - (since[name] or now)))
            since[name] = nil
        end
    end
end)

R.on("ready", function() R.log(("[Trig] armed: %d triggers"):format(#TRIGGERS)) end)
