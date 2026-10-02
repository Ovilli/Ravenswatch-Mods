-- Camera control: keep the in-run camera where the player put it.
--
-- Each field below is this mod's config value AND an R.camera field. The
-- desktop overlay's sliders write them live, R.config.on_change fires here on
-- the loader's tick, and a new run builds new cameras, so everything is
-- re-applied when the hero changes. Yaw turns every camera (zooming keeps the
-- rotation); the others change the default in-run camera only.

local R = require "rsmm"

local FIELDS = {
    yaw      = 45,
    pitch    = 54,
    distance = 33,
    height   = 1,
}

local applied_to, last_why = nil, {}

local function apply(name)
    local n, why = R.camera.set(name, R.config.get(name, FIELDS[name]))
    if not n and why ~= last_why[name] then
        R.log("[camera-control] " .. name .. " not applied: " .. tostring(why))
    end
    last_why[name] = why
    return n ~= nil
end

for name in pairs(FIELDS) do
    R.config.on_change(name, function(v)
        if not R.entity.ready() then
            R.log("[camera-control] " .. name .. " " .. tostring(v) .. " saved; applies when a run starts")
        elseif apply(name) then
            R.log("[camera-control] " .. name .. " -> " .. tostring(v))
        end
    end)
end

R.schedule.every(2, function()
    local hero = R.entity.ready() and R.entity.hero()
    if not hero or hero == applied_to then return end
    local ok = true
    for name in pairs(FIELDS) do ok = apply(name) and ok end
    if ok then
        applied_to = hero
        local parts = {}
        for name in pairs(FIELDS) do parts[#parts + 1] = name .. "=" .. tostring(R.config.get(name, FIELDS[name])) end
        table.sort(parts)
        R.log("[camera-control] run start: " .. table.concat(parts, " "))
    end
end)
