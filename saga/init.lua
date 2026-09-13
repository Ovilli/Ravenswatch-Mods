-- Saga — the meta-progression Ravenswatch does not ship.
--
-- The game forgets you between runs. This keeps a ledger: a global XP bar and
-- a rank that grow across every run you have ever played, feats that unlock
-- once and stay unlocked, and a rotating set of objectives that pay XP when
-- you finish them.
--
-- It is read-only by construction. It subscribes to the event bus, counts, and
-- writes to its own key-value store — no engine call, so there is no
-- main-thread rule to obey (see the loader thread model), nothing to break,
-- and nothing another peer can observe. `multiplayer_scope = "local-only"`.
--
-- Everything below the helpers is DATA: XP weights, the feat table and the
-- objective pool are plain tables. Adding one is a row, not code.

local R = require "rsmm"

local cfg = {
    slots      = R.config.get("quest_slots", 3),
    mult       = R.config.get("xp_multiplier", 1.0),
    overlay    = R.config.get("show_overlay", true),
    on_run_end = R.config.get("report_on_run_end", true),
    on_menu    = R.config.get("report_on_menu", true),
    mine_only  = R.config.get("attribute_to_me", true),
    -- Challenge generator. "off" disables the whole layer; a tier name rolls
    -- that tier; weekly_a/weekly_b roll a tier from the weekly lists.
    ch_tier    = R.config.get("challenge_tier", "off"),
    ch_seed    = R.config.get("challenge_seed", ""),
    ch_coop    = R.config.get("challenge_coop", false),
    ch_apply   = R.config.get("challenge_apply", false),
    ch_hero    = R.config.get("challenge_hero", ""),
    ch_preset  = R.config.get("challenge_preset", ""),
}

-- ---------------------------------------------------------------------------
-- 1. Metrics — the raw counters everything else is expressed in.
--
-- One bus event, one metric. Lifetime totals live in R.kv as `total_<metric>`;
-- the per-run column is a plain table rebuilt at every run boundary.
-- ---------------------------------------------------------------------------

local METRIC = {
    ENEMY_KILLED            = "kills",
    BOSS_DEFEATED           = "bosses",
    BABAYAGA_HOUSE_DEFEATED = "bosses",
    OPEN_CHEST              = "chests",
    GIVE_MAGICAL_OBJECT     = "items",
    CHOOSE_MELODY           = "melodies",
    HERO_DEATH_DOOR         = "downs",
    HERO_REVIVE             = "revives",
    USE_HEAL_FOUNTAIN       = "fountains",
    USE_BLOOD_FOUNTAIN      = "fountains",
    GAIN_DREAM_SHARDS       = "shards",
    WISHING_WELL_FILLED     = "wells",
    STORY_QUEST_FINISHED    = "story",
    GRIMOIRE_QUEST_FINISHED = "grimoire",
    GAME_END_NEXT_CHAPTER   = "chapters",
    START_NIGHTMARE         = "nightmares",
    ALTAR_OF_HEROES_PAID    = "altars",
}

-- What each metric is worth. A kill is the unit; everything else is priced
-- against how rare it is, not how hard it is — the objectives below are what
-- reward playing well.
local XP = {
    kills = 1, bosses = 150, chests = 8, items = 12, melodies = 25,
    revives = 20, fountains = 5, shards = 2, wells = 15, story = 200,
    grimoire = 75, chapters = 250, nightmares = 100, altars = 30,
    downs = 0, levels = 30, wins = 750, losses = 60, runs = 25,
    flawless = 500,
    -- Quitting is not a result. It costs the run's XP, not more, and it stays
    -- out of the winrate denominator below.
    abandons = 0,
}

-- Metrics that are not a bus event: raised by the run-boundary logic.
--   wins/losses  run outcome        levels  hero level-ups
--   flawless     a win with no downs        runs  runs started
local ORDER = { "kills", "bosses", "chests", "items", "melodies", "revives",
                "downs", "shards", "chapters", "story", "grimoire" }

-- Personal bests. `downs` is in ORDER because the run summary should say you
-- went down twice; it is NOT in here, because "most times downed" is not a
-- record anyone wants to beat.
local RECORDS = { "kills", "bosses", "chests", "items", "melodies", "chapters" }

-- ---------------------------------------------------------------------------
-- 1b. Attribution — whose event was that?
--
-- In co-op the bus is not yours alone: a replicated event is dispatched on
-- every machine, so an unfiltered counter records the PARTY's kills as your
-- own, and "flawless" quietly comes to mean "nobody went down" instead of
-- "I didn't".
--
-- What identifies the actor is `ev.dispatcher` — the NamedEventDispatcher the
-- event was delivered to, which for a hero-anchored event is that hero's own.
-- (The sender session id at ev+0x38 is NOT it: three playtests found the base
-- oCGameNamedEvent carrying a handle or the -1 sentinel there, and the loader
-- stopped publishing it on 2026-08-20.) `R.hero.handle()` is the local hero's
-- dispatcher, and the SDK already refuses to let an ally's clobber it.
--
-- The missing half is telling "another hero's dispatcher" from "not a hero's
-- at all" — a world-anchored event belongs to nobody, and dropping those would
-- zero the mod out in solo. So allies are LEARNED: any dispatcher that fires a
-- hero-anchored event is some hero's, and the ones that are not mine are
-- theirs. Nothing else is ever filtered.
--
-- This fails OPEN by construction. An event is dropped only when it was
-- positively identified as another player's hero; an unknown dispatcher, a
-- world event, or a session where the local hero has not acted yet all count
-- exactly as they did before, so solo cannot regress.
--
-- WHICH events this actually reaches is a playtest question, not a static one:
-- an event anchored on the world rather than on a hero is unattributable and
-- stays party-wide. The one-line-per-event log below answers it in a single
-- co-op launch — read it before assuming a counter is now personal.
-- ---------------------------------------------------------------------------

-- Hero-anchored events, used only to learn who is a hero. Same list the SDK
-- captures the local hero from; they fire at the acting hero's own dispatcher.
local ANCHORS = { "GAIN_DREAM_SHARDS", "ABILITY_EXIT", "COMBO_LINK",
                  "ENERGY_COUNTER_INC" }

local ally, seen_kind = {}, {}

local function disp_of(ev)
    local d = ev and ev.dispatcher
    d = (type(d) == "string" or type(d) == "number") and tonumber(d) or nil
    if d == 0 then return nil end
    return d
end

local function my_disp()
    local ok, me = pcall(function() return R.hero and R.hero.handle and R.hero.handle() end)
    if ok and type(me) == "number" and me ~= 0 then return me end
    return nil
end

local function note_hero(ev)
    local d, me = disp_of(ev), my_disp()
    -- Only while the local hero is known. Learning before that would file MY
    -- OWN dispatcher as an ally and then silently drop everything I do.
    if d and me and d ~= me then ally[d] = true end
end

-- Returns true when the event should count. `name` is only for the log.
local function mine(name, ev)
    if not cfg.mine_only then return true end
    local d, me = disp_of(ev), my_disp()
    local kind = "unattributed"
    if d and me then
        if d == me then kind = "mine" elseif ally[d] then kind = "ally" end
    end
    -- Once per event name per verdict. A counter that turns out to be
    -- party-wide is invisible otherwise — it just reads as a generous number.
    if seen_kind[name] ~= kind then
        seen_kind[name] = kind
        R.log(("[Saga] attribution: %s -> %s"):format(name, kind))
    end
    return kind ~= "ally"
end

-- ---------------------------------------------------------------------------
-- 2. Rank curve.
--
-- Cost to leave level n is 750*n — linear, so the bar keeps moving for a long
-- time instead of stalling the way an exponential curve does after level 20.
-- Calibrated against a real run: a won run pays roughly 2500-3000 XP, which is
-- three levels early on and a fraction of one by level 20. A cheaper curve was
-- tried first and handed out seven levels in a single run, which makes the
-- rank meaningless by the end of the first evening. The loop is bounded so a
-- corrupt XP value cannot spin forever.
-- ---------------------------------------------------------------------------

local TITLES = {
    { 60, "Myth" }, { 45, "Legend" }, { 30, "Ravenswatch" },
    { 20, "Nightwarden" }, { 15, "Sentinel" }, { 10, "Watcher" },
    { 5, "Wanderer" }, { 1, "Stranger" },
}

local function rank(xp)
    local lvl, need, spent = 1, 750, 0
    while lvl < 200 and xp >= spent + need do
        spent, lvl = spent + need, lvl + 1
        need = 750 * lvl
    end
    local title = "Stranger"
    for _, band in ipairs(TITLES) do
        if lvl >= band[1] then title = band[2]; break end
    end
    return lvl, title, xp - spent, need
end

-- ---------------------------------------------------------------------------
-- 3. Feats — unlock once, stay unlocked. `need` is a LIFETIME total.
-- ---------------------------------------------------------------------------

local FEATS = {
    { id = "first_blood",  name = "First Blood",        metric = "kills",      need = 1,     xp = 50 },
    { id = "cull_1k",      name = "Cull the Dark",      metric = "kills",      need = 1000,  xp = 400 },
    { id = "cull_10k",     name = "Tide of Iron",       metric = "kills",      need = 10000, xp = 2500 },
    { id = "bosses_10",    name = "Giant-Slayer",       metric = "bosses",     need = 10,    xp = 500 },
    { id = "bosses_50",    name = "The Nightmare Ends", metric = "bosses",     need = 50,    xp = 2000 },
    { id = "chests_100",   name = "Magpie",             metric = "chests",     need = 100,   xp = 400 },
    { id = "items_250",    name = "Hoarder",            metric = "items",      need = 250,   xp = 600 },
    { id = "melodies_50",  name = "Songkeeper",         metric = "melodies",   need = 50,    xp = 500 },
    { id = "revives_25",   name = "Shield of Others",   metric = "revives",    need = 25,    xp = 500 },
    { id = "runs_10",      name = "Regular",            metric = "runs",       need = 10,    xp = 250 },
    { id = "runs_100",     name = "Devoted",            metric = "runs",       need = 100,   xp = 1500 },
    { id = "first_win",    name = "Dawn At Last",       metric = "wins",       need = 1,     xp = 1000 },
    { id = "wins_10",      name = "Repeat Offender",    metric = "wins",       need = 10,    xp = 3000 },
    { id = "flawless_1",   name = "Untouched",          metric = "flawless",   need = 1,     xp = 1200 },
    { id = "flawless_5",   name = "Unbroken",           metric = "flawless",   need = 5,     xp = 4000 },
    { id = "story_10",     name = "Loose Ends",         metric = "story",      need = 10,    xp = 600 },
    { id = "nightmare_1",  name = "Into the Nightmare", metric = "nightmares", need = 1,     xp = 400 },
    { id = "chapters_25",  name = "Long Road",          metric = "chapters",   need = 25,    xp = 800 },
}

