-- Bloodlust — chain kills to stack a temporary attack-power frenzy.
--
-- Every Nth kill applies ONE timed attack-power modifier. Stacks are just
-- overlapping modifiers, so they fade out one at a time on their own timers:
-- keep killing and you stay at full frenzy, stop and you cool down. There is
-- no bookkeeping to get wrong and nothing to clean up on death or run end.
--
-- Why R.stat.modify and not R.stat.set: set() pokes the cached value and the
-- engine's next recompute wipes it. modify() inserts a real engine modifier
-- into the value store, so it COMPOSES with the game's own item and talent
-- modifiers instead of fighting them, and it expires by itself.

local R = require "rsmm"

local TAG = "Bloodlust"

local cfg = {
    kills_per_stack = R.config.get("kills_per_stack", 3),
    power_per_stack = R.config.get("attack_power_per_stack", 6),
    max_stacks      = R.config.get("max_stacks", 5),
    stack_seconds   = R.config.get("stack_seconds", 8),
    lose_on_hit     = R.config.get("stacks_lost_on_hit", 1),
    announce        = R.config.get("announce", true),
}

-- Opt in to the experimental stat write path. This is a CONSENT flag, not a
-- capability probe: whether a write can land depends on the hero having been
-- captured, which happens when a run starts, long after this line runs. An
-- earlier version treated the result as "can I write?" and disabled the mod
-- for the whole session at boot.
R.stat.enable_writes()

local kills, live_stacks = 0, 0

local function expire_one()
    if live_stacks > 0 then live_stacks = live_stacks - 1 end
end

local function on_kill()
    kills = kills + 1
    if kills % cfg.kills_per_stack ~= 0 then return end
    if live_stacks >= cfg.max_stacks then return end
    -- Nothing to buff without a captured hero. Checking here rather than
    -- letting R.stat.modify refuse keeps this off the engine entirely when
    -- capture is off, instead of asking once every few kills for a whole run.
    if not R.entity.ready() then return end

    -- R.stat units are store units: displayed value / 100.
    local amount = cfg.power_per_stack / 100
    if not R.stat.modify("attack_power", amount, cfg.stack_seconds) then
        return
    end
    live_stacks = live_stacks + 1
    if cfg.announce then
        R.log(("[Bloodlust] %d/%d stacks (+%d attack power for %ds)"):format(
            live_stacks, cfg.max_stacks, cfg.power_per_stack, cfg.stack_seconds))
    end
    -- Mirror the engine's own expiry so the stack count stays honest. The
    -- modifier expires whether or not this fires; this only keeps us from
    -- refusing to add a new stack after an old one is already gone.
    R.schedule.after(cfg.stack_seconds, expire_one)
end

-- ENEMY_KILLED comes off the gameplay bus, which dispatches on the game's
-- MAIN thread — which is exactly where an engine-mutating call like
-- R.stat.modify has to run. Handling it here needs no R.schedule.next_main.
R.on("gameplay:ENEMY_KILLED", on_kill)

-- Taking a hit costs progress. Without this the frenzy is pure accumulation —
-- you get it for killing and nothing ever threatens it, which makes the whole
-- mechanic a flat damage buff on a timer. Losing ground when you get hit is
-- what turns it into a reason to play differently.
--
-- "You got hit" comes from R.damage, not from the NETWORK_DAMAGE payload.
--
-- This used to subscribe to gameplay:NETWORK_DAMAGE and compare its
-- `target_entity` field against the hero pointer. That test could never
-- succeed: the field was mislabelled (it is a per-hit HANDLE, not the target —
-- corrected 2026-08-15, see hook_events.cpp), and the event does not fire at
-- all in single player, where the engine applies damage directly. So the
-- whole mechanic was silently dead.
--
-- R.damage watches the local attack resolver, which every hit on this machine
-- goes through — solo included — and publishes a "taken" hit for the local
-- hero. That is the signal this wants.
if cfg.lose_on_hit > 0 then
    R.damage.enable()
    R.damage.on(function(hit)
        if hit.kind ~= "taken" or not hit.is_local then return end
        if kills == 0 and live_stacks == 0 then return end

        -- Reset progress toward the next stack too: a hit should cost the
        -- partial streak, not just finished stacks.
        kills = 0
        if live_stacks > 0 then
            live_stacks = math.max(0, live_stacks - cfg.lose_on_hit)
            if cfg.announce then
                R.log(("[Bloodlust] hit! down to %d stack(s)"):format(live_stacks))
            end
        end
    end)
end

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
    kills, live_stacks = 0, 0
end

for _, boundary in ipairs({ "run:start", "run:end", "menu:enter" }) do
    R.on(boundary, reset_run_state)
end

R.on("ready", function()
    R.log(("[Bloodlust] armed — every %d kills = +%d attack power for %ds, "
           .. "up to %d stacks"):format(cfg.kills_per_stack,
           cfg.power_per_stack, cfg.stack_seconds, cfg.max_stacks))
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

