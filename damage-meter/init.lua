-- Damage Meter — who is carrying the run?
--
-- Boards every hero the engine attributes damage to, and reports damage dealt,
-- share of the team total, and rolling DPS. All of the engine work lives in
-- the SDK (R.damage): this mod decides WHEN to report and WHERE the numbers
-- go, which is the only part a player wants to change.
--
-- Three places to read the board, all fed by the snapshot this mod persists
-- once a second (the game gives a mod nowhere to draw a meter):
--   * the desktop app's OVERLAY window — declared by the [overlay] block in
--     this mod's manifest, drawn by the client
--   * `rsmm overlay damage-meter --watch` — the same board in a terminal
--   * the loader log — `rsmm log -f --grep damage-meter`
--
-- MULTIPLAYER, honestly: a peer can only count what its own machine sees. The
-- host owns the enemies, so the host's board is the complete one. On a client
-- you always get your own damage right, plus whatever the owner replicates.
-- Every peer can run the meter; nothing about it is networked.

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

-- No log TAG here on purpose: the loader already prefixes every R.log line with
-- `[<mod id>] `, so a hand-written "[damage-meter]" produced
-- `[damage-meter] [damage-meter] ...` on every one of the thousands of lines a
-- hit-logging session writes.

-- The scenery filter lives in the SDK, which ships with the LOADER, not with
-- this mod — so a player on an older loader gets this init.lua against an SDK
-- that has no R.damage.ignore_scenery. Reading through these two shims instead
-- of calling directly means that player loses the filter and keeps the meter,
-- rather than losing both to `attempt to call a nil value`.
local function counts_enemies_only()
    local f = R.damage.ignore_scenery
    return f ~= nil and f() or false
end

local function scenery_total()
    local f = R.damage.scenery_total
    return f and f() or 0
end

local cfg = {
    report   = R.config.get("report_seconds", 15),
    snapshot = R.config.get("snapshot_seconds", 1),
    window   = R.config.get("window_seconds", 10),
    quiet    = R.config.get("quiet_when_idle", true),
    hits     = R.config.get("log_hits", false),
    -- Damage dealt to destructible props (fences, jars, dream-shard nodes)
    -- lands on the board like anything else, because the ENGINE counts it —
    -- its own end-screen total does. ON by default anyway: a prop takes a flat
    -- 1.0 per hit, so counting it inflates HIT COUNTS and DPS far more than it
    -- inflates damage, and "who is carrying the fight" is the question this
    -- mod exists to answer. Confirmed in a 5-player run (2026-08-17): enemies
    -- carry an EnemyController component, props carry none. Set false to match
    -- the game's own end-screen total instead.
    enemies_only = R.config.get("ignore_scenery", true),
    -- Diagnostic for the enemy test: what were the first few things hit? Off
    -- now that the classification is confirmed; turn it on if a game patch
    -- makes the board look wrong.
    probe    = R.config.get("probe_victims", false),
}

-- Fixed names by join order, for people who would rather read "Ada" than
-- "Player 2". Blank means "leave it automatic".
local names = {}
for slot = 1, 4 do
    local n = R.config.get("player_" .. slot, "")
    if type(n) == "string" and n ~= "" then names[slot] = n end
end

R.damage.enable{ window = cfg.window, names = names,
                 ignore_scenery = cfg.enemies_only, probe = cfg.probe,
                 -- Off by default: an unidentified row says "Player N" rather
                 -- than wearing a name that might belong to someone else. Turn
                 -- it on to have leftover lobby names handed out in join order;
                 -- every such row prints with a trailing "?".
                 guess_names = R.config.get("guess_names", true),
                 identity_hunt = R.config.get("identity_hunt", false),
                 -- The targeted scan that puts REAL names on ally rows. It is
                 -- bounded (it stands down once a sweep of the roster has
                 -- named nobody), but it reads memory in the background while
                 -- it runs. Turn it off if you feel it: the board keeps its
                 -- lobby names, they just stay marked "?" — and player_1..4
                 -- above give names that are never guesses.
                 identity_scan = R.config.get("identity_scan", true),
                 -- Board everyone in the lobby, not only the players who have
                 -- already dealt damage. A row is otherwise created on a
                 -- player's FIRST counted hit, so a support is missing from the
                 -- scoreboard until they land one — session 104f's healer did
                 -- not appear until 110s into a 165s chapter, which reads as
                 -- the meter losing a player rather than as an honest zero.
                 roster_rows = R.config.get("roster_rows", true) }

