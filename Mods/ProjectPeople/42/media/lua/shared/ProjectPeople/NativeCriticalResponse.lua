-- Session-only SP experiment for installed 42.21. No automatic event policy,
-- persistence, Core commit, lock release or complete mortality guarantee.
-- The original body can occupy its original render square while omitted from
-- the cell object set that rebuilds the native update scheduler each frame.
local Suspension = require "ProjectPeople/NativeSuspension"
local CharacterState = require "ProjectPeople/CharacterState"
local Rendering = require "ProjectPeople/NativeRendering"
ProjectPeople = ProjectPeople or {}
local Response = { VERSION = 1, PROVEN = false, OPPORTUNITY_MS = 10000 }
ProjectPeople.NativeCriticalResponse = Response
local operations, people, actors = {}, {}, {}

local function fail(code, detail)
    return {
        ok = false,
        code = code,
        detail = detail,
        proven = false,
        authorityCommitted = false,
        durable = false,
        completeProtection = false,
    }
end

local function receipt(op)
    return {
        schema = Response.VERSION,
        operationId = op.operationId,
        personId = op.personId,
        revision = op.revision,
        build = op.build,
    }
end

local function resolve(value)
    if type(value) ~= "table" then
        return nil
    end
    local op = operations[value.operationId]
    if not op then
        return nil
    end
    for key, expected in pairs(receipt(op)) do
        if value[key] ~= expected then
            return nil
        end
    end
    return op
end

local function difference(a, b, path)
    if type(a) ~= type(b) then
        return path
    end
    if type(a) ~= "table" then
        return a ~= b and path or nil
    end
    for key, value in pairs(a) do
        local changed = difference(value, b[key], path .. "." .. tostring(key))
        if changed then
            return changed
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return path .. "." .. tostring(key)
        end
    end
end

local function capture(op)
    local actor = op.actor
    local observed = CharacterState.capture(actor, op.personId, op.revision)
    assert(observed.ok, "native_observation_incomplete")
    local result = {
        snapshot = observed.snapshot,
        body = actor:getBodyDamage(),
        stats = actor:getStats(),
        nutrition = actor:getNutrition(),
        inventory = actor:getInventory(),
        items = {},
        count = 0,
        health = actor:getHealth(),
        hours = actor:getHoursSurvived(),
        onFire = actor:isOnFire(),
        x = actor:getX(),
        y = actor:getY(),
        z = actor:getZ(),
        primary = actor:getPrimaryHandItem(),
        secondary = actor:getSecondaryHandItem(),
    }
    local seen = {}
    local function visit(container, depth)
        assert(depth <= 16 and not seen[container], "unsupported_inventory_graph")
        seen[container] = true
        local contents = container:getItems()
        for index = 0, contents:size() - 1 do
            local item = contents:get(index)
            assert(item and not result.items[item] and item:getContainer() == container, "item_ownership_changed")
            result.count = result.count + 1
            assert(result.count <= 4096, "unsupported_inventory_size")
            result.items[item] = { id = item:getID(), owner = container, fullType = item:getFullType() }
            if instanceof(item, "InventoryContainer") then
                visit(item:getInventory(), depth + 1)
            end
        end
    end
    visit(result.inventory, 0)
    return result
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
    for slot = 0, 3 do
        if getSpecificPlayer(slot) == actor then
            return false
        end
    end
    return true
end

local function inspect(op)
    assert(not isClient() and not isServer() and getCell() == op.cell, "native_context_changed")
    assert(getCore():getVersionNumber() == op.build, "native_build_changed")
    assert(uncontrolled(op.actor) and not op.actor:isDead(), "native_life_or_control_changed")
    assert(
        not op.actor:isGodMod() and not op.actor:isInvulnerable() and not op.actor:isInvincible(),
        "healing_or_damage_override_present"
    )
    assert(op.externalHits == 0 and op.unexpectedUpdates == 0, "external_native_interaction_unresolved")
    assert(
        not op.cell:getObjectList():contains(op.actor)
            and not op.cell:getAddList():contains(op.actor)
            and not op.cell:getRemoveList():contains(op.actor),
        "native_scheduler_membership_returned"
    )
    if op.state == "holding" then
        assert(
            op.actor:getCurrentSquare() == op.square
                and op.actor:getMovingSquare() == op.square
                and op.actor:getSquare() == op.square
                and op.square:getMovingObjects():contains(op.actor),
            "original_display_square_changed"
        )
    else
        assert(
            op.actor:getCurrentSquare() == nil
                and op.actor:getMovingSquare() == nil
                and op.actor:getSquare() == nil
                and not op.square:getMovingObjects():contains(op.actor),
            "hidden_actor_not_detached"
        )
    end
    local observed = capture(op)
    local changed = difference(op.before, observed, "native")
    assert(not changed, "original_native_state_changed:" .. tostring(changed))
    return observed
