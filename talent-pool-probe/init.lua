-- Talent pool probe (diagnostic): R.talent.dump() once the hero is captured,
-- then again whenever the controller count or a held slot changes.

local R = require "rsmm"

local last = nil

local function signature()
    local s = {}
    for _, e in ipairs(R.talent.controllers()) do
        s[#s + 1] = e.category .. (e.held and "H" or "-")
    end
    return table.concat(s, ",")
end

local function tick()
    if not R.entity.ready() then return end
    local sig = signature()
    if sig ~= last then
        last = sig
        R.talent.dump()
    end
end

R.on("run:start", function() last = nil end)
R.schedule.every(3, tick)
