-- Let the native window state finish before applying queued movement orders.
local Windows = {}
function Windows.update(binding, record)
    local actor = binding.actor
    local name = actor.getCurrentStateName and tostring(actor:getCurrentStateName()):lower() or ""
    if name:find("climbthroughwindow", 1, true) or name:find("climbwindow", 1, true) then
        binding.windowTraversal = true
        actor:setRunning(false)
        actor:setSprinting(false)
        return true
    end
    if binding.windowTraversal then
        binding.windowTraversal = nil
        -- Window exit restores its old path flags. Dispatch the newest order
        -- from the actual landing instead of trusting that cancelled old path.
        binding.epoch = -1
        binding.pendingPath = nil
    end
    return false
end
-- Native zombie pathfinding skips the human door/window assistance branch.
-- Use the safe IsoWindow toggle, then the native zombie-compatible climb state.
function Windows.assist(binding, record, now)
    if isClient and isClient() or record.mode ~= "move" or record.attacking then
        return false
    end
    local actor = binding.actor
    local current = actor:getCurrentSquare()
    if not current or not current.getWindowTo or actor:isDead() then
        return false
    end
    now = now or getTimestampMs()
    if now < (binding.nextWindowCheck or 0) then
        return false
    end
    binding.nextWindowCheck = now + 250
    local dx, dy = actor:getLookDirectionX(), actor:getLookDirectionY()
    if not actor:getPath2() then
        dx, dy = (record.goalX or actor:getX()) - actor:getX(), (record.goalY or actor:getY()) - actor:getY()
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.01 then
            return false
        end
        dx, dy = dx / length, dy / length
    end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if dx * d[1] + dy * d[2] > 0.7 then
            local other = getCell():getGridSquare(current:getX() + d[1], current:getY() + d[2], current:getZ())
            local window = other and current:getWindowTo(other)
            if
                window
                and instanceof(window, "IsoWindow")
                and not window:isLocked()
                and not window:isPermaLocked()
                and not window:isBarricaded()
                and not window:isInvincible()
                and not window:getModData().CustomLock
                and not (window:isSmashed() and not window:isGlassRemoved())
                and other:TreatAsSolidFloor()
                and other:isFree(false)
                and not other:isWaterSquare()
                and not other:isVehicleIntersecting()
                and SafeHouse
                and not SafeHouse.isSafeHouse(other, nil, false)
            then
                local edgeX = current:getX() + 0.5 + d[1] * 0.5
                local edgeY = current:getY() + 0.5 + d[2] * 0.5
                if (actor:getX() - edgeX) ^ 2 + (actor:getY() - edgeY) ^ 2 <= 0.85 ^ 2 then
                    if not window:IsOpen() and not window:isSmashed() then
                        window:ToggleWindow(actor)
                    end
                    if window:canClimbThrough(actor) then
                        actor:setRunning(false)
                        actor:setSprinting(false)
                        actor:faceThisObject(window)
                        actor:climbThroughWindow(window)
                        binding.windowTraversal = true
                        return true
                    end
                end
            end
        end
    end
    return false
end
return Windows
