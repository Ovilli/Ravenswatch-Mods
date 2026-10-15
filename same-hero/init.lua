-- Same Hero — see manifest.toml.
--
-- Settings:
--   hero   = "none"      everyone plays `player`'s hero (default)
--   hero   = "Carmilla"  `player` plays Carmilla, even if someone else is on her
--   player = ""          you (the host)
--   player = "Name"      that player
--   player = "*"         everyone (only with a `hero`)
local R = require "rsmm"

-- Pick ANY hero in the normal hero select: clicking a portrait someone else
-- has no longer says "already selected"; you play that hero when the run
-- starts (the lobby keeps your previous pick so READY still goes through).
R.hero.allow_taken_pick()

local hero   = R.config.get("hero", "none")
local player = R.config.get("player", "")
local who    = player ~= "" and player or nil

local ok
if hero ~= "" and hero ~= "none" then
    ok = R.hero.play_as(hero, who)
else
    ok = R.hero.share_hero(who)
end
if not ok then
    R.log("[same-hero] not available on this game build; heroes stay as picked")
end
