-- Camera control: keep the in-run camera where the player put it.
--
-- Each field below is this mod's config value. yaw, pitch and distance are also
-- R.camera fields; look_height is derived from R.camera's look offset ("height")
-- and distance (see view()). The desktop overlay's sliders write them live,
-- R.config.on_change fires here on the loader's tick, and a new run builds new
-- cameras, so everything is re-applied when the hero changes. R.camera carries
-- every write to all of the hero's cameras, so the view holds when the game
-- switches camera (Kintaro on foot, Melusine's Sing Stance, ultimates): yaw is
-- copied, tilt and look offset move by the same amount, distance scales by the
-- same ratio. That is R.camera.set's doing; on an SDK older than that, only yaw
-- reaches the other cameras. Hand control is in the second half of this file:
-- the Zoom keys, drag to rotate and tilt, and the action camera. Some
-- cameras exist only for a while (Kintaro's on-foot one is rebuilt with shipped
-- values each time he dismounts), so the camera list is checked twice a second
-- and every field is applied again when it changes. The run-start log lists
-- every camera found, and "camera switch" lines show each re-apply.

local R = require "rsmm"

local FIELDS = {
    yaw      = 45,
    pitch    = 54,
    distance = 33,
    look_height = 0,
}

-- The game's own look offset (R.camera field "height", shipped 1.0) is a ground-
-- plane slide, not a height. Look height is derived from it: aiming h above the
-- hero equals aiming at the ground point further along the line of sight, so
--   height_written   = HEIGHT_BASE - h / tan(tilt)
--   distance_written = distance + h / sin(tilt)
-- gives the same eye and view direction. view() writes tilt, distance and height
-- together, so none of them is ever applied alone. The old saved "height" config
-- key is ignored on purpose: it meant something else.
local HEIGHT_BASE = 1.0
local MIN_TILT, MAX_TILT = 0.01, 1.5   -- radians, the game's own clamp

-- Tilt held by a drag or the action camera between saves; nil otherwise.
local live_pitch = nil
-- Zoom factor held by this mod while Look height > 0 (see zoom below).
local zoom_f = 1

local function num(name)
    return tonumber(R.config.get(name, FIELDS[name])) or FIELDS[name]
end

-- Writes pitch, distance and height from the tilt (live_pitch or config),
-- Distance and Look height. Returns the pitch write's camera count, or nil and
-- the first reason a write failed.
local function view()
    local pitch = live_pitch or num("pitch")
    local t = math.max(MIN_TILT, math.min(MAX_TILT, math.rad(pitch)))
    local d, h = num("distance"), math.max(0, num("look_height"))
    local hgt = HEIGHT_BASE
    if h > 0 then
        -- Zoom is mod-held here: the game's blended zoom scales the eye toward the
        -- ground look-at, which would shift the framing once the aim is raised.
        if R.camera.zoom and R.camera.zoom_factor then
            local nf = R.camera.zoom_factor()
            if nf and math.abs(nf - 1) > 1e-4 then R.camera.zoom(1 / nf) end
        end
        d = d * zoom_f + h / math.sin(t)
        hgt = HEIGHT_BASE - h / math.tan(t)
    else
        zoom_f = 1
    end
    local n, why = R.camera.set("pitch", pitch)
    if not n then return nil, why end
    local n2, why2 = R.camera.set("distance", d)
    if not n2 then return nil, why2 end
    local n3, why3 = R.camera.set("height", hgt)
    if not n3 then return nil, why3 end
    return n
end

local applied_to, last_why = nil, {}

local function apply(name)
    local n, why
    if name == "yaw" then
        n, why = R.camera.set("yaw", num("yaw"))
    else
        n, why = view()
    end
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

-- A change made while the hero isn't ready (the pause menu's Mods page, between
-- runs) is applied by the tick below as soon as the hero is back.
local pending = false

-- Set further down, with the turning helpers: an outside change to yaw or pitch
-- (the overlay) restarts any turn in progress from the new value.
local turn_resync