if cfg.hits then
    R.damage.on(function(hit)
        R.log(("%s %s %.1f (%s)"):format(
            hit.label, hit.kind == "taken" and "took" or "dealt",
            hit.amount, hit.source))
    end)
end

-- The scoreboard, as a single line per player. Damage is rounded: the engine's
-- values are floats and nobody reads three decimal places of a damage total.
--
-- Two columns say "I don't know" rather than printing a zero that looks like a
-- measurement, because both happened in the 2026-08-18 co-op log and both read
-- as bugs in the meter:
--   * `taken` is only observable for players this machine owns, so every ALLY
--     read exactly 0 for a 55-minute run. Printed as "-" now.
--   * a victim the SDK's scenery filter could not classify is still counted
--     (never drop a player's damage on a bad read), so a family of unreadable
--     props lands on the board as carry damage. `?N` is how many of the row's
--     hits rest on that assumption — a big number beside a small damage total
--     is prop chip damage, not carry.
local function board_lines()
    local rows = R.damage.board()
    if #rows == 0 then return nil end
    local out = {}
    for i, row in ipairs(rows) do
        -- Prop damage is reported, never silently dropped: a player who spent
        -- an ultimate on a fence should be able to see where it went.
        local props = (row.scenery or 0) > 0
            and ("  (+%.0f into props)"):format(row.scenery) or ""
        -- Older loader, newer mod: an SDK without these keys prints the board
        -- it always did (same shim reasoning as counts_enemies_only above).
        local unclassified = (row.unknown_hits or 0) > 0
            and ("  ?%d unclassified"):format(row.unknown_hits) or ""
        local taken = row.taken_known == false and "        -"
            or ("%9.0f"):format(row.taken)
        -- A name the SDK INFERRED (nobody's hero id matched, but only one row
        -- and one lobby name were left over) says so. The board used to print
        -- guessed names exactly like measured ones, which is how a co-op run
        -- reported every ally's damage under the wrong player.
        local label = row.label_guess and (row.label .. " ?") or row.label
        out[#out + 1] = ("%d. %-12s %9.0f dmg  %5.1f%%  %7.1f dps  "
                         .. "%5d hits  %s taken%s%s%s"):format(
            i, label, row.dealt, row.share * 100, row.dps,
            row.hits, taken, props, unclassified,
            row.is_local and "  <- you" or "")
    end
    return out
end

-- Publish the board for the client to draw.
--
-- The overlay's SHAPE (title, columns, sorting) is declared in this mod's
-- manifest `[overlay]` block; this only hands over the live rows. So the mod
-- owns both what its HUD says and what it looks like, without shipping any
-- code to the desktop app.
local function top_type(by_type)
    local best_name, best_val = "", -1
    for name, value in pairs(by_type or {}) do
        if value > best_val then best_name, best_val = name, value end
    end
    return best_name
end

local function publish(rows, total)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            -- Same "?" as the text board: the overlay client renders columns
            -- generically, so an inferred name has to carry its own mark.
            label    = row.label_guess and (tostring(row.label) .. " ?")
                        or tostring(row.label),
            dealt    = row.dealt,
            taken    = row.taken,
            hits     = row.hits,
            dps      = row.dps,
            share    = row.share,
            pct      = row.share,
            best     = row.best,
            ability  = top_type(row.by_type),
            scenery  = row.scenery,
            -- Both "I don't know" signals reach the overlay too, so the HUD is
            -- not the one place still printing a confident zero.
            unknown_hits = row.unknown_hits,
            taken_known  = row.taken_known,
            -- In the lobby but has not dealt damage yet. The HUD can say
            -- "waiting" instead of showing a 0 that looks like a measurement.
            pending  = row.pending,
            is_local = row.is_local,
        }
    end
    R.overlay.publish{
        rows = out,
        meta = { total = math.floor(total + 0.5), window = cfg.window,
                 sources = R.damage.mode(),
                 enemies_only = counts_enemies_only(),
                 scenery = math.floor(scenery_total() + 0.5) },
    }
end

