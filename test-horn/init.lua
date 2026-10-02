-- >>> rsmm editor: test grants >>>
-- Written by the rsmm editor (Scripts tab), which rewrites this section when
-- you save; your own code outside the two marker lines is left alone.
-- TESTING ONLY: a published mod should not hand out free items or XP.
-- editor-config: {"hero":"","xp":0,"items":[{"id":"Spawn_Consumables","count":1}],"talents":[]}
do
    local R = require "rsmm"
    local HERO = nil                 -- only for this hero; nil = every hero
    local XP = 0
    local ITEMS = { { "Spawn_Consumables", 1 } }         -- { item id, copies }
    local TALENTS = {  }     -- { talent, rarity 0-3 }

    if XP > 0 then R.xp.arm() end      -- before the run builds the level
    local left, talents_done, xp_tries, mine
    local function reset()
        left = {}
        for _, it in ipairs(ITEMS) do left[#left + 1] = { it[1], it[2] } end
        talents_done, xp_tries, mine = #TALENTS == 0, XP > 0 and 0 or 5, nil
    end
    reset()
    for _, b in ipairs({ "run:start", "run:end", "menu:enter" }) do R.on(b, reset) end

    local function for_this_hero()
        if not HERO then return true end
        if mine == nil and R.hero.entity and R.hero.entity() then
            mine = R.hero.entity_is(HERO)
        end
        return mine == true
    end

    -- Main thread: a grant builds engine objects. One step per tick, and
    -- each counted BEFORE it runs, because a grant fires game events at once.
    R.schedule.every_main(1, function()
        if not R.entity.ready() or not for_this_hero() then return end
        if xp_tries < 5 then
            xp_tries = xp_tries + 1
            R.stat.enable_writes()
            if R.xp.grant(XP) then xp_tries = 5 end
            R.log(("[test-grants] 0 XP: %s"):format(
                xp_tries == 5 and "granted" or "retrying"))
        end
        if not talents_done and #R.talent.controllers() > 0 then
            talents_done = true
            for _, t in ipairs(TALENTS) do R.talent.grant(t[1], t[2]) end
        end
        local it = left[1]
        if it and R.give.ready() and R.give.count() > 0 then
            it[2] = it[2] - 1
            if it[2] <= 0 then table.remove(left, 1) end
            if not R.give.by_name(it[1]) and left[1] == it then table.remove(left, 1) end
        end
    end)
end
-- <<< rsmm editor: test grants <<<
