-- Gate 1: the herodef registered (13 live). Gates 2-4 are your eyes: the name
-- "Nyx" on the select screen, a magenta body, and Piper's abilities working.
local R = require "rsmm"

R.on("ready", function()
    R.schedule.after_main(12, function()
        local n = #(R.defs.instances("oCDtHeroDefinition") or {})
        R.log(("[custom-hero] %d hero defs live (vanilla 12) -> Nyx %s"):format(
            n, n > 12 and "REGISTERED" or "NOT registered"))
    end)
end)
