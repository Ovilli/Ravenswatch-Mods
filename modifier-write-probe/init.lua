-- DOES A RUN MODIFIER WRITTEN THROUGH THE ENGINE'S SETTER TAKE EFFECT?
--
-- At every run start (and chapter change) this logs what the global context
-- reads, then sets two modifiers with an effect you can see:
--   No minimap          -> the minimap should vanish, if the engine reads it live
--   Global Xp Modifier  -> 2.0: levels should come about twice as fast
--
-- Then:  rsmm log --grep modifier-write
--
-- Solo only: in co-op the SDK refuses (the value is replicated to peers), and
-- the log says so rather than writing.

local R = require "rsmm"

local TAG = "[modifier-write] "

local function show(label)
    R.log(TAG .. label .. ": current_chapter=" .. tostring(R.game.get("current_chapter"))
          .. " hero_count=" .. tostring(R.game.get("hero_count"))
          .. " (why: " .. tostring(R.game.why()) .. ")")
    for _, name in ipairs(R.modifier.names()) do
        local v = R.modifier.value(name)
        if v ~= nil and v ~= 0 then
            R.log(TAG .. "  " .. name .. " = " .. tostring(v))
        end
    end
end

local WRITES = {
    { "No minimap", 1 },
    { "Global Xp Modifier", 2.0 },
}

local function apply(label)
    R.schedule.next_main(function()
        show(label .. " before")
        R.modifier.enable_writes()
        for _, w in ipairs(WRITES) do
            local ok = R.modifier.set(w[1], w[2])
            R.log(TAG .. ("set %s = %s -> %s"):format(w[1], tostring(w[2]),
                ok and "read back OK" or ("REFUSED: " .. tostring(R.modifier.why()))))
        end
        show(label .. " after")
    end)
end

R.on("run:start", function() apply("run start") end)
R.on("gameplay:GAME_END_NEXT_CHAPTER", function() apply("next chapter") end)
