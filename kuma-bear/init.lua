-- Kuma the Bear — TESTING spawn.
--
-- Puts one Kuma beside the hero each chapter, so there is no camp to hunt for.
-- Kuma's entity is loaded only on maps that list his tribe (Undead Hogs: Dark
-- Hills). It may also load only once a camp first builds him, so this keeps
-- trying all chapter, and copies a live Kuma when one exists. Solo only: a
-- spawn is refused on a co-op client.

local R = require "rsmm"

local KUMA = "Enemies\\Wolves\\Kuma.entity.ot"
local OFFSET = { 6, 0, 0 }          -- a few steps to the side, not on top of you

local done, reported = false, false
local function rearm() done = false end

-- A Kuma some camp already built: its template is as good as a loaded one.
local function live_kuma()
    for _, row in ipairs(R.spawn.enemies()) do
        if row.name and row.name:lower():find("kuma.entity", 1, true) then
            return row.template
        end
    end
end

local function try_spawn()
    if done or not R.entity.ready() then return end
    local ok, why = R.spawn.named(KUMA, { offset = OFFSET })
    if not ok then
        local t = live_kuma()
        if t then ok, why = R.spawn.near(t, { offset = OFFSET }) end
    end
    if ok then
        done = true
        R.log("[kuma-bear] Kuma spawned beside the hero")
    elseif not reported then
        -- Once per session: what the resource table holds, to tell "not loaded
        -- yet" from "loaded under another key".
        reported = true
        local keys, archives, n = R.spawn.loaded_like("kuma", 8)
        R.log(string.format("[kuma-bear] not yet: %s; %s resources in %s archive(s); "
            .. "kuma keys: %s", tostring(why), tostring(n), tostring(archives),
            #keys > 0 and table.concat(keys, ", ") or "none"))
    end
end

R.on("run:start", rearm)
R.on("gameplay:MAP_GENERATION_DONE", rearm)   -- every chapter, not only the first
R.schedule.every(3, try_spawn)