-- ---------------------------------------------------------------------------
-- 4. Objectives — a rotating handful, drawn from this pool.
--
-- scope = "run"  progress is this run's counter and resets with it.
-- scope = "life" progress is the lifetime counter minus what it was when the
--                objective was handed out, so it survives restarts without
--                needing a separate progress key to keep in sync.
-- ---------------------------------------------------------------------------

local POOL = {
    { id = "q_kill_run_150",  scope = "run",  metric = "kills",    need = 150, xp = 300,  name = "Kill 150 in one run" },
    { id = "q_kill_run_400",  scope = "run",  metric = "kills",    need = 400, xp = 700,  name = "Kill 400 in one run" },
    { id = "q_boss_run_2",    scope = "run",  metric = "bosses",   need = 2,   xp = 400,  name = "Two bosses in one run" },
    { id = "q_chest_run_10",  scope = "run",  metric = "chests",   need = 10,  xp = 250,  name = "Open 10 chests in one run" },
    { id = "q_item_run_12",   scope = "run",  metric = "items",    need = 12,  xp = 300,  name = "Carry 12 objects" },
    { id = "q_mel_run_3",     scope = "run",  metric = "melodies", need = 3,   xp = 250,  name = "Three melodies in one run" },
    { id = "q_rev_run_2",     scope = "run",  metric = "revives",  need = 2,   xp = 250,  name = "Revive an ally twice" },
    { id = "q_chap_run_3",    scope = "run",  metric = "chapters", need = 3,   xp = 600,  name = "Reach chapter 3" },
    { id = "q_kill_life_1k",  scope = "life", metric = "kills",    need = 1000,xp = 600,  name = "Kill 1000 monsters" },
    { id = "q_kill_life_3k",  scope = "life", metric = "kills",    need = 3000,xp = 1200, name = "Kill 3000 monsters" },
    { id = "q_boss_life_10",  scope = "life", metric = "bosses",   need = 10,  xp = 700,  name = "Fell 10 bosses" },
    { id = "q_chest_life_60", scope = "life", metric = "chests",   need = 60,  xp = 450,  name = "Open 60 chests" },
    { id = "q_item_life_120", scope = "life", metric = "items",    need = 120, xp = 500,  name = "Collect 120 objects" },
    { id = "q_shard_life_2k", scope = "life", metric = "shards",   need = 2000,xp = 500,  name = "Gather 2000 dream shards" },
    { id = "q_story_life_5",  scope = "life", metric = "story",    need = 5,   xp = 700,  name = "Finish 5 story quests" },
    { id = "q_grim_life_10",  scope = "life", metric = "grimoire", need = 10,  xp = 550,  name = "Finish 10 grimoire quests" },
    { id = "q_win_life_3",    scope = "life", metric = "wins",     need = 3,   xp = 1500, name = "Win three runs" },
    { id = "q_flaw_life_1",   scope = "life", metric = "flawless",need = 1,    xp = 1000, name = "Win without going down" },
    { id = "q_night_life_3",  scope = "life", metric = "nightmares",need = 3,  xp = 600,  name = "Enter three nightmares" },
    { id = "q_run_life_25",   scope = "life", metric = "runs",     need = 25,  xp = 700,  name = "Play 25 runs" },
}

local BY_ID = {}
for _, q in ipairs(POOL) do BY_ID[q.id] = q end

-- ---------------------------------------------------------------------------
-- 5. State + helpers.
-- ---------------------------------------------------------------------------

local run, rbase, dirty, finalized = {}, {}, false, true
-- The outcome a boundary CLAIMED, held until we have actually left the run.
-- nil = nothing claimed yet. See the settle rules in section 9.
local pending = nil

local function total(metric) return R.kv.get("total_" .. metric, 0) end

local function xp_of(metric, n)
    return math.floor((XP[metric] or 0) * (n or 1) * cfg.mult + 0.5)
end

local function award(n, why)
    if n <= 0 then return end
    local before = rank(R.kv.get("xp", 0))
    local after = rank(R.kv.inc("xp", n))
    if after > before then
        local _, title = rank(R.kv.get("xp", 0))
        R.log(("[Saga] RANK UP — level %d, %s (%s)"):format(after, title, why))
    end
end

-- Every counter in the mod goes through here, so XP, feats and objectives can
-- never disagree about what happened.
local function bump(metric, n)
    n = n or 1
    run[metric] = (run[metric] or 0) + n
    R.kv.inc("total_" .. metric, n)
    award(xp_of(metric, n), metric)
    dirty = true
end

-- ---------------------------------------------------------------------------
-- 6. Feats.
-- ---------------------------------------------------------------------------

local function check_feats()
    for _, f in ipairs(FEATS) do
        if not R.kv.get("feat." .. f.id, false) and total(f.metric) >= f.need then
            R.kv.set("feat." .. f.id, true)
            R.kv.set("feat." .. f.id .. ".at", os.time())
            R.kv.inc("feats", 1)
            R.log(("[Saga] FEAT UNLOCKED — %s (+%d XP)"):format(f.name, f.xp))
            award(math.floor(f.xp * cfg.mult + 0.5), "feat")
        end
    end
end

-- ---------------------------------------------------------------------------
-- 7. Objectives.
--
-- A slot holds an id plus, for a lifetime objective, the counter value it was
-- handed out at. Replacements are drawn by advancing a cursor through the pool
-- rather than at random: the rotation survives a restart with one integer, and
-- a player cannot be handed the same objective twice in a row by bad luck.
-- ---------------------------------------------------------------------------

local function slot_ids()
    local ids, seen = {}, {}
    for i = 1, cfg.slots do
        local id = R.kv.get("slot" .. i .. ".id", nil)
        if id and BY_ID[id] and not seen[id] then ids[i], seen[id] = id, true end
    end
    return ids, seen
end

