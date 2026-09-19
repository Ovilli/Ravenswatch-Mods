-- REWARD PROOF — does the level's reward roll honour an edited reward def?
--
-- Settled already (session 774f): the override is LOADED — R.rewards found
-- Camp_Rewards_Dark_Hills_Update5 live in its edited shape and no vanilla
-- copy of it. Only the LiveOps5 versiondef references that def, so it is the
-- one Dark Hills rolls from. What is left is whether the ROLL obeys its
-- counts, which a ban can never show (vanilla already rolls 0..1 astrolabs).
-- So this forces the astrolab type to exactly 3 and counts what the level
-- actually placed:
--
--   Astrolab == 3     -> the roll honoured the def (PASS)
--   Astrolab <= 1     -> vanilla behaviour, the count edit was ignored (FAIL)
--
-- Two readings:
--   1. R.rewards — the live def's shape, expected (1,2,2)(3,4,3)(3,3,3)(1,3,1)
--   2. R.spawn.entities — every entity the scene spawner placed, tallied by
--      template name. If reward entities are not on that list the tally says
--      0 across the board, which reads as "wrong list", not as a FAIL.
local R = require "rsmm"

local OURS = "(1,2,2)(3,4,3)(3,3,3)(1,3,1)"
local TAG = "[reward-proof]"
local WATCH = { "Astrolab", "Basic_Chest", "DreamCrystal", "Baba_Yaga_Eye" }

local function shape_check(when)
    if not R.rewards then
        R.log(TAG .. " R.rewards missing on this SDK")
        return
    end
    local hits = 0
    for _, e in ipairs(R.rewards.defs()) do
        if R.rewards.format(e.shape) == OURS then hits = hits + 1 end
    end
    R.log(("%s %s: edited def live = %s"):format(TAG, when,
        hits > 0 and "yes" or "NO (override not loaded)"))
end

local names = {}   -- template -> name (or false), so each is resolved once
local histo_done = false
local function tally(when)
    if not (R.spawn and R.spawn.entities and R.interact and R.interact.name) then
        R.log(TAG .. " R.spawn missing on this SDK — cannot count the scene")
        return
    end
    local rows = R.spawn.entities()
    local counts, other = {}, 0
    for _, w in ipairs(WATCH) do counts[w] = 0 end
    for _, row in ipairs(rows) do
        -- R.interact.name reads the entity's own template name (entity+0x28
        -- -> settings -> resource name), proven on live entities. The older
        -- R.spawn.name_of string-walk named 0 of 437 on this build.
        local n = names[row.template]
        if n == nil then
            n = R.interact.name(row.entity) or false
            names[row.template] = n
        end
        local hit = false
        if n then
            for _, w in ipairs(WATCH) do
                if n:find(w, 1, true) then counts[w] = counts[w] + 1; hit = true; break end
            end
        end
        if not hit then other = other + 1 end
    end
    local a = counts.Astrolab
    -- Which chapter: reward entities carry it in their name
    -- (Dark_Hills_Astrolab_T1, Storm_Island_Basic_Chest_T3 ...). The edit is
    -- Dark Hills only; any other chapter is an unedited baseline sample.
    local dh, other_ch = 0, 0
    for _, n in pairs(names) do
        if n then
            if n:find("Dark_Hills_", 1, true) then dh = dh + 1
            elseif n:find("Storm_Island_", 1, true) or n:find("Avalon_", 1, true) then
                other_ch = other_ch + 1 end
        end
    end
    local v
    if dh == 0 and other_ch > 0 then
        v = "not Dark Hills — unedited baseline (vanilla astrolabs 0..1)"
    elseif #rows == 0 then
        v = "NO SCENE (hero not captured yet?)"
    elseif a == 3 then
        v = "PASS — the roll placed exactly the edited count"
    elseif a <= 1 and (counts.Basic_Chest + counts.DreamCrystal) > 0 then
        v = "FAIL — vanilla-range astrolabs while other rewards are visible"
    elseif a == 0 and counts.Basic_Chest == 0 and counts.DreamCrystal == 0 then
        v = "UNKNOWN — no reward entity on the scene list at all (wrong list?)"
    else
        v = "INCONCLUSIVE — astrolabs = " .. a
    end
    -- What IS on the list: without this a zero tally cannot tell "rewards are
    -- elsewhere" from "names do not resolve".
    if not histo_done then
        histo_done = true
        local by, unnamed = {}, 0
        for _, row in ipairs(rows) do
            local n = names[row.template]
            if n then
                local short = n:match("([^\\/]+)$") or n
                by[short] = (by[short] or 0) + 1
            else
                unnamed = unnamed + 1
            end
        end
        local list = {}
        for k, c in pairs(by) do list[#list + 1] = { k, c } end
        table.sort(list, function(x, y) return x[2] > y[2] end)
        R.log(("%s scene list: %d named template(s), %d unnamed entit(ies)")
              :format(TAG, #list, unnamed))
        for i = 1, math.min(#list, 40) do
            R.log(("%s   %4d  %s"):format(TAG, list[i][2], list[i][1]))
        end
    end
    R.log(("%s %s: scene %d entities — astrolab %d, chest %d, crystal %d, eye %d, other %d -> %s")
          :format(TAG, when, #rows, a, counts.Basic_Chest, counts.DreamCrystal,
                  counts.Baba_Yaga_Eye, other, v))
end

R.on("run:start", function()
    shape_check("run start")
    R.schedule.after(15, function() tally("run start +15s") end)
    R.schedule.after(60, function() tally("run start +60s") end)
end)

R.log(TAG .. " armed — start a Dark Hills run, then: rsmm log --grep reward-proof")
