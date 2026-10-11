-- Bounty Board — rotating combat bounties during a run.
--
-- A board of (by default) three bounties is open the whole run. Each one is a
-- small goal with a timer — slay 20, chain 6 kills in 8 seconds, kill 10
-- without being hit — and pays out the moment it is met. When one is paid or
-- runs out, a new one is posted a few seconds later. Three in a row without an
-- expiry also pays a mystery item, and every boss fight posts a special bounty.
--
-- Everything here is observation plus the game's own reward events:
--   counts   gameplay:ENEMY_KILLED / OPEN_CHEST / ACTIVITY_SUCCESS, level_up,
--            R.damage "taken" hits, BOSS_* and HERO_DEATH_DOOR
--   pays     R.shards.gain, R.reroll.add, R.talent.upgrade_random,
--            R.revive.add_token, R.give.random
--
-- THREADS. Kill/hit callbacks run on the game's main thread; the 1-second
-- board tick runs on the loader's background thread. Payouts mutate the hero,
-- which is main-thread only (calling a grant from a timer crashed the game in
-- EntityComponent_Activate, 2026-10-01). So nothing pays directly: completions
-- go into `payouts`, and only the every_main pump spends it.
--
-- Where the board shows: the desktop app's overlay window (declared in the
-- manifest), `rsmm overlay bounty-board --watch`, and the loader log.

local R = require "rsmm"

local cfg = {
    slots        = math.max(1, math.min(4, R.config.get("slots", 3))),
    streak_bonus = R.config.get("streak_bonus", true),
    boss_bounty  = R.config.get("boss_bounty", true),
    announce     = R.config.get("announce", true),
}

-- goal x targets, time x limits, pay x rewards. Read when a bounty is POSTED,
-- so the overlay control changes the next bounty and never a running one.
local DIFFICULTY = {
    relaxed  = { goal = 0.7, time = 1.4,  pay = 0.8 },
    standard = { goal = 1.0, time = 1.0,  pay = 1.0 },
    brutal   = { goal = 1.5, time = 0.75, pay = 1.6 },
}

local RESULT_SECONDS = 6     -- how long a paid/expired row stays up
local STREAK_FOR_BONUS = 3

local function say(fmt, ...)
    if cfg.announce then R.log(fmt:format(...)) end
end

local function round(x) return math.floor(x + 0.5) end

local function difficulty()
    return DIFFICULTY[R.config.get("difficulty", "standard")] or DIFFICULTY.standard
end

-- ---------------------------------------------------------------------------
-- Rewards
-- ---------------------------------------------------------------------------
-- One entry per thing paid. `label` is what the board shows.
local PAY = {
    shards  = { label = function(n) return n .. " shards" end,
                send  = function(n) return R.shards and R.shards.gain and R.shards.gain(n) end },
    reroll  = { label = function(n) return n == 1 and "1 reroll" or (n .. " rerolls") end,
                send  = function(n) return R.reroll and R.reroll.add and R.reroll.add(n) end },
    talent  = { label = function() return "talent upgrade" end,
                send  = function(n) return R.talent and R.talent.upgrade_random and R.talent.upgrade_random(n) end },
    revive  = { label = function() return "revive token" end,
                send  = function(n) return R.revive and R.revive.add_token and R.revive.add_token(n) end },
    item    = { label = function() return "mystery item" end,
                send  = function() return R.give and R.give.random and R.give.random() ~= nil end },
}

local TIERS = {
    -- quick ones: a shard purse
    [1] = function(p) return { { "shards", round(40 * p) } } end,
    -- hard ones: a bigger purse and a reroll (two on Brutal)
    [2] = function(p) return { { "shards", round(60 * p) }, { "reroll", p >= 1.5 and 2 or 1 } } end,
    -- the boss bounty
    [3] = function() return { { "talent", 1 }, { "revive", 1 } } end,
}

