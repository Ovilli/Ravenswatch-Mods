-- Chapter Timer: a day/night timer per chapter.
--
-- Every chapter load copies the game's day/night settings into that chapter's
-- clock (see R.daynight). So the values for chapter N+1 are written the
-- moment chapter N ends, and chapter 1's at load and after every run, and the
-- engine builds the next clock from them -- boss warning, modifiers and all.
--
-- The chapter in progress keeps the timer it started with; a config change
-- applies from the next chapter.

local R = require "rsmm"

local TAG = "[chapter-timer]"
local CHAPTERS = 4                       -- a later chapter reuses chapter 4's
local DEFAULT = { day = 180.0, night = 180.0, half_cycles = 6, overtime = 180.0 }

local chapter = 1                        -- the chapter that loads NEXT

local function values(n)
    n = math.min(math.max(n, 1), CHAPTERS)
    local t = {}
    for key, d in pairs(DEFAULT) do
        t[key] = R.config.get(("ch%d_%s"):format(n, key), d)
    end
    t.half_cycles = math.floor(t.half_cycles + 0.5)
    return t
end

local function apply(n, why)
    if not R.daynight then
        R.log(TAG, "this loader has no R.daynight -- run `rsmm update-loader`")
        return false
    end
    local t = values(n)
    local ok, err = R.daynight.set(t)
    if not ok then
        R.log(TAG, ("chapter %d: NOT applied (%s): %s"):format(n, why, tostring(err)))
        return false
    end
    R.log(TAG, ("chapter %d set (%s): %s"):format(n, why, R.daynight.describe()))
    return true
end

-- The proof: what the engine's clock for THIS chapter actually runs on, next
-- to what was written for it. "Day duration" etc. are the clock's own values,
-- pushed into the scene by the day/night component every frame.
local function report()
    if not R.config.get("verbose", true) or not (R.game and R.game.get) then return end
    local want = values(chapter)
    local got = {
        day = R.game.get("day_duration"),
        night = R.game.get("night_duration"),
        boss = R.game.get("boss_sleep_duration"),
        ch = R.game.get("current_chapter"),
    }
    local expect_boss = R.daynight and R.daynight.boss_time(want) or nil
    local match = got.day and math.abs(got.day - want.day) < 0.01
                  and got.night and math.abs(got.night - want.night) < 0.01
    R.log(TAG, ("chapter %d started (engine chapter index %s): clock day=%s night=%s "
                .. "boss_sleep=%s | set day=%g night=%g boss=%s -> %s")
          :format(chapter, tostring(got.ch), tostring(got.day), tostring(got.night),
                  tostring(got.boss), want.day, want.night, tostring(expect_boss),
                  match and "MATCH" or "MISMATCH (or not readable yet)"))
end

local function new_run(why)
    chapter = 1
    apply(1, why)
end

-- Ready at load: the settings section exists from boot, so chapter 1 of the
-- first run is covered before it loads.
R.on("ready", function() new_run("mod load") end)

-- Chapter N ended: the next load builds chapter N+1's clock.
R.on("gameplay:GAME_END_NEXT_CHAPTER", function()
    chapter = chapter + 1
    apply(chapter, "chapter " .. (chapter - 1) .. " ended")
end)

R.on("gameplay:MAP_GENERATION_DONE", function()
    -- A beat later: the clock pushes its values on its first frame.
    R.schedule.after(3, report)
end)

-- Run boundaries: the next run starts from chapter 1 again. NOT on
-- GAME_END_SUCCESS -- that fires at every chapter change too, just before
-- GAME_END_NEXT_CHAPTER (Sky's 2026-10-07 log), so resetting there would give
-- every chapter after the second chapter 2's timer.
R.on("run:start", function() new_run("run started") end)
R.on("run:end", function() new_run("run ended") end)
R.on("gameplay:GAME_END_FAILED", function() new_run("run lost") end)

-- A config edit while playing: re-apply what the NEXT chapter will use.
for n = 1, CHAPTERS do
    for key in pairs(DEFAULT) do
        R.config.on_change(("ch%d_%s"):format(n, key), function()
            if n == math.min(chapter, CHAPTERS) then apply(chapter, "config changed") end
        end)
    end
end
