-- Pass: "5 mapdefs live (vanilla 4)" — the chapter's resref loaded the clone.
local R = require "rsmm"

local function count(when)
    local n = #R.defs.instances("oCDtMapDefinition")
    R.log(("[TEST map] %s: %d mapdefs live (vanilla 4)%s"):format(
        when, n, n >= 5 and " -> clone LOADED" or ""))
end

R.on("ready", function() R.schedule.after(10, function() count("boot") end) end)
R.on("run:start", function() R.schedule.after(5, function() count("run start") end) end)
