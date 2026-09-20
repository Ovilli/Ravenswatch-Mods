-- Melody probe — does the game's own CHOOSE_MELODY event grant a melody?
--
-- Notes are not a keyed stat: melodies keep their own storage
-- (HeroMelodyPersistentData per hero, MelodyProfileData per profile), so
-- R.stat has nothing for them. What the game DOES have is a pair of named
-- events on the hero's bus, CHOOSE_MELODY and REMOVE_MELODY.
--
-- The event class is only ever built by a network-deserialisation factory, so
-- no emitter exists to read the payload's meaning from. R.melody.choose writes
-- a melody definition's GUID into +0x38/+0x48 on the hypothesis that it works
-- like R.give's magical-object GUID. This probe tests exactly that, and logs
-- any REAL one the game sends so the two can be compared.

local R = require "rsmm"

local TAG = "MelodyProbe"

-- Fully_Heal.melodydef: field_a = 3, guid a284971b7ccb5f46a60c8eb637ce3a44.
-- Picked because its effect is unmistakable in game.
local MELODY_NAME = "Fully_Heal"
local GUID_LO, GUID_HI = 0x465fcb7c1b9784a2, 0x443ace37b68e0ca6

-- Log every melody event the GAME sends, with the fields the bus publishes.
-- A vanilla one is the reference our own dispatch has to match.
for _, name in ipairs({ "CHOOSE_MELODY", "REMOVE_MELODY" }) do
    R.on("gameplay:" .. name, function(ev)
        R.log(("[%s] GAME sent %s  id=%s  disp=%s  seq=%s"):format(
            TAG, name, tostring(ev and ev.id), tostring(ev and ev.dispatcher),
            tostring(ev and ev.seq)))
    end)
end

-- Fire ours ONCE per run, on the gameplay bus (main thread). Latched BEFORE
-- the call: a dispatch reaches every R.on handler synchronously, so latching
-- on the result is how R.stat.modify recursed 99 deep.
local tried = false

R.on("*", function(ev)
    if tried or not (ev and ev.source == "gameplay") then return end
    if not R.melody or not R.melody.choose then
        tried = true
        R.log(("[%s] this loader's SDK has no R.melody — run `rsmm install-loader`"):format(TAG))
        return
    end
    tried = true
    if not R.melody.choose(GUID_LO, GUID_HI) then
        tried = false   -- no dispatcher yet (the hero must act once): retry
        return
    end
    R.log(("[%s] dispatched CHOOSE_MELODY for %s — check the melody UI, and see "
           .. "whether the game logs one of its own for comparison"):format(TAG, MELODY_NAME))
end)

for _, boundary in ipairs({ "run:start", "run:end", "menu:enter" }) do
    R.on(boundary, function() tried = false end)
end

R.on("ready", function()
    R.log(("[%s] armed — will try one CHOOSE_MELODY (%s) once the hero has acted. "
           .. "PROBE: delete when done."):format(TAG, MELODY_NAME))
end)
