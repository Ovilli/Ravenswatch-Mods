-- Raven Chronicle — a career log that outlives the session.
--
-- Ravenswatch forgets you between runs. This remembers: how many things you
-- have killed across every run you have ever played, how many bosses fell, how
-- many chests you opened, how often you went down.
--
-- It is also the safest possible mod, and deliberately so — a worked example
-- of the read-only half of the event bus. It subscribes, it counts, it writes
-- to its own key-value store. It never calls into the engine, so there is no
-- main-thread rule to obey, no capture flag to enable, and nothing it can
-- break. If you want to see what the bus is actually doing, enable this one.

local R = require "rsmm"

local cfg = {
    report_on_menu    = R.config.get("report_on_menu", true),
    report_on_run_end = R.config.get("report_on_run_end", true),
}

-- gameplay event -> the counter it feeds. Lifetime totals live in R.kv (which
-- persists to the mod's state file); the run column is rebuilt each run.
local TRACKED = {
    ENEMY_KILLED        = "kills",
    BOSS_DEFEATED       = "bosses",
    OPEN_CHEST          = "chests",
    CHOOSE_MELODY       = "melodies",
    HERO_DEATH_DOOR     = "downs",
    HERO_REVIVE         = "revives",
    GAIN_DREAM_SHARDS   = "shard_pickups",
    USE_HEAL_FOUNTAIN   = "fountains",
}

local ORDER = { "kills", "bosses", "chests", "melodies", "downs", "revives",
                "shard_pickups", "fountains" }

local run = {}

local function bump(field)
    run[field] = (run[field] or 0) + 1
    R.kv.inc("total_" .. field, 1)
end

for event, field in pairs(TRACKED) do
    R.on("gameplay:" .. event, function() bump(field) end)
end

local function line(label, tbl, prefix)
    local parts = {}
    for _, f in ipairs(ORDER) do
        local v = tbl[prefix and (prefix .. f) or f]
        if v and v > 0 then parts[#parts + 1] = ("%s %d"):format(f, v) end
    end
    if #parts == 0 then return nil end
    return ("[Chronicle] %s: %s"):format(label, table.concat(parts, ", "))
end

-- Per-run state clears on EVERY boundary, not just run:start. run:start is
-- derived from the analytics firehose, so if that bus is off or the game uses
-- a name the SDK does not normalise, it never fires and the "this run" column
-- would keep accumulating across runs — and every run after the first would
-- look like a new record.
--
-- run:end clears too, but only AFTER the report below has read the totals, so
-- the reset lives at the end of that handler rather than in this loop.
R.on("run:start", function()
    run = {}
    R.kv.inc("total_runs", 1)
end)
R.on("menu:enter", function() run = {} end)

-- Personal bests. Lifetime totals only ever go up, so they stop being
-- interesting after a few runs; a record you can beat is the part worth
-- reading. Checked at the run boundary against the same KV store.
local RECORDS = { kills = "most kills", bosses = "most bosses",
                  chests = "most chests" }

local function check_records()
    local beaten = {}
    for field, label in pairs(RECORDS) do
        local got = run[field] or 0
        if got > 0 and got > R.kv.get("best_" .. field, 0) then
            R.kv.set("best_" .. field, got)
            beaten[#beaten + 1] = ("%s %d"):format(label, got)
        end
    end
    return beaten
end

R.on("run:end", function()
    if cfg.report_on_run_end then
        local msg = line("this run", run)
        R.log(msg or "[Chronicle] this run: nothing recorded")
    end
    local beaten = check_records()
    if #beaten > 0 then
        R.log("[Chronicle] NEW RECORD — " .. table.concat(beaten, ", "))
    end
    -- Persist here rather than on every kill: the bus is hot, and a run
    -- boundary is the natural place to pay for a write.
    R.kv.save()
    run = {}   -- AFTER reporting: the next run starts from zero even if
               -- run:start never fires for it.
end)

R.on("menu:enter", function()
    if not cfg.report_on_menu then return end
    local totals = R.kv.all()
    R.log(("[Chronicle] %d run(s) played"):format(totals.total_runs or 0))
    local msg = line("lifetime", totals, "total_")
    if msg then R.log(msg) end
    local best = line("records", totals, "best_")
    if best then R.log(best) end
end)

-- Flush on the way out so a session's last run is not lost.
R.on("exit", function() R.kv.save(true) end)

R.on("ready", function()
    R.log(("[Chronicle] watching %d event types — read-only, safe in co-op")
        :format(#ORDER))
end)
