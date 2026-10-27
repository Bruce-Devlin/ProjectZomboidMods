-- Creates and observes single-player human actor candidates. The authority owns person records.
ProjectPeople = ProjectPeople or {}
local Rendering = require "ProjectPeople/NativeRendering"
local Actor = { PROVEN = false }
ProjectPeople.NativeActor = Actor
local candidates = {}

function Actor.createCandidate(personId, square, descriptor)
    if type(personId) ~= "string" or #personId == 0 or #personId > 96 or not square then
        return { ok = false, code = "person_and_loaded_square_required" }
    end
    if candidates[personId] then
        return { ok = false, code = "candidate_already_dispatched" }
    end
    if isClient() or isServer() then
        return { ok = false, code = "singleplayer_candidate_only" }
    end
    if getCore():getVersionNumber() ~= "42.21" then
        return { ok = false, code = "uninspected_build" }
    end
    if not square:isFree(false) or not square:TreatAsSolidFloor() then
        return { ok = false, code = "free_solid_floor_required" }
    end
    local operation = { personId = personId, state = "creating" }
    candidates[personId] = operation
    local ok, err = pcall(function()
        local actor = IsoPlayer.new(
            getCell(),
            descriptor or SurvivorFactory.CreateSurvivor(),
            square:getX(),
            square:getY(),
            square:getZ()
        )
        operation.actor = actor
        actor:setNpc(true)
        actor:getModData().ProjectPeoplePersonId = personId
        -- Ordinary exposed method owns registration with native model/animation
        -- management. World-set membership alone does not create a visible body.
        actor:setSceneCulled(false)
        local enrolled = Rendering.add(actor, "actor:" .. personId)
        assert(enrolled.ok, "native_render_enrollment_failed:" .. tostring(enrolled.code))
        operation.state = "constructed"
    end)
    if not ok then
        operation.state = "unknown"
        return { ok = false, code = "creation_outcome_unknown", detail = tostring(err) }
    end
    return {
        ok = true,
        code = "candidate_requires_observation",
        actor = operation.actor,
        personId = personId,
        proven = false,
    }
end

function Actor.observeCandidate(personId)
    local operation = candidates[personId]
    if not operation or not operation.actor then
        return { ok = false, code = "candidate_not_observable" }
    end
    local actor = operation.actor
    local ok, result = pcall(function()
        return {
            ok = true,
            actor = actor,
            personId = personId,
            state = operation.state,
            inWorld = getCell():getObjectList():contains(actor),
            hasSquare = actor:getCurrentSquare() ~= nil,
            model = actor:isAddedToModelManager(),
            animationPresent = actor:hasAnimationPlayer(),
            activeModel = actor:hasActiveModel(),
            rendering = Rendering.observe(actor, 0),
            npc = actor:isNpc(),
            dead = actor:isDead(),
            localPlayer = actor:isLocalPlayer(),
            proven = false,
        }
    end)
    return ok and result or { ok = false, code = "native_observation_failed", detail = tostring(result) }
end

function Actor.removeCandidate(personId)
    local operation = candidates[personId]
    if not operation or not operation.actor then
        return { ok = false, code = "candidate_not_observable" }
    end
    local actor = operation.actor
    for slot = 0, 3 do
        if getSpecificPlayer(slot) == actor then
            return { ok = false, code = "controlled_person_cannot_be_removed" }
        end
    end
    if not getCell():isSafeToAdd() then
        return { ok = false, code = "unsafe_native_boundary" }
    end
    local ok, err = pcall(function()
        Rendering.remove(actor, "actor:" .. personId)
        actor:setSceneCulled(true)
        actor:removeFromWorld()
        actor:removeFromSquare()
        actor:setSquare(nil)
    end)
    if not ok then
        operation.state = "unknown"
        return { ok = false, code = "removal_outcome_unknown", detail = tostring(err) }
    end
    if
        getCell():getObjectList():contains(actor)
        or getCell():getAddList():contains(actor)
        or getCell():getRemoveList():contains(actor)
        or actor:getCurrentSquare()
        or actor:getSquare()
    then
        operation.state = "unknown"
        return { ok = false, code = "removal_not_observed" }
    end
    operation.state = "removed"
    -- Keep the tombstone: no silent second construction for this identity.
    return { ok = true, code = "candidate_removed" }
end

return Actor
