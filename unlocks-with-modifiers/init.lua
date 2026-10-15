-- Unlocks With Modifiers — see manifest.toml.
local R = require "rsmm"

if not R.modifier.allow_unlocks() then
    R.log("[unlocks-with-modifiers] not available on this game build; unlocks stay blocked under modifiers")
end
