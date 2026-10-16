-- Same Hero — see manifest.toml.
--
-- Normal use: just click the hero you want in hero select, even one another
-- player already has. You become that hero when the run starts; nobody else
-- is changed.
--
-- Optional settings (leave hero = "none" for click-only):
--   hero   = "Carmilla"  `player` plays Carmilla, even if someone else is on her
--   player = ""          you
--   player = "Name"      that player (only applied when YOUR game hosts)
--   player = "*"         everyone     (only applied when YOUR game hosts)
local R = require "rsmm"

-- Click a portrait someone else has -> you play that hero at run start
-- (the lobby keeps your previous pick so READY still goes through).
if not R.hero.allow_taken_pick() then
    R.log("[same-hero] not available on this game build; heroes stay as picked")
end

local hero   = R.config.get("hero", "none")
local player = R.config.get("player", "")

-- "none" means change NOBODY: only your own clicks count.
if hero ~= "" and hero ~= "none" then
    R.hero.play_as(hero, player ~= "" and player or nil)
end