local function reward_label(list)
    local parts = {}
    for _, r in ipairs(list) do parts[#parts + 1] = PAY[r[1]].label(r[2]) end
    return table.concat(parts, " + ")
end

-- Main-thread payout queue. A grant needs the hero's event dispatcher, which
-- the SDK learns from the hero's own first action, so an entry waits until
-- R.give.ready() and is retried a few times before it is dropped (logged).
local payouts = {}

local function queue_payout(list, why)
    for _, r in ipairs(list) do
        payouts[#payouts + 1] = { kind = r[1], n = r[2], why = why, tries = 0 }
    end
end

local function drain()
    if #payouts == 0 or not (R.give and R.give.ready and R.give.ready()) then return end
    local p = table.remove(payouts, 1)          -- one per pump: grants cascade events
    local ok, res = pcall(PAY[p.kind].send, p.n)
    if ok and res then
        say("[Bounty] paid %s (%s)", PAY[p.kind].label(p.n), p.why)
        return
    end
    p.tries = p.tries + 1
    if p.tries < 5 then
        payouts[#payouts + 1] = p
    else
        R.log(("[Bounty] could not pay %s for %s: %s"):format(
            PAY[p.kind].label(p.n), p.why, ok and "the game refused it" or tostring(res)))
    end
end

-- ---------------------------------------------------------------------------
-- Bounty templates
-- ---------------------------------------------------------------------------
-- `make(d)` returns the posted bounty for difficulty `d`. `on` names the
-- signal that advances it (see the event wiring at the bottom).
local TEMPLATES = {
    { kind = "slayer", weight = 3, tier = 1, on = "kill", make = function(d)
        local n = round(20 * d.goal)
        return { title = ("Slay %d enemies"):format(n), goal = n, left = round(120 * d.time) }
    end },
    { kind = "rampage", weight = 2, tier = 2, on = "kill", make = function(d)
        local n = math.max(4, round(6 * d.goal))
        return { title = ("Kill %d within 8 seconds"):format(n), goal = n,
                 left = round(180 * d.time), window = 8, stamps = {} }
    end },
    { kind = "flawless", weight = 2, tier = 2, on = "kill", make = function(d)
        local n = round(10 * d.goal)
        return { title = ("Kill %d without getting hit"):format(n), goal = n, left = round(240 * d.time) }
    end },
    { kind = "treasure", weight = 2, tier = 1, on = "chest", make = function(d)
        local n = math.max(1, round(2 * d.goal))
        return { title = n == 1 and "Open a chest" or ("Open %d chests"):format(n),
                 goal = n, left = round(300 * d.time) }
    end },
    { kind = "ascend", weight = 2, tier = 1, on = "level", make = function(d)
        local n = math.max(1, round(2 * d.goal))
        return { title = n == 1 and "Gain a level" or ("Gain %d levels"):format(n),
                 goal = n, left = round(360 * d.time) }
    end },
    -- World-event success has not been watched firing in a playtest yet; a
    -- bounty that never completes just expires, so it is kept rare.
    { kind = "champion", weight = 1, tier = 2, on = "activity", make = function(d)
        return { title = "Win a world event", goal = 1, left = round(420 * d.time) }
    end },
}

-- ---------------------------------------------------------------------------
-- Board state
-- ---------------------------------------------------------------------------
local board = {}          -- slot -> bounty | { result = text, ttl = n, ... }
local boss = nil          -- the special boss bounty, outside the slots
local active, paused = false, false
local streak, completed, failed = 0, 0, 0

local function on_board(kind)
    for _, b in pairs(board) do
        if b.kind == kind and not b.result then return true end
    end
    return false
end

local function pick_template(avoid)
    local pool, total = {}, 0
    for _, t in ipairs(TEMPLATES) do
        if t.kind ~= avoid and not on_board(t.kind) then
            pool[#pool + 1] = t
            total = total + t.weight
        end
    end
    if total == 0 then return nil end
    local roll = math.random() * total
    for _, t in ipairs(pool) do
        roll = roll - t.weight
        if roll <= 0 then return t end
    end
    return pool[#pool]
end

local function post(slot, avoid)
    local t = pick_template(avoid)
    if not t then board[slot] = nil; return end
    local d = difficulty()
    local b = t.make(d)
    b.kind, b.on, b.tier, b.progress = t.kind, t.on, t.tier, 0
    b.reward = TIERS[t.tier](d.pay)
    b.reward_text = reward_label(b.reward)
    board[slot] = b
    say("[Bounty] posted: %s — %s", b.title, b.reward_text)
end

local function finish(slot, b, ok, why)
    if ok then
        completed, streak = completed + 1, streak + 1
        queue_payout(b.reward, b.title)
        say("[Bounty] COMPLETE: %s — %s", b.title, b.reward_text)
        if cfg.streak_bonus and streak % STREAK_FOR_BONUS == 0 then
            queue_payout({ { "item" } }, ("streak of %d"):format(streak))
            say("[Bounty] streak x%d — mystery item incoming", streak)
        end
    else
        failed, streak = failed + 1, 0
        say("[Bounty] failed: %s (%s)", b.title, why)
    end
    if slot then
        board[slot] = { result = ok and ("Paid: " .. b.reward_text) or why,
                        title = b.title, ok = ok, kind = b.kind, ttl = RESULT_SECONDS }
    end
end

local function advance(b, slot, amount)
    b.progress = math.min(b.goal, b.progress + amount)
    if b.progress >= b.goal then finish(slot, b, true) end
end

local function reset(why)
    board, boss, payouts = {}, nil, {}
    active, paused, streak = false, false, 0
    if R.overlay and R.overlay.clear then R.overlay.clear() end
    if why then say("[Bounty] board closed (%s)", why) end
end

local function open(why)
    if active then paused = false; return end
    active, paused = true, false
    for slot = 1, cfg.slots do post(slot) end
    say("[Bounty] board open (%s) — %s difficulty", why, R.config.get("difficulty", "standard"))
end

-- ---------------------------------------------------------------------------
-- Signals
-- ---------------------------------------------------------------------------
local function each_live(signal, fn)
    if not active then return end
    for slot, b in pairs(board) do
        if not b.result and b.on == signal then fn(b, slot) end
    end
end

local function on_kill()
    if not active then open("first kill") end
    paused = false
    local now = os.time()
    each_live("kill", function(b, slot)
        if b.window then
            -- Rampage: the best run of kills inside the window is the progress.
            b.stamps[#b.stamps + 1] = now
            while #b.stamps > 0 and now - b.stamps[1] >= b.window do table.remove(b.stamps, 1) end
            b.progress = math.max(b.progress, #b.stamps)
            if #b.stamps >= b.goal then finish(slot, b, true) end
        else
            advance(b, slot, 1)
        end
    end)
end

local function on_hit()
    each_live("kill", function(b)
        if b.kind == "flawless" and b.progress > 0 then
            say("[Bounty] hit! %s resets (%d/%d lost)", b.title, b.progress, b.goal)
            b.progress = 0
        end
    end)
end

R.on("gameplay:ENEMY_KILLED", on_kill)
R.on("gameplay:OPEN_CHEST", function() each_live("chest", function(b, s) advance(b, s, 1) end) end)
R.on("level_up", function() each_live("level", function(b, s) advance(b, s, 1) end) end)
for _, name in ipairs({ "ACTIVITY_SUCCESS", "SOLO_ACTIVITY_SUCCESS" }) do
    R.on("gameplay:" .. name, function() each_live("activity", function(b, s) advance(b, s, 1) end) end)
end

-- Hits taken by the LOCAL hero, from the attack resolver (works solo; the
-- NETWORK_DAMAGE event does not fire in single player — see mods/bloodlust).
if R.damage and R.damage.on then
    R.damage.enable()
    R.damage.on(function(hit)
        if hit.kind == "taken" and hit.is_local then on_hit() end
    end)
end

-- The boss bounty: posted when the fight starts, failed by going down once.
R.on("gameplay:BOSS_FIGHTING_START", function()
    if not (active and cfg.boss_bounty) or boss then return end
    boss = { title = "Defeat the boss without falling", goal = 1, progress = 0,
             tier = 3, reward = TIERS[3](difficulty().pay) }
    boss.reward_text = reward_label(boss.reward)
    say("[Bounty] BOSS BOUNTY: %s — %s", boss.title, boss.reward_text)
end)
R.on("gameplay:BOSS_DEFEATED", function()
    if boss and not boss.result then
        boss.progress = 1
        finish(nil, boss, true)
        boss.result, boss.ok, boss.ttl = "Paid: " .. boss.reward_text, true, RESULT_SECONDS
    end
end)
R.on("gameplay:HERO_DEATH_DOOR", function()
    if boss and not boss.result then
        finish(nil, boss, false, "You fell")
        boss.result, boss.ok, boss.ttl = "You fell", false, RESULT_SECONDS
    end
end)

-- Run boundaries. Reset on every one of them, not only run:start: run:start
-- is derived from the analytics firehose and a run that misses it would
-- otherwise keep the last run's board (the same reasoning as lucky-chests).
for _, ev in ipairs({ "run:start", "gameplay:GAME_START", "gameplay:MAP_GENERATION_DONE" }) do
    R.on(ev, function() open(ev) end)
end
for _, ev in ipairs({ "run:end", "menu:enter", "gameplay:GAME_END_FAILED" }) do
    R.on(ev, function() reset(ev) end)
end
-- Between chapters and during cinematics the clocks stop.
for _, ev in ipairs({ "gameplay:GAME_END_NEXT_CHAPTER", "gameplay:GAME_END_SUCCESS",
                      "gameplay:CINE_START" }) do
    R.on(ev, function() paused = true end)
end
for _, ev in ipairs({ "gameplay:CINE_STOP", "gameplay:CINE_END" }) do
    R.on(ev, function() paused = false end)
end

-- ---------------------------------------------------------------------------
-- The board tick (background thread: timers + overlay only, no engine calls)
-- ---------------------------------------------------------------------------
local function clock(s)
    if not s then return "" end
    return ("%d:%02d"):format(s // 60, s % 60)
end

local function row_for(b)
    if b.result then
        return { bounty = (b.ok and "✔ " or "✘ ") .. b.title, progress = b.ok and 1 or 0,
                 count = "", time = "", reward = b.result, done = b.ok and true or false }
    end
    return { bounty = b.title, progress = b.progress / b.goal,
             count = ("%d/%d"):format(b.progress, b.goal), time = clock(b.left),
             reward = b.reward_text, done = false }
end

local function publish()
    if not (R.overlay and R.overlay.publish) then return end
    local rows = {}
    if boss then
        local r = row_for(boss)
        if not boss.result then r.bounty, r.time = "★ " .. r.bounty, "boss" end
        rows[#rows + 1] = r
    end
    for slot = 1, cfg.slots do
        if board[slot] then rows[#rows + 1] = row_for(board[slot]) end
    end
    if cfg.streak_bonus then
        local s = streak % STREAK_FOR_BONUS
        if streak > 0 and s == 0 then
            -- Just paid: a bare "0/3" here read as if the streak had been lost.
            rows[#rows + 1] = { bounty = ("✔ Streak x%d"):format(streak), progress = 1,
                                count = "", time = "", reward = "Paid: mystery item", done = true }
        else
            rows[#rows + 1] = { bounty = ("Streak %d/%d"):format(s, STREAK_FOR_BONUS),
                                progress = s / STREAK_FOR_BONUS, count = "", time = "",
                                reward = "mystery item", done = false }
        end
    end
    R.overlay.publish({ rows = rows, meta = {
        difficulty = R.config.get("difficulty", "standard"),
        completed = completed, failed = failed, streak = streak } })
end

R.schedule.every(1, function()
    if not active then return end
    for slot = 1, cfg.slots do
        local b = board[slot]
        if not b then
            post(slot)
        elseif b.result then
            b.ttl = b.ttl - 1
            if b.ttl <= 0 then post(slot, b.kind) end
        elseif not paused and b.left then
            b.left = b.left - 1
            if b.left <= 0 then finish(slot, b, false, "Time ran out") end
        end
    end
    if boss and boss.result then
        boss.ttl = boss.ttl - 1
        if boss.ttl <= 0 then boss = nil end
    end
    publish()
end)

R.schedule.every_main(0.5, drain)

R.on("ready", function()
    math.randomseed(os.time())
    R.log(("[Bounty] armed — %d slots, %s difficulty, streak bonus %s, boss bounty %s")
        :format(cfg.slots, R.config.get("difficulty", "standard"),
                cfg.streak_bonus and "on" or "off", cfg.boss_bounty and "on" or "off"))
end)
