-- Steamroller — a test harness for reaching a chapter transition fast.
--
-- This is not a content mod. Chapter-load crashes can only be reproduced by
-- GETTING to the load, and playing chapter one honestly costs six minutes a
-- try. This pins the offensive stats high and keeps you alive so a chapter
-- takes a couple of minutes, then gets deleted.
--
-- Everything here is a write to the LOCAL hero's value store through the SDK.
-- No engine pointer is handled by this file, so there is nothing here to crash
-- the game with — a failed write is refused by R.stat / R.combat and logged.

local R = require "rsmm"

-- Degrade against an SDK that predates exp. An old planted lib/ with a newer
-- mod is the normal state between updating a mod and running
-- `rsmm update-loader`, and a mod that HARD-ERRORS at load there does not
-- merely lose its readout -- it does not run at all, which costs the playtest
-- this harness exists to make cheap.
local exp = R.exp or {
    case    = function() end,
    observe = function() end,
    verdict = function(_, pass) return pass end,
    run     = function(_, _, fn) pcall(fn) end,
}

local TAG = "Steamroller"

local cfg = {
    attack     = R.config.get("attack_power", 4000),
    speed      = R.config.get("move_speed", 1.6),
    godmode    = R.config.get("godmode", true),
    heal_below = R.config.get("heal_below", 0.5),
}