local function assign(i, taken)
    local cursor = R.kv.get("cursor", 0)
    for _ = 1, #POOL do
        cursor = (cursor % #POOL) + 1
        local q = POOL[cursor]
        local done = R.kv.get("done." .. q.id, false)
        if not taken[q.id] and not (q.scope == "life" and done) then
            R.kv.set("cursor", cursor)
            R.kv.set("slot" .. i .. ".id", q.id)
            -- A lifetime objective needs its baseline to survive a restart, so
            -- it goes in the store. A run objective's baseline is meaningless
            -- once the run is over, so it stays in memory and dies with it —
            -- persisting it is how a slot handed out at 150 kills ends up
            -- silently asking for 150 MORE in the next run.
            R.kv.set("slot" .. i .. ".base", q.scope == "life" and total(q.metric) or 0)
            rbase[i] = q.scope == "run" and (run[q.metric] or 0) or nil
            taken[q.id] = true
            return q
        end
    end
    R.kv.set("cursor", cursor)
    -- Pool exhausted (every lifetime objective is done). Clear the slot rather
    -- than leaving the finished one in it, or it re-completes on every pass.
    R.kv.set("slot" .. i .. ".id", nil)
    rbase[i] = nil
    return nil
end

local function fill_slots()
    local ids, taken = slot_ids()
    for i = 1, cfg.slots do
        if not ids[i] then assign(i, taken) end
    end
end

-- Progress of one slot as (have, need). A run objective reads this run's
-- column; a lifetime objective reads the delta since it was handed out.
local function progress(i, q)
    if q.scope == "run" then
        return math.max(0, (run[q.metric] or 0) - (rbase[i] or 0)), q.need
    end
    return math.max(0, total(q.metric) - R.kv.get("slot" .. i .. ".base", 0)), q.need
end

local function check_quests()
    local _, taken = slot_ids()
    for i = 1, cfg.slots do
        local id = R.kv.get("slot" .. i .. ".id", nil)
        local q = id and BY_ID[id]
        if q then
            local have, need = progress(i, q)
            if have >= need then
                R.kv.set("done." .. q.id, true)
                R.kv.inc("quests_done", 1)
                R.log(("[Saga] OBJECTIVE COMPLETE — %s (+%d XP)"):format(q.name, q.xp))
                award(math.floor(q.xp * cfg.mult + 0.5), "objective")
                taken[q.id] = nil
                assign(i, taken)
            end
        end
    end
end


-- ---------------------------------------------------------------------------
-- 7b. Challenges — the generator pool (SPEC v2.2).
--
-- Three sub-pools sharing one schema. `malus` is an in-game negative, `boon` an
-- in-game positive (NEGATIVE weight — a boon REDUCES the set's difficulty
-- score), and `self` a rule you hold yourself to. A rolled set is malus + boon
-- + self drawn to land inside a tier's score band.
--
-- Fields, all optional but `id/kind/name/desc/w`:
--   w          difficulty score. ALSO the draw weight (|w|, floored at 100 so a
--              zero-scored entry can still be drawn).
--   conflicts  ids that may not share a set. Made SYMMETRIC at load — the spec
--              lists most pairs once and a one-way conflict is how two
--              contradictory rules end up in the same set depending on draw
--              order.
--   flags      preset_only | flavor_only | freq_up | freq_down | aladdin_only
--   weight_if  { ids = {...}, w = n }  score override when any id is in the set
--   requires   ids that must ALREADY be in the set
--   boost      { ids = {...}, mult = n }  draw-probability multiplier
--   min_tier   "HARD" — only drawn for HARD/BRUTAL/IMPOSSIBLE
--   mode       "coop" — only drawn with the co-op toggle on
--   apply      { "<R.modifier name>", value } — auto-appliable (see 7d)
--   track      "auto" | "partial" — how the mod verifies it. ABSENT MEANS
--              HONOUR SYSTEM: it is shown and scored, never checked.
--
-- `category`, `archetype`, `slot` and `synergies` from the spec are deliberately
-- NOT carried: nothing reads them, and a field nothing reads is a field that
-- silently goes stale.
-- ---------------------------------------------------------------------------

local CHAL = {
    -- ===== MALUS (in-game Custom Mode) =====
    { id = "G12", kind = "malus", w = 800, name = "Invigorating Death", desc = "Dying enemies heal nearby enemies." },
    { id = "G13", kind = "malus", w = 400, name = "Inflation", desc = "All Dream Shard costs are increased by 100%.", conflicts = { "G02" }, apply = { "Dream Shard Costs Modifier", 2.0 } },
    { id = "G14", kind = "malus", w = 500, name = "Lack of Inspiration", desc = "One fewer option on every Talent and reward choice.", conflicts = { "E02" } },
    { id = "G15", kind = "malus", w = 200, name = "Dried-up Fountains", desc = "Healing Fountains are empty.", conflicts = { "S01", "S02", "S06", "R08" } },
    { id = "G16", kind = "malus", w = 500, name = "Corruption", desc = "All enemies are Corrupted.", flags = { "freq_up" } },
    { id = "G17", kind = "malus", w = 200, name = "Disease", desc = "Hero healing is reduced by 50%." },
    { id = "G18", kind = "malus", w = 150, name = "Bloodlust", desc = "You steadily lose max HP while out of combat." },
    { id = "G19", kind = "malus", w = 50,  name = "Angry Birds", desc = "Start with no raven feather and none can be recovered — no revive.", conflicts = { "S03" }, apply = { "No revive token", 1 } },
    { id = "G20", kind = "malus", w = 500, name = "Shadowy Fog", desc = "The map is hidden and cannot be used.", conflicts = { "R01", "R06" }, apply = { "No minimap", 1 } },
    { id = "G21", kind = "malus", w = 800, name = "Oppressive Nightmare", desc = "Fewer cycles before the Nightmare — chapters are shorter.", conflicts = { "C01", "C03", "C06", "R02", "T02" }, apply = { "Half Cycle Count Before Boss Awakens", 2 } },
    { id = "G22", kind = "malus", w = 400, name = "Berserker Foes", desc = "Enemies deal up to 50% more damage as their HP drops." },

    -- ===== BOONS (negative weights) =====
    { id = "G01", kind = "boon", w = -800,  name = "Light Feet", desc = "Dash cooldown is drastically reduced.", conflicts = { "S04" } },
    { id = "G02", kind = "boon", w = -300,  name = "Living the Dream", desc = "Start the run with 500 Dream Shards." },
    { id = "G03", kind = "boon", w = -600,  name = "Quick Learner", desc = "+50% XP gain.", apply = { "Global Xp Modifier", 1.5 } },
    { id = "G04", kind = "boon", w = -150,  name = "Solid Heroes", desc = "+100% max health.", conflicts = { "S06" } },
    { id = "G05", kind = "boon", w = -1000, name = "Explorer", desc = "No countdown — the Master Nightmare never wakes on its own.", conflicts = { "T01", "T02", "T03", "T06" }, apply = { "No boss timer", 1 } },
    { id = "G06", kind = "boon", w = -300,  name = "Legacy", desc = "Start with a choice of Legendary Object.", conflicts = { "M01" } },
    { id = "G07", kind = "boon", w = -150,  name = "Hyperactive", desc = "+1 Power, Special and Defense charge.", conflicts = { "S05" } },
    { id = "G08", kind = "boon", w = -700,  name = "Rain of Stars", desc = "The first reroll of any choice is free.", conflicts = { "E03", "M01" } },
    { id = "G09", kind = "boon", w = 0, name = "Eternal Sun", desc = "Play only during the day.", flags = { "preset_only" }, conflicts = { "G10" }, apply = { "Day only", 1 } },
    { id = "G10", kind = "boon", w = 0, name = "Solar Eclipse", desc = "Play only at night.", flags = { "preset_only" }, conflicts = { "G09" }, apply = { "Night only", 1 } },
    { id = "G11", kind = "boon", w = 0, name = "Single Chapter", desc = "Play a single random chapter.", flags = { "freq_down" }, conflicts = { "C01", "A01" }, apply = { "One chapter", 1 } },

    -- ===== SELF — SURVIVE =====
    { id = "S01", kind = "self", w = 300, name = "No Healing Items", desc = "Take zero healing or lifesteal Magical Objects the entire run." },
    { id = "S02", kind = "self", w = 200, name = "Fountains Sealed", desc = "Never drink from a Healing Fountain.", track = "auto" },
    { id = "S03", kind = "self", w = 300, name = "No Revive", desc = "Spend no raven feather — the first death ends the attempt.", track = "auto" },
    { id = "S04", kind = "self", w = 600, name = "Combat Dashless", desc = "No dash while enemies are aggroed — reposition on foot.", conflicts = { "F01c" }, track = "partial" },
    { id = "S05", kind = "self", w = 800, name = "No Defense Input", desc = "Never use your Defense ability.", track = "auto" },
    { id = "S06", kind = "self", w = 200, name = "Glass Frame", desc = "Never raise max HP through items or talents — no Vitality stacking.", track = "partial" },
    { id = "S07", kind = "self", w = 300, name = "No Shields", desc = "Skip every shield or armor-granting talent and item.", weight_if = { ids = { "G22", "G16" }, w = 500 } },
    { id = "S08", kind = "self", w = 100, name = "No Melodies", desc = "Don't take any melody the entire run.", track = "auto" },

    -- ===== SELF — ROUTE =====
    { id = "R01",  kind = "self", w = 100, name = "Scout First", desc = "Reveal every Main POI in a chapter before you fight at any of them.", conflicts = { "G21" } },
    { id = "R02",  kind = "self", w = 800, name = "Straight to the Nightmare", desc = "Skip all optional POIs — go directly to each chapter boss.", conflicts = { "C01", "G05" } },
    { id = "R03",  kind = "self", w = 250, name = "No Backtracking", desc = "Never re-enter an area you have already cleared." },
    { id = "R04",  kind = "self", w = 550, name = "One Shop", desc = "Enter the Shop exactly once the whole run.", conflicts = { "E08", "R04b" }, track = "partial" },
    { id = "R04b", kind = "self", w = 300, name = "One Shop Visit Per Chapter", desc = "Enter the Shop at most once per chapter.", conflicts = { "E08" }, track = "partial" },
    { id = "R06",  kind = "self", w = 200, name = "Pre-Plan the Chapter", desc = "Before moving in a new chapter, call your full route out loud, then follow it." },
    { id = "R07",  kind = "self", w = 150, name = "POI Priority", desc = "Always take the nearest un-scouted POI next — no cherry-picking." },
    { id = "R08",  kind = "self", w = 50,  name = "Fountain Route", desc = "Route so you pass every Healing Fountain, lorestone, and sacrificial idol." },
    { id = "R09",  kind = "self", w = 250, name = "Area Level Gates", desc = "Do the green area at level 1, the yellow area at level 2, the red area at level 3." },
    { id = "R10",  kind = "self", w = 400, name = "Early Red Chest", desc = "Open a red chest at level 2 and copy the item (when a copy source is available).", track = "partial" },

    -- ===== SELF — COMPLETE =====
    { id = "C03",  kind = "self", w = 300, name = "Scorched Earth Leveling", desc = "Kill every tree and phoenix egg you see.", boost = { ids = { "C03b" }, mult = 1.7 } },
    { id = "C01",  kind = "self", w = 100, name = "Total Clear", desc = "Full-clear every chapter — no camp or POI left standing." },
    { id = "C03b", kind = "self", w = 300, name = "Level 6 Before Overtime", desc = "Reach level 6 before Overtime in Chapter 1.", conflicts = { "G21", "C03c", "C03d" }, boost = { ids = { "C03" }, mult = 1.7 }, track = "partial" },
    { id = "C03c", kind = "self", w = 300, name = "Level 7 in Chapter 1", desc = "Reach level 7 within Chapter 1.", conflicts = { "G21", "C03d" }, track = "auto" },
    { id = "C03d", kind = "self", w = 300, name = "Level 8 in Chapter 1", desc = "Reach level 8 within Chapter 1.", requires = { "G03" }, conflicts = { "G21" }, track = "auto" },
    { id = "C06",  kind = "self", w = 500, name = "Max Level", desc = "Reach hero max level before the final Nightmare. (Aladdin only)", flags = { "aladdin_only" }, conflicts = { "G21" }, track = "auto" },
    { id = "C09",  kind = "self", w = 300, name = "Level 15", desc = "Reach hero level 15 before the final Nightmare. Any hero.", conflicts = { "G21" }, track = "auto" },
    { id = "C07",  kind = "self", w = 300, name = "Trigger the Super Effect", desc = "Trigger the super effect of every item you hold at least once.", min_tier = "HARD" },

    -- ===== SELF — ECONOMY =====
    { id = "E01", kind = "self", w = 500, name = "Shard Fast", desc = "Spend no Dream Shards before Chapter 2.", conflicts = { "E06", "G13" }, track = "partial" },
    { id = "E02", kind = "self", w = 300, name = "First Offer Only", desc = "In the Shop, only ever buy the first item offered — no browsing." },
    { id = "E03", kind = "self", w = 550, name = "No Rerolls", desc = "Never reroll a choice.", conflicts = { "E04" }, track = "partial" },
    { id = "E04", kind = "self", w = 300, name = "Reroll Everything", desc = "Reroll the first offer on every reward choice at least once, whenever a reroll is available.", conflicts = { "M03" } },
    { id = "E06", kind = "self", w = 150, name = "Big Spender", desc = "Spend every Dream Shard within one chapter of earning it.", conflicts = { "E07", "E09" } },
    { id = "E07", kind = "self", w = 50,  name = "Hoarder's Gate", desc = "Hold 3000 Dream Shards at some point in the run.", track = "auto" },
    { id = "E08", kind = "self", w = 600, name = "No Shop", desc = "Never buy from the Shop. Wishing wells, refugees, and the mirror are allowed.", conflicts = { "E02" }, track = "auto" },
    { id = "E09", kind = "self", w = 450, name = "Savings First", desc = "Spend no Dream Shards until you have held 1000 — each player, in co-op.", track = "partial" },

    -- ===== SELF — TEMPO =====
    { id = "T01", kind = "self", w = 150, name = "Level 3 Quest", desc = "Pig quest: start the quest at level 3. Bean quest: start the boss at level 3.", conflicts = { "T02" } },
    { id = "T02", kind = "self", w = 150, name = "Overtime Opener", desc = "Complete the first chapter's quest during Overtime, not before.", track = "partial" },
    { id = "T03", kind = "self", w = 0,   name = "Legendary by 4", desc = "Upgrade a talent to Legendary before the 4-minute mark. (Adds no weight.)", track = "auto" },
    { id = "T06", kind = "self", w = 150, name = "Beat the Clock", desc = "Finish each chapter before the Master Nightmare fully awakens.", conflicts = { "G05" }, track = "partial" },
    { id = "T08", kind = "self", w = 300, name = "Double Legendary by 7", desc = "Upgrade 2 talents to Legendary before 7 minutes.", conflicts = { "G05" }, track = "auto" },
    { id = "T09", kind = "self", w = 300, name = "Staggered Awakening", desc = "Start boss 1 at least 2 minutes before it wakes, boss 2 at least 4 minutes before, and the final boss at least 7 minutes before.", conflicts = { "G05" } },

    -- ===== SELF — FOCUS (mutually exclusive) =====
    { id = "F01a", kind = "self", w = 300, name = "Force Power Build", desc = "Build around your POWER ability — every offensive pick must feed it.", conflicts = { "F01b", "F01c", "F07" } },
    { id = "F01b", kind = "self", w = 300, name = "Force Special Build", desc = "Build around your SPECIAL ability — every offensive pick must feed it.", conflicts = { "F01c", "F07" } },
    { id = "F01c", kind = "self", w = 300, name = "Force Dash Build", desc = "Build around your dash attack — every offensive pick must feed it.", conflicts = { "F07", "G01" } },
    { id = "F07",  kind = "self", w = 350, name = "Ultimate Engine", desc = "Every pick must lower Ultimate cooldown or boost Ultimate damage." },

    -- ===== SELF — COMMIT =====
    { id = "M01", kind = "self", w = 150, name = "Don't Reroll Your 1st Legendary", desc = "Keep the first Legendary you are offered — never reroll it." },
    { id = "M02", kind = "self", w = 50,  name = "Build Around Your 1st Talent", desc = "Your first talent pick defines the build — every later pick must serve it." },
    { id = "M03", kind = "self", w = 500, name = "No Take-Backs", desc = "Never reroll, never skip — accept the first of every reward." },
    { id = "M04", kind = "self", w = 150, name = "Marry the Build", desc = "Declare your build at Level 3 out loud; every pick after must fit it.", conflicts = { "A06" } },
    { id = "M06", kind = "self", w = 100, name = "Blind Hero", desc = "Random hero — no reroll of the roll.", apply = { "Random hero at map start", 1 } },

    -- ===== SELF — ADAPT =====
    { id = "A01", kind = "self", w = 150, name = "Chapter 1 Loadout", desc = "After Chapter 2 begins, pick nothing outside items you already hold — except Legendaries and Curses, which stay allowed." },
    { id = "A06", kind = "self", w = 450, name = "Drop Your Best", desc = "At the start of Chapter 3, stop using your highest-damage ability." },

    -- ===== SELF — INVERT =====
    { id = "I02", kind = "self", w = 200, name = "Off-Meta Build", desc = "Build the weakest-rated build on your hero and make it work." },
    { id = "I04", kind = "self", w = 150, name = "Worst Pick", desc = "Take an item AND a talent you never (or rarely) pick, and keep them." },
    { id = "I05", kind = "self", w = 50,  name = "Support Carry", desc = "Prioritise utility talents — Force, Vulnerable, Mark, Strength — over raw damage." },

    -- ===== SELF — CO-OP (behind the co-op toggle) =====
    { id = "K02", kind = "self", w = 150, mode = "coop", name = "No Shared Healing", desc = "No player may heal or shield another.", conflicts = { "G17" } },
    { id = "K03", kind = "self", w = 150, mode = "coop", name = "Split the Map", desc = "Players may not share a POI — applies to the Grimoire-war quest, red areas, side bosses, and bosses." },
    { id = "K05", kind = "self", w = 50,  mode = "coop", name = "Mirror Builds", desc = "All players build the same ability line." },
    { id = "K06", kind = "self", w = 150, mode = "coop", name = "Dedicated Healer", desc = "One player plays healer and picks at least 4 healing talents.", conflicts = { "K02" } },

    -- ===== SELF — STORY (flavor only) =====
    { id = "Y01", kind = "self", w = 150, name = "Arbor Day", desc = "Kill every destructible tree you pass.", flags = { "flavor_only" } },
    { id = "Y04", kind = "self", w = 0,   name = "Narrate Everything", desc = "Say every pick and why, out loud, all run. (Adds no weight.)", flags = { "flavor_only" } },
    { id = "Y05", kind = "self", w = 150, name = "Pacifist Opening", desc = "Don't attack until an enemy attacks you first, each chapter.", flags = { "flavor_only" } },
}

-- "Forced cursed": one banned ability per chapter. Every permutation of the four
-- abilities across chapters 1-4 is its own entry, all mutually exclusive — so a
-- draw picks the ORDER as well as the rule. Generated rather than written out
-- because 24 hand-copied rows is 24 chances to typo a conflict list.
local CURSE_ABILITIES = { "ATTACK", "SPECIAL", "POWER", "ULTIMATE" }
do
    local perms = {}
    local function permute(rest, acc)
        if #rest == 0 then perms[#perms + 1] = acc; return end
        for i = 1, #rest do
            local tail = {}
            for j = 1, #rest do if j ~= i then tail[#tail + 1] = rest[j] end end
            local head = { table.unpack(acc) }
            head[#head + 1] = rest[i]
            permute(tail, head)
        end
    end
    permute(CURSE_ABILITIES, {})
    local ids = {}
    for i = 1, #perms do ids[i] = ("A03-%02d"):format(i) end
    for i, p in ipairs(perms) do
        local x = { "F01a", "F01b", "F01c", "M04" }
        for j, other in ipairs(ids) do if j ~= i then x[#x + 1] = other end end
        CHAL[#CHAL + 1] = {
            id = ids[i], kind = "self", w = 300, name = "Forced cursed",
            desc = ("A named ability is banned each chapter — Ch1: %s \u{00b7} Ch2: %s \u{00b7} Ch3: %s \u{00b7} Ch4: %s.")
                :format(p[1], p[2], p[3], p[4]),
            curse = p, conflicts = x, track = "partial",
        }
    end
end

-- Hand-designed, never rolled. `ids` are pool entries the preset forces in.
local PRESETS = {
    { name = "Blood Moon Pack", ids = { "G10" },
      desc = "Solar Eclipse + all players must pick Scarlet and may NOT take Shapeshifter — forced wolf form at night." },
}

local CHAL_BY_ID, CHAL_X = {}, {}
for _, c in ipairs(CHAL) do
    CHAL_BY_ID[c.id] = c
    if type(c.w) ~= "number" then error("challenge " .. c.id .. " has no numeric weight") end
    if not c.desc or c.desc == "" then error("challenge " .. c.id .. " has an empty desc") end
end
-- Conflicts, made symmetric. The spec lists most pairs once; a one-way conflict
-- is how two contradictory rules end up together depending on draw order.
for _, c in ipairs(CHAL) do
    for _, other in ipairs(c.conflicts or {}) do
        CHAL_X[c.id] = CHAL_X[c.id] or {}; CHAL_X[c.id][other] = true
        CHAL_X[other] = CHAL_X[other] or {}; CHAL_X[other][c.id] = true
    end
end

local TIERS = { "FLAVOR", "LIGHT", "STANDARD", "HARD", "BRUTAL", "IMPOSSIBLE" }
-- band = score window; the three count ranges are {min, max} per sub-pool.
-- Every tier rolls at least ONE self-imposed rule.
local TIER_TABLE = {
    FLAVOR     = { band = { 150, 300 },   malus = { 0, 0 }, boon = { 0, 2 }, self = { 1, 3 } },
    LIGHT      = { band = { 301, 650 },   malus = { 1, 1 }, boon = { 0, 2 }, self = { 1, 3 } },
    STANDARD   = { band = { 651, 1000 },  malus = { 2, 2 }, boon = { 0, 1 }, self = { 1, 4 } },
    HARD       = { band = { 1001, 1500 }, malus = { 3, 5 }, boon = { 0, 0 }, self = { 1, 3 } },
    BRUTAL     = { band = { 1501, 2200 }, malus = { 4, 5 }, boon = { 0, 0 }, self = { 1, 5 } },
    IMPOSSIBLE = { band = { 2201, math.huge }, malus = { 5, 5 }, boon = { 0, 0 }, self = { 2, 5 } },
}
local HARD_TIERS = { HARD = true, BRUTAL = true, IMPOSSIBLE = true }
-- FLAVOR and IMPOSSIBLE never appear in a weekly.
local WEEKLY_A = { "LIGHT", "STANDARD" }
local WEEKLY_B = { "STANDARD", "HARD", "BRUTAL" }
-- Boons can only take 500 points off a set, however many are drawn.
local BOON_OFFSET_CAP = -500

-- ---------------------------------------------------------------------------
-- 7c. The generator.
--
-- Deterministic by construction: the same seed string yields the same set on
-- every machine, which is the whole point of a weekly. The default seed is the
-- ISO week (or the date, for a daily), so a group rolls the same challenge
-- without passing anything around.
--
-- Draw weight is |score| floored at 100 — score and draw probability are the
-- SAME number in the spec, but four entries score zero on purpose ("adds no
-- weight") and a zero draw weight means they can never be rolled at all.
-- ---------------------------------------------------------------------------

local function rng_from(seed)
    local s = 0
    for i = 1, #seed do s = (s * 31 + seed:byte(i)) % 2147483647 end
    if s == 0 then s = 1 end
    return function(n)                       -- integer in 1..n
        s = (s * 48271) % 2147483647
        return (s % n) + 1
    end
end

local function has_any(set, ids)
    for _, id in ipairs(ids or {}) do if set[id] then return true end end
    return false
end

local function has_flag(c, f)
    for _, x in ipairs(c.flags or {}) do if x == f then return true end end
    return false
end

-- The score an entry contributes to THIS set (weight_if can raise it).
local function score_of(c, set)
    if c.weight_if and has_any(set, c.weight_if.ids) then return c.weight_if.w end
    return c.w
end

local function eligible(c, set, tier, opts)
    if set[c.id] then return false end
    if has_flag(c, "preset_only") then return false end
    if has_flag(c, "flavor_only") and tier ~= "FLAVOR" then return false end
    if has_flag(c, "aladdin_only") and opts.hero ~= "" and opts.hero ~= "Aladdin" then return false end
    if c.min_tier == "HARD" and not HARD_TIERS[tier] then return false end
    if c.mode == "coop" and not opts.coop then return false end
    if c.requires and not has_any(set, c.requires) then return false end
    for id in pairs(CHAL_X[c.id] or {}) do if set[id] then return false end end
    return true
end

local function draw_weight(c, set)
    local w = math.abs(c.w)
    if w < 100 then w = 100 end
    if has_flag(c, "freq_up") then w = w * 2 end
    if has_flag(c, "freq_down") then w = w * 0.5 end
    if c.boost and has_any(set, c.boost.ids) then w = w * c.boost.mult end
    return math.max(1, math.floor(w))
end

-- One weighted draw from `kind`'s sub-pool, or nil when nothing is eligible.
local function draw_one(kind, set, tier, opts, rng)
    local cands, total = {}, 0
    for _, c in ipairs(CHAL) do
        if c.kind == kind and eligible(c, set, tier, opts) then
            local w = draw_weight(c, set)
            total = total + w
            cands[#cands + 1] = { c = c, acc = total }
        end
    end
    if total == 0 then return nil end
    local r = rng(total)
    for _, e in ipairs(cands) do if r <= e.acc then return e.c end end
    return cands[#cands].c
end

local function count_in(range, rng)
    if range[2] <= range[1] then return range[1] end
    return range[1] + rng(range[2] - range[1] + 1) - 1
end

-- Total difficulty score of a set. Boons are summed apart so their combined
-- discount can be capped — three big boons must not zero out a BRUTAL set.
local function score_set(ids)
    local set, pos, neg = {}, 0, 0
    for _, id in ipairs(ids) do set[id] = true end
    for _, id in ipairs(ids) do
        local c = CHAL_BY_ID[id]
        local s = score_of(c, set)
        if s < 0 then neg = neg + s else pos = pos + s end
    end
    return pos + math.max(neg, BOON_OFFSET_CAP)
end

-- Drop the heaviest droppable entry until the set fits under the band ceiling.
--
-- Needed because draw probability IS difficulty here: heavy entries are drawn
-- most often, and a tight band routinely overshoots on the last pick. HARD is
-- the case that forced it — 500 points wide with a three-malus floor, it landed
-- in band 12 times in 30 before this and 30 in 30 after.
--
-- Removing an entry can never CREATE a conflict, but it can strand a `requires`
-- (dropping Quick Learner out from under Level 8 in Chapter 1), so an entry
-- something else still needs is not droppable.
local function trim_to_band(ids, spec)
    local count, needed = { malus = 0, boon = 0, self = 0 }, {}
    for _, id in ipairs(ids) do
        local c = CHAL_BY_ID[id]
        count[c.kind] = count[c.kind] + 1
        for _, req in ipairs(c.requires or {}) do needed[req] = true end
    end
    while score_set(ids) > spec.band[2] do
        local worst, at = nil, nil
        for i, id in ipairs(ids) do
            local c = CHAL_BY_ID[id]
            if not needed[id] and count[c.kind] > spec[c.kind][1]
               and (not worst or c.w > worst.w) then
                worst, at = c, i
            end
        end
        if not at then break end
        table.remove(ids, at)
        count[worst.kind] = count[worst.kind] - 1
    end
    return ids
end

-- Roll a set for `tier`. Returns { ids = {...}, score = n, tier = t }.
-- Up to 40 attempts to land inside the band; the closest miss is returned
-- rather than nothing, because a pool that cannot reach a band (every heavy
-- malus conflicting out, say) must still hand the player a playable set.
local function roll_set(tier, seed, opts)
    local spec = TIER_TABLE[tier]
    local best, best_miss = nil, math.huge
    for attempt = 1, 40 do
        local rng = rng_from(seed .. ":" .. attempt)
        local set, ids = {}, {}
        for _, kind in ipairs({ "malus", "boon", "self" }) do
            local want = count_in(spec[kind], rng)
            for _ = 1, want do
                local c = draw_one(kind, set, tier, opts, rng)
                if not c then break end
                set[c.id] = true; ids[#ids + 1] = c.id
            end
        end
        trim_to_band(ids, spec)
        local score = score_set(ids)
        local miss = 0
        if score < spec.band[1] then miss = spec.band[1] - score
        elseif score > spec.band[2] then miss = score - spec.band[2] end
        if miss == 0 then return { ids = ids, score = score, tier = tier } end
        if miss < best_miss then best, best_miss = { ids = ids, score = score, tier = tier }, miss end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- 7d. Tracking — what the mod can actually verify.
--
-- A challenge is one of three things, and the difference is stated rather than
-- implied, because a rule the mod silently fails to watch is worse than one it
-- never claimed to:
--
--   track = "auto"     a bus event proves it, one-to-one.
--   track = "partial"  the closest available signal, with a KNOWN blind spot
--                      (named in the comment on each). It can miss a violation;
--                      it does not invent one.
--   (absent)           honour system. Shown, scored, never checked.
--
-- Nothing here fails a rule it cannot see. `status` starts "open" and only ever
-- moves to "done" or "failed" on positive evidence.
-- ---------------------------------------------------------------------------

local chal = {
    ids = {}, tier = nil, score = 0, status = {},
    chapter = 1, chapter_at = 0, legendary = 0, combat = 0, best_shards = 0,
    -- `shards` is the LAST SEEN balance, which is what makes a spend visible:
    -- the bus has a GAIN_DREAM_SHARDS event and no spend event at all, so the
    -- only observable is the balance going down between two polls. nil means
    -- "not sampled yet" and is deliberately not 0 — treating an unsampled
    -- balance as zero makes the first sample of a funded hero look like income
    -- and, worse, makes the first sample after a reset look like a spend.
    shards = nil,
    -- Shop presence is a boolean the engine exposes, with no enter/leave event
    -- of its own, so visits are counted as RISING EDGES of that boolean.
    in_shop = false, shop_visits = 0, shop_visits_chapter = 0,
    -- Last seen engine reroll counter; nil until first sampled, for the same
    -- reason `shards` is (an unsampled counter must not read as activity).
    rerolls = nil,
    applied = {}, rolled = false,
}

local function chal_active(id) return chal.status[id] ~= nil end
local function chal_elapsed() return math.max(0, os.time() - (chal.chapter_at or 0)) end

-- R.game — the engine's OWN answer, when the loader has published the global
-- entity-value context; nil otherwise. Every use below is written so that nil
-- falls back to the proxy the rule used before, because this capability is
-- new and unproven in game: a rule must not become LESS tracked than it was.
local function gv(name)
    if not (R.game and R.game.get) then return nil end
    local ok, v = pcall(R.game.get, name)
    if not ok then return nil end
    return v
end

local function gvflag(name)
    local v = gv(name)
    if v == nil then return nil end
    return v ~= 0
end

-- Which chapter we are in. The engine tracks this directly; the hand-kept
-- counter (bumped on GAME_END_NEXT_CHAPTER) is the fallback and drifts if a
-- transition is ever missed, which is exactly what a "within chapter 1" rule
-- cannot survive.
local function chal_chapter()
    return gv("current_chapter") or chal.chapter
end

local function chal_level()
    local ok, lvl = pcall(function() return R.xp and R.xp.level and R.xp.level() end)
    return (ok and type(lvl) == "number") and lvl or 0
end

-- Marks a challenge. "failed" is sticky: a rule you broke stays broken, and a
-- later goal check must not quietly clear it.
local function chal_mark(id, state)
    if not chal_active(id) or chal.status[id] == "failed" then return end
    if chal.status[id] == state then return end
    chal.status[id] = state
    local c = CHAL_BY_ID[id]
    R.log(("[Saga] CHALLENGE %s — %s"):format(state == "done" and "DONE" or "BROKEN", c.name))
    dirty = true
end

-- Ability -> the charge-consumed event that proves it was used. The four names
-- in the spec are UI names; this is the mapping to engine slots, and it is the
-- reason "Forced cursed" is partial rather than auto — a hero whose ability
-- spends no charge fires nothing here.
local ABILITY_EVENT = {
    ATTACK   = "REMOVE_BASIC_CHARGE",
    POWER    = "REMOVE_PRIMARY_CHARGE",
    SPECIAL  = "REMOVE_SECONDARY_CHARGE",
    ULTIMATE = "REMOVE_ULTIMATE_CHARGE",
}

-- id -> tracker. `fail` is the simple case: any of these events breaks the rule.
-- `events` + `on` is the conditional one; `goal` is polled on the 3s tick.
local TRACK = {
    S02 = { fail = { "USE_HEAL_FOUNTAIN", "USE_BLOOD_FOUNTAIN" } },
    S03 = { fail = { "HERO_REVIVE", "REVIVE_TOKEN_LOSS" } },
    S05 = { fail = { "REMOVE_DEFENSIVE_CHARGE" } },
    S08 = { fail = { "CHOOSE_MELODY" } },

    -- BLIND SPOT: MAX_HEALTH_MODIFICATION carries no decoded direction, so a
    -- max-HP LOSS (Bloodlust, curses) reads the same as a Vitality stack. It is
    -- counted as a violation either way, which is why this is partial.
    S06 = { fail = { "MAX_HEALTH_MODIFICATION" } },

    -- "Aggroed" has no signal of its own, but "Active Enemies Count" is the
    -- engine's own count of enemies currently engaged, which covers the trash
    -- combat the old boss/tumor proxy missed entirely. The proxy stays as the
    -- fallback for a loader that has not published the global context.
    --
    -- BLIND SPOT (fallback path only): a named fight — boss or tumor — is the
    -- only combat visible, so a dash during trash combat is not seen.
    S04 = { events = { "REMOVE_DASH_CHARGE" },
            on = function()
                local n = gv("active_enemies_count")
                if n ~= nil then
                    if n > 0 then return "failed" end
                    return
                end
                if chal.combat > 0 then return "failed" end
            end },

    T03 = { events = { "UPGRADE_LOWER_SKILL_TO_LEGENDARY" },
            on = function() if chal_elapsed() <= 240 then return "done" end end },
    T08 = { events = { "UPGRADE_LOWER_SKILL_TO_LEGENDARY" },
            on = function()
                if chal.legendary >= 2 and chal_elapsed() <= 420 then return "done" end
            end },

    -- BLIND SPOT: "Overtime" has no event of its own. BOSS_ACTIVATED is the
    -- closest thing the bus offers to "the Nightmare is up"; if the boss is
    -- never engaged in chapter 1 this never resolves either way.
    C03b = { events = { "BOSS_ACTIVATED" },
             on = function()
                 if chal_chapter() ~= 1 then return end
                 return chal_level() >= 6 and "done" or "failed"
             end },
    C03c = { events = { "GAME_END_NEXT_CHAPTER" },
             on = function()
                 if chal_chapter() ~= 1 then return end
                 return chal_level() >= 7 and "done" or "failed"
             end },
    C03d = { events = { "GAME_END_NEXT_CHAPTER" },
             on = function()
                 if chal_chapter() ~= 1 then return end
                 return chal_level() >= 8 and "done" or "failed"
             end },

    C06 = { goal = function() return chal_level(), 20 end },
    C09 = { goal = function() return chal_level(), 15 end },
    E07 = { goal = function() return chal.best_shards, 3000 end },

    -- Spend-driven rules. `spend` is called with the amount the balance fell
    -- by; returning a verdict marks the challenge, returning nothing leaves it
    -- open. See chal_poll for why a fall IS a spend.
    --
    -- BLIND SPOT, shared by all three: the engine has no spend event, so any
    -- fall in the balance reads as one. Nothing observed takes shards away
    -- except spending them, but a modifier that confiscated them would be
    -- indistinguishable — hence partial, not auto.
    E01 = { spend = function() if chal_chapter() <= 1 then return "failed" end end,
            chapter_end = function() if chal_chapter() == 1 then return "done" end end },
    E09 = { spend = function() if chal.best_shards < 1000 then return "failed" end end,
            goal = function() return chal.best_shards, 1000 end },

    -- "Is boss awaken" is the engine's own answer, polled. BOSS_ACTIVATED is
    -- kept as the fallback for a loader without the global context; it reads
    -- as "the Nightmare woke", which it may not exactly mean — if it turns out
    -- to be "a player engaged the boss" it fails this rule a beat late, never
    -- early.
    T06 = { fail = { "BOSS_ACTIVATED" },
            poll = function()
                if gvflag("is_boss_awaken") then return "failed" end
            end },

    -- Entering the Shop is a PRESENCE, not an event: the engine exposes a
    -- boolean and no enter/leave event exists, so these count rising edges off
    -- the poll. Both are silent without the global context — they are new
    -- capability, not a downgrade of anything.
    R04  = { visit = function(n) if n > 1 then return "failed" end end },
    R04b = { visit = function(n, per_chapter)
                 if per_chapter > 1 then return "failed" end
             end },

    -- Analytics-bus rules. The gameplay bus says an event happened; the
    -- ANALYTICS bus says what — `sandman_buy` carries the article's name,
    -- price and rarity, `open_chest` whether it was locked. Neither has any
    -- equivalent on the gameplay bus, so these are new capability rather than
    -- an upgrade of an existing proxy.
    E08 = { fail = { "sandman_buy" } },

    -- A red chest is the locked one. `locked` is the engine's own flag, and
    -- the level check is ours.
    R10 = { events = { "open_chest" },
            on = function(ev)
                if ev and ev.locked ~= nil and ev.locked == 0 then return end
                if chal_level() == 2 then return "done" end
            end },

    -- "Reroll count" is the engine's own counter, so any increase breaks the
    -- rule. Doubly attested: the reroll writer loads this key immediately
    -- after incrementing the counter it reports.
    E03 = { reroll = function() return "failed" end },

    -- The first chapter's quest has to land DURING Overtime. The quest events
    -- say when it finished; "Is in overtime" says whether that was late enough.
    T02 = { events = { "STORY_QUEST_FINISHED", "GRIMOIRE_QUEST_FINISHED" },
            on = function()
                if chal_chapter() ~= 1 then return end
                local over = gvflag("is_in_overtime")
                if over == nil then return end          -- unknown: judge nothing
                return over and "done" or "failed"
            end },
}

-- Every event any tracker needs, plus the four ability events and the fight
-- markers the proxies are built on. Subscribed ONCE at load and dispatched from
-- there: a per-roll subscribe/unsubscribe would leak handles across runs.
local CHAL_EVENTS = { "BOSS_FIGHTING_START", "BOSS_FIGHTING_STOP",
                      "TUMOR_FIGHTING_START", "TUMOR_FIGHTING_STOP",
                      "UPGRADE_LOWER_SKILL_TO_LEGENDARY", "GAME_END_NEXT_CHAPTER" }
do
    local seen = {}
    for _, n in ipairs(CHAL_EVENTS) do seen[n] = true end
    for _, t in pairs(TRACK) do
        for _, n in ipairs(t.fail or t.events or {}) do
            if not seen[n] then seen[n] = true; CHAL_EVENTS[#CHAL_EVENTS + 1] = n end
        end
    end
    for _, n in pairs(ABILITY_EVENT) do
        if not seen[n] then seen[n] = true; CHAL_EVENTS[#CHAL_EVENTS + 1] = n end
    end
    -- An event renamed by a game patch turns a watched rule into an unwatched
    -- one with NO symptom: the subscription still succeeds, it just never
    -- fires, and the rule silently becomes honour-system. Say so once at load.
    local known = {}
    for _, n in ipairs(R.events.known("gameplay") or {}) do known[n] = true end
    if next(known) then
        for _, n in ipairs(CHAL_EVENTS) do
            if not known[n] then
                R.log("[Saga] challenge tracker watches an event the catalog "
                      .. "does not know: " .. n)
            end
        end
    end
end

-- One dispatcher for all of them. Order matters in exactly one place: the
-- chapter counter is bumped AFTER the trackers have seen the event, so a
-- "within chapter 1" rule is judged on the chapter it was played in.
local function chal_event(name, ev)
    if name == "BOSS_FIGHTING_START" or name == "TUMOR_FIGHTING_START" then
        chal.combat = chal.combat + 1
    elseif name == "BOSS_FIGHTING_STOP" or name == "TUMOR_FIGHTING_STOP" then
        chal.combat = math.max(0, chal.combat - 1)
    elseif name == "UPGRADE_LOWER_SKILL_TO_LEGENDARY" then
        chal.legendary = chal.legendary + 1
    end

    for id in pairs(chal.status) do
        local t = TRACK[id]
        if t and chal.status[id] == "open" then
            for _, want in ipairs(t.fail or {}) do
                if want == name then chal_mark(id, "failed") end
            end
            for _, want in ipairs(t.events or {}) do
                if want == name then
                    -- Pass the payload. Analytics events carry their fields on
                    -- `ev` (object_name, article_price, locked, ...); gameplay
                    -- events carry none, and the handlers that predate this
                    -- simply ignore the argument.
                    local verdict = t.on(ev)
                    if verdict then chal_mark(id, verdict) end
                end
            end
        end
        -- Forced cursed: the banned ability is per chapter, so the event that
        -- breaks it changes as the run goes on.
        local c = CHAL_BY_ID[id]
        if c and c.curse and chal.status[id] == "open" then
            local banned = c.curse[math.min(chal.chapter, #c.curse)]
            if ABILITY_EVENT[banned] == name then chal_mark(id, "failed") end
        end
    end

    if name == "GAME_END_NEXT_CHAPTER" then
        -- Evaluated BEFORE the bump, for the same reason the tracker loop above
        -- runs first: a "within chapter N" rule is judged on the chapter it was
        -- played in, not the one about to start.
        for id, st in pairs(chal.status) do
            local t = TRACK[id]
            if t and t.chapter_end and st == "open" then
                local verdict = t.chapter_end()
                if verdict then chal_mark(id, verdict) end
            end
        end
        chal.chapter = chal.chapter + 1
        chal.chapter_at = os.time()
        chal.shop_visits_chapter = 0
    end
end

-- Polled goals. Cheap: a handful of reads on the same 3s tick the HUD uses.
local function chal_poll()
    local ok, shards = pcall(function() return R.stat and R.stat.get and R.stat.get("dream_shards") end)
    if ok and type(shards) == "number" then
        if shards > chal.best_shards then chal.best_shards = shards end
        -- A fall in the balance is a spend. Order matters: the rules below read
        -- `best_shards`, so the high-water mark is updated FIRST — otherwise
        -- buying at exactly 1000 is judged against the previous poll's maximum
        -- and "Savings First" fails on the purchase it was meant to allow.
        if chal.shards and shards < chal.shards then
            local spent = chal.shards - shards
            for id, st in pairs(chal.status) do
                local t = TRACK[id]
                if t and t.spend and st == "open" then
                    local verdict = t.spend(spent)
                    if verdict then chal_mark(id, verdict) end
                end
            end
        end
        chal.shards = shards
    end
    -- Shop visits. A rising edge of the engine's own "Is in sandman shop" is
    -- one visit; the per-chapter tally is reset by the chapter handler. Both
    -- counters stay at zero without the global context, and the rules that
    -- read them simply never fire — which is the honest outcome, since there
    -- is no other signal for entering a shop.
    local shop = gvflag("is_in_sandman_shop")
    if shop ~= nil then
        if shop and not chal.in_shop then
            chal.shop_visits = chal.shop_visits + 1
            chal.shop_visits_chapter = chal.shop_visits_chapter + 1
            for id, st in pairs(chal.status) do
                local t = TRACK[id]
                if t and t.visit and st == "open" then
                    local verdict = t.visit(chal.shop_visits, chal.shop_visits_chapter)
                    if verdict then chal_mark(id, verdict) end
                end
            end
        end
        chal.in_shop = shop
    end

    -- Rerolls, off the engine's own counter. Same first-sample rule as shards:
    -- nil means unsampled, and the first sample establishes a baseline rather
    -- than reporting every reroll taken before the mod looked.
    local rr = gv("reroll_count")
    if type(rr) == "number" then
        if chal.rerolls and rr > chal.rerolls then
            for id, st in pairs(chal.status) do
                local t = TRACK[id]
                if t and t.reroll and st == "open" then
                    local verdict = t.reroll(rr - chal.rerolls)
                    if verdict then chal_mark(id, verdict) end
                end
            end
        end
        chal.rerolls = rr
    end

    for id, state in pairs(chal.status) do
        local t = TRACK[id]
        if t and state == "open" then
            if t.goal then
                local have, need = t.goal()
                if have >= need then chal_mark(id, "done") end
            end
            if t.poll then
                local verdict = t.poll()
                if verdict then chal_mark(id, verdict) end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 7e. Rolling, applying and reporting a set.
--
-- AUTO-APPLY is opt-in and OFF by default, and it is honest about how far it
-- reaches: only 9 of the 22 in-game entries map to a modifier key this SDK can
-- write (plus "Blind Hero", which is a self rule the SDK happens to be able to
-- set for you), and of those, the ones consumed at map generation ("Single
-- Chapter", "Eternal Sun", "Blind Hero") cannot be turned on after a run has
-- started.
-- Everything else is printed for you to tick in the Custom Mode screen. The
-- write path itself is experimental — see R.modifier.set.
-- ---------------------------------------------------------------------------

local function chal_seed()
    if cfg.ch_seed ~= "" then return cfg.ch_seed end
    -- UTC so a party spread across timezones rolls the same set. Weekly tiers
    -- get the ISO week; everything else rolls daily.
    local weekly = cfg.ch_tier == "weekly_a" or cfg.ch_tier == "weekly_b"
    return os.date(weekly and "!%G-W%V" or "!%Y-%m-%d")
end

local function chal_tier(seed)
    local t = cfg.ch_tier
    if t == "weekly_a" or t == "weekly_b" or t == "random" then
        local list = t == "weekly_a" and WEEKLY_A or (t == "weekly_b" and WEEKLY_B or TIERS)
        return list[rng_from(seed .. ":tier")(#list)]
    end
    return t:upper()
end

local function chal_preset(name)
    for _, p in ipairs(PRESETS) do if p.name:lower() == name:lower() then return p end end
    return nil
end

-- Turn a rolled set into live state. Idempotent per run through `rolled`.
local function chal_roll()
    if cfg.ch_tier == "off" or chal.rolled then return end
    chal.rolled = true
    chal.status, chal.ids = {}, {}
    chal.chapter, chal.chapter_at = 1, os.time()
    chal.legendary, chal.combat, chal.best_shards = 0, 0, 0
    chal.shards, chal.rerolls = nil, nil
    chal.in_shop, chal.shop_visits, chal.shop_visits_chapter = false, 0, 0

    local preset = cfg.ch_preset ~= "" and chal_preset(cfg.ch_preset) or nil
    if preset then
        chal.ids, chal.tier, chal.score = preset.ids, "PRESET", score_set(preset.ids)
        R.log(("[Saga] CHALLENGE preset: %s — %s"):format(preset.name, preset.desc))
    else
        local seed = chal_seed()
        local tier = chal_tier(seed)
        if not TIER_TABLE[tier] then
            R.log("[Saga] unknown challenge tier: " .. tostring(cfg.ch_tier)); return
        end
        local set = roll_set(tier, seed, { coop = cfg.ch_coop, hero = cfg.ch_hero })
        if not set then R.log("[Saga] challenge roll produced nothing"); return end
        chal.ids, chal.tier, chal.score = set.ids, set.tier, set.score
        R.log(("[Saga] CHALLENGE %s \u{00b7} score %d \u{00b7} seed %s")
            :format(chal.tier, chal.score, seed))
    end

    for _, id in ipairs(chal.ids) do
        local c = CHAL_BY_ID[id]
        chal.status[id] = "open"
        local how = c.track and (" [" .. c.track .. "]") or ""
        R.log(("[Saga]   %s %s (%+d)%s \u{2014} %s")
            :format(c.kind == "self" and "\u{2022}" or (c.kind == "boon" and "+" or "!"),
                    c.name, c.w, how, c.desc))
    end

    -- The half we cannot set. Printed as one list rather than one line each,
    -- because it is a checklist you work through in the Custom Mode screen.
    local todo = {}
    for _, id in ipairs(chal.ids) do
        local c = CHAL_BY_ID[id]
        if c.kind ~= "self" and not (cfg.ch_apply and c.apply) then todo[#todo + 1] = c.name end
    end
    if #todo > 0 then
        R.log("[Saga] tick these in Custom Mode: " .. table.concat(todo, ", "))
    end

    if not cfg.ch_apply then return end
    -- Engine-mutating: MAIN THREAD only, and after the hero exists. next_main
    -- is that guarantee; run:start can arrive on the loader's own thread.
    R.schedule.next_main(function()
        R.modifier.enable_writes()
        for _, id in ipairs(chal.ids) do
            local c = CHAL_BY_ID[id]
            if c.apply then
                local okset = R.modifier.set(c.apply[1], c.apply[2])
                chal.applied[id] = okset and true or false
                R.log(("[Saga] apply %s -> %s = %s%s"):format(c.name, c.apply[1],
                    tostring(c.apply[2]), okset and "" or " (REFUSED)"))
            end
        end
    end)
end

-- HUD rows. One per challenge plus a header carrying the tier and score, which
-- is the number the whole set exists to express.
local function chal_rows()
    local rows = {}
    if not chal.tier then return rows end
    rows[#rows + 1] = {
        name = ("\u{2694} Challenge \u{00b7} %s"):format(chal.tier),
        xp = chal.score, pct = 0, done = false,
    }
    for _, id in ipairs(chal.ids) do
        local c, st = CHAL_BY_ID[id], chal.status[id]
        local glyph = st == "done" and "\u{2713}" or (st == "failed" and "\u{2717}" or "\u{25cb}")
        rows[#rows + 1] = {
            name = ("%s %s"):format(glyph, c.name),
            pct = st == "done" and 1 or 0, done = st == "done",
        }
    end
    return rows
end

-- Settle the set with the run. A clean sheet pays the set's score as XP —
-- unverifiable rules included, because the honour system is the point.
local function chal_finish()
    if not chal.tier or #chal.ids == 0 then return end
    local broke = {}
    for _, id in ipairs(chal.ids) do
        if chal.status[id] == "failed" then broke[#broke + 1] = CHAL_BY_ID[id].name end
    end
    if #broke == 0 then
        R.kv.inc("challenges_kept", 1)
        R.log(("[Saga] CHALLENGE KEPT \u{2014} %s, %d points"):format(chal.tier, chal.score))
        award(math.floor(math.max(0, chal.score) * cfg.mult + 0.5), "challenge")
    else
        R.kv.inc("challenges_broken", 1)
        R.log(("[Saga] CHALLENGE BROKEN \u{2014} %s"):format(table.concat(broke, ", ")))
    end
    chal.rolled = false
end

-- ---------------------------------------------------------------------------
-- 8. The HUD.
--
-- Rows are the active objectives plus the three feats closest to unlocking, so
-- the panel always shows something worth chasing rather than an empty table
-- between runs.
--
-- Every field except `name` is a NUMBER. The client lays a row out with one
-- `flex-1` per text column, so a second text column halves the width of the
-- objective — which is the only part of the row a player actually reads.
-- ---------------------------------------------------------------------------

local function feat_rows()
    local near = {}
    for _, f in ipairs(FEATS) do
        if not R.kv.get("feat." .. f.id, false) then
            local have = math.min(total(f.metric), f.need)
            near[#near + 1] = { f = f, have = have, pct = have / f.need }
        end
    end
    table.sort(near, function(a, b) return a.pct > b.pct end)
    local rows = {}
    for i = 1, math.min(3, #near) do
        local n = near[i]
        -- The star is the type marker. It used to be a "Feat" column, which
        -- cost the objective text a third of the row to say what one glyph
        -- says just as well.
        rows[#rows + 1] = {
            name = "\u{2605} " .. n.f.name, left = n.f.need - n.have,
            pct = n.pct, xp = n.f.xp, done = false,
        }
    end
    return rows
end

local function publish()
    if not cfg.overlay then return end
    local xp = R.kv.get("xp", 0)
    local lvl, title, into, need = rank(xp)

    -- Row one is the rank bar. It is a ROW rather than a footer entry because
    -- the footer is plain key/value text — there is no bar in it — and the one
    -- number a meta-progression mod exists to show is how far along you are.
    -- This is also why the overlay declares no `sort`: sorting by progress
    -- buried this row in the middle of the list.
    local rows = { {
        name = ("Level %d \u{00b7} %s"):format(lvl, title),
        xp = xp, left = need - into, pct = into / need, done = false,
    } }

    for i = 1, cfg.slots do
        local id = R.kv.get("slot" .. i .. ".id", nil)
        local q = id and BY_ID[id]
        if q then
            local have, need = progress(i, q)
            have = math.min(have, need)
            rows[#rows + 1] = {
                name = q.name, left = need - have,
                pct = have / need, xp = q.xp, done = have >= need,
            }
        end
    end
    for _, r in ipairs(chal_rows()) do rows[#rows + 1] = r end
    for _, r in ipairs(feat_rows()) do rows[#rows + 1] = r end

    -- EXACTLY three meta entries. The client renders the first three and drops
    -- the rest, and the keys arrive sorted, so publishing seven meant the
    -- footer silently showed whichever three sorted first. Level and XP moved
    -- into the rank row above; what is left is the lifetime flavour.
    R.overlay.publish{
        rows = rows,
        meta = { runs = total("runs"), feats = R.kv.get("feats", 0),
                 kills = total("kills") },
    }
end

-- ---------------------------------------------------------------------------
-- 8b. Run identity — which hero, and solo or co-op.
--
-- The hero comes from the lobby member record's `RequestedHero`, which is the
-- only source that names a hero without guessing (the hero ENTITY carries no
-- hero id — see R.lobby.hero_name). In a solo session the lobby attribute
-- parser may never run at all, so the roster is empty: that is read as "solo,
-- hero unknown" rather than invented, with R.hero.name() (signature-based,
-- and only seeded for heroes catalogued on this machine) as the fallback.
--
-- Both are recorded per result, so "abandoned" never lands in a winrate.
-- ---------------------------------------------------------------------------

local ident = { hero = "Unknown", mode = "solo" }

local function sample_ident()
    local hero, n = nil, 0
    local ok, ms = pcall(function() return R.lobby and R.lobby.members() end)
    if ok and type(ms) == "table" then
        n = #ms
        local me = R.player and R.player.name and R.player.name()
        for _, m in ipairs(ms) do
            -- Match the local player by name; with a roster of one there is
            -- nobody else it could be.
            if m.hero_id and (m.name == me or n == 1) then
                hero = R.lobby.hero_name(m.hero_id) or hero
            end
        end
    end
    if not hero then
        local ok2, h = pcall(function() return R.hero and R.hero.name() end)
        if ok2 and type(h) == "string" then hero = h end
    end
    ident.hero, ident.mode = hero or "Unknown", n > 1 and "coop" or "solo"
end

local function tally(result)
    R.kv.inc(("hero.%s.%s"):format(ident.hero, result), 1)
    R.kv.inc(("hero.%s.%s.%s"):format(ident.hero, ident.mode, result), 1)
    R.kv.inc(("mode.%s.%s"):format(ident.mode, result), 1)
end

-- One line per hero/mode that has been played. Abandoned runs are reported
-- but kept OUT of the percentage: a run you walked away from is not a loss,
-- and counting it as one makes the number say something nobody asked it.
local function winrate_lines()
    local names, seen = { "Unknown" }, { Unknown = true }
    for _, h in pairs(R.lobby and R.lobby.HERO_NAMES or {}) do
        if not seen[h] then names[#names + 1], seen[h] = h, true end
    end
    table.sort(names)
    local out = {}
    for _, h in ipairs(names) do
        for _, mode in ipairs{ "solo", "coop" } do
            local k = ("hero.%s.%s."):format(h, mode)
            local w = R.kv.get(k .. "wins", 0)
            local l = R.kv.get(k .. "losses", 0)
            local a = R.kv.get(k .. "abandons", 0)
            if w + l + a > 0 then
                out[#out + 1] = ("%s %s: %d%% (%dW %dL, %d abandoned)"):format(
                    h, mode, w + l > 0 and math.floor(w / (w + l) * 100 + 0.5) or 0,
                    w, l, a)
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- 9. Wiring.
-- ---------------------------------------------------------------------------

for event, metric in pairs(METRIC) do
    R.on("gameplay:" .. event, function(ev)
        if mine(event, ev) then bump(metric) end
    end)
end

for _, a in ipairs(ANCHORS) do R.on("gameplay:" .. a, note_hero) end

-- Challenge trackers. Subscribed once, for the life of the session, and gated
-- on attribution like every other counter: in co-op an ALLY's dash must not
-- break your Combat Dashless.
-- Gameplay-bus names are prefixed and attributed; ANALYTICS names are not.
-- The analytics firehose publishes under the raw event name and carries no
-- dispatcher, so `mine()` cannot judge it and must not be asked to — in co-op
-- an analytics event is the local client's own, which is the attribution we
-- want anyway.
local ANALYTICS_EVENTS = { "sandman_buy", "open_chest" }
do
    local seen = {}
    for _, n in ipairs(ANALYTICS_EVENTS) do seen[n] = true end
    for _, t in pairs(TRACK) do
        for _, n in ipairs(t.fail or t.events or {}) do
            -- An analytics name is lower_snake_case; a gameplay one is SHOUTY.
            if not seen[n] and n == n:lower() then
                seen[n] = true; ANALYTICS_EVENTS[#ANALYTICS_EVENTS + 1] = n
            end
        end
    end
end

for _, name in ipairs(CHAL_EVENTS) do
    if name ~= name:lower() then                 -- gameplay bus only
        R.on("gameplay:" .. name, function(ev)
            if mine(name, ev) then chal_event(name, ev) end
        end)
    end
end

for _, name in ipairs(ANALYTICS_EVENTS) do
    R.on(name, function(ev) chal_event(name, ev) end)
end

-- One-shot payload probe.
--
-- The analytics bus carries the identity the gameplay bus does not:
-- object_selected names the item, skill_selected names the talent,
-- sandman_buy names the article and its price. The FIELD NAMES are certain
-- (they are literals in the emitter). What is NOT known is the shape of the
-- VALUES — whether object_name is a def id or a display name, what
-- object_quality reads as, whether a rarity is a word or an index.
--
-- Guessing that cost real crashes twice today, so this logs the first
-- occurrence of each identity-carrying event verbatim and nothing after. One
-- playtest turns roughly ten honour-system rules into implementable ones, at
-- the price of a handful of log lines.
local PROBE = {
    object_selected = true, object_proposed = true,
    skill_selected  = true, skill_proposed  = true,
    sandman_buy     = true, open_chest      = true,
    hero_death      = true, event_end       = true,
    active_boss     = true, note_gain       = true,
}
for name in pairs(PROBE) do
    R.on(name, function(ev)
        if not PROBE[name] then return end
        PROBE[name] = false
        local parts = {}
        for k, v in pairs(ev or {}) do
            if k ~= "event" and k ~= "source" and k ~= "seq" then
                parts[#parts + 1] = ("%s=%s"):format(k, tostring(v))
            end
        end
        table.sort(parts)
        R.log(("[Saga] PROBE %s: %s"):format(
            name, #parts > 0 and table.concat(parts, " ") or "(no fields decoded)"))
    end)
end

-- Hero level-ups arrive as a typed symbol event, not on the gameplay bus. The
-- analytics firehose carries the same thing as `level_up_reach` /
-- `level_up_book` — two names for one level-up, so subscribing to those as
-- well would count most of them twice.
R.on("level_up", function() bump("levels") end)

-- Outcome. GAME_END_NEXT_CHAPTER is deliberately a chapter, not a run — it is
-- already counted as `chapters` above.
--
-- `result` is one of wins / losses / abandons. Only the gameplay bus's
-- GAME_END_* and ALL_PLAYER_DEAD say which of the first two it was; everything
-- else that ends a run says only that it ended (see `abandon` below).
local function finish(result)
    if finalized then return end
    finalized, pending = true, nil
    -- A solo run can reach here with the lobby never parsed. Try once more at
    -- the end, when the hero has certainly acted and its signature is known.
    if ident.hero == "Unknown" then sample_ident() end
    tally(result)
    bump(result)
    if result == "wins" and (run.downs or 0) == 0 then bump("flawless") end

    for _, m in ipairs(RECORDS) do
        local got = run[m] or 0
        if got > R.kv.get("best_" .. m, 0) then R.kv.set("best_" .. m, got) end
    end
    check_feats()
    check_quests()
    chal_finish()

    if cfg.on_run_end then
        local parts = {}
        for _, m in ipairs(ORDER) do
            if (run[m] or 0) > 0 then parts[#parts + 1] = ("%s %d"):format(m, run[m]) end
        end
        local lvl, title = rank(R.kv.get("xp", 0))
        local verb = ({ wins = "won", losses = "lost", abandons = "abandoned" })[result]
        R.log(("[Saga] run %s as %s (%s) — %s"):format(verb, ident.hero, ident.mode,
            #parts > 0 and table.concat(parts, ", ") or "nothing recorded"))
        R.log(("[Saga] level %d %s, %d XP total"):format(lvl, title, R.kv.get("xp", 0)))
    end
    publish()
    R.kv.save()
end

-- GAME_END_SUCCESS IS NOT A WON RUN. It fires when a CHAPTER is cleared, and
-- the run carries on into the next one — measured in session e304, where the
-- Dark Hills boss died at 19:40:43, GAME_END_SUCCESS landed at :44 and
-- GAME_END_NEXT_CHAPTER at :46. Acting on it directly booked a win and
-- unlocked "Dawn At Last" at the end of chapter one.
--
-- So no boundary is acted on where it fires. Each one CLAIMS an outcome, and
-- the claim is settled only when we have actually left the run (`run:end`,
-- `menu:enter`, the next `begin`, or shutdown). GAME_END_NEXT_CHAPTER
-- withdraws a claimed win, because it proves the run continued.
--
-- Deferring also fixes the ordering hazard that made this a latch in the first
-- place: `run:end` rides the analytics firehose and the GAME_END_* events ride
-- the gameplay bus, nothing orders the two, and whichever arrived first used
-- to win outright — so a run:end landing first filed a won run as abandoned
-- and took the flawless and every win feat with it. A claim can be upgraded
-- until the moment we leave; only leaving is final.
local function claim(result)
    if not finalized then pending = result end
end

R.on("gameplay:GAME_END_SUCCESS", function() claim("wins") end)
-- "skip next" is the last chapter: a success with no chapter to follow.
R.on("gameplay:GAME_END_SUCCESS_SKIP_NEXT", function() claim("wins") end)
R.on("gameplay:GAME_END_FAILED", function() claim("losses") end)
R.on("gameplay:ALL_PLAYER_DEAD", function() claim("losses") end)

-- The chapter ended, the run did not. Withdraw the win the chapter clear
-- claimed; a defeat is left alone, since dying does not advance a chapter.
R.on("gameplay:GAME_END_NEXT_CHAPTER", function()
    if pending == "wins" then pending = nil end
end)

-- We have left the run. Whatever was claimed is now what happened; a run with
-- no claim at all was walked away from.
local function settle()
    if not finalized then finish(pending or "abandons") end
end

-- A run can start without the analytics boundary firing (that bus can be off),
-- so GAME_START opens one too. Both paths are idempotent through `finalized`.
local function begin()
    settle()                           -- a previous run we never saw the end of
    if not finalized then return end   -- already inside a run
    run, rbase, finalized, pending = {}, {}, false, nil
    sample_ident()
    bump("runs")
    fill_slots()
    chal_roll()
    publish()
end

R.on("run:start", begin)
R.on("gameplay:GAME_START", begin)

-- run:end is the analytics boundary; menu:enter is the backstop for a run
-- abandoned from the pause menu, which fires no GAME_END at all.
R.on("run:end", settle)
R.on("menu:enter", function()
    settle()
    if not cfg.on_menu then return end
    local xp = R.kv.get("xp", 0)
    local lvl, title, into, need = rank(xp)
    R.log(("[Saga] level %d %s — %d XP (%d/%d to next), %d run(s), %d feat(s), %d objective(s)")
        :format(lvl, title, xp, into, need, total("runs"), R.kv.get("feats", 0),
                R.kv.get("quests_done", 0)))
    for _, line in ipairs(winrate_lines()) do R.log("[Saga] " .. line) end
end)

-- Feats, objectives and the HUD are re-evaluated on a timer rather than on
-- every kill: the bus is hot, each pass walks both tables, and publishing
-- writes the state file. `every_main` runs on the gameplay bus, which is the
-- same thread the counters are raised on, so nothing here needs a lock.
if R.schedule and R.schedule.every_main then
    R.schedule.every_main(3, function()
        -- The challenge poll runs UNGATED, ahead of the dirty check. Everything
        -- else here is driven by a bus event, which sets `dirty` on its way
        -- past; the poll exists precisely for the things no event reports, and
        -- a spend is the clearest case — the bus has GAIN_DREAM_SHARDS and no
        -- spend event at all, so a purchase marks nothing dirty and, gated,
        -- was only ever noticed if some unrelated event happened to fire in the
        -- same window. It is a handful of reads; the expensive half is the
        -- publish below, and that stays gated. chal_poll sets `dirty` itself
        -- when it marks a challenge, so a verdict still reaches the HUD on the
        -- tick that found it rather than the one after.
        chal_poll()
        if not dirty then return end
        dirty = false
        check_feats()
        check_quests()
        publish()
    end)
end

-- Shutting down mid-run still counts it, and closing the game from a run is
-- the commonest way to abandon one.
R.on("exit", function() settle(); R.kv.save(true) end)

R.on("ready", function()
    fill_slots()
    publish()
    local lvl, title = rank(R.kv.get("xp", 0))
    R.log(("[Saga] level %d %s, %d feat(s) — %d objective slot(s), challenges %s")
        :format(lvl, title, R.kv.get("feats", 0), cfg.slots,
                cfg.ch_tier == "off" and "off"
                    or (cfg.ch_tier .. (cfg.ch_apply and " (auto-apply ON)" or ""))))
end)
