-- Mute sounds: silence exactly the sounds picked in this mod's config.
--
-- `muted` holds FMOD paths from the config panel ("bus:/Music",
-- "event:/Heroes/Red", "all"); R.audio.select does the rest, and a change
-- saved while the game runs is picked up live.

local R = require "rsmm"

if not (R.audio and R.audio.select) then
    R.log("[mute-sounds] this SDK has no R.audio; update the loader (rsmm update-loader)")
    return
end

local function apply(list)
    if type(list) ~= "table" then list = {} end
    if not R.audio.select(list) then
        R.log("[mute-sounds] the running loader cannot mute by sound; update it (rsmm update-loader)")
        return
    end
    R.log("[mute-sounds] muting " .. #list .. " selection(s)")
end

apply(R.config.get("muted", {}))
R.config.on_change("muted", apply)

-- One report once FMOD is running, so the log answers "did it arm?".
R.schedule.after(15, function()
    local st = R.audio.status()
    R.log(string.format(
        "[mute-sounds] core=%s studio=%s buses %d/%d muted, %d/%d live sounds muted, last_error=%d",
        tostring(st.hooked), tostring(st.studio_hooked), st.buses_muted or 0, st.buses or 0,
        st.instances_muted or 0, st.instances or 0, st.last_error or 0))
end)
