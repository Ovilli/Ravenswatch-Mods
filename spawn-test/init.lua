-- Spawn Test — a testing tool for R.spawn.
--
-- Two steps, one launch each:
--   1. probe_only = true (default): logs every link of the spawn chain — hero
--      entity, its template, the scene's entity spawner — plus how many entities
--      and enemies that spawner lists. Calls nothing.
--   2. probe_only = false: spawns `count` copies of an enemy in a ring around the
--      hero, once per run. The enemy is taken from the scene spawner's list when
--      it has one, otherwise from the first enemy you HIT (camp spawners may keep
--      their enemies on their own list, which the scene walk cannot see).
--
-- Needs the gameplay bus (RSMM_ENABLE_GAMEPLAY_EVENTS=1): engine calls run on
-- the game's main thread, and that bus is the main-thread heartbeat.

local R = require "rsmm"

local cfg = {
    probe_only = R.config.get("probe_only", true),
    enemy      = (R.config.get("enemy", "") or ""):lower(),
    count      = math.max(1, math.min(tonumber(R.config.get("count", 1)) or 1, 8)),
}

local done, listening = false, false

local function matches(name)
    return cfg.enemy == "" or (name or ""):lower():find(cfg.enemy, 1, true) ~= nil
end

local function spawn_ring(template, name)
    done = true
    if not R.spawn.probe() then return end
    for i = 1, cfg.count do
        local a = (i - 1) / cfg.count * 2 * math.pi
        local ok, why = R.spawn.near(template, {
            offset = { 4 * math.cos(a), 0, 4 * math.sin(a) },
            on_spawned = function(e)
                R.log(string.format("[spawn-test] spawned %s #%d -> 0x%x", tostring(name), i, e))
            end,
        })
        if not ok then R.log("[spawn-test] refused: " .. tostring(why)) end
    end
end

local function listen_for_hits()
    if listening or not (R.damage and R.damage.on) then return end
    listening = true
    if R.damage.enable then pcall(R.damage.enable) end
    R.log(cfg.probe_only and "[spawn-test] hit enemies to describe them"
          or "[spawn-test] no matching enemy on the scene list; hit an enemy to copy it")
    local described = {}
    local n_described = 0
    R.damage.on(function(hit)
        if hit.kind ~= "dealt" or not hit.target then return end
        -- Probe mode: describe the first few distinct victims, spawn nothing.
        if n_described < 6 and not described[hit.target] then
            described[hit.target] = true
            n_described = n_described + 1
            local d = R.spawn.describe(hit.target)
            local on_list = false
            for _, row in ipairs(R.spawn.entities()) do
                if row.entity == d.entity then on_list = true; break end
            end
            R.log(string.format(
                "[spawn-test] victim 0x%x live=%s template=%s enemy(damage)=%s enemy(component)=%s "
                .. "owner=0x%x (%s) scene_spawner=0x%x on_scene_list=%s name=%s",
                hit.target, tostring(d.live), d.template and string.format("0x%x", d.template) or "nil",
                tostring(d.enemy_damage), tostring(d.enemy_component), d.owner or 0,
                tostring(d.owner_class), d.scene_spawner or 0, tostring(on_list),
                tostring(d.template and R.spawn.name_of(d.template))))
        end
        if done or cfg.probe_only then return end
        if not R.spawn.is_enemy(hit.target) then return end
        local t = R.spawn.template_of(hit.target)
        local name = t and R.spawn.name_of(t)
        if t and matches(name) then spawn_ring(t, name) end
    end)
end

local function step()
    if done or not R.entity.ready() then return end
    local all = R.spawn.entities()
    local enemies = R.spawn.enemies()
    R.log(string.format("[spawn-test] scene spawner lists %d entit(ies), %d enemy template(s)",
        #all, #enemies))
    for _, r in ipairs(enemies) do
        R.log(string.format("[spawn-test]   x%d %s (template 0x%x)", r.count, tostring(r.name), r.template))
    end
    if cfg.probe_only then
        done = true
        R.spawn.probe()
        listen_for_hits()          -- logs what a hit would have copied
        return
    end
    for _, r in ipairs(enemies) do
        if matches(r.name) then return spawn_ring(r.template, r.name) end
    end
    listen_for_hits()
end

R.on("run:start", function() done = false end)
R.schedule.every(5, step)