for name in pairs(FIELDS) do
    R.config.on_change(name, function(v)
        if name == "pitch" then live_pitch = nil end
        if name == "yaw" or name == "pitch" then turn_resync(name, v) end
        if capture_off() then return end
        if not R.entity.ready() then
            pending = true
            R.log("[camera-control] " .. name .. " " .. tostring(v) .. " saved; applies when play resumes")
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
    if hero == applied_to and set == applied_set and not pending then return end
    local ok = true
    ok = (apply("yaw") ~= nil) and ok
    ok = (apply("pitch") ~= nil) and ok
    if ok then
        local new_run = hero ~= applied_to
        local camera_switch = set ~= applied_set
        applied_to, applied_set, pending = hero, set, false
        if not new_run and not camera_switch then
            R.log("[camera-control] settings changed while paused, re-applied")
        elseif new_run then
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
-- factor stays within the Distance slider's 10-80. With Look height above 0 the
-- zoom is a factor this mod holds and view() applies to Distance (it snaps
-- instead of easing, but keeps the framing). Presses only arrive in play.
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
    local step = math.max(2, math.min(25, tonumber(R.config.get("wheel_step", 10)) or 10))
    if num("look_height") > 0 then
        -- R.camera.get("distance") is the written value here, so use the config.
        local d = num("distance")
        local want = zoom_f * (1 - step / 100) ^ steps
        want = math.max(MIN_DISTANCE / d, math.min(MAX_DISTANCE / d, want))
        if math.abs(want - zoom_f) < 1e-4 then return end
        zoom_f = want
        local n, why = view()
        if not n then tell_once("zoom", "zoom unavailable: " .. tostring(why)) end
        return
    end
    local base = R.camera.get("distance")
    if not base or base <= 0 then
        tell_once("distance", "zoom key pressed but no camera distance to zoom from "
            .. "(is hero capture on?)")
        return
    end
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

-- Two ways to turn the camera by hand, both writing yaw and tilt live and
-- sharing one turning helper (same speed, invert options and tilt range).
--
-- Classic middle-drag: "Rotate camera" is a row in Settings > Controls on the
-- middle mouse button; holding it and dragging sideways turns the camera, up and
-- down tilts it within the Tilt slider's range (R.input.on_drag). The drag only
-- comes from the middle button, so the row is the switch: while it holds the
-- middle button the drag rotates, and unbinding it, moving it to another key, or
-- a game action taking the middle button (which clears this row) turns the drag
-- off. yaw and tilt are saved to config once, when the drag ends.
--
-- Action camera: "Action camera" is a row in Settings > Controls, unbound by
-- default. Each press toggles it. While on, the game's cursor lock holds the
-- cursor at the window centre (R.input.mouse_look) and every mouse move turns
-- the camera with no button held. The loader pauses the lock itself while a
-- menu is open or the game is in the background. Yaw and tilt are saved when the
-- mode turns off and at most every 2 s while it is on, so the overlay follows
-- without writing the file every frame. Needs a loader with R.input.mouse_look;
-- on an older one the row is not declared.
--
-- Both run on the game thread: they write live and keep the work short. Moving
-- right adds to yaw and moving down tilts toward top-down (a higher pitch);
-- "Invert drag horizontal / vertical" flip each axis for both styles.
local MIDDLE = 89
local DEG_PER_PX = 0.2
local MIN_PITCH, MAX_PITCH = 2, 89

-- One turning state per style: yaw/pitch are nil while it is not turning.
local turns = {}
local function new_turn()
    local t = { sx = 1, sy = 1 }
    turns[#turns + 1] = t
    return t
end

-- A config change to yaw or pitch that is not this mod's own save (a save sets
-- saved_yaw / saved_pitch first, so it matches) moves every active turn there,
-- so the next move or save starts from the new value, not the old one.
function turn_resync(name, v)
    v = tonumber(v)
    if not v then return end
    for _, t in ipairs(turns) do
        if t.yaw and math.abs(v - t["saved_" .. name]) > 1e-6 then
            if name == "yaw" then
                t.yaw = v % 360
            else
                t.pitch = math.max(MIN_PITCH, math.min(MAX_PITCH, v))
            end
            t["saved_" .. name] = t[name]
        end
    end
end

-- Start from the config values and read the invert options.
local function turn_begin(t)
    t.yaw = tonumber(R.config.get("yaw", FIELDS.yaw)) or FIELDS.yaw
    t.pitch = tonumber(R.config.get("pitch", FIELDS.pitch)) or FIELDS.pitch
    t.sx = R.config.get("drag_invert_x", false) and -1 or 1
    t.sy = R.config.get("drag_invert_y", false) and -1 or 1
    t.saved_yaw, t.saved_pitch = t.yaw, t.pitch
end

local function turn_by(t, dx, dy)
    if not t.yaw then return end
    if dx ~= 0 then
        t.yaw = (t.yaw + t.sx * dx * DEG_PER_PX) % 360
        R.camera.set("yaw", t.yaw)
    end
    if dy ~= 0 then
        local p = math.max(MIN_PITCH, math.min(MAX_PITCH, t.pitch + t.sy * dy * DEG_PER_PX))
        if p ~= t.pitch then
            t.pitch = p
            live_pitch = p
            view()
        end
    end
end

-- Save to config when changed since the last save.
local function turn_save(t)
    if not t.yaw then return end
    if t.yaw ~= t.saved_yaw then R.config.set("yaw", t.yaw) end
    if t.pitch ~= t.saved_pitch then R.config.set("pitch", t.pitch) end
    t.saved_yaw, t.saved_pitch = t.yaw, t.pitch
end

-- The SDK declares R.input.on_drag / mouse_look even when the loader DLL lacks
-- the native side. Only a definite "loader too old" skips a row: while the input
-- hook is still pending they report another reason, and the row is kept.
local function native_missing(available)
    if not available then return false end
    local ok, why = available()
    return not ok and tostring(why):find("loader too old", 1, true) ~= nil
end

-- Checked on every move, not only at the start: a menu or blocked input that
-- appears mid-drag ends the drag.
local function turn_ok(ev)
    if ev.blocked then return false end
    if R.game.flag("is_game_menu_open") or R.game.flag("is_menu_open") then return false end
    return R.entity.ready()
end

local rotate
if K and R.input.on_drag and not native_missing(R.input.drag_available) then
    rotate = K.add{ id = "RotateCamera", label = "Rotate camera", key = MIDDLE }
end

if rotate then
    local drag = new_turn()
    R.input.on_drag(function(phase, dx, dy, ev)
        if phase == "start" then
            drag.yaw, drag.pitch = nil, nil
            live_pitch = nil
            if K.keys(rotate) ~= MIDDLE or not turn_ok(ev) then return end
            turn_begin(drag)
        elseif drag.yaw and phase == "move" then
            if turn_ok(ev) then
                turn_by(drag, dx, dy)
            else
                -- Keep what was applied, save it once, ignore the rest until
                -- the next start.
                turn_save(drag)
                drag.yaw, drag.pitch = nil, nil
                live_pitch = nil
            end
        elseif drag.yaw and phase == "end" then
            turn_save(drag)
            drag.yaw, drag.pitch = nil, nil
            live_pitch = nil
        end
    end)
    K.on_ready(function(ok, why2)
        local live, dwhy = R.input.drag_available()
        if ok and live then
            R.log("[camera-control] drag rotate live (Settings > Controls: Rotate camera, middle mouse)")
        else
            R.log("[camera-control] drag rotate off: " .. tostring(ok and dwhy or why2))
        end
    end)
end

local action
if K and R.input.mouse_look and R.input.on_mouse_move
    and not native_missing(R.input.mouse_look_available) then
    action = K.add{ id = "ActionCamera", label = "Action camera", key = 0 }   -- unbound
end

if action then
    local look = new_turn()
    local on = false

    local function set_mode(want)
        if want then
            local ok, why3 = R.input.mouse_look(true, { hide = R.config.get("action_hide_cursor", false) })
            if not ok then
                tell_once("mouse_look", "action camera unavailable: " .. tostring(why3))
                return
            end
            turn_begin(look)
            on = true
        else
            R.input.mouse_look(false)
            turn_save(look)
            look.yaw, look.pitch = nil, nil
            live_pitch = nil
            on = false
        end
    end

    K.on_press(action, function() set_mode(not on) end)
    -- A run that ends (death, victory, abandon) drops the action camera, so the
    -- end-of-run screens and the next run start with a free cursor.
    R.on("run:end", function() if on then set_mode(false) end end)

    R.input.on_mouse_move(function(dx, dy, ev)
        if not on then return end
        -- With game events off run:end never arrives. A finished run lands in the
        -- main menu, where the lock is paused and moves still arrive unlocked, so
        -- the mode ends there instead. (A new captured hero is not a new run:
        -- every transform, death and respawn captures one.) Game thread, so the
        -- live flag read is safe.
        if R.game.flag("is_in_main_menu") == true then
            set_mode(false)
            return
        end
        if not ev.locked or ev.blocked then return end
        -- Not ready while a menu is open: that alone does not end the mode.
        if not R.entity.hero() then return end
        turn_by(look, dx, dy)
    end)

    R.schedule.every(2, function()
        if on then turn_save(look) end
    end)

    K.on_ready(function()
        local live, awhy = true, nil
        if R.input.mouse_look_available then live, awhy = R.input.mouse_look_available() end
        if live then
            R.log("[camera-control] action camera live (Settings > Controls: Action camera, unbound until you bind it)")
        else
            R.log("[camera-control] action camera off: " .. tostring(awhy))
        end
    end)
end
