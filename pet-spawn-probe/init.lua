-- Diagnostic (local only): watch Blood Wolf's "Kit Pet" spawner.
-- EntitySpawner_SpawnOne(self): self = the spawner component instance;
-- self+0x10 its settings (name pointer at settings+0xe8), self+0x08 its entity,
-- spawned entities at self+0x210 (count +0x218), records count +0x1c8
-- (Ghidra b9c3, 2026-11-03).
local R = require "rsmm"
local I = R._internal
local TAG = "[pet-spawn-probe] "
local ok_ptr = R.ptr.plausible

local function settings_name(inst)
    local s = ok_ptr(inst) and I.read_u64(inst + 0x10) or nil
    local sp = ok_ptr(s) and I.read_u64(s + 0xe8) or nil
    return ok_ptr(sp) and I.read_cstr(sp, 120) or "?"
end

local watch, lines = {}, 0
local function log(fmt, ...)
    lines = lines + 1
    if lines <= 400 then R.log(TAG .. string.format(fmt, ...)) end
end

local before = {}
local ok1 = R.debug.observe("EntitySpawner_SpawnOne", "vp", function(_, self)
    local nm = settings_name(self)
    if not nm:find("Kit Pet", 1, true) then return end
    local recs = I.read_u32(self + 0x1c8) or -1
    local n = I.read_u32(self + 0x218) or 0
    local arr = I.read_u64(self + 0x210)
    local e = (n > 0 and ok_ptr(arr)) and I.read_u64(arr + (n - 1) * 8) or 0
    log("%s: SpawnOne done, records=%d spawned=%d last=0x%x class=%s",
        nm, recs, n, e or 0, tostring(ok_ptr(e) and R.rtti.name(e)))
    if ok_ptr(e) and not watch[e] then watch[e] = { nm = nm, age = 0 } end
end)
local ok2 = R.debug.observe("EntitySpawner_InstantiateRecord", "vpp", function(_, self, rec)
    local nm = settings_name(self)
    if nm:find("Kit Pet", 1, true) then log("%s: InstantiateRecord rec=0x%x", nm, rec or 0) end
end)
log("observers: SpawnOne=%s InstantiateRecord=%s", tostring(ok1), tostring(ok2))

R.schedule.every(2, function()
    for e, w in pairs(watch) do
        w.age = w.age + 2
        local cls = R.rtti.name(e)
        local comps = I.read_u32(e + 0x198)
        log("  0x%x (%s) after %ds: class=%s components=%s", e, w.nm, w.age,
            tostring(cls), tostring(comps))
        if cls ~= "oCEntity" or w.age >= 20 then watch[e] = nil end
    end
end)
