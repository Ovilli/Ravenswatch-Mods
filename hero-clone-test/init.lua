-- Gate 1: did the clone register? 12 herodefs ship; the clone makes 13.
-- Gate 2 is the select screen (a second Piper portrait) — only your eyes.
local R = require "rsmm"

R.on("ready", function()
    R.schedule.after_main(12, function()
        local n = #(R.defs.instances("oCDtHeroDefinition") or {})
        R.log(("[hero-clone] %d hero defs live (vanilla 12) -> clone %s"):format(
            n, n > 12 and "REGISTERED — open the hero select screen" or "NOT registered"))
    end)
end)
