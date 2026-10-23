-- Hero component dump (diagnostic): logs the live hero's components once per
-- run, a few seconds after the hero is captured. See R.debug.components.

local R = require "rsmm"

local done = false

local function try_dump()
    if done or not R.entity.ready() then return end
    if R.debug.components(nil, "components") then done = true end
end

R.on("run:start", function() done = false end)
R.schedule.every(5, try_dump)
