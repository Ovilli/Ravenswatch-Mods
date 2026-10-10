-- TESTING ONLY. Logs every analytics-firehose event with all of its fields, so
-- one ordinary run shows which catalogued events fire and what they carry.
local R = require "rsmm"

local TAG = "[analytics-events-test] "
local seen, order = {}, {}

local function fields(ev)
    local keys = {}
    for k in pairs(ev) do
        if k ~= "event" and k ~= "seq" and k ~= "source" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. tostring(ev[k]) end
    return table.concat(out, ", ")
end

R.on("*", function(ev, name)
    if type(ev) ~= "table" or ev.source ~= "analytics" then return end
    if not seen[name] then seen[name] = 0; order[#order + 1] = name end
    seen[name] = seen[name] + 1
    R.log(TAG .. name .. " {" .. fields(ev) .. "}")
end)

R.schedule.every(60, function()
    local parts = {}
    for _, n in ipairs(order) do parts[#parts + 1] = n .. " x" .. seen[n] end
    R.log(TAG .. "fired so far: " .. (#parts > 0 and table.concat(parts, ", ") or "nothing yet"))
end)

R.log(TAG .. "loaded — logging every analytics event")
