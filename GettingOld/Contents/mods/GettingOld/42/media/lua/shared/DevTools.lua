------------------------------------
-- Devlin's shared tool library
--
-- Just functions that I can use across several mods to make my life easier.
------------------------------------
DevTools = DevTools or {}
DevTools.debugMode = true

function DevTools.debugLog(modName, msg)
    if DevTools.debugMode then
        print("[" .. modName .. "] " .. tostring(msg))
    end
end

function DevTools.saySafe(player, text)
    if not player then return end

    if isClient() then
        sendClientCommand("chat", "sendPlayerSay", { text = text })
    else
        player:addLineChatElement(text)
    end
end

DevTools._chanceBuckets = DevTools._chanceBuckets or {}
function DevTools.chance(odd, outOf, key)
    odd = tonumber(odd) or 0
    outOf = tonumber(outOf) or 0

    if outOf <= 0 then return false end
    if odd <= 0 then return false end
    if odd >= outOf then return true end

    if key then
        local p = odd / outOf
        DevTools._chanceBuckets[key] = (DevTools._chanceBuckets[key] or 0) + p
        if DevTools._chanceBuckets[key] >= 1 then
            DevTools._chanceBuckets[key] = DevTools._chanceBuckets[key] - 1
            return true
        else
            return false
        end
    end

    local roll = ZombRand(outOf)
    local result = roll < odd
    DevTools.debugLog("DevTools", string.format("Chance %d/%d roll=%d result=%s", odd, outOf, roll, tostring(result)))
    return result
end


DevTools._activeTimers = DevTools._activeTimers or {}
function DevTools.waitSeconds(seconds, callback, id)
    if DevTools._activeTimers[id] then
        return
    end

    DevTools._activeTimers[id] = true
    DevTools.debugLog("DevTools", "Waiting to execute: " .. tostring(id) .. " in " .. tostring(seconds) .. " seconds...")

    local ticks = 0
    local delayTicks = math.floor(seconds * 60)

    local function delayedActions()
        ticks = ticks + 1
        if ticks >= delayTicks then
            Events.OnTick.Remove(delayedActions)
            DevTools.debugLog("DevTools", "Executing: " .. tostring(id))
            pcall(callback)
            DevTools._activeTimers[id] = nil
        end
    end

    Events.OnTick.Add(delayedActions)
end

function DevTools.waitUntilNotNil(condition, id)
    if DevTools._activeTimers[id] then
        return
    end

    DevTools._activeTimers[id] = true
    DevTools.debugLog("DevTools", "Waiting on condition to execute: " .. tostring(id))

    local ticks = 0
    local delayTicks = math.floor(seconds * 60)

    local function delayedActions()
        if condition then
            Events.OnTick.Remove(delayedActions)
            DevTools.debugLog("DevTools", "Executing: " .. tostring(id))
            pcall(callback)
            DevTools._activeTimers[id] = nil
        end
    end

    Events.OnTick.Add(delayedActions)
end
