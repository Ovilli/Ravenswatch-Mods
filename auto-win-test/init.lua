-- TEST — auto-completes each chapter. See manifest.toml.
local R = require "rsmm"

local TAG = "[auto-win-test] "
local DELAY = 8      -- seconds into a chapter before it is completed
local chapter = 0

-- MAP_GENERATION_DONE marks a live chapter; R.run only accepts an end while one
-- is live, and at most one end per chapter, so a late or duplicate call is
-- refused rather than landing on the next chapter.
R.on("gameplay:MAP_GENERATION_DONE", function()
    chapter = chapter + 1
    local n = chapter
    R.schedule.after_main(DELAY, function()
        R.log(TAG .. ("chapter %d: next_chapter() -> %s"):format(n, tostring(R.run.next_chapter())))
    end)
end)

R.on("run_start", function() chapter = 0 end)

-- What a win produced: the run result and any unlock the analytics bus reports.
R.on("*", function(ev, name)
    if type(name) ~= "string" then return end
    if name == "run_end" or name:find("^unlock_") or name == "gameplay:GAME_END_SUCCESS"
        or name == "gameplay:GAME_END_SUCCESS_SKIP_NEXT" or name == "gameplay:GAME_END_FAILED" then
        local parts = {}
        if type(ev) == "table" then
            for k, v in pairs(ev) do
                if k ~= "event" and k ~= "seq" and k ~= "source" and type(v) ~= "table" then
                    parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
                end
            end
            table.sort(parts)
        end
        R.log(TAG .. name .. " {" .. table.concat(parts, ", ") .. "}")
    end
end)

R.log(TAG .. "armed: each chapter completes " .. DELAY .. " s after it starts")
