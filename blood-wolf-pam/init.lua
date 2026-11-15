local R = require "rsmm"
R.on("gameplay:COMBO_LINK", function(ev)
    R.log("[blood-wolf-diag] COMBO_LINK fired")
end)
R.on("gameplay:ABILITY_EXIT", function(ev)
    R.log("[blood-wolf-diag] ABILITY_EXIT fired")
end)
