-- Force the run seed so the generated map is identical every launch.
--
-- The engine honours "Forced seed" only while its "Dev" build flag is true, so
-- both are set together -- that pairing is the whole trick, and setting the
-- seed alone silently does nothing.
--
-- Written on every `ready` rather than once at load: the options singleton is
-- rebuilt across some transitions, and a seed that quietly stopped applying
-- looks exactly like a map that legitimately rerolled.

local R = require "rsmm"

local seed = R.config.get("seed") or 1337

local function force()
    if seed == 0 then
        R.log("[seeded-runs] seed 0 = disabled; maps will generate normally")
        return
    end
    local ok_dev = R.options.set("Dev", true)
    local ok_seed = R.options.set("Forced seed", seed)
    if not (ok_dev and ok_seed) then
        R.log("[seeded-runs] could not write the options singleton — maps will "
            .. "generate normally this run")
        return
    end
    R.log(("[seeded-runs] seed forced to %d — every run generates the same map"):format(seed))
end

R.on("ready", force)