end

local function guarded(op, fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    op.state = "unknown"
    if op.renderingEnrolled then
        Rendering.remove(op.actor, op.renderOwner)
        op.renderingEnrolled = false
    end
    return fail("critical_response_outcome_unknown", tostring(result))
end

local function remaining(op)
    local value = 0
    local count = 0
    for _, viewer in pairs(op.viewers) do
        count = count + 1
        value = math.max(value, Response.OPPORTUNITY_MS - viewer.elapsed)
    end
    return count == 0 and Response.OPPORTUNITY_MS or math.max(0, value), count
end

local function result(op, code)
    local left, count = remaining(op)
    local render = op.renderingEnrolled and Rendering.observe(op.actor) or nil
    local submissions = op.renderSubmissions or 0
    if render and render.ok then
        submissions = submissions + render.renderSubmissions - op.renderBase
    end
    return {
        ok = true,
        code = code,
        receipt = receipt(op),
        suspensionReceipt = op.suspensionReceipt,
        state = op.state,
        remainingMs = left,
        observers = count,
        invisible = op.actor:isInvisible(),
        modelAdded = op.actor:isAddedToModelManager(),
        animationPresent = op.actor:hasAnimationPlayer(),
        activeModel = op.actor:hasActiveModel(),
        originalActor = op.actor,
        externalHits = op.externalHits,
        unexpectedUpdates = op.unexpectedUpdates,
        renderSubmissions = submissions,
        renderError = render and render.renderError or op.renderError,
        renderLastSkip = render and render.lastSkip or nil,
        presentationUpdates = op.presentationUpdates or 0,
        presentationError = op.presentationError,
        readyModels = op.actor:getReadyModelData():size(),
        sceneCulled = op.actor:isSceneCulled(),
        animationTrack = op.actor:dbgGetAnimTrackName(0, 0),
        animationTime = op.actor:dbgGetAnimTrackTime(0, 0),
        animationWeight = op.actor:dbgGetAnimTrackWeight(0, 0),
        proven = false,
        authorityCommitted = false,
        durable = false,
        completeProtection = false,
        pixelVisibilityProven = false,
    }
end

-- This owns the actor/receipt binding. An arbitrary actor plus somebody else's
-- public suspension receipt can never be supplied to showCandidate instead.

function Response.suspendCandidate(actor, personId, revision, operationId)
    if operations[operationId] or people[personId] or actors[actor] then
        return fail "critical_response_operation_unresolved"
    end
    local ok, prepared = pcall(function()
        assert(not isClient() and not isServer(), "singleplayer_candidate_only")
        assert(uncontrolled(actor) and actor:getCurrentSquare(), "uncontrolled_physical_actor_required")
        assert(not actor:avoidDamage() and not actor:getNoDamage(), "preexisting_damage_override")
        local op = {
            actor = actor,
            personId = personId,
            revision = revision,
            operationId = operationId,
            build = getCore():getVersionNumber(),
            cell = getCell(),
            square = actor:getCurrentSquare(),
            state = "preparing",
            viewers = {},
            externalHits = 0,
            unexpectedUpdates = 0,
            renderOwner = "NativeCriticalResponse:" .. tostring(operationId),
            renderSubmissions = 0,
            prior = {
                invisible = actor:isInvisible(),
                solid = actor:isSolid(),
                shootable = actor:isShootable(),
                collidable = actor:isCollidable(),
                avoidDamage = actor:avoidDamage(),
            },
        }
        op.before = capture(op)
        return op
    end)
    if not ok then
        return fail("critical_response_precondition_unavailable", tostring(prepared))
    end
    local suspended = Suspension.suspendCandidate(actor, personId, revision, operationId)
    if not suspended.ok then
        return suspended
    end
    local op = prepared
    op.suspensionReceipt = suspended.receipt
    op.state = "detached"
    operations[operationId], people[personId], actors[actor] = op, op, op
    return guarded(op, function()
        inspect(op)
        return result(op, "original_actor_detached")
    end)
end

function Response.showCandidate(value)
    local op = resolve(value)
    if not op then
        return fail "session_response_receipt_required"
    end
    if op.state ~= "detached" and op.state ~= "hidden" then
        return fail "response_already_dispatched_or_unresolved"
    end
    return guarded(op, function()
        inspect(op)
        assert(op.cell:isSafeToAdd(), "unsafe_native_boundary")
        if op.state == "detached" then
            local held = Suspension.observe(op.suspensionReceipt)
            assert(held.ok, "prior_suspension_receipt_unresolved")
            -- Standard role check and standard one-argument setter only.
            if not op.prior.invisible and Role.hasCapability(op.actor, Capability.ToggleInvisibleHimself) then
                op.actor:setInvisible(true)
                assert(op.actor:isInvisible(), "native_invisibility_rejected")
                op.changedInvisible = true
            end
            op.actor:setSolid(false)
            op.actor:setCollidable(false)
            op.actor:setShootable(false)
            -- One ordinary Hit can be refused without healing. This is consumed
            -- by Hit; it is not a guard against zombie contact or body updates.
            op.actor:setAvoidDamage(true)
        end
        op.actor:setCurrentSquare(op.square)
        op.actor:setSquare(op.square)
        op.actor:setMovingSquare(op.square)
        op.actor:setSceneCulled(false)
        op.state = "holding"
        local enrolled = Rendering.add(op.actor, op.renderOwner)
        assert(enrolled.ok, "native_render_enrollment_failed:" .. tostring(enrolled.code))
        op.renderingEnrolled = true
        op.renderBase = enrolled.renderSubmissions
        op.renderShownAt = getTimestampMs()
        inspect(op)
        return result(op, "original_body_displayed_outside_scheduler")
    end)
end

function Response.observe(value)
    local op = resolve(value)
    if not op then
        return fail "session_response_receipt_required"
    end
    if op.state ~= "detached" and op.state ~= "hidden" and op.state ~= "holding" then
        return fail("response_not_in_observable_hold", op.presentationError or op.state)
    end
    return guarded(op, function()
        inspect(op)
        return result(op, "same_original_body_observed")
    end)
end

-- Call from an actually displayed response UI. This records eligibility and
-- elapsed UI opportunities; it does not certify pixels or human attention.

function Response.recordOpportunity(value, observer)
    local op = resolve(value)
    if not op or op.state ~= "holding" then
        return fail "response_not_displayed"
    end
    return guarded(op, function()
        inspect(op)
        local slot
        for index = 0, 3 do
            if getSpecificPlayer(index) == observer then
                slot = index
            end
        end
        assert(slot ~= nil and observer ~= op.actor and not observer:isDead(), "living_local_observer_required")
        local now = getTimestampMs()
        local viewer = op.viewers[observer]
        if not viewer then
            viewer = { elapsed = 0, slot = slot }
            op.viewers[observer] = viewer
        end
        local near = math.abs(observer:getZ() - op.actor:getZ()) < 0.2 and observer:DistToSquared(op.actor) <= 64
        local render = Rendering.observe(op.actor, slot)
        assert(render.ok, "native_render_enrollment_lost")
        assert(not render.renderError, "native_render_submission_failed:" .. tostring(render.renderError))
        local submitted = render.renderedAt[slot]
        local eligible = near
            and render.submittedRecently
            and submitted >= op.renderShownAt
            and op.square:isCouldSee(slot)
            and op.actor:getAlpha(slot) > 0.05
            and op.actor:isAddedToModelManager()
            and op.actor:hasAnimationPlayer()
            and op.actor:hasActiveModel()
        if eligible and viewer.lastAt then
            viewer.elapsed =
                math.min(Response.OPPORTUNITY_MS, viewer.elapsed + math.max(0, math.min(250, now - viewer.lastAt)))
        end
        viewer.lastAt = eligible and now or nil
        local answer = result(op, "response_ui_opportunity_observed")
        answer.eligible = eligible
        return answer
    end)
end

function Response.hideCandidate(value)
    local op = resolve(value)
    if not op or op.state ~= "holding" then
        return fail "response_not_displayed"
    end
    return guarded(op, function()
        inspect(op)
        assert(op.cell:isSafeToAdd(), "unsafe_native_boundary")
        local render = Rendering.remove(op.actor, op.renderOwner)
        assert(render.ok, "native_render_enrollment_lost")
        op.renderSubmissions = op.renderSubmissions + render.renderSubmissions - op.renderBase
        op.renderError = render.renderError
        op.renderingEnrolled = false
        op.actor:setSceneCulled(true)
        op.actor:removeFromSquare()
        op.actor:setSquare(nil)
        op.state = "hidden"
        for _, viewer in pairs(op.viewers) do
            viewer.lastAt = nil
        end
        inspect(op)
        return result(op, "original_body_hidden_grace_retained")
    end)
end

function Response.acknowledge(value, observer, choice)
    local op = resolve(value)
    if not op or op.state ~= "holding" then
        return fail "response_not_displayed"
    end
    if choice ~= "resume-without-treatment" then
        return fail "explicit_response_choice_required"
    end
    local viewer = op.viewers[observer]
    if not viewer or viewer.elapsed < Response.OPPORTUNITY_MS then
        return fail "response_opportunity_incomplete"
    end
    return guarded(op, function()
        inspect(op)
        assert(getSpecificPlayer(viewer.slot) == observer and not observer:isDead(), "observer_control_changed")
        viewer.acknowledged = true
        return result(op, "explicit_response_recorded")
    end)
end

-- Diagnostic resume only. All NativeSuspension receipts/locks remain unresolved
-- and no person-authority transition is committed. Ordinary death may follow an
-- explicit decision to resume an untreated critical condition.

function Response.resumeCandidate(value)
    local op = resolve(value)
    if not op or op.state ~= "holding" then
        return fail "response_not_displayed"
    end
    local left, count = remaining(op)
    if left > 0 or count == 0 then
        return fail "response_opportunity_incomplete"
    end
    for slot = 0, 3 do
        local player = getSpecificPlayer(slot)
        if player and not player:isDead() then
            local viewer = op.viewers[player]
            if not viewer or viewer.elapsed < Response.OPPORTUNITY_MS or not viewer.acknowledged then
                return fail "all_local_observers_must_respond"
            end
        end
    end
    return guarded(op, function()
        inspect(op)
        assert(op.cell:isSafeToAdd(), "unsafe_native_boundary")
        op.actor:setSolid(op.prior.solid)
        op.actor:setCollidable(op.prior.collidable)
        op.actor:setShootable(op.prior.shootable)
        op.actor:setAvoidDamage(op.prior.avoidDamage)
        if op.changedInvisible then
            op.actor:setInvisible(op.prior.invisible)
            assert(op.actor:isInvisible() == op.prior.invisible, "native_invisibility_restore_rejected")
        end
        -- AddBurningCharacter only restores tracking; SetOnFire would create a
        -- new random burn wound. The original onFire flag has never been changed.
        if op.before.onFire then
            IsoFireManager.AddBurningCharacter(op.actor)
        end
        op.cell:addMovingObject(op.actor)
        assert(
            op.cell:getObjectList():contains(op.actor) and not op.cell:getAddList():contains(op.actor),
            "native_readmission_not_observed"
        )
        assert(not difference(op.before, capture(op), "native"), "state_changed_during_readmission")
        local render = Rendering.remove(op.actor, op.renderOwner)
        assert(render.ok, "native_render_enrollment_lost")
        op.renderSubmissions = op.renderSubmissions + render.renderSubmissions - op.renderBase
        op.renderError = render.renderError
        op.renderingEnrolled = false
        op.state = "resumed_candidate"
        return result(op, "native_readmission_after_explicit_response")
    end)
end

-- Observations never veto or replace engine events. An incoming native hit or
-- unexpected actor update prevents further clean-hold/resume claims. The prior
-- authority locks remain retained even if an outside attack kills this actor.
Events.OnWeaponHitCharacter.Add(function(_, target)
    local op = actors[target]
    if op and (op.state == "holding" or op.state == "hidden") then
        op.externalHits = op.externalHits + 1
    end
end)
Events.OnPlayerUpdate.Add(function(actor)
    local op = actors[actor]
    if op and (op.state == "holding" or op.state == "hidden") then
        op.unexpectedUpdates = op.unexpectedUpdates + 1
    end
end)

-- A render submission alone does not advance the model's bones/readiness.
-- This public native wrapper advances animator/model/light presentation only;
-- it does not run the actor's update/postupdate, physiology or hours clock.
-- Animation callbacks remain a candidate risk, so admit only the idle original
-- body and retain independent full-state observations in the response UI/test.
Events.OnTick.Add(function()
    for _, op in pairs(operations) do
        if op.state == "holding" then
            local outcome = guarded(op, function()
                local actor = op.actor
                assert(
                    not op.cell:getObjectList():contains(actor)
                        and not op.cell:getAddList():contains(actor)
                        and not op.cell:getRemoveList():contains(actor),
                    "presentation_actor_rescheduled"
                )
                assert(
                    actor:getCurrentSquare() == op.square
                        and not actor:isAttacking()
                        and not actor:hasPath()
                        and not actor:isDead(),
                    "presentation_actor_not_idle"
                )
                local health, bodyHealth, hours, fire =
                    actor:getHealth(),
                    actor:getBodyDamage():getOverallBodyHealth(),
                    actor:getHoursSurvived(),
                    actor:isOnFire()
                local x, y, z = actor:getX(), actor:getY(), actor:getZ()
                actor:updateForServerGui()
                assert(
                    actor:getHealth() == health
                        and actor:getBodyDamage():getOverallBodyHealth() == bodyHealth
                        and actor:getHoursSurvived() == hours
                        and actor:isOnFire() == fire
                        and actor:getX() == x
                        and actor:getY() == y
                        and actor:getZ() == z,
                    "presentation_update_changed_condition_clock_or_position"
                )
                op.presentationUpdates = (op.presentationUpdates or 0) + 1
                return { ok = true }
            end)
            if not outcome.ok then
                op.presentationError = outcome.detail or outcome.code
            end
        end
    end
end)

return Response
