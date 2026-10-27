-- Session-only native body detachment. The caller owns the authority transition and reconciliation.
local DevTools = require "ProjectPeople/DevTools"
local CharacterState = require "ProjectPeople/CharacterState"
ProjectPeople = ProjectPeople or {}
local Suspension = { VERSION = 1, PROVEN = false }
ProjectPeople.NativeSuspension = Suspension

local operations, people, actors = {}, {}, {}
local operationCount = 0

local function fail(code, detail)
    return { ok = false, code = code, detail = detail, proven = false, authorityCommitted = false }
end

local isSafeId = DevTools.isSafeId

local isFinite = DevTools.isFinite

local function environment()
    local ok, result = pcall(function()
        if isClient() or isServer() then
            return fail "singleplayer_candidate_only"
        end
        local build = getCore():getVersionNumber()
        if build ~= "42.21" and build ~= "42.21.0" then
            return fail("uninspected_game_build", build)
        end
        local cell = getCell()
        if not cell then
            return fail "native_cell_unavailable"
        end
        return { ok = true, cell = cell, build = build }
    end)
    return ok and result or fail("native_environment_unavailable", tostring(result))
end

local function receipt(operation)
    return {
        schema = Suspension.VERSION,
        personId = operation.personId,
        revision = operation.revision,
        operationId = operation.operationId,
        build = operation.build,
    }
end

local function resolve(supplied)
    if type(supplied) ~= "table" or not isSafeId(supplied.operationId) then
        return nil
    end
    local operation = operations[supplied.operationId]
    if not operation then
        return nil
    end
    for key, value in pairs(receipt(operation)) do
        if supplied[key] ~= value then
            return nil
        end
    end
    return operation
end

local function uncontrolled(actor)
    if
        not actor
        or not instanceof(actor, "IsoPlayer")
        or not actor:isNpc()
        or actor:isLocalPlayer()
        or actor:isSaveFileInUse()
    then
        return false
    end
    -- This build has four local slots. IsoPlayer.instance is temporarily changed
    -- during native NPC updates, so it is not a controller-ownership witness.
    for slot = 0, 3 do
        if getSpecificPlayer(slot) == actor then
            return false
        end
    end
    return true
end

local function available(actor)
    return actor:getVehicle() == nil
        and actor:getCharacterActions():isEmpty()
        and not actor:isGrappling()
        and not actor:isBeingGrappled()
        and not actor:isPerformingGrappleAnimation()
        and not actor:isDeathDragDown()
        and not actor:isKilledByFall()
        and not actor:isbFalling()
        and not actor:isClimbing()
        and not actor:isKnockedDown()
        and not actor:isAttacking()
        and not actor:hasHitReaction()
        and not actor:hasPath()
end

