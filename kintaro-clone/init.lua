-- kintaro-clone: nothing to script yet. Hero changes are data in manifest.toml.
local R = require "rsmm"
R.health.checkpoint("per_mod:kintaro-clone")

R.on("ready", function()
    R.log("[kintaro-clone] loaded")
end)
