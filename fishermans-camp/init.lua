-- PLACEMENT PROBE for the hut entrance and its platform room.
--
-- Answers, once per map generation, the question the first v0.7 run left
-- open ("I don't see the hut"): was the hut PICKED, was its ROOM placed in an
-- off-map slot (x = -350), and which underground rooms took those slots.
-- Read it with `rsmm log --grep fisher-probe`. Observes only.

local R = require "rsmm"

local OURS = "fishermans_camp"

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
