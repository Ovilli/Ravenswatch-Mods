-- Jack (from scratch): button probe, TEMPORARY.
--
-- His buttons froze in one pose in the 2026-11-08 playtests. Once his hero is
-- live this logs, for three minutes:
--   * the starting bytes of his ability states, clip selectors and animatics,
--     then every byte that flips while you play (R.debug.watch_components);
--   * every ability / attack / animation event on the gameplay bus, with the
--     time, so each button press is visible (an ability whose timeline runs
--     sends its ABILITY_EXIT there).
-- Press each button once, a few seconds apart, then quit. Remove this file
-- once the buttons work.

local R = require "rsmm"

local TAG = "[jack-probe]"
local started, t0 = false, nil
local seen = {}

local function now() return t0 and (os.clock() - t0) or 0 end

R.on_match("^gameplay:", function(_, name)
    if not started or now() > 180 then return end
    local ev = name:sub(10)
    if not (ev:find("ABILIT") or ev:find("ATTACK") or ev:find("ANIM") or ev:find("SKILL")
            or ev:find("DASH") or ev:find("ULTI") or ev:find("EXIT") or ev:find("CAST")) then
        return
    end
    local t = now()
    if seen[ev] and t - seen[ev] < 0.25 then return end   -- one line per burst
    seen[ev] = t
    R.log(TAG, string.format("t=%.2f event %s", t, ev))
end)

R.schedule.every(1.0, function()
    if started or not (R.entity and R.entity.ready and R.entity.ready()) then return end
    if not (R.debug and R.debug.watch_components) then
        R.log(TAG, "this loader has no R.debug.watch_components -- run `rsmm install-loader`")
        started = true
        return
    end
    started, t0 = true, os.clock()
    R.log(TAG, "hero live: probing for 180 s -- press each button once, a few seconds apart")
    -- Round 3: the selectors fire on a press; the animatic never changed in
    -- 0x80 bytes. Watch every clip and animatic wide, the ones that DO play
    -- (dash, hit reaction, idle, move) as the reference.
    local function w(pat, label) R.debug.watch_components(pat, { label = label, seconds = 180, len = 0x140, baseline = 0x140 }) end
    -- Round 4: the basic attack is now a combo (combo -> step states -> clips
    -- -> animatics). Watch every piece of it, the dash as the reference.
    w("^Attack Ability Combo$", "jack-combo")
    w("^State Attack Ability", "jack-attack")       -- the state and its steps
    w("^Attack Ability Clip Step", "jack-clip")
    w("^Attack Ability Anim Step", "jack-anim")
    w("^Dash Ability A?n?i?m?$", "jack-dash")
    w("Anim Player", "jack-player")
end)
