-- Second Wind — one comeback per run.
--
-- The engine already has an event for "this hero is down but not out"
-- (HERO_DEATH_DOOR), and the revive flow is entirely the game's. This mod does
-- not touch that flow: it just heals you at the moment you go down and hands
-- you a short attack-power surge so the comeback feels like one.
--
-- Deliberately budgeted. A rescue every time removes the tension the game is
-- built around; one per run turns a death into a story.

local R = require "rsmm"

local TAG = "SecondWind"

local cfg = {
    rescues       = R.config.get("rescues_per_run", 1),
    heal          = R.config.get("heal_amount", 60),
    surge_power   = R.config.get("surge_attack_power", 30),
    surge_seconds = R.config.get("surge_seconds", 10),
}

-- Consent flag, not a probe (see Bloodlust). Whether the surge lands depends
-- on the hero being captured at rescue time, which is checked there.
R.stat.enable_writes()
local used = 0

local function rescue()
    if used >= cfg.rescues then return end

    -- R.combat needs the hero, which the loader captures at spawn. If capture
    -- is off (RSMM_ENABLE_HERO_CAPTURE) there is nothing to heal, so bail
    -- before burning the rescue — the player keeps it for a run where it works.
    if not R.entity.ready() then
        R.log("[SecondWind] hero not captured; rescue skipped "
              .. "(needs RSMM_ENABLE_HERO_CAPTURE=1)")
        return
    end

    -- R.hp is the real health (proven in game 2026-09-18). The old R.combat
    -- call this mod used moved dream shards, not health.
    if not R.hp.heal(cfg.heal) then
        R.log("[SecondWind] heal refused; rescue not consumed")
        return
    end
    used = used + 1

    if cfg.surge_power > 0 then
        -- Stat amounts are store units: displayed value / 100.
        R.stat.modify("attack_power", cfg.surge_power / 100, cfg.surge_seconds)
    end

    R.log(("[SecondWind] back up! +%d HP, +%d attack power for %ds (%d/%d used)")
        :format(cfg.heal, cfg.surge_power, cfg.surge_seconds, used, cfg.rescues))
end

-- Fires on the gameplay bus, i.e. the game's main thread — the only place an
-- engine-mutating call like heal/modify is safe.
R.on("gameplay:HERO_DEATH_DOOR", rescue)

-- Per-run state resets on EVERY boundary, not just run:start.
--
-- run:start is derived from the analytics firehose: rsmm.lua republishes it
-- when the raw `run_start` event arrives. If that bus is off, or the game uses
-- a name the SDK does not normalise, run:start simply never fires — and a mod
-- that only resets there carries the previous run's state forever. For Second
-- Wind that means one rescue per SESSION instead of per run; for the others it
-- means a streak or a counter that never clears.
--
-- Resetting on run:end and menu:enter as well means a new run begins clean as
-- long as ANY one of the three boundaries is observed. Resetting twice is
-- harmless; resetting never is not.
local function reset_run_state()
    used = 0
end

for _, boundary in ipairs({ "run:start", "run:end", "menu:enter" }) do
    R.on(boundary, reset_run_state)
end

R.on("ready", function()
    R.log(("[SecondWind] armed — %d rescue(s) per run, +%d HP and +%d attack "
           .. "power for %ds"):format(cfg.rescues, cfg.heal, cfg.surge_power,
           cfg.surge_seconds))
end)

-- Positive confirmation. The old boot-time note fired at "ready", which is the
-- main menu — there is never a hero at that point, so it printed on every
-- launch whether or not anything was wrong. Report when capture actually
-- lands, and only complain if a RUN has started and the hero still has not
-- shown up after a grace period.
R.on("hero:captured", function()
    R.log(("[%s] hero captured — effects are live"):format(TAG))
end)

-- Only nag about the SETTING when the setting is actually the problem.
--
-- The first version warned whenever no hero was captured 15s into a run, and a
-- playtest with the flag correctly enabled got told to go and enable it. Not
-- being captured yet is normal: the hero's HUD mirror is not populated until
-- the run is genuinely under way, and that took ~3 minutes in that session.
-- capture_enabled() separates "you need to change a setting" from "wait".
-- Nothing is logged in the second case because hero:captured already announces
-- it the moment it lands.
R.on("run:start", function()
    R.schedule.after(15, function()
        if R.entity.ready() then return end
        if not R.entity.capture_enabled() then
            R.log(("[%s] hero capture is OFF, so this mod cannot do anything. "
                   .. "Enable it in the desktop app's flags panel, or put "
                   .. "RSMM_ENABLE_HERO_CAPTURE=1 BEFORE %%command%% in the "
                   .. "Steam launch options."):format(TAG))
        end
    end)
end)

