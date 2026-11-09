-- Camera control: keep the in-run camera where the player put it.
--
-- Each field below is this mod's config value AND an R.camera field. The
-- desktop overlay's sliders write them live, R.config.on_change fires here on
-- the loader's tick, and a new run builds new cameras, so everything is
-- re-applied when the hero changes. Every field carries to all of the hero's
-- cameras, so the view holds when the game switches camera (Kintaro on foot,
-- Melusine's Sing Stance, ultimates): yaw is copied, tilt and look height move
-- by the same amount, distance scales by the same ratio. That is R.camera.set's
-- doing; on an SDK older than that, only yaw reaches the other cameras. Some
-- cameras exist only for a while (Kintaro's on-foot one is rebuilt with shipped
-- values each time he dismounts), so the camera list is checked twice a second
-- and every field is applied again when it changes. The run-start log lists
-- every camera found, and "camera switch" lines show each re-apply.

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
    return n
end

-- Hero capture switched off: the camera can never be found, so "applies when a
-- run starts" would be a promise that never comes true. Say what to change.
local told_off = false
local function capture_off()
    if R.entity.capture_enabled and not R.entity.capture_enabled() then
        if not told_off then
            told_off = true
            R.log("[camera-control] hero capture is off, so the camera cannot be moved. "
                .. "Update the app and apply again (this mod switches it on), or turn on "
                .. "Hero capture under Loader features.")
        end
        return true
    end
    return false
end

for name in pairs(FIELDS) do
    R.config.on_change(name, function(v)
        if capture_off() then return end
        if not R.entity.ready() then
            R.log("[camera-control] " .. name .. " " .. tostring(v) .. " saved; applies when a run starts")
        else
            local n = apply(name)
            if n then
                R.log(("[camera-control] %s -> %s (%d camera%s)"):format(
                    name, tostring(v), n, n == 1 and "" or "s"))
            end
        end
    end)
end

-- Which cameras the hero has right now. Kintaro's on-foot camera is built new
-- (shipped values) every time he dismounts, so a new camera means apply again.
local function camera_set()
    local cams = R.camera.cameras and R.camera.cameras()
    if not cams then return nil, 0 end
    local s = {}
    for _, c in ipairs(cams) do s[#s + 1] = ("%x"):format(c.settings) end
    table.sort(s)
    return table.concat(s, ","), #cams
end

local applied_set = nil


R.schedule.every(0.5, function()
    if capture_off() then return end
    local hero = R.entity.ready() and R.entity.hero()
    if not hero then return end
    local set, count = camera_set()
    if hero == applied_to and set == applied_set then return end
    local ok = true
    for name in pairs(FIELDS) do ok = (apply(name) ~= nil) and ok end
    if ok then
        local new_run = hero ~= applied_to
        applied_to, applied_set = hero, set
        if new_run then
            local parts = {}
            for name in pairs(FIELDS) do parts[#parts + 1] = name .. "=" .. tostring(R.config.get(name, FIELDS[name])) end
            table.sort(parts)
            R.log("[camera-control] run start: " .. table.concat(parts, " "))
            -- One line per camera with the values now in it.
            if R.camera.describe then R.camera.describe() end
        else
            R.log(("[camera-control] camera switch: %d camera%s now, settings re-applied")
                :format(count, count == 1 and "" or "s"))
        end
    end
end)
