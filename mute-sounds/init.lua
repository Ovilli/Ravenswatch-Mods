-- Mute sounds: silence exactly the sounds picked in this mod's config.
--
-- Every field in config_schema.toml is a list of FMOD paths: `muted` holds
-- categories ("bus:/Music", "event:/GUI", "all"), each `hero_*` field holds
-- single sounds or folders of that hero. They are merged into one selection
-- for R.audio.select, re-sent whenever any of them changes.

local R = require "rsmm"

local FIELDS = {
    "muted",
    "hero_scarlet", "hero_piper", "hero_beowulf", "hero_snow_queen", "hero_aladdin",
    "hero_melusine", "hero_geppetto", "hero_sun_wukong", "hero_carmilla",
    "hero_romeo", "hero_juliet", "hero_merlin", "hero_kintaro",
}

if not (R.audio and R.audio.select) then
    R.log("[mute-sounds] this SDK has no R.audio; update the loader (rsmm update-loader)")
    return
end

local function selection()
    local out, seen = {}, {}
    for _, key in ipairs(FIELDS) do
        local list = R.config.get(key, {})
        if type(list) == "table" then
            for _, p in ipairs(list) do
                if type(p) == "string" and not seen[p] then
                    seen[p] = true
                    out[#out + 1] = p
                end
            end
        end
    end
    return out
end

local function apply()
    local list = selection()
    if not R.audio.select(list) then
        R.log("[mute-sounds] the running loader cannot mute by sound; update it (rsmm update-loader)")
        return
    end
    R.log("[mute-sounds] muting " .. #list .. " selection(s)")
end

apply()
for _, key in ipairs(FIELDS) do R.config.on_change(key, apply) end

-- One report once FMOD is running, so the log answers "did it arm?".
R.schedule.after(15, function()
    local st = R.audio.status()
    R.log(string.format(
        "[mute-sounds] core=%s studio=%s buses %d/%d muted, %d/%d live sounds muted, last_error=%d",
        tostring(st.hooked), tostring(st.studio_hooked), st.buses_muted or 0, st.buses or 0,
        st.instances_muted or 0, st.instances or 0, st.last_error or 0))
end)
