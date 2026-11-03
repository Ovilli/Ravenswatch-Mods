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
-- Not in the loader's symbol table (observe() said "unknown symbol"), so by
-- address: module base + the RVA on build b9c3642884a8 (Ghidra).
local BASE = I.module_base()
local function observe_at(rva, sig, after)
    if not BASE or BASE == 0 then return false end
    local ok, slot = pcall(R.hook, BASE + rva, sig, function(...)
        local n = select("#", ...)
        local nxt = select(n, ...)
        local args = { ... }
        args[n] = nil
        local r = nxt(table.unpack(args, 1, n - 1))
        local ran, err = pcall(after, r, table.unpack(args, 1, n - 1))
        if not ran then R.log(TAG .. "handler error: " .. tostring(err)) end
        return r or 0
    end)
    return ok and slot ~= nil
end

local any = 0
local ok1 = observe_at(0x72e920, "vp", function(_, self)        -- EntitySpawner_SpawnOne
    local nm = settings_name(self)
    any = any + 1
    if any <= 60 then log("any SpawnOne #%d: %s", any, nm) end
    if not nm:find("Kit Pet", 1, true) then return end
    local recs = I.read_u32(self + 0x1c8) or -1
    local n = I.read_u32(self + 0x218) or 0
    local arr = I.read_u64(self + 0x210)
    local e = (n > 0 and ok_ptr(arr)) and I.read_u64(arr + (n - 1) * 8) or 0
    local s = I.read_u64(self + 0x10)
    local tmpl = ok_ptr(s) and I.read_u64(s + 0x1a8) or 0
    log("%s: SpawnOne done, template resource=0x%x records=%d spawned=%d last=0x%x class=%s",
        nm, tmpl or 0, recs, n, e or 0, tostring(ok_ptr(e) and R.rtti.name(e)))
    if ok_ptr(e) and not watch[e] then watch[e] = { nm = nm, age = 0 } end
end)
local ok2 = observe_at(0x72f750, "vpp", function(_, self, rec)  -- EntitySpawner_InstantiateRecord
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

-- Which kit parts exist on the live hero? Its components are at entity+0x190
-- (count +0x198); each instance's settings at +0x10, name pointer at +0xe8
-- (R.debug.components' layout). Logged once per run, 8 s after capture.
local listed = false
local function list_kit_parts()
    if listed or not R.entity.ready() then return end
    local ctrl = R.entity.hero()
    local e = ok_ptr(ctrl) and I.read_u64(ctrl + 0x08) or nil
    if not ok_ptr(e) then return end
    local arr, n = I.read_u64(e + 0x190), I.read_u32(e + 0x198)
    if not ok_ptr(arr) or not n or n == 0 or n > 8192 then return end
    listed = true
    local hits = 0
    for pos = 0, n - 1 do
        local nm = settings_name(I.read_u64(arr + pos * 8))
        if nm:find("Kit ", 1, true) or nm:find("Wolf Lock", 1, true) then
            hits = hits + 1
            log("hero part %d: %s", pos, nm)
        end
    end
    log("hero has %d components, %d kit/lock parts (name: %s)", n, hits,
        tostring(R.interact and R.interact.name and R.interact.name(e)))
end
R.on("run:start", function() listed = false end)
R.schedule.every(8, list_kit_parts)

-- Is the pet registered with the hero? Character_Common's "Registered entities
-- holder" keeps its entries at instance+0x68 (count +0x70); each entry is a
-- pet's "Register Alive in owners" component (its entity at +0x08). The alive
-- listener's count output sits at +0x180, its reader count at +0x188
-- (Ghidra b9c3: FUN_140739450, FUN_140752830).
local function find_part(e, want)
    local arr, n = I.read_u64(e + 0x190), I.read_u32(e + 0x198)
    if not ok_ptr(arr) or not n or n > 8192 then return nil end
    for pos = 0, n - 1 do
        local inst = I.read_u64(arr + pos * 8)
        if settings_name(inst) == want then return inst end
    end
end
R.schedule.every(5, function()
    if not R.entity.ready() then return end
    local ctrl = R.entity.hero()
    local e = ok_ptr(ctrl) and I.read_u64(ctrl + 0x08) or nil
    if not ok_ptr(e) then return end
    local h = find_part(e, "Registered entities holder")
    if h then
        local vec, cnt = I.read_u64(h + 0x68), I.read_u32(h + 0x70) or -1
        local names = {}
        for k = 0, math.min(cnt, 8) - 1 do
            local entry = ok_ptr(vec) and I.read_u64(vec + k * 8)
            local pe = ok_ptr(entry) and I.read_u64(entry + 0x08)
            names[#names + 1] = tostring(ok_ptr(pe) and R.interact and R.interact.name and R.interact.name(pe))
        end
        log("holder: %d registered [%s]", cnt, table.concat(names, ", "))
    else
        log("holder: none on the hero")
    end
    local l = find_part(e, "Kit Pet Alive Listener")
    if l then
        log("alive listener: count=%s readers=%s", tostring(I.read_u32(l + 0x180)),
            tostring(I.read_u32(l + 0x188)))
    else
        log("alive listener: not on the hero")
    end
end)
