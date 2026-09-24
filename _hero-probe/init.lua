-- DEV PROBE (raw reads on purpose; delete after use). The hero-select setup
-- (FUN_1403e8f80) calls Registry_EnumInstances with the class key stored at
-- 0x1414762c8. Which class is that, and how many instances does it hold?
local native = rawget(_G, "rsmm")
local I = native._internal or native
local R = require "rsmm"

local function probe()
    local base = I.module_base()
    local function g(va) return I.read_u64(base + (va - 0x140000000)) end
    local key, sentinel = g(0x1414762c8), g(0x141476450)
    R.log(("[hero-probe] select-screen class key=0x%x sentinel=0x%x"):format(key or 0, sentinel or 0))
    for _, c in ipairs(R.defs.classes()) do
        if c.desc == key or (c.name or ""):find("Hero") then
            R.log(("[hero-probe] class %s desc=0x%x count=%d %s"):format(
                tostring(c.name), c.desc, c.count, c.desc == key and "<<< ENUMERATED BY SELECT SCREEN" or ""))
        end
    end
end

R.on("ready", function()
    R.schedule.after_main(12, function()
        local ok, err = pcall(probe)
        if not ok then R.log("[hero-probe] raised: " .. tostring(err)) end
    end)
end)
