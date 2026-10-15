-- TEST — duplicate-hero probe. See manifest.toml.
--
-- Answers ONE question: when you pick a hero someone else has, is the confirm
-- button disabled (the click never reaches the handler), or does the click go
-- through and get refused further on?
local R = require "rsmm"

local TAG = "[dup-hero-probe] "

R.log(TAG .. "hero-select gates forced: " .. R.hero.unlock_hero_select())

-- The confirm handler. One line per press (capped) proves the click arrives.
local presses = 0
local ok_press = R.debug.observe("HeroSelect_ConfirmPressed", "vp", function()
    presses = presses + 1
    if presses <= 20 then R.log(TAG .. ("confirm handler reached (press #%d)"):format(presses)) end
end)

-- The button's enabled state. Logged only when it changes.
local last_enabled
local ok_enable = R.debug.observe("HeroSelect_SetConfirmEnabled", "vpi", function(_, _, enabled)
    if enabled ~= last_enabled then
        last_enabled = enabled
        R.log(TAG .. "confirm button set " .. (enabled ~= 0 and "ENABLED" or "DISABLED (padlock)"))
    end
end)

R.log(TAG .. ("observers: confirm handler %s, button state %s"):format(
    ok_press and "armed" or "UNAVAILABLE", ok_enable and "armed" or "UNAVAILABLE"))
