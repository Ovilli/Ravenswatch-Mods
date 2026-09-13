-- Serializer Bridge Probe — see manifest.toml for what it is measuring.
--
-- The claim under test: `Serialize` (vftable slot 3) is direction-agnostic, so
-- handing a live definition to the engine's own oCBinarySaver writes a cooked
-- file — payload bytes included, without rsmm having decoded them. If that
-- holds, every "the codec carries this as opaque _tail_hex" problem has a way
-- out, and a map editor has a save path.
--
-- Everything here runs on the MAIN thread: the saver opens a file, vcalls into
-- the object and allocates on the game's heap. R.schedule.after_main is what
-- guarantees that (see [[loader-thread-model]]).

local R = require "rsmm"

-- Degrade against an SDK that predates exp. An old planted lib/ with a newer
-- mod is the normal state between updating a mod and running
-- `rsmm update-loader`, and a mod that HARD-ERRORS at load there does not
-- merely lose its readout -- it does not run at all, which costs the playtest
-- this harness exists to make cheap.
local exp = R.exp or {
    case    = function() end,
    observe = function() end,
    verdict = function(_, pass) return pass end,
    run     = function(_, _, fn) pcall(fn) end,
}

-- `x or default` is WRONG for a boolean key: a configured `false` is falsy, so
-- it would silently read back as the default. Go through one helper that only
-- falls back when R.config itself is missing.
local function cfg(key, default)
    if R.config and R.config.get then return R.config.get(key, default) end
    return default
end

local CLASS = cfg("target_class", "oCDtEnemyDefinition")
local DUMP  = cfg("dump_registry", true)
local DELAY = cfg("delay", 20)
local COUNT = cfg("count", 1)
local MUTATE = cfg("mutate", false)
local SENTINEL = cfg("sentinel", 77)

-- The questions, declared before anything runs so an early return leaves them
-- readable as NO-DATA rather than as silence. `rsmm exp` prints them.
exp.case("bridge_resolvable", "does Object_SaveToFile resolve on this build?")
exp.case("registry_readable", "is the definition registry readable?")
exp.case("engine_wrote_file", "does the engine's own saver write a cooked file when a mod asks?")

