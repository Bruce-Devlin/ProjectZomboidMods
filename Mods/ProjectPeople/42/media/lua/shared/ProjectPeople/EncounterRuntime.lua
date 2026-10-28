-- One server-owned person, one native replicated body. Ordinary Workshop Lua.
-- No client-created replicas, position assignments or player-controller changes.
ProjectPeople = ProjectPeople or {}
if ProjectPeople.Encounter then
    return ProjectPeople.Encounter
end
local State = require "ProjectPeople/EncounterState"
local Visual = require "ProjectPeople/ZombieVisual"
local Encounter = { BUILD = State.BUILD, MODULE = "ProjectPeopleEncounter", enabled = false }
ProjectPeople.Encounter = Encounter
local state, body, visual, baseline
local ledger, ledgerOrder = {}, {}
local requestSeq, nextPublish, nextLocate, nextSample, nextAudit = 0, 0, 0, 0, 0
local appliedEpoch, appliedDamage, wasLocal = -1, -1, false
local witness =
    { created = 0, samples = 0, worldSamples = 0, maxBodies = 0, nativeFrames = 0, assignments = 0, pathDispatches = 0 }
local replyText = "Choose Start encounter"

local function now()
    return getTimestampMs()
end

local function audit(event, detail)
    print("[PPEncounter] " .. Encounter.BUILD .. " " .. event .. " " .. tostring(detail or ""))
end

local function snapshot()
    return state and State.copy(state) or nil
end

local function publish(p)
    if not state or state.nativeId < 0 then
        return
    end
    if p then
        sendServerCommand(p, Encounter.MODULE, "state", snapshot())
    else
        sendServerCommand(Encounter.MODULE, "state", snapshot())
    end
end

local function stop(a)
    a:getPathFindBehavior2():cancel()
    a:setPath2(nil)
    a:setVariable("bPathfind", false)
    a:setMoving(false)
    a:setDefaultState()
end

local function attach(a)
    if body and body ~= a then
        error "person_body_conflict"
    end
    body = a
    witness.createdAt = witness.createdAt or now()
    body:getModData().ProjectPeoplePersonId = state.personId
    body:setUseless(true)
    body:setNoTeeth(true)
    body:setTarget(nil)
    body:getDescriptor():setForename(state.name)
    body:getDescriptor():setSurname "Project People"
    if not isServer() then
        local p = getSpecificPlayer(0)
        if p and not baseline then
            baseline = {
                human = p,
                id = p:getOnlineID(),
                instance = IsoPlayer.getInstance(),
                camera = IsoCamera.getCameraCharacter(),
            }
        end
        visual = Visual.configure(body, state.skin)
        assert(visual.ok and visual.appearanceApplied, "human_presentation_failed:" .. tostring(visual.appearanceError))
    end
    audit("attach", state.personId .. " native=" .. body:getOnlineID())
end

local function locate()
    if not state or body or now() < nextLocate then
        return
    end
    nextLocate = now() + 200
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local a = list:get(i)
        if a:getOnlineID() == state.nativeId then
            attach(a)
            return
        end
    end
end

local function drive(a)
    if a ~= body or not state or Encounter.error then
        return
    end
    a:setUseless(true)
    a:setNoTeeth(true)
    a:setTarget(nil)
    -- Map one authoritative health scalar once per controlled event. Native
    -- combat, wounds and full physiology require their own integration proof.
    if appliedDamage ~= state.damageCount then
        a:setHealth(state.health / 100)
        appliedDamage = state.damageCount
    end
    local localOwner = a:isLocal()
    if localOwner then
        witness.nativeFrames = witness.nativeFrames + 1
        if appliedEpoch ~= state.epoch or not wasLocal then
            stop(a)
            if state.mode == "move" then
                a:pathToLocationF(state.goalX, state.goalY, state.goalZ)
                -- Direct WalkTowardState cancels useless zombies. Use the native
                -- PathFindState on the actual simulator, retaining AI suppression.
                a:setVariable("bPathfind", true)
                a:setMoving(false)
                witness.pathDispatches = witness.pathDispatches + 1
                audit("path", "epoch=" .. state.epoch .. " target=" .. state.goalX .. "," .. state.goalY)
            end
            appliedEpoch = state.epoch
        end
    end
    wasLocal = localOwner
end

local function sample()
    if not body then
        return
    end
    local count = 0
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local a = list:get(i)
        if a:getOnlineID() == state.nativeId or a:getModData().ProjectPeoplePersonId == state.personId then
            count = count + 1
        end
    end
    witness.samples = witness.samples + 1
    witness.bodyCount = count
    witness.maxBodies = math.max(witness.maxBodies, count)
    if count == 1 and getCell():getObjectList():contains(body) then
        witness.worldSamples = witness.worldSamples + 1
    elseif witness.worldSamples > 0 then
        witness.lostBody = true
    end
    if
        baseline
        and (
            getSpecificPlayer(0) ~= baseline.human
            or IsoPlayer.getInstance() ~= baseline.instance
            or IsoCamera.getCameraCharacter() ~= baseline.camera
            or baseline.human:getOnlineID() ~= baseline.id
        )
    then
        witness.controlChanged = true
    end
