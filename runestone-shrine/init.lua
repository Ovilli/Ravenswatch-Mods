-- THE SHRINE'S INTERACTION — the last unproven link in the POI chain.
--
-- Everything else is confirmed in game: the tile generates, the mesh renders,
-- the minimap icon draws. The prop entity already inherits
-- `Interactive_Object_Model` and carries all ten override records the machine
-- reads, including `Event Interaction Available At Start`, which is what ARMS
-- the interaction at spawn. So the prompt should work. Nobody has watched it.
--
-- This file exists because of a second, sharper gap. `R.interact` publishes
-- every interaction in the run -- chest, fountain, teleporter, ours -- and does
-- NOT say which object fired it. The event payload words (`a`, `b`) and the
-- dispatcher pointer are handed over verbatim on purpose, so that one playtest
-- can pin down which of them identifies the source, instead of the SDK guessing
-- a meaning and mods building on the guess.
--
-- So this probe answers two questions in one run:
--
--   1. does the shrine's prompt appear, fill and succeed?
--   2. which handle names the object, so a mod can react to OUR shrine only?
--
-- Read it back with `rsmm log --grep shrine-probe`, and close the experiment
-- with `rsmm exp answer runestone-shrine poi_interactable pass`.
--
-- The interaction protocol is host-authoritative (a client ASKS, the host
-- validates, the outcome comes back), so `request` is an intent that may never
-- land. Anything real hangs off `success` / `local_success`. This probe only
-- observes -- it changes nothing in the run.

local R = require "rsmm"

-- Our own assets all carry the mod id, so any engine path containing this
-- belongs to the shrine and nothing else in the game does.
local OURS = "runestone_shrine"

-- A live run fires interactions constantly. Past this many lines the probe goes
-- quiet rather than burying the answer in fountain traffic -- except for a hit
-- on our own shrine, which is the thing we are here for and is never silenced.
local LOG_BUDGET = 60

local logged = 0

local function note(text)
    logged = logged + 1
    R.log("[shrine-probe] " .. text)
end

-- Entities already reported on, so a repeated interaction with the same object
-- does not re-dump it. Keyed by pointer.
local seen = {}

R.interact.on("*", function(ev)
    -- `entity` is the object interacted WITH, which the first playtest
    -- (2026-09-17) established is carried by `request` in `b` and by `validate`
    -- as its own dispatcher, 0x4d8 above it. The SDK now normalises both into
    -- this one field.
    local entity = ev.entity

    if entity and not seen[entity] then
        seen[entity] = true
        local name, off = R.interact.name(ev)
        if name then
            note(("entity 0x%x names %q%s"):format(
                entity, name, off and (" (field +0x%x)"):format(off) or ""))
        else
            -- A miss is a result too: it says the name is not reachable by
            -- either walk, and the raw object view is what finds the field.
            note(("entity 0x%x — no name found, dumping it"):format(entity))
            R.debug.dump(entity, 0x200, "shrine-entity")
        end
    end

    local name = entity and R.interact.name(ev) or nil
    if name and name:find(OURS, 1, true) then
        -- ★ Ours, and filterable: this is exactly what a mod needs to react to
        -- its OWN point of interest instead of to every chest in the run.
        note(("★ OUR SHRINE on %s (seq %s) — entity 0x%x named %q"):format(
            tostring(ev.phase), tostring(ev.seq), entity, name))
        if ev.phase == "success" or ev.phase == "local_success" then
            note("★★ INTERACTION SUCCEEDED on the shrine — the POI chain is complete end to end")
        end
        return
    end

    if logged >= LOG_BUDGET then return end
    if logged == LOG_BUDGET - 1 then
        note("log budget reached; staying quiet now except for hits on our own shrine")
    end
    note(("%s seq=%s dispatcher=%s entity=%s a=%s b=%s class=%s"):format(
        tostring(ev.phase), tostring(ev.seq), tostring(ev.dispatcher),
        entity and ("0x%x"):format(entity) or "nil",
        tostring(ev.a), tostring(ev.b), tostring(ev.class)))
end)

R.log("[shrine-probe] armed — interact with the pillar, then: rsmm log --grep shrine-probe")
