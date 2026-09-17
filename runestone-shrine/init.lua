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
        local name, off, all = R.interact.name(ev)
        -- EVERY candidate, not just the chosen one. The first attempt picked a
        -- neighbouring melody's resource path and reported it as the shrine's
        -- name, which is what a single confident answer buys you here.
        note(("entity 0x%x — %d name candidate(s), best=%s%s"):format(
            entity, all and #all or 0, tostring(name),
            off and (" @+0x%x"):format(off) or ""))
        for i, c in ipairs(all or {}) do
            if i > 12 then
                note(("  ... %d more"):format(#all - 12))
                break
            end
            note(("  [%d] +0x%-4x %s%s"):format(
                i, c.at or 0, c.text, c.text:find(OURS, 1, true) and "   <<< OURS" or ""))
        end
        if not all or #all == 0 then
            note("no strings reachable — dumping the object so the field can be found")
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

-- IS THE SHRINE EVEN IN THIS RUN?
--
-- Without this, "no prompt appeared" and "the tile never generated" produce the
-- same evidence: silence. Three runs were spent reading interaction traffic
-- that turned out to be a melody, with no way to tell whether the pillar was
-- standing somewhere unvisited the whole time.
--
-- `R.poi.on_generated` fires once per map generation with the spawner that just
-- placed the tiles, and `R.poi.placed` names what it placed. So each chapter now
-- says out loud whether our tile is in it.
if R.poi and R.poi.on_generated then
    local armed = R.poi.on_generated(function(spawner)
        local entries = R.poi.placed(spawner)
        local ours = {}
        for _, e in ipairs(entries or {}) do
            if e.name and e.name:find(OURS, 1, true) then ours[#ours + 1] = e end
        end
        if #ours == 0 then
            R.log(("[shrine-probe] map generated: %d tile(s) placed, NONE ours — "
                   .. "the shrine is not in this chapter, so nothing to interact with")
                  :format(#(entries or {})))
            return
        end
        for _, e in ipairs(ours) do
            -- `pos` is nil when the placement does not read, and that means
            -- UNKNOWN, never the origin — reporting (0,0,0) would send you to
            -- the wrong corner of the map and read as the tile being missing.
            local where = e.pos
                and (" at (%.0f, %.0f, %.0f)"):format(e.pos[1], e.pos[2], e.pos[3])
                or " (position did not read)"
            R.log(("[shrine-probe] ★ SHRINE TILE PLACED%s — %s%s"):format(
                where, e.name, e.entity and "" or " [no entity — placed but not instantiated]"))
        end
    end)
    if not armed then
        -- Fails closed rather than detouring a stale address, so say so: a
        -- silent probe would read as "the tile never placed".
        R.log("[shrine-probe] tile reporting unavailable on this build "
              .. "(the map-generation symbol did not resolve)")
    end
end

R.log("[shrine-probe] armed — interact with the pillar, then: rsmm log --grep shrine-probe")
