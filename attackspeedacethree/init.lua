-- TESTING ONLY. Gives you the Ace of Spades at the start of every run, so the
-- change can be tried at once. Delete this file before you share the mod.
local R = require "rsmm"

local ITEM = "Damage_Attack"   -- Ace of Spades Card
local COPIES = 15              -- 4 turns the super effect on

local given = 0
for _, boundary in ipairs({ "run:start", "run:end", "menu:enter" }) do
    R.on(boundary, function() given = 0 end)
end
-- every_main: a grant builds the item's entity, which only works on the game's
-- main thread (from the timer thread it crashed the game, 2026-10-01).
R.schedule.every_main(3, function()
    if given >= COPIES or not R.give.ready() or R.give.count() == 0 then return end
    -- Count it BEFORE granting: the grant fires an event synchronously, so
    -- anything that runs inside it must already see this copy as given.
    given = given + 1
    if R.give.by_name(ITEM) then
        R.log(("[ace-test] granted %s (%d/%d)"):format(ITEM, given, COPIES))
    else
        given = COPIES  -- not found: say so once, don't spam
    end
end)
