-- PR #110 in-game pass: what R.ui sees. Read the result with `rsmm log --grep ui-probe`.
local R = require "rsmm"

R.on("ui:open", function(e)
    R.log(string.format("[ui-probe] OPEN  %-8s %s", e.kind, e.class))
end)
R.on("ui:close", function(e)
    R.log(string.format("[ui-probe] CLOSE %-8s %s", e.kind, e.class))
end)

local last
R.schedule.every(2, function()
    local parts = {}
    for _, k in ipairs({ "menu", "book", "modal", "loading", "page" }) do
        local n, why = R.ui.count(k)
        parts[#parts + 1] = k .. "=" .. (n == nil and ("?(" .. tostring(why) .. ")") or tostring(n))
    end
    parts[#parts + 1] = "on page " .. tostring(R.ui.page())
    local line = table.concat(parts, " ")
    if line ~= last then           -- log changes only, not every tick
        R.log("[ui-probe] state " .. line)
        last = line
    end
end)
