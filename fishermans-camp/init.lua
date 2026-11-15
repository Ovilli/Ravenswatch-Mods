-- PLACEMENT PROBE for the hut entrance and its platform room.
--
-- Answers, once per map generation, the question the first v0.7 run left
-- open ("I don't see the hut"): was the hut PICKED, was its ROOM placed in an
-- off-map slot (x = -350), and which underground rooms took those slots.
-- Read it with `rsmm log --grep fisher-probe`. Observes only.

local R = require "rsmm"

local OURS = "fishermans_camp"

-- Where our hut stands this map (from the generation report below), so an
-- interaction can be checked against it by POSITION, not by name.
local hut = nil

local function short(name)
    return (name or "?"):match("([^\\/]+)$") or name
end

if R.poi and R.poi.on_generated then
    local armed = R.poi.on_generated(function(spawner)
        local entries = R.poi.placed(spawner) or {}
        local ours, rooms, crystals = {}, {}, 0
        for _, e in ipairs(entries) do
            local n = e.name or ""
            if n:find(OURS, 1, true) then ours[#ours + 1] = e end
            if n:find("Crystal", 1, true) then crystals = crystals + 1 end
            -- Off-map room slots sit at x = -350.
            if e.pos and e.pos[1] < -300 then rooms[#rooms + 1] = e end
        end
        local hist = {}
        for _, e in ipairs(entries) do
            local n = short(e.name)
            if n:find("Crystal", 1, true) or n:find(OURS, 1, true) then
                hist[n] = (hist[n] or 0) + 1
            end
        end
        for n, c in pairs(hist) do R.log(("[fisher-probe]   %3d x %s"):format(c, n)) end
        R.log(("[fisher-probe] map generated: %d tile(s), %d crystal tile(s), %d ours, %d in room slots")
              :format(#entries, crystals, #ours, #rooms))
        hut = nil
        for _, e in ipairs(ours) do
            if e.pos and (e.name or ""):find("fishermans_hut", 1, true) then hut = e.pos end
        end
        for _, e in ipairs(ours) do
            R.log(("[fisher-probe]   OURS %s at %s %s"):format(short(e.name),
                e.pos and ("(%.0f, %.0f, %.0f)"):format(e.pos[1], e.pos[2], e.pos[3]) or "(?)",
                e.entity and "instantiated" or "NOT instantiated"))
        end
        for _, e in ipairs(rooms) do
            R.log(("[fisher-probe]   room slot: %s at (%.0f, %.0f)"):format(short(e.name), e.pos[1], e.pos[3]))
        end
    end)
    if not armed then R.log("[fisher-probe] could not arm R.poi.on_generated (another mod owns it?)") end
else
    R.log("[fisher-probe] R.poi unavailable in this loader build")
end

-- WHAT HAPPENS AT THE DOOR. Every interaction phase near the hut (and the
-- first few anywhere), plus the events the sub-tile teleporter sends. No line
-- at all while holding the key at the door = the teleporter is not
-- interactive; a request/validate with no teleport = it is, but finds no
-- partner.
local budget = 30
-- After each successful interaction, the next gameplay events of ANY name:
-- what the teleporter actually did (or that it did nothing).
local trail = 0
local function dist(p)
    if not (hut and p) then return nil end
    local dx, dz = p[1] - hut[1], p[3] - hut[3]
    return math.sqrt(dx * dx + dz * dz)
end
if R.interact and R.interact.on then
    R.interact.on("*", function(ev)
        local d = dist(ev.pos)
        if not (d and d < 15) then
            if budget <= 0 then return end
            budget = budget - 1
        end
        local nm = R.interact.name and R.interact.name(ev) or nil
        R.log(("[fisher-probe] interact %s at %s%s entity=%s a=%s b=%s class=%s name=%s"):format(
            tostring(ev.phase),
            ev.pos and ("(%.1f, %.1f, %.1f)"):format(ev.pos[1], ev.pos[2], ev.pos[3]) or "(?)",
            d and (" — %.1f from the hut"):format(d) or "",
            ev.entity and ("0x%x"):format(ev.entity) or "nil",
            tostring(ev.a), tostring(ev.b), tostring(ev.class), tostring(nm)))
        if ev.phase == "success" or ev.phase == "local_success" then trail = 40 end
    end)
end
for _, name in ipairs({ "HERO_TELEPORTED", "TELEPORT_SUBMAP_EXIT", "TELEPORT_SUBMAP_ENTER",
                        "HERO_ENTER_THIEVES_STASH" }) do
    R.on("gameplay:" .. name, function()
        R.log("[fisher-probe] event " .. name)
    end)
end

if R.on_match then
    R.on_match("^gameplay:", function(_ev, name)
        if trail <= 0 then return end
        if name:find("INTERACTION", 1, true) then return end
        trail = trail - 1
        R.log("[fisher-probe]   after: " .. tostring(name))
    end)
end
