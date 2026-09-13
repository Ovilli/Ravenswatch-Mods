-- Lucky Chests — chests sometimes pay out twice.
--
-- The game already knows how to hand you a duplicate of something you own:
-- DUPLICATE_RANDOM_MAGICAL_OBJECT (and the per-rarity variants) are real
-- gameplay events it fires itself. This mod does not invent an effect, it just
-- asks for one the engine already implements, on a chest roll.
--
-- That is why this is safe where a hand-rolled "give the player an item" would
-- not be: the engine picks the object, applies its own rules, and updates the
-- HUD, exactly as it does when a shrine grants a duplicate.

local R = require "rsmm"

local EVENT_FOR_RARITY = {
    any    = "DUPLICATE_RANDOM_MAGICAL_OBJECT",
    common = "DUPLICATE_RANDOM_COMMON_OBJECT",
    rare   = "DUPLICATE_RANDOM_RARE_OBJECT",
    epic   = "DUPLICATE_RANDOM_EPIC_OBJECT",
}

local cfg = {
    chance      = R.config.get("chance_percent", 20),
    rarity      = R.config.get("rarity", "any"),
    max_per_run = R.config.get("max_per_run", 0),
    pity        = R.config.get("pity_after", 6),
}

local event_name = EVENT_FOR_RARITY[cfg.rarity] or EVENT_FOR_RARITY.any
local granted, dry_streak = 0, 0

R.on("gameplay:OPEN_CHEST", function()
    if cfg.max_per_run > 0 and granted >= cfg.max_per_run then return end

    -- Pity. A flat 20% roll means a real run can end having opened six chests
    -- and seen the mod do nothing at all — which is exactly what happened in
    -- the first playtest — and the player has no way to tell that from the mod
    -- being broken. Guaranteeing the drop after a dry streak keeps the average
    -- close to the configured chance while removing the "is this even
    -- installed?" outcome.
    dry_streak = dry_streak + 1
    local forced = cfg.pity > 0 and dry_streak > cfg.pity
    if not forced and math.random(100) > cfg.chance then return end

    -- Duplicating needs something to duplicate. Asking on an empty loadout
    -- would spend the roll for nothing, so skip and leave the odds intact.
    if R.give.ready() and R.give.owned_count() == 0 then return end

    if R.emit("gameplay:" .. event_name) then
        granted = granted + 1
        R.log(("[LuckyChests] %s duplicated a %s object (%d this run)"):format(
            forced and "pity —" or "lucky!", cfg.rarity, granted))
        dry_streak = 0
    end
end)

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
    granted, dry_streak = 0, 0
end

for _, boundary in ipairs({ "run:start", "run:end", "menu:enter" }) do
    R.on(boundary, reset_run_state)
end

R.on("ready", function()
    -- Seed per session so two launches don't roll the same chest sequence.
    math.randomseed(os.time())
    R.log(("[LuckyChests] armed — %d%% chance per chest to duplicate a %s "
           .. "object%s%s"):format(cfg.chance, cfg.rarity,
                cfg.pity > 0 and (", guaranteed after %d dry"):format(cfg.pity) or "",
                cfg.max_per_run > 0 and (", max %d/run"):format(cfg.max_per_run) or ""))
end)