-- Consent to the experimental stat-write path. NOT a capability probe: whether
-- a write can land depends on the hero being captured, which happens once a
-- run is under way — long after this line runs. (Treating the result as "can I
-- write?" is what disabled bloodlust for a whole session at boot.)
R.stat.enable_writes()

-- The two things that keep going wrong here, declared up front. Sessions ef4f
-- and 4b4f each burned a full chapter on "the mod did nothing", which was
-- really "the hero was never captured" and "nothing was ever pinned" -- both
-- invisible until somebody read the log afterwards. As cases they are on the
-- table the moment the run ends.
exp.case("stats_pinned", "did any stat pin actually land?")
exp.case("hero_captured", "was the hero ENTITY captured? (health top-up needs it; stats do not)")

-- R.stat works in STORE units, which are the displayed value / 100. Passing
-- the displayed number straight through asks for 100x what you meant.
local PINS = {
    attack_power = cfg.attack / 100,
    -- Displayed as a percentage, stored as a fraction: 1.0 = always crits.
    crit_chance  = 1.0,
    crit_damage  = 3.0,
    move_speed   = cfg.speed,
}

local pinned = false
-- How many stat pins actually landed. This doubles as the ONLY evidence that
-- the captured object really is a readable hero — see top_up().
local pins_ok = 0

-- Pin the stats once the hero exists. `stick` (not `set`) because the engine
-- rebuilds every stat from base+modifiers on the next recompute — a level-up
-- or an item pickup — and a plain set() is silently wiped by it. `stick`
-- re-asserts after each recompute, on the gameplay bus, i.e. the main thread.
-- Attempts since the last success, so a retry loop cannot spam the log or the
-- engine on every single gameplay event.
local pin_tries = 0

-- Attack power goes through the ENGINE as a real modifier, not stick(): the
-- in-run stat strip reads a cache the engine refreshes only when it folds a
-- modifier itself (a stick()-pinned 40 showed 0). R.stat.modify's default
-- route sends it as ADD_MODIFIER on the hero's bus, the game's own path —
-- counted once, shown on the strip, and carried into the next chapter like the
-- game's own upgrades (all proven 2026-09-19), so a chapter change does NOT
-- re-apply it; only a new run does. Never stick() this stat as well: the two
-- would fight.
--
-- Its own latch because the bus needs the hero's dispatcher, which only exists
-- once the hero has acted: the other stats can land first, and sharing their
-- latch would give up on attack for the whole run.
local attack_done = false
local function try_attack()
    if attack_done then return true end
    -- Latch BEFORE the call. Our own dispatch reaches this mod's R.on("*")
    -- handler synchronously, so latching on the return value let every nested
    -- handler call modify again: 99 deep and +99 attack in game (2026-09-19).
    attack_done = true
    if not R.stat.modify("attack_power", PINS.attack_power) then
        attack_done = false   -- genuinely refused (no dispatcher yet): retry later
    end
    return attack_done
end

local function pin()
    if pinned then try_attack(); return end
    -- DELIBERATELY NOT gated on R.entity.ready(). That is exactly "has the hero
    -- ENTITY been captured", and capture is the part that keeps failing — but
    -- R.stat does not need the entity any more. Its store hangs off the hero's
    -- value CONTEXT, which the loader publishes straight off the give handler,
    -- so stats can be pinned from the first item pickup even when no hero is
    -- ever captured. Session ef4f is why this comment exists: the give handler
    -- fired 8 times, the context was published, R.stat was ready to write — and
    -- this function returned at the ready() check without one attempt, so the
    -- mod did nothing for the whole run and logged not a single [rsmm.stat]
    -- line. Let R.stat be the one to say no.
    pin_tries = pin_tries + 1
    local ok = {}
    for name, value in pairs(PINS) do
        if name == "attack_power" and R.stat.modify then
            -- Applied by try_attack(), on its own latch — see there.
            if try_attack() then ok[#ok + 1] = name end
        elseif R.stat.stick(name, value) then
            ok[#ok + 1] = name
        end
    end
    if #ok == 0 then
        -- Nothing to write to yet (no captured hero AND no published context —
        -- the context arrives on the first pickup). Stay unlatched and retry.
        if pin_tries % 250 == 0 then
            R.log(("[%s] still nothing to pin to after %d attempts — waiting for "
                   .. "a hero capture or the first item pickup"):format(TAG, pin_tries))
        end
        return
    end
    pinned = true
    pins_ok = #ok
    exp.observe("stats_pinned", "landed", pins_ok)
    exp.observe("stats_pinned", "attempts", pin_tries)
    exp.verdict("stats_pinned", true,
                  pins_ok .. "/4 after " .. pin_tries .. " attempts: " .. table.concat(ok, ", "))
    R.log(("[%s] pinned %d/%d stats: %s"):format(
        TAG, pins_ok, 4, table.concat(ok, ", ")))
end

-- Health top-up. R.combat goes through Entity_ModifyHealth, the engine's own
-- committed path, rather than poking the HP field — a poked value is a cached
-- one and the next recompute takes it back.
--
-- Deliberately NOT a "set HP every frame" godmode: that fights the engine on
-- its own tick and hides whether damage is being applied at all. Topping up
-- past a threshold leaves the health bar readable, which matters when the
-- whole point is watching for a crash.
-- Latches the hero_captured verdict. MUST be declared above top_up(): a local
-- below the closure that reads it compiles to a global, which is nil forever.
local captured = false

local function top_up()
    -- This one DOES need the captured entity: R.combat goes through
    -- Entity_ModifyHealth, which dereferences the hero object itself. A value
    -- context has no HP fields, so unlike the stat pins there is nothing to
    -- fall back to here.
    if not cfg.godmode or not R.entity.ready() then return end
    -- First time through means the capture landed. Closed once: a verdict is
    -- flushed to disk, and this runs on every gameplay event.
    if not captured then
        captured = true
        exp.verdict("hero_captured", true, "capture landed")
    end
    -- REQUIRE a landed stat pin first. R.entity.hp() is a page-guarded read at
    -- a fixed offset with no check that the object is a hero, so on a wrong
    -- capture it returns plausible-looking floats and hp_frac() happily comes
    -- out under the threshold — after which R.combat hands that pointer to
    -- Entity_ModifyHealth and the engine owns the deref.
    --
    -- That is not hypothetical: session 8c4f adopted 0x3cb111a0 through the
    -- give-handler, logged "value store not found for this build — refusing"
    -- four times and "HP-FIELD SCAN ... no candidate pair found", and this
    -- function then crashed the game at Entity_ModifyHealth+0x45 on that exact
    -- pointer. The value-store lookup is the one gate that told the truth, so
    -- gate on it.
    if pins_ok == 0 then return end
    -- R.hp is the real health (proven in game 2026-09-18). It re-verifies the
    -- HitPoint component on every read and returns nil rather than guess, so a
    -- wrong capture cannot reach the engine through here. The old R.combat
    -- path this replaced moved dream shards, not health.
    local frac = R.hp.frac()
    if not frac or frac >= cfg.heal_below then return end
    local max = R.hp.max()
    if max then R.hp.set(max) end
end

-- DIAGNOSTIC: the in-run stat strip reads a CACHE (R.stat.cached), not the
-- store R.stat writes, and the engine refreshes it only when it folds a
-- modifier itself. With attack going through R.stat.modify the two should
-- move together (4000 on the strip); a store/cache split in this line means
-- that stopped being true. Logs once at pin, then on any change. Read-only;
-- skipped on an SDK that predates R.stat.cached.
local last_cached = false   -- false = never logged; nil is a real reading
local last_store  = false
local function report_stats()
    if not (pinned and R.stat.cached) then return end
    local cached = R.stat.cached("attack_power")
    local store = R.stat.get("attack_power")
    -- Log when EITHER side moves; they can move independently.
    if last_cached ~= false and cached == last_cached and store == last_store then return end
    local first = last_cached == false
    local what = first and "" or ((cached ~= last_cached and store ~= last_store) and "  <- STORE+CACHE CHANGED"
        or (cached ~= last_cached and "  <- CACHE CHANGED" or "  <- STORE CHANGED"))
    last_cached, last_store = cached, store
    exp.observe("stats_pinned", first and "cache_at_pin" or "cache_changed", cached)
    R.log(("[%s] attack_power: store=%s  cached=%s  (strip shows cached x100 = %s)%s"):format(
        TAG, tostring(R.stat.get("attack_power")), tostring(cached),
        cached and tostring(math.floor(cached * 100 + 0.5)) or "?",
        what))
end

-- Both of these MUTATE ENGINE STATE, so they may only run on the game's main
-- thread. The gameplay bus dispatches there; "tick" is the loader's background
-- thread and calling either from it is the documented way to crash the game
-- (see the loader thread model). Gating on ev.source is what keeps them apart.
-- Say so when the hero never arrives. Without this the mod logs "armed" and
-- then goes silent for the whole run, which reads as "the mod did nothing"
-- when what actually happened is that R.entity never captured a hero — a
-- pre-existing capture failure this mod only rides on. Session 4b4f burned a
-- full eight-minute chapter that way.
local seen_gameplay = 0
local warned = false
local QUIET_EVENTS = 200   -- a few seconds of normal combat traffic

R.on("*", function(ev)
    if not (ev and ev.source == "gameplay") then return end
    pin()
    top_up()
    report_stats()
    if not pinned and not warned then
        seen_gameplay = seen_gameplay + 1
        if seen_gameplay >= QUIET_EVENTS then
            warned = true
            exp.observe("stats_pinned", "quiet_events", seen_gameplay)
            exp.verdict("stats_pinned", false,
                          seen_gameplay .. " gameplay events and nothing pinned")
            R.log(("[%s] %d gameplay events in and nothing is pinned yet. Stats "
                   .. "need EITHER a captured hero or one item pickup (which "
                   .. "publishes the value context); health top-up needs the "
                   .. "capture specifically. Check the [rsmm.entity] lines above."
                   ):format(TAG, seen_gameplay))
        end
    end
end)

-- A new run reallocates the hero, so the old capture is stale and the pins
-- went with it. Re-pin against the new one rather than trusting the flag.
for _, boundary in ipairs({ "run:start", "run:end", "menu:enter" }) do
    R.on(boundary, function()
        -- pins_ok MUST be cleared with the latch. It is the sole evidence that
        -- the captured object is a readable hero, and top_up() hands that
        -- object to Entity_ModifyHealth on the strength of it. Leaving a count
        -- from the PREVIOUS run authorises a health write against a new,
        -- unverified capture — the 8c4f crash shape exactly. The mods spec
        -- caught this the moment pin() stopped latching unconditionally.
        pinned, pin_tries, pins_ok = false, 0, 0
        attack_done = false   -- a new RUN (not a new chapter) starts a new hero
        seen_gameplay, warned = 0, false
        last_cached, last_store = false, false
        -- `captured` is deliberately NOT reset with the rest. It latches a
        -- verdict, not a capability, and re-closing the same case on every run
        -- boundary would write to disk for no new information.
    end)
end

R.on("ready", function()
    R.log(("[%s] armed — attack %d, crit 100%%, speed x%.1f, top-up %s. "
           .. "TEST HARNESS: turn it off when you are done."):format(
        TAG, cfg.attack, cfg.speed, cfg.godmode and "on" or "off"))
end)
