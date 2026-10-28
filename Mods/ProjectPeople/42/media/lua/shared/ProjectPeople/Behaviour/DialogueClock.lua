-- Real reading time, excluding a paused simulation. Shared by authority and UI.
local Clock = {}
local previous, elapsed, wasPaused
function Clock.paused()
    return isGamePaused and isGamePaused() or false
end
function Clock.now()
    local wall, paused = getTimestampMs(), Clock.paused()
    if not previous or wall < previous then
        elapsed = wall
    elseif not paused and not wasPaused then
        elapsed = elapsed + wall - previous
    end
    previous, wasPaused = wall, paused
    return elapsed
end
if Events and Events.OnTickEvenPaused then
    Events.OnTickEvenPaused.Add(Clock.now)
end
return Clock
