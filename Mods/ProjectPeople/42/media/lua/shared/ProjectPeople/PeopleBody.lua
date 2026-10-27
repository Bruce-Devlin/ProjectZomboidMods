-- Native body adapter. The coordinator owns records and events; this module
-- never creates client replicas or writes positions to simulate locomotion.
local Visual = require "ProjectPeople/ZombieVisual"
local Clothing = require "ProjectPeople/PeopleClothing"
local Equipment = require "ProjectPeople/PeopleEquipment"
local Locomotion = require "ProjectPeople/Pathing/Locomotion"
local Doors = require "ProjectPeople/PeopleDoors"
local Fences = require "ProjectPeople/PeopleFences"
local Body = { VERSION = 1 }
-- Native multiplayer zombie IDs are signed; only -1 means unassigned/SP.

function Body.hasNetworkId(id)
    return type(id) == "number" and id ~= -1
end

function Body.stop(actor)
    Fences.release(actor)
    actor:getPathFindBehavior2():cancel()
    actor:setPath2(nil)
    actor:setVariable("bPathfind", false)
    actor:setMoving(false)
    actor:setDefaultState()
end

function Body.attach(actor, record)
    assert(actor and actor:getOnlineID() == record.nativeId, "native_body_identity_mismatch")
    local existing = actor:getModData().ProjectPeoplePersonId
    assert(not existing or existing == record.personId, "native_body_already_bound")
    actor:getModData().ProjectPeoplePersonId = record.personId
    if record.worldId then
        actor:getModData().ProjectPeopleWorldId = record.worldId
    end
    -- Native ReanimatedPlayers saves the actual body, original inventory and
    -- ModData to reanimated.bin and restores it when its chunk loads.
    actor:setReanimatedPlayer(true)
    if not isClient or not isClient() then
        Clothing.initialise(actor)
        record.clothing = Clothing.snapshot(actor)
    end
    actor:setUseless(true)
    actor:setNoTeeth(true)
    actor:setTarget(nil)
    actor:getDescriptor():setForename(record.name)
    actor:getDescriptor():setSurname ""
    local visual
    if not isServer() then
        visual = Visual.configure(actor, record.skin)
        assert(visual.appearanceApplied, visual.appearanceError or "human_appearance_failed")
    end
    return { actor = actor, personId = record.personId, epoch = -1, wasLocal = false, visual = visual }
end

function Body.recover(person, worldId)
    local found
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local a = list:get(i)
        local md = a:getModData()
        if md.ProjectPeoplePersonId == person.id and md.ProjectPeopleWorldId == worldId then
            assert(not found, "duplicate_persistent_person_body")
            found = a
        end
    end
    if not found or found:isDead() then
        return nil
    end
    -- IsoGameCharacter.save omits zombie BodyDamage/XP and aggregate health.
    -- Keep this representation's actual native health in that same body's
    -- native ModData payload, avoiding a cross-file health rewind or free heal.
    local savedHealth = found:getModData().ProjectPeopleNativeHealth
    if type(savedHealth) == "number" and savedHealth > 0 and savedHealth <= 1 then
        found:setHealth(savedHealth)
    end
    local saved = person.bodyRecord or {}
    local record = {
        personId = person.id,
        name = person.name,
        worldId = worldId,
        nativeId = found:getOnlineID(),
        skin = saved.skin or found:getDescriptor():getHumanVisual():getSkinTexture(),
        x = found:getX(),
        y = found:getY(),
        z = found:getZ(),
        health = found:getHealth() * 100,
        epoch = 0,
        mode = "wait",
    }
    return Body.attach(found, record), record
end

function Body.create(person, location)
    assert(not isClient(), "authority_only")
    local actor = createZombie(math.floor(location.x), math.floor(location.y), location.z, nil, 0, IsoDirections.S)
    assert(actor, "native_factory_returned_no_body")
    actor:setHealth(1)
    local record = {
        personId = person.id,
        name = person.name,
        nativeId = actor:getOnlineID(),
        skin = actor:getDescriptor():getHumanVisual():getSkinTexture(),
        x = actor:getX(),
        y = actor:getY(),
        z = actor:getZ(),
        epoch = 0,
        mode = "wait",
    }
    return Body.attach(actor, record), record
end

function Body.find(record)
    if not Body.hasNetworkId(record.nativeId) then
        return nil
    end
    local found
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local actor = list:get(i)
        if actor:getOnlineID() == record.nativeId then
            assert(not found, "duplicate_native_body")
            found = actor
        end
    end
    return found and Body.attach(found, record) or nil
