-- Pass: interacting with the shrine pillar logs the prop's bare name with
-- at=0x28 (the entity-template hop), and a chest/fountain logs its own name.
local R = require "rsmm"

R.interact.on("request", function(ev)
    local name, at = R.interact.name(ev)
    R.log(("[TEST interact] request: name=%s at=%s"):format(
        tostring(name), at and ("0x%x"):format(at) or "nil"))
end)

R.interact.on("success", function(ev)
    R.log(("[TEST interact] success on %s"):format(tostring(R.interact.name(ev))))
end)
