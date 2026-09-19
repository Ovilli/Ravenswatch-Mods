-- TILEGEN PROOF — does an edited recipe change what the generator places?
--
-- The manifest LOWERS Dark Hills' Camp count 5 -> 2 and raises the
-- Wishing_Well quota 1 -> 2. Looking at a minimap for "more camps than usual" is a judgement call;
-- the spawner's own placed set is a number. So every map generation is tallied
-- here and compared against both recipes.
--
-- Classifier: all 15 Camp-flagged tiles in the Dark Hills pool, and nothing
-- else, end in `_Camp` (Refugee_Camp_01 / Wandering_Camp_01 / JackOldHouseCamp
-- do not). Storm Island's pool obeys the same rule.
--
-- Verdict per Dark Hills generation:
--   camps <= 2  -> the edited recipe was honoured (PASS)
--   camps >= 5  -> the edit did not bring the count down (FAIL)
--   3 or 4      -> inconclusive; run again
-- Any other chapter is logged as an UNEDITED sample, which is the baseline.
local R = require "rsmm"

-- Count 2, not 8: Storm Island placed 8 camps on 2026-09-19 with its recipe
-- saying 5, so a high count cannot be told from what the generator adds on its
-- own. A LOW count can: only an honoured edit brings Dark Hills down to 2.
local VANILLA_CAMPS, MOD_CAMPS = 5, 2

local function is_dark_hills(entries)
    for _, e in ipairs(entries) do
        if e.name and (e.name:find("Dark_Hills", 1, true)
                       or e.name:find("DarkHills", 1, true)) then
            return true
        end
    end
    return false
end

if not (R.poi and R.poi.on_generated) then
    R.log("[tilegen-proof] R.poi missing on this SDK — cannot measure")
    return
end

-- Is our edit even in the LIVE kind table? The installed file carries Camp
-- count 2 / footprints [0,0,0,1] (checked on disk), yet generation ignored
-- both. Dump the runtime Camp entry once: our 2 and the 0,0,0,1 mask bytes, or
-- the vanilla 5 and 0,0,1,1, answer "not loaded" vs "not consulted".
local dumped = false
local armed = R.poi.on_generated(function(spawner, before)
    if not dumped and before and R.debug and R.debug.dump then
        for _, k in ipairs(before) do
            if k.name == "Camp" and k.entry then
                dumped = true
                R.log(("[tilegen-proof] live Camp kind entry 0x%x (pool %d)"):format(k.entry, k.count))
                R.debug.dump(k.entry, 0x90, "camp-kind")
            end
        end
        if not dumped then
            local ns = {}
            for _, k in ipairs(before) do ns[#ns + 1] = tostring(k.name) end
            R.log("[tilegen-proof] no Camp kind by name; kinds = " .. table.concat(ns, ","))
        end
    end
    local entries, misses = R.poi.placed(spawner)
    entries = entries or {}
    local camps, wells, names = 0, 0, {}
    for _, e in ipairs(entries) do
        local n = e.name or ""
        if n:match("_Camp$") then
            camps = camps + 1
            names[#names + 1] = n
        elseif n:find("Wishing_Well", 1, true) then
            wells = wells + 1
        end
    end
    -- Only Dark Hills carries the edit. The chapter is inferred from tile
    -- names, so it is reported rather than used to suppress the line.
    local where = is_dark_hills(entries) and "Dark Hills"
                  or "chapter ?(no Dark_Hills tile name seen)"
    -- 2026-09-19 (ed36): Camp count 2 still gave 7 camps, so the count is a
    -- floor, not a cap. The decisive edit is now the FOOTPRINT mask: Camp may
    -- not use 40x40 slots. Every map measured so far placed several 40x40
    -- camps, so zero of them is unmistakable.
    local small, large = 0, 0
    for _, n in ipairs(names) do
        if n:sub(1, 6) == "40x40_" then small = small + 1
        elseif n:sub(1, 6) == "64x64_" then large = large + 1 end
    end
    local verdict
    if where == "Dark Hills" then
        if small == 0 and large > 0 then
            verdict = "PASS — footprint edit honoured (no 40x40 camps)"
        elseif small > 0 then
            verdict = "FAIL — 40x40 camps placed despite the footprint edit"
        else
            verdict = "INCONCLUSIVE — no camps named"
        end
    end
    R.log(("[tilegen-proof] %s camps by footprint: 40x40=%d 64x64=%d"):format(where, small, large))
    if verdict then
        R.log("[tilegen-proof] footprint verdict: " .. verdict)
    end
    verdict = nil
    if where ~= "Dark Hills" then
        verdict = "not Dark Hills: an UNEDITED sample (recipe says 5)"
    elseif camps <= MOD_CAMPS then
        verdict = "PASS — edited recipe honoured"
    elseif camps >= VANILLA_CAMPS then
        verdict = "FAIL — the edit did not bring the count down"
    else
        verdict = "INCONCLUSIVE — run again"
    end
    R.log(("[tilegen-proof] %s: %d camp(s) placed (vanilla %d, mod %d), "
           .. "%d wishing well(s) (quota vanilla 1, mod 2), %d tiles, %d unnamed -> %s")
          :format(where, camps, VANILLA_CAMPS, MOD_CAMPS, wells, #entries, misses or 0, verdict))
    for _, n in ipairs(names) do R.log("[tilegen-proof]   camp: " .. n) end
end)

if not armed then
    -- false = the symbol did not resolve OR another mod's state already owns
    -- the detour (R.poi has one owner per launch; rsmm.poi logs which). The
    -- manifest's load_order puts this mod first for exactly that reason.
    R.log("[tilegen-proof] NOT armed (see the [rsmm.poi] line above) — no measurement")
else
    R.log("[tilegen-proof] armed — start a Dark Hills run, then: rsmm log --grep tilegen-proof")
end
