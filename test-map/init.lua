-- Pass 1: "5 mapdefs live (vanilla 4)" — the clone loaded.
-- Pass 2: chapter 0 is a RESREF whose map pointer is an oCDtMapDefinition that
-- is NOT the vanilla Dark Hills pointer (builtin[0]) — the chapter plays the clone.
local R = require "rsmm"

local function hx(v) return type(v) == "number" and ("0x%x"):format(v) or tostring(v) end

local function report(when)
    local n = #R.defs.instances("oCDtMapDefinition")
    R.log(("[TEST map] %s: %d mapdefs live (vanilla 4)%s"):format(
        when, n, n >= 5 and " -> clone LOADED" or ""))
    local chapters, vanilla = R.maps.chapters()
    if not chapters then
        R.log("[TEST map] chapters unreadable: " .. tostring(vanilla)); return
    end
    for i = 0, 3 do
        R.log(("[TEST map] builtin[%d] = %s (%s)"):format(i, hx(vanilla[i]),
            tostring(vanilla[i] and R.rtti.name(vanilla[i]))))
    end
    for _, c in ipairs(chapters) do
        local verdict = ""
        if c.resref and c.map and c.map ~= vanilla[0] and c.class == "oCDtMapDefinition" then
            verdict = " -> plays a NON-vanilla mapdef (the clone)"
        end
        R.log(("[TEST map] chapter %d: %s map=%s class=%s%s"):format(
            c.index, c.resref and "RESREF" or ("biome " .. tostring(c.biome)),
            hx(c.map), tostring(c.class), verdict))
    end
end

R.on("ready", function() R.schedule.after(10, function() report("boot") end) end)
R.on("run:start", function() R.schedule.after(5, function() report("run start") end) end)