end

local function tick()
    if not state or Encounter.error then
        return
    end
    locate()
    if not body then
        return
    end
    if isServer() then
        state.nativeId = body:getOnlineID()
        -- Native server actor is the position witness, never client assertions.
        state.x, state.y, state.z = body:getX(), body:getY(), body:getZ()
        local owner = body:getOwnerPlayer()
        state.simulator = owner and owner:getOnlineID() or -1
        if state.mode == "move" then
            local arrived = (state.x - state.goalX) ^ 2 + (state.y - state.goalY) ^ 2 <= 0.25
                and math.floor(state.z) == state.goalZ
            if arrived or now() - (state.moveStarted or now()) > 30000 then
                state.mode = arrived and "wait" or "blocked"
                state.epoch = state.epoch + 1
                state.revision = state.revision + 1
                audit("movement", state.mode .. " actual=" .. state.x .. "," .. state.y)
                publish()
            end
        end
        if now() >= nextPublish then
            nextPublish = now() + 250
            state.revision = state.revision + 1
            publish()
        end
    end
    if now() >= nextSample then
        nextSample = now() + 200
        sample()
    end
    if now() >= nextAudit then
        nextAudit = now() + 2000
        audit(
            "physical",
            state.personId
                .. " native="
                .. body:getOnlineID()
                .. " mode="
                .. state.mode
                .. " xyz="
                .. body:getX()
                .. ","
                .. body:getY()
                .. ","
                .. body:getZ()
                .. " health="
                .. body:getHealth() * 100
                .. " authorityHealth="
                .. state.health
                .. " bodies="
                .. tostring(witness.bodyCount)
                .. " retainedMs="
                .. (now() - witness.createdAt)
                .. " controlChanged="
                .. tostring(witness.controlChanged == true)
                .. " local="
                .. tostring(body:isLocal())
                .. " nativeState="
                .. tostring(body:getCurrentStateName())
        )
    end
end

local function nearby(p)
    return p
        and not p:isDead()
        and state
        and math.abs(p:getZ() - state.z) < 0.1
        and (p:getX() - state.x) ^ 2 + (p:getY() - state.y) ^ 2 <= 400
end

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < 1000000
end

local function free(a)
    if not finite(a.x) or not finite(a.y) or not finite(a.z) then
        return nil
    end
    local sq = getCell():getGridSquare(a.x, a.y, a.z)
    return sq and sq:TreatAsSolidFloor() and sq:isFree(false) and sq or nil
end

