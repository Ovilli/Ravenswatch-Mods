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

--- Names any engine resource paths reachable from a handle.
--
-- `R.interact.identify` is best-effort by construction: it reads the strings
-- hanging off a pointer and keeps the ones shaped like a resource path. That is
-- exactly the right tool for FINDING the identifier and the wrong one to key
-- behaviour on, which is why this probe reports what it sees rather than
-- deciding what it means.
local function probe(label, handle)
    if not handle then return nil end
    local first, all = R.interact.identify(handle)
    if not first then return nil end
    note(("  %s -> %d path(s), first=%s"):format(label, #all, tostring(first)))
    for _, path in ipairs(all) do
        if path:find(OURS, 1, true) then
            return path
        end
    end
    return nil
end

R.interact.on("*", function(ev)
    local quiet = logged >= LOG_BUDGET

    -- Identify BEFORE deciding to stay quiet: a hit on our shrine is the
    -- finding, and budgeting it away would lose the one line that matters.
    local hits = {}
    for _, field in ipairs({ "dispatcher", "a", "b" }) do
        local path = probe(field, ev[field])
        if path then hits[#hits + 1] = field .. "=" .. path end
    end

    if #hits > 0 then
        -- ★ The answer to question 2. Whichever field named our own asset is
        -- the handle a mod can filter on.
        note(("★ OUR SHRINE on %s (seq %s) via %s"):format(
            tostring(ev.phase), tostring(ev.seq), table.concat(hits, ", ")))

        -- The full protocol reaching success is what "the interaction works"
        -- means. Reported as it happens, so a partial run still says how far
        -- it got.
        if ev.phase == "success" or ev.phase == "local_success" then
            note("★★ INTERACTION SUCCEEDED on the shrine — the POI chain is complete end to end")
        end
        return
    end

    if quiet then return end
    if logged == LOG_BUDGET - 1 then
        note("log budget reached; staying quiet now except for hits on our own shrine")
    end
    note(("%s seq=%s dispatcher=%s a=%s b=%s class=%s"):format(
        tostring(ev.phase), tostring(ev.seq), tostring(ev.dispatcher),
        tostring(ev.a), tostring(ev.b), tostring(ev.class)))
end)

R.log("[shrine-probe] armed — interact with the pillar, then: rsmm log --grep shrine-probe")
