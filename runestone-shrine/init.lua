-- THE SHRINE'S INTERACTION — confirmed, and now filterable.
--
-- Settled in game on 2026-09-17: the pillar shows the hold prompt and runs the
-- full protocol (validate -> request -> local_success -> success, with
-- `canceled` on an early release). Tile, mesh, marker and interaction are all
-- proven on a mod-owned POI.
--
-- What this file is still for is the second half: `R.interact` fires for every
-- chest, fountain and teleporter in the run, so a mod needs to know which
-- interaction is ITS OWN.
--
-- That took four attempts and only the last one holds:
--
--   1. first string within 0x1000 of the object   -> a neighbouring melody
--   2. the `+0x220` field                         -> the same melody, stably
--   3. an RTTI walk for an oCEntitySettingsResource -> no such field in range
--   4. POSITION                                   -> works
--
-- The lesson is in the first three: reading strings near an object answers
-- "what text is nearby", which is a different question from "what is this".
-- A coordinate cannot be borrowed from a neighbour. The object reports
-- (-160.5, 0, -22.85) and `R.poi.placed` had already recorded a shrine tile at
-- (-158, 0, -22), so the match is against a number this mod wrote down itself.
--
-- Read it back with `rsmm log --grep shrine-probe`, and close the experiment
-- with `rsmm exp answer runestone-shrine poi_interactable pass`.
--
-- The protocol is host-authoritative (a client ASKS, the host validates), so
-- `request` is an intent that may never land. Anything real hangs off
-- `success` / `local_success`. This probe only observes.

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

-- Where our shrines stand this run, filled in by the tile report below. This is
-- what makes "is this OUR point of interest" answerable: the interacted object
-- reports its own world position, and ours are the only placements we recorded.
local shrines = {}

-- A tile is 6 units across and the prop sits near its origin; the measured gap
-- between the pillar and its tile was about 2.6 units. Ten is comfortably
-- inside "same clearing" without reaching the next one.
local NEAR = 10.0

local function at_a_shrine(pos)
    if not pos then return nil end
    for i, s in ipairs(shrines) do
        local dx, dz = pos[1] - s[1], pos[3] - s[3]
        local d = math.sqrt(dx * dx + dz * dz)
        if d <= NEAR then return i, d end
    end
    return nil
end

R.interact.on("*", function(ev)
    -- `entity` is the object interacted WITH, which the first playtest
    -- (2026-09-17) established is carried by `request` in `b` and by `validate`
    -- as its own dispatcher, 0x4d8 above it. The SDK now normalises both into
    -- this one field.
    local entity = ev.entity

    if entity and not seen[entity] then
        seen[entity] = true
        -- The object's OWN class, straight from RTTI. Unlike a name walk this
        -- cannot pick up a neighbour: it is read off the object's vtable. A
        -- melody pickup and a scenery prop are not the same class, so this
        -- alone separates "the name lookup is wrong" from "the target really
        -- is a melody".
        local cls = R.rtti and R.rtti.name and R.rtti.name(entity) or nil
        note(("entity 0x%x class=%s"):format(entity, tostring(cls)))

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
        -- IDENTITY BY POSITION, because the name walks have now been wrong
        -- twice and this checks itself against numbers we already hold.
        --
        -- The tile report above prints where each shrine was placed. The object
        -- the hero interacts with stands at one of those spots, so its world
        -- position is in this dump — and finding the tile's own coordinates
        -- inside the object both identifies it and names the offset the
        -- position lives at. A name lookup can pick up a neighbour; a
        -- coordinate that matches a placement we recorded cannot.
        R.debug.dump(entity, 0x300, "shrine-entity")
    end

    -- IS THIS OURS? By position, against the placements recorded at generation.
    -- Names were tried three ways and were wrong three ways; a coordinate that
    -- lands on a tile we placed is not a heuristic.
    local which, dist = at_a_shrine(ev.pos)
    if which then
        note(("★ OUR SHRINE #%d on %s (seq %s) — %.1f units from the tile at (%.0f, %.0f, %.0f)")
            :format(which, tostring(ev.phase), tostring(ev.seq), dist,
                    shrines[which][1], shrines[which][2], shrines[which][3]))
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
        -- Each generation replaces the map, so last chapter's coordinates are
        -- not just stale, they are actively wrong: a live interaction could
        -- land within 10 units of a shrine that no longer exists.
        shrines = {}
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
            if e.pos then shrines[#shrines + 1] = { e.pos[1], e.pos[2], e.pos[3] } end
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
