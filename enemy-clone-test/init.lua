-- Enemy Clone Test — see manifest.toml for what it is measuring.
--
-- Two gates, reported separately, because "never saw a crab" has two very
-- different causes:
--   1. did the clone def LOAD at all?  81 enemy defs ship; the clone makes 82.
--   2. did a camp SPAWN it?            only your eyes can say: a crab in a
--                                      gnoll camp on Storm Island.
-- Gate 1 without gate 2 means the def is registered but never a candidate;
-- neither means the boot-time definition scan never saw the file.

local R = require "rsmm"

local VANILLA_ENEMY_DEFS = 81

local exp = R.exp or {
    case    = function() end,
    verdict = function(_, pass) return pass end,
}

exp.case("clone_loaded", "is the cloned enemy def live in the definition registry?")
exp.case("clone_spawned",
         "did a Mud Crab appear in a GNOLL camp on Storm Island? (look, then `rsmm exp answer`)")

local function count_defs()
    if not R.defs.ready() then
        R.log("[clone-test] definition registry unreadable: " .. tostring(R.defs.why_not()))
        return
    end
    local n = #R.defs.instances("oCDtEnemyDefinition")
    local loaded = n > VANILLA_ENEMY_DEFS
    exp.verdict("clone_loaded", loaded,
                ("%d enemy defs live (vanilla %d)"):format(n, VANILLA_ENEMY_DEFS))
    R.log(("[clone-test] %d enemy defs live (vanilla %d) -> clone %s. Now play "
           .. "Storm Island and look for a crab in a gnoll camp.")
          :format(n, VANILLA_ENEMY_DEFS, loaded and "LOADED" or "NOT loaded"))
end

R.on("ready", function()
    -- Definitions load at boot ("InitialLoading - Load all definitions"), so
    -- by a few seconds after ready the registry is complete.
    R.schedule.after_main(10, function()
        local ok, err = pcall(count_defs)
        if not ok then R.log("[clone-test] raised: " .. tostring(err)) end
    end)
end)
