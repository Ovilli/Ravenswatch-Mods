-- HOW MANY NEGATIVE MODES CAN A RUN ACTUALLY CARRY?
--
-- The "5" has been attributed to three places and none survived reading:
--
--   * the challenge page's slot widgets -- the page has NONE. The selected
--     list is spawner-driven (`Selected GameModifier Entity Spawner`), and the
--     only Count values in the asset are browse-list COLUMN counts.
--   * a >=4/5/6 ladder in the page controller -- that gates UI widget GROUPS
--     by profile value 0x1aa35816. Progressive unlocking, not a cap.
--   * `GameModifierUi_PadSelectedSlots` -- it pads the list UP to five and
--     never trims, so five is a FLOOR: a list already holding six would draw
--     six.
--
-- A sweep of all 168 functions in the two controller clusters found no
-- `count >= 5` bound anywhere; every other small compare is a boolean test. So
-- the refusal that plays "Modifier Added Fail" is probably "no free slot"
-- rather than a number.
--
-- Static reading cannot settle that, because the question is what count the
-- display path RECEIVES. This probe watches exactly that.
--
-- WHAT TO DO: open the challenge / custom-run page, add modifiers one at a
-- time, and try to add a sixth. Then:
--
--     rsmm log --grep modifier-cap
--
-- HOW TO READ IT:
--   counts climb 0,1,2..5 and stop           -> the ceiling is upstream, in the
--                                               add path's slot search
--   a count of 6 ever arrives                -> the display already scales and
--                                               only that search needs lifting
--   nothing logs at all                      -> the hook did not arm; the line
--                                               below says why
--
-- Read-only. The original padding runs untouched and nothing is written back.

local R = require "rsmm"

local seen_max = 0
local logged = 0

-- A UI refresh fires this repeatedly with the same number. Only report a count
-- that is new, so the log carries the shape of the climb instead of hundreds of
-- identical lines -- and never goes quiet on a NEW maximum, which is the whole
-- point of the probe.
local counts = {}

local armed = R.modifier.on_slots(function(count, _controller)
    if count == nil then
        if logged < 3 then
            logged = logged + 1
            R.log("[modifier-cap] slot refresh, but the vector did not read")
        end
        return
    end

    if count > seen_max then
        seen_max = count
        R.log(("[modifier-cap] ★ NEW MAXIMUM: %d selected modifier(s) reached the "
               .. "display path%s"):format(
              count, count > 5 and " — ABOVE FIVE, so the display is not the cap"
                              or ""))
        return
    end

    if not counts[count] then
        counts[count] = true
        R.log(("[modifier-cap] %d selected modifier(s)"):format(count))
    end
end)

-- STAGE 2 — ask for a sixth slot.
--
-- Stage 1 (above) established that the stored count stops at five while the
-- engine's padding only ever appends. Since the UI spawns one widget per vector
-- element, a six-element vector should draw a sixth EMPTY slot. What happens
-- when you click it is the whole answer:
--
--   the slot fills   -> "add" just finds a free slot, and the cap is the slot
--                       list alone -- no byte patching needed
--   it refuses       -> the bound lives in the store, and the serialization
--                       risk is the real obstacle
--
-- Off by default because it WRITES to a live engine vector. Turn it on with
-- `slots = 6` in this mod's config (5 = vanilla behaviour, 8 is the ceiling the
-- SDK allows).
local want = R.config and R.config.get("slots", 5) or 5
if armed and type(want) == "number" and want > 5 then
    R.modifier.slot_count(want)
    R.log(("[modifier-cap] STAGE 2: asking for %d slots. Open the custom-run "
           .. "page, then try to fill the extra slot."):format(want))
end

if armed then
    R.log("[modifier-cap] watching. Add modifiers on the custom-run page, and "
          .. "try for a sixth.")
else
    -- Fails closed rather than detouring a stale address, and the usual reason
    -- is a pattern DB older than this symbol -- so say the actionable thing
    -- instead of leaving a silent probe that reads as "nothing happened".
    R.log("[modifier-cap] NOT watching: the symbol did not resolve on this "
          .. "install. Run `rsmm update-data` (the pattern DB ships out of "
          .. "band), or check `rsmm log --errors`.")
end