local function probe()
    -- 1. Is the bridge even resolvable on this build? A false here is a
    --    symbol-map/game-build mismatch, not a failure of the idea.
    if not R.serialize.ready() then
        exp.verdict("bridge_resolvable", false,
                      "Object_SaveToFile unresolved — symbol map vs game build")
        R.log("[probe] Object_SaveToFile did not resolve — symbol map vs game build "
              .. "mismatch. Run `rsmm update-data`, then `rsmm symbols audit` after a "
              .. "launch with RSMM_DUMP_SYMBOLS.")
        return
    end
    exp.verdict("bridge_resolvable", true, "Object_SaveToFile resolved")
    if not R.defs.ready() then
        -- why_not() names WHICH of the five failures it was. The first run of
        -- this probe printed a five-cause message and cost a launch to
        -- diagnose (it was the missing image rebase, fixed in the SDK).
        exp.verdict("registry_readable", false, tostring(R.defs.why_not()))
        R.log("[probe] definition registry unreadable: " .. tostring(R.defs.why_not()))
        return
    end
    exp.verdict("registry_readable", true, "registry readable")

    -- 2. What does the game actually hold? Useful on its own.
    if DUMP then R.defs.dump() end

    -- 3. Take the first COUNT live instances and ask the engine to write them.
    --    More than one matters for a class whose payload rsmm cannot decode:
    --    a single byte-identical file could be luck, eight cannot.
    local defs = R.defs.instances(CLASS, COUNT)
    exp.observe("engine_wrote_file", "class", CLASS)
    exp.observe("engine_wrote_file", "instances", #defs)
    if #defs == 0 then
        exp.verdict("engine_wrote_file", false,
                      "no live instance of " .. CLASS .. " to write")
        R.log(("[probe] no live instance of %q — try another class from the dump "
               .. "above, via the target_class config key."):format(CLASS))
        return
    end
    local name = R.rtti.name(defs[1]) or CLASS
    R.log(("[probe] target %s x%d (first @0x%x)"):format(name, #defs, defs[1]))

    -- NOT R.serialize.clone here, tempting as a no-disk smoke test is: clone
    -- DESERIALIZES OVER its destination, so every candidate destination is a
    -- live definition the game is still using. There is no spare object to
    -- aim it at, so the first probe goes straight to the file.
    --
    -- The path is flat on purpose: the engine's file stream opens a file, it
    -- does not create directories, so a "dump/" prefix would fail as a write
    -- error and read like the bridge itself failed. `::` in a namespaced class
    -- name is not a legal filename either.
    local stem = name:gsub("[^%w%-_%.]", "_")
    local wrote, failed = 0, 0
    for i, def in ipairs(defs) do
        local leaf = (#defs == 1) and (stem .. ".ot")
                      or ("%s_%02d.ot"):format(stem, i)
        local ok, err = R.serialize.save(def, leaf)
        if ok then
            wrote = wrote + 1
            R.log(("[probe] WROTE %s"):format(err))   -- second return is the path
        else
            failed = failed + 1
            R.log(("[probe] save refused (#%d @0x%x): %s"):format(i, def, tostring(err)))
        end
    end
    -- 4. MUTATION EXPERIMENT (opt-in). Does a change made to the LIVE object
    --    reach the bytes the engine writes? That is the difference between
    --    "the engine can re-emit what it loaded" and "we can author with it".
    --
    --    The field picked is a tiledef's {width,height} pair: both are u32, the
    --    footprint set is a known small vocabulary ({3,6,20,40,50,64}) and both
    --    halves are equal on a square tile, which is what makes the pair
    --    findable without knowing the struct. Every candidate is written for
    --    the duration of ONE save and restored immediately (R.debug.with_u32),
    --    so a wrong guess cannot outlive the call.
    if MUTATE then
        exp.case("mutation_reaches_bytes",
                   "does a change to the LIVE object reach the bytes the engine writes?")
        local obj = defs[1]
        local cands = {}
        for _, v in ipairs({ 3, 6, 20, 40, 50, 64 }) do
            for _, hit in ipairs(R.debug.find_u32(obj, v,
                    { max_off = 0x400, pairs_with = v, log = false })) do
                cands[#cands + 1] = { off = hit.off, value = v }
            end
        end
        R.log(("[probe] mutation: %d square-footprint candidate(s) on 0x%x")
              :format(#cands, obj))
        for i, c in ipairs(cands) do
            if i > 6 then
                R.log("[probe] mutation: stopping at 6 candidates")
                break
            end
            local leaf = ("mut_%04x_%d.ot"):format(c.off, c.value)
            local res, why = R.debug.with_u32(obj, c.off, SENTINEL, function()
                return { R.serialize.save(obj, leaf) }
            end)
            if res and res[1] then
                R.log(("[probe] mutation: +0x%x (was %d -> %d) saved as %s")
                      :format(c.off, c.value, SENTINEL, leaf))
            else
                R.log(("[probe] mutation: +0x%x refused: %s")
                      :format(c.off, tostring(why or (res and res[2]))))
            end
        end
        exp.observe("mutation_reaches_bytes", "candidates", #cands)
        -- Whether the sentinel actually LANDED in the bytes is a diff, not
        -- something this process can see. Left open on purpose.
        R.log("[probe] mutation: every candidate was restored after its save")
    end

    exp.observe("engine_wrote_file", "written", wrote)
    exp.observe("engine_wrote_file", "refused", failed)
    -- Written is not yet PROVEN-CORRECT: the bytes still have to match the
    -- shipped cooked file. That diff happens on disk, afterwards, so it is a
    -- case of its own for a person to close.
    exp.verdict("engine_wrote_file", wrote > 0,
                  wrote .. " written, " .. failed .. " refused")
    exp.case("bytes_match_shipped",
               "does a written file match its shipped cooked original? (diff on disk, then `rsmm exp answer`)")

    R.log(("[probe] %d written, %d refused. Next: diff each against its shipped "
           .. "cooked file — the engine writes container type B, so promote the "
           .. "header (rsmm.engine.cooked.promote_to_cooked) before comparing.")
          :format(wrote, failed))
end

R.on("ready", function()
    R.log(("[probe] armed — dumping %s in %.0fs (main thread)"):format(CLASS, DELAY))
    R.schedule.after_main(DELAY, function()
        local ok, err = pcall(probe)
        if not ok then
            -- The probe died part-way. Say so against the case it was in the
            -- middle of, rather than leaving a NO-DATA that reads as "never ran".
            exp.verdict("engine_wrote_file", false, "probe raised: " .. tostring(err))
            R.log("[probe] raised: " .. tostring(err))
        end
    end)
end)
