-- TEST — observe-only probe for issue #54. See manifest.toml.
--
-- Two signals, compared between a run WITH modifiers and one WITHOUT:
--   1. which unlock / achievement / run-end events fire (no hooks: the
--      analytics firehose and the gameplay bus already publish them);
--   2. what the unlock gates answer, per gate instance.
local R = require "rsmm"

local TAG = "[modifier-unlock-probe] "

-- Run modifiers in force right now, as a "name=value" list.
local function modifier_snapshot()
    local parts = {}
    for _, name in ipairs(R.modifier.names()) do
        local v = R.modifier.value(name)
        if type(v) == "number" and v ~= 0 then
            parts[#parts + 1] = name .. "=" .. tostring(v)
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or "none"
end

local function fields(ev)
    if type(ev) ~= "table" then return "" end
    local keys = {}
    for k in pairs(ev) do
        if k ~= "event" and k ~= "seq" and k ~= "source" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. tostring(ev[k]) end
    return table.concat(out, ", ")
end

-- 1. Events. Every analytics event is logged (a handful per run); gameplay-bus
-- events only when the name looks unlock / achievement / run-end related.
local GAMEPLAY_PATTERNS = { "UNLOCK", "ACHIEV", "COUNTER", "GAME_END", "TROPH" }

local function interesting(name)
    if type(name) ~= "string" then return false end
    for _, p in ipairs(GAMEPLAY_PATTERNS) do
        if name:find(p, 1, true) then return true end
    end
    return false
end

R.on("*", function(ev, name)
    local analytics = type(ev) == "table" and ev.source == "analytics"
    if not (analytics or interesting(name)) then return end
    local extra = ""
    if name == "run_start" or name == "run_end" or name == "chapter_end" then
        extra = " modifiers: " .. modifier_snapshot()
    end
    R.log(TAG .. tostring(name) .. " {" .. fields(ev) .. "}" .. extra)
end)

-- 2. Gate answers. Logged once per (gate, instance, answer) so a per-frame UI
-- poll cannot flood the log; hard cap as a backstop.
-- AdditionalContentGate (ownership) is observed, never forced.
local GATES = {
    "ChallengeUnlock_IsUnlocked",
    "HeroProgressionUnlock_IsUnlocked",
    "HeroRankLock_IsUnlocked",
    "HeroStoryUnlock_IsUnlocked",
    "AdditionalContentGate_IsUnlocked",
}
local MAX_GATE_LINES = 400
local seen, lines, hooked = {}, 0, {}

for _, name in ipairs(GATES) do
    local ok = R.debug.observe(name, "up", function(r, this)
        local key = name .. ":" .. tostring(this) .. ":" .. tostring(r)
        if seen[key] or lines >= MAX_GATE_LINES then return end
        seen[key] = true
        lines = lines + 1
        R.log(("%s%s this=0x%x -> %s"):format(TAG, name, this or 0, tostring(r)))
        if lines == MAX_GATE_LINES then R.log(TAG .. "gate log cap reached") end
    end)
    hooked[#hooked + 1] = name .. (ok and "" or " UNAVAILABLE")
end
R.log(TAG .. "gate observers: " .. table.concat(hooked, ", "))