local function squareWitnesses(actor)
    local result, seen = {}, {}
    for _, method in ipairs({ "getCurrentSquare", "getLastSquare", "getMovingSquare", "getSquare" }) do
        local square = actor[method](actor)
        if square and not seen[square] then
            result[#result + 1], seen[square] = square, true
        end
    end
    return result
end

local function membership(actor, cell, oldSquares)
    local result = {
        object = cell:getObjectList():contains(actor),
        added = cell:getAddList():contains(actor),
        removed = cell:getRemoveList():contains(actor),
        current = actor:getCurrentSquare() ~= nil,
        last = actor:getLastSquare() ~= nil,
        moving = actor:getMovingSquare() ~= nil,
        square = actor:getSquare() ~= nil,
        oldMoving = false,
        oldStatic = false,
        oldObject = false,
        oldSpecial = false,
    }
    for _, square in ipairs(oldSquares) do
        if square:getMovingObjects():contains(actor) then
            result.oldMoving = true
        end
        if square:getStaticMovingObjects():contains(actor) then
            result.oldStatic = true
        end
        if square:getObjects():contains(actor) then
            result.oldObject = true
        end
        if square:getSpecialObjects():contains(actor) then
            result.oldSpecial = true
        end
    end
    return result
end

local function absent(observed)
    for _, present in pairs(observed) do
        if present ~= false then
            return false
        end
    end
    return true
end

local function membershipDetail(observed)
    local fields = {}
    for _, key in ipairs({
        "object",
        "added",
        "removed",
        "current",
        "last",
        "moving",
        "square",
        "oldMoving",
        "oldStatic",
        "oldObject",
        "oldSpecial",
    }) do
        fields[#fields + 1] = key .. "=" .. tostring(observed[key])
    end
    return table.concat(fields, ",")
end

-- Handles stay private and remain the actual native owners. This is not an
-- inventory payload or a claim that perishable items stop their own processing.

local function inventoryWitness(actor)
    local result = {
        root = actor:getInventory(),
        items = {},
        containers = {},
        count = 0,
        primary = actor:getPrimaryHandItem(),
        secondary = actor:getSecondaryHandItem(),
    }
    assert(result.root:getParent() == actor, "inventory_parent_mismatch")
    local function visit(container, depth)
        assert(depth <= 16 and not result.containers[container], "cyclic_or_deep_inventory")
        result.containers[container] = true
        local items = container:getItems()
        assert(items:size() <= 4096, "inventory_size_unsupported")
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            assert(
                item and not result.items[item] and item:getContainer() == container,
                "native_inventory_ownership_mismatch"
            )
            result.count = result.count + 1
            assert(result.count <= 4096, "inventory_size_unsupported")
            result.items[item] = { id = item:getID(), fullType = item:getFullType(), owner = container }
            if instanceof(item, "InventoryContainer") then
                visit(item:getInventory(), depth + 1)
            end
        end
    end
    visit(result.root, 0)
    return result
end

local function capture(actor, personId, revision)
    local observation = CharacterState.capture(actor, personId, revision)
    assert(observation.ok, "native_character_observation_incomplete")
    local hours = actor:getHoursSurvived()
    assert(isFinite(hours), "native_actor_clock_unavailable")
    return {
        snapshot = observation.snapshot,
        hours = hours,
        onFire = actor:isOnFire(),
        position = { x = actor:getX(), y = actor:getY(), z = actor:getZ() },
        body = actor:getBodyDamage(),
        stats = actor:getStats(),
        nutrition = actor:getNutrition(),
        inventory = inventoryWitness(actor),
    }
end

local function difference(first, second, path)
    if type(first) ~= type(second) then
        return path
    end
    if type(first) ~= "table" then
        return first ~= second and path or nil
    end
    for key, value in pairs(first) do
        local changed = difference(value, second[key], path .. "." .. tostring(key))
        if changed then
            return changed
        end
    end
    for key in pairs(second) do
        if first[key] == nil then
            return path .. "." .. tostring(key)
        end
    end
    return nil
end

local function unchanged(before, after)
    for _, key in ipairs({ "snapshot", "hours", "onFire", "position", "body", "stats", "nutrition" }) do
        local changed = difference(before[key], after[key], key)
        if changed then
            return changed
        end
    end
    local old, new = before.inventory, after.inventory
    if
        old.root ~= new.root
        or old.primary ~= new.primary
        or old.secondary ~= new.secondary
        or old.count ~= new.count
    then
        return "inventory.handles_or_count"
    end
    for container in pairs(old.containers) do
        if not new.containers[container] then
            return "inventory.container_missing"
        end
    end
    for container in pairs(new.containers) do
        if not old.containers[container] then
            return "inventory.container_added"
        end
    end
    for item, previous in pairs(old.items) do
        local actual = new.items[item]
        if
            not actual
            or previous.id ~= actual.id
            or previous.fullType ~= actual.fullType
            or previous.owner ~= actual.owner
        then
            return "inventory.item_or_owner_changed"
        end
    end
    return nil
end

local function inspect(operation)
    local env = environment()
    if not env.ok then
        return env
    end
    if env.cell ~= operation.cell or env.build ~= operation.build then
        return fail "native_context_changed"
    end
    local actor = operation.actor
    local observed = membership(actor, env.cell, operation.squares)
    if not absent(observed) then
        return fail("native_actor_not_detached", membershipDetail(observed))
    end
    if
        not uncontrolled(actor)
        or actor:isDead()
        or actor:isGodMod()
        or actor:isInvulnerable()
        or actor:isInvincible()
    then
        return fail "detached_actor_life_or_control_changed"
    end
    local after = capture(actor, operation.personId, operation.revision)
    local changed = unchanged(operation.before, after)
    if changed then
        return fail("detached_native_state_changed", changed)
    end
    return {
        ok = true,
        code = "same_live_actor_detached_observation",
        proven = false,
        authorityCommitted = false,
        receipt = receipt(operation),
        membership = observed,
        hours = after.hours,
        onFire = after.onFire,
        snapshot = after.snapshot,
        itemCount = after.inventory.count,
        durable = false,
        reentrySupported = false,
    }
end

-- Call synchronously at a naturally safe boundary. Never change safeToAdd or
-- call inside an unsafe native update. Unknown/partial outcomes keep all locks.

function Suspension.suspendCandidate(actor, personId, revision, operationId)
    if
        not isSafeId(personId)
        or not isSafeId(operationId)
        or not isFinite(revision)
        or revision < 0
        or revision > 2147483647
        or revision ~= math.floor(revision)
    then
        return fail "restricted_ids_and_revision_required"
    end
    if operations[operationId] then
        return fail "operation_already_dispatched"
    end
    if people[personId] or actors[actor] then
        return fail "person_or_actor_operation_unresolved"
    end
    if operationCount >= 128 then
        return fail "candidate_session_operation_limit"
    end
    local env = environment()
    if not env.ok then
        return env
    end
    local ok, preparation = pcall(function()
        if not env.cell:isSafeToAdd() then
            return fail "unsafe_native_boundary"
        end
        if not uncontrolled(actor) then
            return fail "uncontrolled_native_npc_required"
        end
        if actor:isDead() or actor:isDeathDragDown() or actor:isKilledByFall() then
            return fail "native_death_already_committed"
        end
        if actor:isGodMod() or actor:isInvulnerable() or actor:isInvincible() then
            return fail "native_damage_override_present"
        end
        if not available(actor) then
            return fail "native_activity_requires_resolution"
        end
        if
            not env.cell:getObjectList():contains(actor)
            or env.cell:getAddList():contains(actor)
            or env.cell:getRemoveList():contains(actor)
            or not actor:getCurrentSquare()
        then
            return fail "stable_physical_membership_required"
        end
        -- Verify the required removal entry points BEFORE recording dispatch.
        assert(
            actor.removeFromWorld
                and actor.removeFromSquare
                and actor.setSquare
                and IsoFireManager
                and IsoFireManager.RemoveBurningCharacter,
            "native_removal_capability_unavailable"
        )
        local squares = squareWitnesses(actor)
        local before = capture(actor, personId, revision)
        return { ok = true, before = before, squares = squares }
    end)
    if not ok then
        return fail("native_precondition_unavailable", tostring(preparation))
    end
    if not preparation.ok then
        return preparation
    end
    local operation = {
        personId = personId,
        revision = revision,
        operationId = operationId,
        build = env.build,
        actor = actor,
        cell = env.cell,
        before = preparation.before,
        squares = preparation.squares,
        state = "dispatching",
    }
    operations[operationId], people[personId], actors[actor] = operation, operation, operation
    operationCount = operationCount + 1
    local dispatched, result = pcall(function()
        -- IsoCell ignores queued deletion of living IsoPlayers. The safe flag
        -- must still be true: unsafe removeFromWorld is not a weaker fallback.
        assert(env.cell:isSafeToAdd(), "safe_boundary_lost")
        actor:removeFromWorld()
        actor:removeFromSquare()
        -- IsoObject.removeFromSquare removes lists but retains its square field.
        -- Vanilla animal pickup explicitly clears it after these same calls.
        actor:setSquare(nil)
        -- This drops SP fire-manager tracking only; onFire and burn wounds stay.
        -- StopBurning would silently treat the condition and is never called.
        IsoFireManager.RemoveBurningCharacter(actor)
        return inspect(operation)
    end)
    if not dispatched or not result.ok then
        operation.state = "unknown"
        local failure = fail(
            "native_suspension_outcome_unknown",
            dispatched and (result.code .. ":" .. tostring(result.detail)) or tostring(result)
        )
        failure.receipt = receipt(operation)
        return failure
    end
    operation.state = "detached_candidate"
    result.code = "candidate_detached_requires_authority_reconciliation"
    return result
end

function Suspension.observe(suppliedReceipt)
    local operation = resolve(suppliedReceipt)
    if not operation then
        return fail "session_operation_receipt_required"
    end
    local ok, result = pcall(function()
        return inspect(operation)
    end)
    if not ok or not result.ok then
        operation.state = "unknown"
        return ok and result or fail("native_observation_unavailable", tostring(result))
    end
    if operation.state ~= "detached_candidate" then
        return fail "previous_native_outcome_unresolved"
    end
    return result
end

function Suspension.canResume(_receipt)
    return fail "physical_critical_hold_and_reentry_unproven"
end

return Suspension