local last_total = -1
local last_snapshot = -1

-- The board is a LIVE ranking: the snapshot is refreshed every second (cheap —
-- a few hundred bytes through a temp-file rename) so the overlay and
-- `rsmm overlay --watch` re-order themselves as the fight moves, while the
-- chattier log report stays on its own slower cadence.
local function snapshot()
    local total = R.damage.total()
    if total == last_snapshot then return end
    last_snapshot = total
    publish(R.damage.board(), total)
end

local function report(force)
    local rows = R.damage.board()
    local total = R.damage.total()
    if #rows == 0 then return end
    -- Nothing happened since the last report: in a lull (menus, walking
    -- between fights) repeating the same board every 15s just buries the rest
    -- of the log.
    if cfg.quiet and not force and total == last_total then return end
    last_total = total
    for _, line in ipairs(board_lines() or {}) do R.log(line) end
    publish(rows, total)
    last_snapshot = total
end

if cfg.report > 0 then
    R.schedule.every(cfg.report, function() report(false) end)
end
if cfg.snapshot > 0 then
    R.schedule.every(cfg.snapshot, snapshot)
end

-- The two things about this mod that are still unproven in a real lobby, and
-- that only a co-op run can answer. Closed at the run boundary, off the final
-- board, because that is the one moment every ally has certainly been seen.
exp.case("allies_tracked", "does the board carry ALL players, not just you?")
exp.case("names_measured", "does an ally row get a MEASURED name rather than a guess?")

local function record_experiments(rows)
    exp.observe("allies_tracked", "rows", #rows)
    exp.observe("allies_tracked", "hook", tostring(R.damage.tracks_allies()))
    exp.verdict("allies_tracked", #rows > 1,
                  #rows .. " row(s) on the final board")

    -- `label_guess` is the SDK saying "nobody's id matched; this name is the
    -- one left over". A guessed name on an ally row is exactly the failure the
    -- gamertag sweep was meant to end, so a guess is NOT a pass.
    local measured, guessed = 0, 0
    for _, row in ipairs(rows) do
        if not row.is_local then
            if row.label_guess then guessed = guessed + 1
            elseif row.label and row.label ~= "" and row.label ~= "?" then
                measured = measured + 1
            end
        end
    end
    exp.observe("names_measured", "measured", measured)
    exp.observe("names_measured", "guessed", guessed)
    if #rows > 1 then
        exp.verdict("names_measured", measured > 0,
                      measured .. " measured, " .. guessed .. " guessed")
    end
    -- Solo: left open. One row proves nothing either way, and a FAIL here would
    -- read as "the join is broken" when nothing was ever tested.
end

-- Per-run scores. Report the final board FIRST, then clear — a run's last
-- fight is the one people argue about.
local function finish_and_reset()
    report(true)
    record_experiments(R.damage.board())
    R.damage.reset()
    last_total, last_snapshot = -1, -1
    R.overlay.clear()
end

R.on("run:end", finish_and_reset)
R.on("run:start", function()
    R.damage.reset()
    last_total, last_snapshot = -1, -1
    R.overlay.clear()
end)

R.on("ready", function()
    R.log(("armed — report every %ds, snapshot every %ds, %ds DPS window, "
           .. "sources: %s, counting %s"):format(
              cfg.report, cfg.snapshot, cfg.window, R.damage.mode(),
              counts_enemies_only() and "enemy damage only"
                  or "everything the game counts (props included)"))
    -- A DPS window SHORTER than the report interval leaves a blind gap: a
    -- player who stopped attacking just before the report reads 0.0 dps on the
    -- same line that shows their damage climbing, which reads as a broken
    -- column rather than a stale one.
    if cfg.report > 0 and cfg.window < cfg.report then
        R.log(("note: the %ds DPS window is shorter than the %ds report "
               .. "interval, so a report can show 0.0 dps for a player who was "
               .. "fighting during it — set window_seconds = %d to close the gap")
              :format(cfg.window, cfg.report, cfg.report))
    end
    if not R.damage.tracks_allies() then
        R.log("the engine's per-hero damage hook is unavailable on this game "
              .. "build — ally damage will only be counted where the game "
              .. "replicates it to this machine (update the pattern DB with "
              .. "`rsmm update-data`)")
    end
end)
