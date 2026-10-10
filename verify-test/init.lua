-- TESTING ONLY. Confirms the SDK calls that shipped as "sent" (event reaches
-- the game, visible effect unconfirmed). One step per ability use, >= 5 s
-- apart; each step logs what to look for. Step 12 ends the run as LOST.
local R = require "rsmm"

local TAG = "[verify-test] "
local step, queued, last = 0, false, -10

R.xp.arm()
R.on("run:start", function() step, last = 0, -10 end)

local function keys() return "(watch the key counter)" end

local STEPS = {
    function()
        R.stat.enable_writes()
        local lv = R.xp.set_level(5)
        local k = R.ingredient.add("Key", 3)
        return "setup: set_level(5)=" .. tostring(lv) .. ", +3 keys=" .. tostring(k)
            .. " — PICK YOUR TALENTS, note your key count"
    end,
    function()
        return "ingredient.remove(Key, 1): " .. tostring(R.ingredient.remove("Key", 1))
            .. " — LOOK: keys -1 " .. keys()
    end,
    function()
        return "xp.set_xp(10): " .. tostring(R.xp.set_xp(10)) .. " — LOOK: the XP bar drops near empty"
    end,
    function()
        return "talent.upgrade_lowest(): " .. tostring(R.talent.upgrade_lowest())
            .. " — LOOK: one lowest-tier talent goes up ONE tier (not to legendary)"
    end,
    function()
        return "ability.reduce_cooldown(999, ultimate): " .. tostring(R.ability.reduce_cooldown(999, "ultimate"))
            .. " — USE YOUR ULTIMATE AS THE TRIGGER FOR THIS STEP; LOOK: it is ready again at once"
    end,
    function()
        return "ability.remove_charge(dash): " .. tostring(R.ability.remove_charge("dash"))
            .. " — LOOK: one dash charge gone (heroes with dash charges only)"
    end,
    function()
        return "melody.choose(Fully_Heal): " .. tostring(R.melody.choose("Fully_Heal"))
            .. " — LOOK: Fully_Heal shows as the melody being collected"
    end,
    function()
        return "melody.remove(Fully_Heal): " .. tostring(R.melody.remove("Fully_Heal"))
            .. " — LOOK: it is no longer the melody being collected"
    end,
    function()
        return "status.clear(): " .. tostring(R.status.clear())
            .. ", clear_stagger(): " .. tostring(R.status.clear_stagger())
            .. " — LOOK: any slow/poison/burn on you ends (get hit by one first if you can)"
    end,
    function()
        local before = R.revive.tokens()
        local ok = R.revive.add_token(1)
        return "revive.add_token(1): " .. tostring(ok) .. " (tokens " .. tostring(before) .. " -> "
            .. tostring(R.revive.tokens()) .. ") — LOOK: the revive-token counter shows one more"
    end,
    function()
        local nc = R.run.next_chapter()
        local again = R.run.win()     -- must be REFUSED: one end per chapter
        return "run.next_chapter(): " .. tostring(nc) .. "; win() right after: " .. tostring(again)
            .. " (must be false) — LOOK: the next chapter loads, the run does NOT end"
    end,
    function()
        return "world ready: " .. tostring(R.run.world_ready()) .. "; run.lose(): " .. tostring(R.run.lose())
            .. " — LOOK: the run ends as a DEFEAT"
    end,
}

-- ABILITY_EXIT fires from inside the engine's own dispatch; act on the next
-- main-thread tick instead.
R.on("gameplay:ABILITY_EXIT", function()
    if queued or step >= #STEPS or os.clock() - last < 5 then return end
    queued = true
    R.schedule.next_main(function()
        queued, last = false, os.clock()
        step = step + 1
        R.log(TAG .. ("step %d/%d: %s"):format(step, #STEPS, STEPS[step]()))
    end)
end)

R.log(TAG .. "loaded")
