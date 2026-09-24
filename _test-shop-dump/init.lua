-- Read-only DEV PROBE, local only, delete after use. Uses loader internals on
-- purpose: no SDK surface reaches the Sandman controller yet (that is what this
-- probe is for). The Sandman does not fire interaction `request`, so it hooks
-- the controller's own open routine instead:
--   oCDtEntityCpntSandmanMenuUiController vft 0x140f333a0 slot 28 = 0x14036e320
-- Open the shop, wait 5 s, close it, open it again.
local native = rawget(_G, "rsmm")
local I = native._internal or native
local R = require "rsmm"

local IMG = 0x140000000
local OPEN_VA = 0x14036e320

local function hx(v) return type(v) == "number" and ("0x%x"):format(v) or tostring(v) end
local function L(fmt, ...) R.log("[TEST shop] " .. fmt:format(...)) end

-- A {begin, count-or-end} pair: returns begin, n.
local function vec(p, off)
    local b = I.read_u64(p + off)
    local e = I.read_u64(p + off + 8)
    if not b or b == 0 then return b, 0, e end
    if e and e > b and e - b < 0x10000 then return b, (e - b) // 8, e end
    if e and e < 0x1000 then return b, e, e end
    return b, nil, e
end

local function dump_offer(tag, o)
    L("%s offer %s class=%s", tag, hx(o), tostring(R.rtti.name(o)))
    R.debug.dump(o, 0x100, "TEST shop " .. tag .. " offer")
    local inner = I.read_u64(o + 0x280)
    if inner and R.ptr.plausible(inner) then
        local def = I.read_u64(inner + 0x10)
        L("%s   ->+0x280 %s (%s) ->+0x10 %s (%s), strings follow", tag, hx(inner),
            tostring(R.rtti.name(inner)), hx(def), tostring(def and R.rtti.name(def)))
        if def then R.debug.strings(def) end
    end
end

local function dump_ctrl(ctrl, when)
    L("%s ctrl=%s class=%s", when, hx(ctrl), tostring(R.rtti.name(ctrl)))
    R.debug.dump(ctrl, 0x280, "TEST shop " .. when .. " ctrl")
    for i = 0, 6 do
        local d = I.read_u64(ctrl + 0x138 + 8 * i)
        if d and R.ptr.plausible(d) then
            local tag = ("%s drop#%d"):format(when, i)
            L("%s %s class=%s", tag, hx(d), tostring(R.rtti.name(d)))
            R.debug.dump(d, 0x280, "TEST shop " .. tag)
            for _, off in ipairs({ 0x230, 0x250 }) do
                local b, n, e = vec(d, off)
                L("%s vec+0x%x begin=%s second=%s n=%s", tag, off, hx(b), hx(e), tostring(n))
                if b and b ~= 0 and n then
                    for k = 0, math.min(n, 4) - 1 do
                        local o = I.read_u64(b + 8 * k)
                        if o and R.ptr.plausible(o) then
                            dump_offer(("%s +0x%x[%d]"):format(tag, off, k), o)
                        else
                            L("%s +0x%x[%d] = %s (not a pointer)", tag, off, k, hx(o))
                        end
                    end
                end
            end
        else
            L("%s drop#%d = %s (not a pointer)", when, i, hx(d))
        end
    end
end

local opens = 0
local base = I.module_base()
if not base or base == 0 then
    L("module base unknown; probe disabled")
    return
end
local ok, err = pcall(R.hook, base + (OPEN_VA - IMG), "vp", function(ctrl)
    opens = opens + 1
    if opens > 3 or not ctrl or ctrl == 0 then return nil end
    local n = opens
    L("open #%d ctrl=%s (before the engine's open runs)", n, hx(ctrl))
    R.schedule.after(1, function() dump_ctrl(ctrl, ("open%d+1s"):format(n)) end)
    return nil
end)
L("hook on Sandman open: %s %s", tostring(ok), tostring(err))
