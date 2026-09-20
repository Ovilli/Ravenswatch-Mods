-- Netcode probe. Read-only: session state, host GUID, peer table, RakNet
-- remote-system table, and the GUID -> port -> name join.
--
-- Everything here is a poll. There is deliberately no hook and no engine call:
-- the whole point is to observe a live co-op match without changing how it
-- behaves, because both questions this answers are about what the engine does
-- on its own.
local R = require "rsmm"

local TAG  = "[netcode-probe] "
local last = { state = nil, host = nil, peers = nil, said_solo = false }

local function hex(v)
    if type(v) ~= "number" then return "nil" end
    return ("0x%x"):format(v)
end

-- The join, spelled out: a remote system's GUID identifies the machine, its
-- port identifies the same machine in the peer table, and the peer table is
-- the only place a display NAME lives. Returns "name" or nil -- never a guess.
local function name_for_port(peers, port)
    if not (peers and port) then return nil end
    local hit
    for _, p in ipairs(peers) do
        if p.port == port then
            -- Two peers on one port would identify neither.
            if hit then return nil end
            hit = p
        end
    end
    return hit and hit.name or nil
end

local function snapshot(force)
    local code, name = R.net.session_state()
    local host       = R.net.session_host()
    local peers      = R.net.peers()
    local systems    = R.net.systems()

    -- Solo: no session context at all. Say so ONCE, then stay quiet, so a
    -- single-player run does not fill the log with "nothing here".
    if not code and (not peers or #peers == 0) then
        if not last.said_solo then
            R.log(TAG .. "offline / solo - no P2P session. Start a co-op match.")
            last.said_solo = true
        end
        return
    end
    last.said_solo = false

    local changed = force
    if code ~= last.state then
        R.log(("%sSESSION STATE: %s -> %s (%s)"):format(
            TAG, tostring(last.state), tostring(code), name or "UNNAMED CODE"))
        last.state, changed = code, true
    end
    if host ~= last.host then
        -- This is the line the host-migration question turns on. If it ever
        -- prints a SECOND time in one match, the host moved mid-run.
        R.log(("%sSESSION HOST: %s -> %s%s"):format(
            TAG, hex(last.host), hex(host),
            last.host and "   *** HOST CHANGED MID-MATCH ***" or ""))
        last.host, changed = host, true
    end

    local npeers = peers and #peers or 0
    if npeers ~= last.peers then
        R.log(("%speers: %d -> %d"):format(TAG, last.peers or -1, npeers))
        last.peers, changed = npeers, true
    end
    if not changed then return end

    R.log(("%sstate=%s(%s) host=%s peers=%d systems=%d"):format(
        TAG, tostring(code), name or "?", hex(host), npeers,
        systems and #systems or 0))

    for _, p in ipairs(peers or {}) do
        R.log(("%s  peer #%d name=%s port=%s state=%s"):format(
            TAG, p.index, tostring(p.name), tostring(p.port), tostring(p.state)))
    end

    if not systems then
        R.log(TAG .. "  remote-system table did not resolve (chain not up yet)")
        return
    end
    for _, s in ipairs(systems) do
        local who = name_for_port(peers, s.port)
        R.log(("%s  system guid=%s port=%s state=%s -> %s"):format(
            TAG, hex(s.guid), tostring(s.port), tostring(s.state),
            who or "NO PEER MATCH"))
        if host and s.guid == host then
            R.log(("%s    ^ this system is the SESSION HOST (%s)"):format(
                TAG, who or "unnamed"))
        end
    end

    -- The other half: does a hero's owner GUID appear in that table? If it
    -- does, the join is real and the damage board can name rows from it.
    local hero = R.entity.hero()
    if hero then
        local mine = R.net.owner(hero)
        R.log(("%s  my hero owner guid=%s (local=%s)"):format(
            TAG, hex(mine), tostring(R.net.is_local(hero))))
    end
end

R.schedule.every(5, function() snapshot(false) end)

-- A run starting is the moment the mesh is freshly up, which is the most
-- informative single snapshot in the match. The event is GAME_START, not
-- RUN_START -- the latter is not in the mined catalog, and R.on would have
-- subscribed to a name nothing ever emits, silently.
R.on("gameplay:GAME_START", function() snapshot(true) end)
