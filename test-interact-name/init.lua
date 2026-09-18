-- Question this answers: is the interaction event's entity the OBJECT or the
-- HERO? Session 1e4f named it "Hero_Aladdin_Guardian" while holding interact on
-- the shrine. Compare `event entity` with the hero's own entity (`owner=` in the
-- diagnose line). Same pointer = the event carries the interactor, not the target.
local R = require "rsmm"

local function hx(v) return type(v) == "number" and ("0x%x"):format(v) or tostring(v) end

R.interact.on("request", function(ev)
    local name, at = R.interact.name(ev)
    R.log(("[TEST interact] request: event entity=%s name=%s at=%s dispatcher=%s a=%s b=%s"):format(
        hx(ev.entity), tostring(name), at and ("0x%x"):format(at) or "nil",
        hx(ev.dispatcher), hx(ev.a), hx(ev.b)))
    R.log("[TEST interact] hero chain: " .. R.hp.diagnose())
end)

R.interact.on("validate", function(ev)
    R.log(("[TEST interact] validate: dispatcher=%s entity=%s name=%s"):format(
        hx(ev.dispatcher), hx(ev.entity), tostring(R.interact.name(ev))))
end)

R.interact.on("success", function(ev)
    R.log(("[TEST interact] success: entity=%s name=%s"):format(
        hx(ev.entity), tostring(R.interact.name(ev))))
end)
