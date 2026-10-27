-- Original, bounded SP melee adapter. The native player collision callback is
-- limited to actual local players in 42.21. An additive NPC-only animation node
-- emits the contact signal; this adapter validates that signal and real reach
-- before invoking the ordinary native Hit API once. It never assigns health.
ProjectPeople = ProjectPeople or {}
local Combat = { PROVEN = false }
ProjectPeople.NativeCombat = Combat
local active = {}

local function available(actor)
    if
        not actor
        or not instanceof(actor, "IsoPlayer")
        or not actor:isNpc()
        or actor:isLocalPlayer()
        or actor:isDead()
        or not actor:getCurrentSquare()
        or not actor:getModData().ProjectPeoplePersonId
    then
        return false
    end
    for slot = 0, 3 do
        if getSpecificPlayer(slot) == actor then
            return false
        end
    end
    return true
end

local function finish(op, state, reason)
    op.state, op.reason = state, reason
    active[op.actor] = nil
    op.actor:clearVariable "ProjectPeopleMelee"
    return {
        state = state,
        reason = reason,
        contactObserved = op.contactObserved == true,
        hitDispatched = op.hitDispatched == true,
    }
end

local function validTarget(op)
    local actor, target, weapon = op.actor, op.target, op.weapon
    if
        not available(actor)
        or not target
        or not instanceof(target, "IsoZombie")
        or target:isDead()
        or not target:getCurrentSquare()
        or not getCell():getObjectList():contains(target)
        or actor:getPrimaryHandItem() ~= weapon
        or weapon:getContainer() ~= actor:getInventory()
        or weapon:getCondition() <= 0
    then
        return false, "actor_target_or_weapon_changed"
    end
    if math.abs(actor:getZ() - target:getZ()) > 0.2 then
        return false, "different_floor"
    end
    local dx, dy = target:getX() - actor:getX(), target:getY() - actor:getY()
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= weapon:getMinRange() or distance > weapon:getMaxRange(actor) then
        return false, "out_of_reach"
    end
    if
        actor:getCurrentSquare():isBlockedTo(target:getCurrentSquare())
        or actor:getCurrentSquare():isSomethingTo(target:getCurrentSquare())
    then
        return false, "blocked_contact"
    end
    local facing = actor:getForwardDirection()
    if (facing:getX() * dx + facing:getY() * dy) / distance < 0.35 then
        return false, "target_outside_swing"
    end
    return true
end

function Combat.start(actor, target, operationId)
    if isClient() or isServer() then
        return { ok = false, code = "singleplayer_candidate_only" }
    end
    if getCore():getVersionNumber() ~= "42.21" then
        return { ok = false, code = "uninspected_build" }
    end
    if
        type(operationId) ~= "string"
        or #operationId == 0
        or #operationId > 120
        or not available(actor)
        or active[actor]
    then
        return { ok = false, code = "available_owned_actor_required" }
    end
    local op = {
        actor = actor,
        target = target,
        weapon = actor:getPrimaryHandItem(),
        id = operationId,
        state = "preparing",
        started = getTimestampMs(),
    }
    local ok, result = pcall(function()
        if
            not op.weapon
            or not instanceof(op.weapon, "HandWeapon")
            or not op.weapon:isMelee()
            or actor:getVariableString "Weapon" ~= "1handed"
            or not actor:isWeaponReady()
            or actor:isPerformingAttackAnimation()
        then
            return { ok = false, code = "ready_one_handed_melee_required" }
        end
        actor:faceThisObject(target)
        local valid, reason = validTarget(op)
        if not valid then
            return { ok = false, code = reason }
        end
        actor:clearVariable "ProjectPeopleMeleeContact"
        actor:clearVariable "ProjectPeopleMeleeStarted"
        actor:setVariable("ProjectPeopleMelee", true)
        active[actor] = op
        op.state = "animating"
        actor:pressedAttack()
        -- Public native postupdate evaluates the attack before the NPC AI's
        -- next empty control record clears it. This adds one survival-clock
        -- update per attack; it is explicit and not a complete timing solution.
        actor:postupdate()
        return { ok = true, operation = op }
    end)
    if ok then
        return result
    end
    if active[actor] then
        finish(op, "unknown", tostring(result))
    end
    return { ok = false, code = "attack_outcome_unknown", detail = tostring(result) }
end

function Combat.tick(op)
    if type(op) ~= "table" then
        return { state = "rejected", reason = "operation_required" }
    end
    if op.state ~= "animating" then
        return { state = op.state, reason = op.reason, hitDispatched = op.hitDispatched == true }
    end
    if active[op.actor] ~= op then
        return { state = "rejected", reason = "not_active_operation" }
    end
    local ok, result = pcall(function()
        op.animationObserved = op.animationObserved or op.actor:isPerformingAttackAnimation()
        op.startObserved = op.startObserved or op.actor:getVariableBoolean "ProjectPeopleMeleeStarted"
        if op.actor:getVariableBoolean "ProjectPeopleMeleeContact" then
            op.contactObserved = true
            if not op.startObserved or not op.animationObserved then
                return finish(op, "unknown", "contact_without_animation")
            end
            local valid, reason = validTarget(op)
            if not valid then
                return finish(op, "missed", reason)
            end
            local damage = (op.weapon:getMinDamage() + op.weapon:getMaxDamage()) * 0.5
            assert(damage > 0 and damage < 100, "unsupported_native_weapon_damage")
            op.hitDispatched = true -- dispatch fence precedes the native effect
            op.target:Hit(op.weapon, op.actor, damage, false, 1, false)
            return finish(op, "contact", "native_hit_dispatched")
        end
        if not available(op.actor) then
            return finish(op, "interrupted", "actor_unavailable")
        end
        if getTimestampMs() - op.started > 5000 then
            return finish(op, "blocked", "animation_contact_timeout")
        end
        return { state = op.state, animationObserved = op.animationObserved, startObserved = op.startObserved }
    end)
    if not ok then
        return finish(op, "unknown", tostring(result))
    end
    return result
end

function Combat.cancel(op)
    if type(op) ~= "table" or active[op.actor] ~= op then
        return { state = "rejected", reason = "not_active_operation" }
    end
    return finish(op, "interrupted", "cancelled")
end
return Combat
