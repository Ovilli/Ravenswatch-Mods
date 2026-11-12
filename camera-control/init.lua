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

-- Zoom keys. "Zoom in" and "Zoom out" are rows in the game's Settings >
-- Controls menu (R.input.keybinds), on the mouse wheel by default and bindable
-- to any key there; the game saves them with the other keys and clears one when
-- another action takes its key. R.camera.zoom eases the camera through the
-- game's own camera blend, so the zoom is smooth where a Distance change snaps.
-- Distance stays the base; each press multiplies on top of it, kept so base x
-- factor stays within the Distance slider's 10-80. Presses only arrive in play.
-- On a loader without keybinds the wheel zooms instead (R.input.on_wheel).
-- Both run on the game thread inside the input poll: they only read values and
-- queue a zoom.
local MIN_DISTANCE, MAX_DISTANCE = 10, 80
local told = {}

local function tell_once(key, msg)
    if told[key] then return end
    told[key] = true
    R.log("[camera-control] " .. msg)
end

-- steps > 0 moves closer.
local function zoom(steps)
    if steps == 0 or not R.config.get("wheel_zoom", true) then return end
    local base = R.camera.get("distance")
    if not base or base <= 0 then
        tell_once("distance", "zoom key pressed but no camera distance to zoom from "
            .. "(is hero capture on?)")
        return
    end
    local step = math.max(2, math.min(25, tonumber(R.config.get("wheel_step", 10)) or 10))
    local now = R.camera.zoom_factor()
    local want = now * (1 - step / 100) ^ steps
    want = math.max(MIN_DISTANCE / base, math.min(MAX_DISTANCE / base, want))
    if math.abs(want - now) < 1e-4 then return end
    local ok, why = R.camera.zoom(want / now)
    if not ok then tell_once("zoom", "zoom unavailable: " .. tostring(why)) end
end

local function wheel_zoom(why)
    if not (R.input and R.input.on_wheel and R.camera.zoom) then
        R.log("[camera-control] zoom needs a newer loader (no R.input / R.camera.zoom)")
        return
    end
    R.log("[camera-control] no zoom keys (" .. tostring(why) .. "); the wheel zooms instead")
    R.input.on_wheel(function(steps, ev)
        if ev.blocked then return end
        if R.game.flag("is_game_menu_open") or R.game.flag("is_menu_open") then return end
        local free, holder = R.input.wheel_free()
        if free == false then
            tell_once("bound:" .. tostring(holder), "wheel zoom off: the wheel is bound to "
                .. tostring(holder) .. " in the Controls menu")
            return
        end
        zoom(steps)
    end)
end

local K = R.input and R.input.keybinds
local zoom_in, why = nil, "this loader has no R.input.keybinds"
if K and R.camera.zoom then
    zoom_in, why = K.add{ id = "ZoomIn", label = "Zoom in", key = 92 }   -- wheel up
end

if zoom_in then
    local zoom_out = K.add{ id = "ZoomOut", label = "Zoom out", key = 93 }  -- wheel down
    K.on_press(zoom_in, function(n) zoom(n) end)
    if zoom_out then K.on_press(zoom_out, function(n) zoom(-n) end) end
    K.on_ready(function(ok, why2)
        if ok then
            R.log("[camera-control] zoom keys live (Settings > Controls: Zoom in / Zoom out)")
        else
            wheel_zoom(why2)
        end
    end)
else
    wheel_zoom(why)
end
