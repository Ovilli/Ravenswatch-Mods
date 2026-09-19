-- TILEGEN PROOF — does an edited recipe change what the generator places?
--
-- The manifest raises Dark Hills' Camp count 5 -> 8 and the Wishing_Well quota
-- 1 -> 2. Looking at a minimap for "more camps than usual" is a judgement call;
-- the spawner's own placed set is a number. So every map generation is tallied
-- here and compared against both recipes.
--
-- Classifier: all 15 Camp-flagged tiles in the Dark Hills pool, and nothing
-- else, end in `_Camp` (Refugee_Camp_01 / Wandering_Camp_01 / JackOldHouseCamp
-- do not). The Camp kind has 138 eligible slots against a count of 8, so slot
-- supply is not what would hold the number down.
--
-- Verdict per Dark Hills generation:
--   camps == 8  -> the edited recipe was honoured (PASS)
--   camps == 5  -> the engine placed the vanilla count (FAIL: override ignored)
--   other       -> reported raw; min_distance 100 m can starve a count, so a
--                  6 or 7 is worth a second run before reading it either way.
local R = require "rsmm"

local VANILLA_CAMPS, MOD_CAMPS = 5, 8

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

local armed = R.poi.on_generated(function(spawner)
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
    local verdict
    if camps == MOD_CAMPS then
        verdict = "PASS — edited recipe honoured"
    elseif camps == VANILLA_CAMPS then
        verdict = "FAIL — vanilla count, override ignored"
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
