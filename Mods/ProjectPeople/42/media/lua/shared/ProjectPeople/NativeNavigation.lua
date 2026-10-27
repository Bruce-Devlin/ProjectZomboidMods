-- Advances native human paths during OnPlayerUpdate, before collision resolution.
local DevTools = require "ProjectPeople/DevTools"
ProjectPeople = ProjectPeople or {}
local Navigation = { RUNTIME_PROVEN = false }
ProjectPeople.NativeNavigation = Navigation
local active = {}

local isFinite = DevTools.isFinite

local function stop(operation, state, reason)
    local ok, err = pcall(function()
        operation.actor:getPathFindBehavior2():cancel()
        operation.actor:setPath2(nil)
        operation.actor:setMoving(false)
    end)
    operation.state, operation.reason = state, reason
    operation.cleanupError = not ok and tostring(err) or nil
    active[operation.actor] = nil
    return { state = state, reason = reason, cleanupError = operation.cleanupError }
end

function Navigation.start(actor, goal, operationId)
    if
        not actor
        or type(goal) ~= "table"
        or not isFinite(goal.x)
        or not isFinite(goal.y)
        or not isFinite(goal.z)
        or type(operationId) ~= "string"
        or #operationId == 0
        or #operationId > 120
    then
        return { ok = false, code = "actor_destination_and_operation_required" }
    end
    if active[actor] then
        return { ok = false, code = "actor_already_navigating" }
    end
    local ok, result = pcall(function()
        if isServer() then
            return { ok = false, code = "server_native_path_state_unproven" }
        end
        local kind = instanceof(actor, "IsoZombie") and "zombie"
            or (instanceof(actor, "IsoPlayer") and actor:isNpc() and not actor:isLocalPlayer() and "human" or nil)
        if not kind then
            return { ok = false, code = "uncontrolled_native_npc_required" }
        end
        if actor:isDead() or not actor:getCurrentSquare() or actor:getVehicle() then
            return { ok = false, code = "actor_not_available" }
        end
        if not getCell():getGridSquare(goal.x, goal.y, goal.z) then
            return { ok = false, code = "destination_not_loaded" }
        end
        local operation = {
            actor = actor,
            id = operationId,
            kind = kind,
            state = "starting",
            goal = { x = goal.x, y = goal.y, z = goal.z },
            started = getTimestampMs(),
            lastProgress = getTimestampMs(),
            lastX = actor:getX(),
            lastY = actor:getY(),
        }
        active[actor] = operation
        -- Record dispatch before the engine effect. An exception is an unknown
        -- operation until cancellation is observed, never an automatic retry.
        actor:pathToLocationF(goal.x, goal.y, goal.z)
        operation.state = "moving"
        return { ok = true, operation = operation }
    end)
    if ok then
        return result
    end
    local operation = active[actor]
    if operation then
        stop(operation, "unknown", tostring(result))
    end
    return { ok = false, code = "native_path_start_failed", detail = tostring(result) }
end

function Navigation.tick(operation)
    if type(operation) ~= "table" then
        return { state = "rejected", reason = "operation_required" }
    end
    if operation.state ~= "moving" then
        return { state = operation.state, reason = operation.reason }
    end
    if active[operation.actor] ~= operation then
        return { state = "rejected", reason = "not_active_operation" }
    end
    local ok, result = pcall(function()
        local actor, goal = operation.actor, operation.goal
        if operation.kind == "human" and (not actor:isNpc() or actor:isLocalPlayer()) then
            return stop(operation, "interrupted", "controller_changed")
        end
        if actor:isDead() or not actor:getCurrentSquare() then
            return stop(operation, "interrupted", "actor_unavailable")
        end
        local dx, dy = actor:getX() - goal.x, actor:getY() - goal.y
        if dx * dx + dy * dy <= 0.25 and math.floor(actor:getZ()) == math.floor(goal.z) then
            return stop(operation, "arrived", "native_position_observed")
        end
        local now = getTimestampMs()
        if (actor:getX() - operation.lastX) ^ 2 + (actor:getY() - operation.lastY) ^ 2 > 0.04 then
            operation.lastProgress, operation.lastX, operation.lastY = now, actor:getX(), actor:getY()
        end
        if now - operation.started > 30000 then
            return stop(operation, "blocked", "path_time_limit")
        end
        if now - operation.lastProgress > 8000 then
            return stop(operation, "blocked", "no_native_progress")
        end
        return { state = "moving", nativeResult = operation.lastNativeResult }
    end)
    if not ok then
        return stop(operation, "unknown", tostring(result))
    end
    return result
end

Events.OnPlayerUpdate.Add(function(actor)
    local operation = active[actor]
    if not operation or operation.kind ~= "human" or operation.state ~= "moving" then
        return
    end
    local ok, err = pcall(function()
        if not actor:isNpc() or actor:isLocalPlayer() then
            stop(operation, "interrupted", "controller_changed")
            return
        end
        if actor:isDead() or not actor:getCurrentSquare() then
            stop(operation, "interrupted", "actor_unavailable")
            return
        end
        local native = actor:getPathFindBehavior2():update()
        operation.lastNativeResult = tostring(native)
        operation.nativeFrames = (operation.nativeFrames or 0) + 1
        if native == BehaviorResult.Failed then
            stop(operation, "blocked", "native_path_failed")
        end
    end)
    if not ok then
        stop(operation, "unknown", tostring(err))
    end
end)

-- Succession may inspect this before reserving a person; never expose the mutable
-- native operation to a caller that only needs to check whether work is pending.

function Navigation.isActive(actor)
    return active[actor] ~= nil
end

function Navigation.cancel(operation)
    if type(operation) ~= "table" or active[operation.actor] ~= operation then
        return { state = "rejected", reason = "not_active_operation" }
    end
    return stop(operation, "interrupted", "cancelled")
end

return Navigation
