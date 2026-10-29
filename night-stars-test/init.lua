-- Grants Test_Night_Stars at run start, then logs every change of the reroll
-- count: expect +1 at each nightfall.
local R = require "rsmm"
local granted, last = false, nil
R.schedule.every_main(1, function()
    if not granted and R.give.ready() then
        granted = R.give.by_name("Test_Night_Stars") and true or false
        if granted then R.log("[NightStars] item granted") end
    end
    local n = R.reroll.get()
    if n and n ~= last then
        R.log(("[NightStars] rerolls %s -> %d"):format(tostring(last), n))
        last = n
    end
end)
