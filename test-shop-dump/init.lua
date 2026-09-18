-- Read-only. Open the Sandman's shop once, close it, open it again.
-- The dumps answer what drop+0x230/+0x238 and +0x250/+0x258 hold.
local R = require "rsmm"

local dumped = 0

local function dump_drops(entity, when)
    local comps = R.entity.components(entity)
    if not comps then return 0 end
    local n = 0
    for i, c in ipairs(comps) do
        local cls = R.rtti.name(c.ptr)
        if type(cls) == "string" and cls:find("MagicalObjectsDrop", 1, true)
            and not cls:find("Settings", 1, true) then
            n = n + 1
            R.debug.dump(c.ptr, 0x300, ("TEST shop %s drop#%d %s"):format(when, i - 1, cls))
        end
    end
    return n
end

R.interact.on("request", function(ev)
    if dumped >= 3 or not ev.entity then return end
    local found = dump_drops(ev.entity, "open")
    if found == 0 then return end
    dumped = dumped + 1
    R.log(("[TEST shop] %s: %d offer generator(s) dumped"):format(
        tostring(R.interact.name(ev)), found))
    local entity = ev.entity
    R.schedule.after(3, function() dump_drops(entity, "open+3s") end)
end)
