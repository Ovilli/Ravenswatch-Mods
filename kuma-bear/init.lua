-- Kuma the Bear — TESTING spawn.
--
-- Puts one Kuma beside the hero as each chapter starts, so there is no camp to
-- hunt for. Kuma's definition loads only on maps that list his tribe (Undead
-- Hogs: Dark Hills); R.spawn.named loads his body the way a camp's first pick
-- does, then spawns him. Solo only: a spawn is refused on a co-op client.

local R = require "rsmm"

local KUMA = "Enemies\\Wolves\\Kuma.entity.ot"
local OFFSET = { 6, 0, 0 }          -- a few steps to the side, not on top of you
local TRIES = 20                    -- every 3 s while the level settles

local tries, done, pending = 0, false, false
local function rearm() tries, done, pending = 0, false, false end

local function try_spawn()
    if done or pending or tries >= TRIES or not R.entity.ready() then return end
    tries = tries + 1
    pending = true
    local ok, why = R.spawn.named(KUMA, {
        offset = OFFSET,
        on_spawned = function()
            done = true
            R.log("[kuma-bear] Kuma spawned beside the hero")
        end,
    })
    if not ok then R.log("[kuma-bear] not yet: " .. tostring(why)) end
    -- A queued attempt reports through on_spawned; give it one beat, then
    -- allow the next try (and say why this one did not land).
    R.schedule.after(1, function()
        pending = false
        if not done and ok then R.log("[kuma-bear] not yet: " .. tostring(R.spawn.why())) end
        if not done and tries >= TRIES then R.log("[kuma-bear] gave up spawning Kuma") end
    end)
end

R.on("run:start", rearm)
R.on("gameplay:MAP_GENERATION_DONE", rearm)   -- every chapter, not only the first
R.schedule.every(3, try_spawn)