end

function Body.matches(binding, record)
    return binding
        and binding.actor:getOnlineID() == record.nativeId
        and binding.actor:getModData().ProjectPeoplePersonId == record.personId
        and getCell():getObjectList():contains(binding.actor)
end

function Body.update(binding, record)
    local actor = binding.actor
    assert(
        actor:getOnlineID() == record.nativeId and actor:getModData().ProjectPeoplePersonId == record.personId,
        "native_body_identity_changed"
    )
    Clothing.present(actor, record.clothing, binding)
    Equipment.present(actor, record, binding)
    if isClient and not isClient() then
        actor:getModData().ProjectPeopleNativeHealth = actor:getHealth()
    end
    if not isServer() and record.health and binding.health ~= record.health then
        actor:setHealth(record.health / 100)
        binding.health = record.health
    end
    actor:setUseless(true)
    actor:setNoTeeth(true)
    actor:setTarget(nil)
    local localOwner = actor:isLocal()
    Locomotion.apply(actor, record)
    actor:setVariable("ProjectPeopleSwing", record.attacking == true)
    actor:setVariable("ProjectPeopleSwingWalkBlend", 0.4)
    actor:setVariable("ProjectPeopleSwingWalkBlendY", 0.1)
    if not record.attacking then
        actor:setVariable("ProjectPeopleMovingSwingActive", false)
        actor:setVariable("ProjectPeopleStandingSwingActive", false)
    end
    actor:setVariable("ProjectPeopleRetreat", record.retreating == true)
    actor:setVariable("isAnimatingBackwards", record.retreating == true)
    local traversing = Fences.update(binding, record)
    if not traversing and record.attacking and record.attackX and record.attackY then
        actor:faceLocationF(record.attackX, record.attackY)
    elseif not traversing and localOwner and record.mode == "wait" and record.faceX and record.faceY then
        actor:faceLocationF(record.faceX, record.faceY)
    end
    -- Complete the native crossing before applying a new path or wait. Calling
    -- stop mid-vault aborts the state's collision/path cleanup.
    if traversing then
        return
    end
    Doors.update(binding, record)
    if localOwner and (binding.epoch ~= record.epoch or not binding.wasLocal) then
        Body.stop(actor)
        binding.epoch = record.epoch
        binding.pendingPath = record.mode == "move" and record.epoch or nil
    elseif localOwner and binding.pendingPath == record.epoch and record.mode == "move" then
        -- PathFindState.exit cancels native requests. Let the stopped state
        -- leave before issuing a subsequent route, otherwise its exit can
        -- cancel the new request. A newer wait/epoch fences this pending path.
        binding.pendingPath = nil
        actor:pathToLocationF(record.goalX, record.goalY, record.goalZ)
        -- WalkTowardState rejects useless zombies. PathFindState keeps native
        -- collision/locomotion while ordinary zombie aggression stays disabled.
        actor:setVariable("bPathfind", true)
        actor:setMoving(false)
    end
    binding.wasLocal = localOwner
end

function Body.observe(binding)
    local a = binding.actor
    return {
        x = a:getX(),
        y = a:getY(),
        z = a:getZ(),
        health = a:getHealth() * 100,
        dead = a:isDead(),
        nativeId = a:getOnlineID(),
        personId = a:getModData().ProjectPeoplePersonId,
        inWorld = getCell():getObjectList():contains(a),
        hasSquare = a:getCurrentSquare() ~= nil,
        localSimulation = a:isLocal(),
        nativeState = a:getCurrentStateName(),
    }
end

function Body.clothing(binding)
    return Clothing.snapshot(binding.actor)
end

function Body.checkpoint(record, previous)
    -- Native bodies own worn items and inventory. Recovery needs identity,
    -- appearance and observed position/health, not transient attack/path flags
    -- or a second copy of every clothing mark in each command receipt.
    local saved, changed = {}, not previous
    for _, key in ipairs({ "personId", "name", "worldId", "nativeId", "skin", "x", "y", "z", "health" }) do
        saved[key] = record[key]
        if previous and previous[key] ~= record[key] then
            changed = true
        end
    end
    return changed and saved or nil
end

function Body.order(record, goal, now, actor)
    record.epoch = record.epoch + 1
    record.started = now
    record.mode = goal and "move" or "wait"
    if goal then
        record.goalX, record.goalY, record.goalZ = goal.x, goal.y, goal.z
    end
    record.fenceHint = Fences.hint(actor, goal)
end
return Body