local function serverCommand(module, kind, p, a)
    if module ~= Encounter.MODULE or not p or type(a) ~= "table" then
        return
    end
    if not require("ProjectPeople/DebugAccess").allowed(p) then
        return
    end
    if kind == "sync" then
        publish(p)
        return
    end
    if kind ~= "start" and kind ~= "move" and kind ~= "wait" and kind ~= "damage" then
        return
    end
    if type(a.requestId) ~= "string" or #a.requestId > 96 or p:isDead() then
        return
    end
    local key = tostring(p:getOnlineID()) .. ":" .. a.requestId
    local saved = ledger[key]
    if saved then
        sendServerCommand(p, Encounter.MODULE, "reply", saved)
        publish(p)
        return
    end
    local ok, code = false, "encounter_not_started"
    if Encounter.error then
        code = "runtime_fault"
    elseif kind == "start" then
        if ProjectPeople.Survivors and ProjectPeople.Survivors.active then
            code = "household_already_active"
        elseif state then
            ok, code = true, "existing_encounter"
        elseif Encounter.creationStarted then
            code = "construction_outcome_unknown"
        elseif free(a) and a.z == math.floor(p:getZ()) and (a.x - p:getX()) ^ 2 + (a.y - p:getY()) ^ 2 <= 36 then
            Encounter.creationStarted = true
            local created = createZombie(math.floor(a.x), math.floor(a.y), a.z, nil, 0, IsoDirections.S)
            assert(created, "native_factory_returned_no_body")
            body = created
            witness.created = 1
            state = State.new(p:getOnlineID(), body:getX(), body:getY(), body:getZ())
            state.nativeId = body:getOnlineID()
            state.skin = body:getDescriptor():getHumanVisual():getSkinTexture()
            attach(body)
            Encounter.enabled = true
            ok, code = true, "encounter_started"
        else
            code = "nearby_free_floor_required"
        end
    elseif state and a.personId == state.personId and nearby(p) then
        if kind ~= "move" or free(a) then
            ok, code = State.command(state, kind, a)
            if ok and kind == "move" then
                state.moveStarted = now()
            end
            if ok and kind == "damage" then
                body:setHealth(state.health / 100)
            end
        else
            code = "free_loaded_destination_required"
        end
    elseif state then
        code = "nearby_matching_person_required"
    end
    saved = { requestId = a.requestId, ok = ok, code = code }
    ledger[key] = saved
    ledgerOrder[#ledgerOrder + 1] = key
    if #ledgerOrder > 256 then
        ledger[table.remove(ledgerOrder, 1)] = nil
    end
    audit("command", kind .. " caller=" .. p:getOnlineID() .. " " .. code)
    sendServerCommand(p, Encounter.MODULE, "reply", saved)
    if ok then
        publish()
    end
end

function Encounter.request(kind, fields)
    if Encounter.error then
        return false, "runtime_fault"
    end
    if kind == "start" and ProjectPeople.Survivors and ProjectPeople.Survivors.active then
        return false, "household_already_active"
    end
    if not isClient() then
        return false, "dedicated_client_required"
    end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then
        return false, "living_player_required"
    end
    requestSeq = requestSeq + 1
    local a = fields and State.copy(fields) or {}
    a.requestId = tostring(p:getOnlineID()) .. "-" .. string.format("%.0f", now()) .. "-" .. requestSeq
    a.personId = state and state.personId or State.ID
    sendClientCommand(p, Encounter.MODULE, kind, a)
    replyText = "Pending " .. kind
    return true, a.requestId
end

function Encounter.startNearby()
    local p = getSpecificPlayer(0)
    if not p then
        return false, "player_required"
    end
    if Encounter.openDevelopment then
        Encounter.openDevelopment()
    end
    for _, d in ipairs({ { 2, 0 }, { 0, 2 }, { -2, 0 }, { 0, -2 }, { 1, 0 }, { 0, 1 } }) do
        local a = { x = math.floor(p:getX()) + d[1], y = math.floor(p:getY()) + d[2], z = math.floor(p:getZ()) }
        local sq = free(a)
        if sq and sq:getRoom() == p:getCurrentSquare():getRoom() and not sq:isBlockedTo(p:getCurrentSquare()) then
            return Encounter.request("start", a)
        end
    end
    return false, "no_nearby_free_floor"
end

function Encounter.moveNearby()
    if not body then
        return false, "body_not_ready"
    end
    local origin = body:getCurrentSquare()
    for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
        local previous = origin
        local destination
        for distance = 1, 3 do
            local a = { x = origin:getX() + d[1] * distance, y = origin:getY() + d[2] * distance, z = origin:getZ() }
            local sq = free(a)
            if not sq or sq:getRoom() ~= origin:getRoom() or previous:isBlockedTo(sq) then
                break
            end
            previous = sq
            if distance >= 2 then
                destination = a
            end
        end
        if destination then
            destination.x = destination.x + 0.5
            destination.y = destination.y + 0.5
            return Encounter.request("move", destination)
        end
    end
    return false, "no_clear_two_tile_destination"
end

function Encounter.observe()
    local o = { build = Encounter.BUILD, state = snapshot(), reply = replyText, error = Encounter.error }
    if body then
        local owner = body:getOwnerPlayer()
        o.body = {
            x = body:getX(),
            y = body:getY(),
            z = body:getZ(),
            health = body:getHealth() * 100,
            personId = body:getModData().ProjectPeoplePersonId,
            onlineId = body:getOnlineID(),
            inWorld = getCell():getObjectList():contains(body),
            dead = body:isDead(),
            hasSquare = body:getCurrentSquare() ~= nil,
            readyModels = not isServer() and body:getReadyModelData():size() or 0,
            retainedMs = now() - (witness.createdAt or now()),
            simulator = owner and owner:getOnlineID() or -1,
            localSimulation = body:isLocal(),
            target = body:getTarget() ~= nil,
            useless = body:isUseless(),
            noTeeth = body:isNoTeeth(),
            animation = not isServer() and body:dbgGetAnimTrackName(0, 0) or "server",
            nativeState = body:getCurrentStateName(),
            pathMoving = body:getPathFindBehavior2():shouldBeMoving(),
            moving = body:isMoving(),
        }
        o.witness = State.copy(witness)
        o.visual = visual and { skin = visual.skinTexture, applied = visual.appearanceApplied } or nil
    end
    return o
end

local function guarded(fn, ...)
    if Encounter.error then
        return
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        Encounter.error = tostring(err)
        audit("FAULT", Encounter.error)
    end
end
if isServer() then
    Events.OnClientCommand.Add(function(...)
        guarded(serverCommand, ...)
    end)
elseif isClient() then
    Events.OnServerCommand.Add(function(module, command, a)
        if module ~= Encounter.MODULE or type(a) ~= "table" then
            return
        end
        if command == "state" and a.personId == State.ID and a.build == Encounter.BUILD then
            if not state or a.revision >= state.revision then
                state = State.copy(a)
                Encounter.enabled = true
            end
        elseif command == "reply" then
            replyText = (a.ok and "Accepted: " or "Refused: ") .. tostring(a.code)
        end
    end)
    Events.OnGameStart.Add(function()
        Encounter.request "sync"
    end)
end
Events.OnZombieUpdate.Add(function(a)
    guarded(drive, a)
end)
Events.OnTick.Add(function()
    guarded(tick)
end)
return Encounter
