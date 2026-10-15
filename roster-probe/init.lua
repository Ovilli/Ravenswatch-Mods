-- TEST — roster probe. See manifest.toml.
local R = require "rsmm"

local TAG = "[roster-probe] "

-- A few readable strings hanging off the hero definition, to name it.
local function hero_label(ptr)
    local parts = {}
    for _, s in ipairs(R.debug.strings(ptr) or {}) do
        parts[#parts + 1] = ("+0x%x %q"):format(s.off, s.text)
        if #parts == 3 then break end
    end
    return (R.rtti.name(ptr) or "?") .. " " .. table.concat(parts, " ")
end

local ok = R.hero.on_roster(function(entries)
    R.log(TAG .. ("roster built: %d entr%s"):format(#entries, #entries == 1 and "y" or "ies"))
    for i, e in ipairs(entries) do
        R.log(TAG .. ("  #%d key=0x%x (%d) hero=0x%x skin=%d  %s"):format(
            i, e.key or 0, e.key or 0, e.hero or 0, e.skin or -1, hero_label(e.hero)))
    end
end)
R.log(TAG .. "roster observer: " .. (ok and "armed" or "UNAVAILABLE"))
