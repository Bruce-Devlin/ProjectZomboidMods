-- Coordinates survivors, players and native bodies. Social decisions go through the authority.
ProjectPeople = ProjectPeople or {}
if ProjectPeople.Survivors then
    return ProjectPeople.Survivors
end
local Service = require "ProjectPeople/SurvivorService"
local InteractionDanger = require "ProjectPeople/InteractionDanger"
local Body = require "ProjectPeople/PeopleBody"
local Core = require "ProjectPeople/Core"
local Combat = require "ProjectPeople/PeopleCombat"
local FriendlyFire = require "ProjectPeople/FriendlyFire"
local Alarm = require "ProjectPeople/PeopleAlarm"
local Party = require "ProjectPeople/Party"
local ZombieThreat = require "ProjectPeople/ZombieThreat"
local Work = require "ProjectPeople/HouseholdWork"
local homeWork = require("ProjectPeople/HomeRuntime").new()
local BehaviourRuntime = require "ProjectPeople/Behaviour/Runtime"
local PairConversation = require "ProjectPeople/Behaviour/PairConversation"
local PlayerAlerts = require "ProjectPeople/Behaviour/PlayerAlerts"
local DialogueClock = require "ProjectPeople/Behaviour/DialogueClock"
local playerAlerts = PlayerAlerts.new(function(limit)
    return ZombRand(limit)
end)
local CombatSpace = require "ProjectPeople/Pathing/CombatSpace"
local Movement = require "ProjectPeople/Pathing/Movement"
local Scavenging = require "ProjectPeople/Pathing/Scavenging"
local companionMovement = Movement.new()
local locomotion = require("ProjectPeople/Pathing/Locomotion").new()
local behaviour = BehaviourRuntime.new()
local conversations
local population = require("ProjectPeople/Population/Runtime").new()
local SaveStore = require "ProjectPeople/SaveStore"
local SupplyJobs = require "ProjectPeople/SupplyJobs"
local SuccessionService = require "ProjectPeople/SuccessionService"
local EquipmentService = require "ProjectPeople/EquipmentService"
local Equipment = require "ProjectPeople/PeopleEquipment"
local DebugAccess = require "ProjectPeople/DebugAccess"
local DebugService = require "ProjectPeople/DebugService"
local TrustRewards = require "ProjectPeople/Behaviour/Trust"
local TrustSpace = require "ProjectPeople/Pathing/CombatSpace"
local Runtime = { MODULE = "ProjectPeopleSurvivors", BUILD = "people-20261023-locomotion-p1", active = false }
ProjectPeople.Survivors = Runtime
local service, metadata, latest
local bodies, records, pendingBirths = {}, {}, {}
local nextTick, sequence = 0, 0
local combat, hitSequence
local companionCombat = require("ProjectPeople/Behaviour/CompanionCombat").new()
local combatPeople = {}
local threats, threatOrders, threatReceivedAt
local observedHelp = {}
local readyClients, nextReady = {}, 0
local initialSpawnAt
local nextCheckpoint = 0
local jobs
local succession
local equipment
local health
local debugTools
local debugHealthUpdates = {}
local alarms = Alarm.new()
local alarmWorld

local function now()
    return getTimestampMs()
end

local function pursued(z, id)
    local order = threats and threats:inspect(z)
    return order and order.personId == id or false
end

local function authority()
    return not isClient()
end

local function players()
    if isServer() then
        return getOnlinePlayers()
    end
    local localPlayers = {}
    for i = 0, 3 do
        local p = getSpecificPlayer(i)
        if p then
            localPlayers[#localPlayers + 1] = p
        end
    end
    return {
        size = function()
            return #localPlayers
        end,
        get = function(_, i)
            return localPlayers[i + 1]
        end,
    }
end

local function identity(player)
    if not player then
        return nil
    end
    local md = player:getModData()
    if not md.ProjectPeopleCharacterId and player:isDead() then
        return nil
    end
    if not md.ProjectPeopleCharacterId then
        md.ProjectPeopleCharacterId = "person:"
            .. metadata.worldId
            .. ":"
            .. tostring(now())
            .. ":"
            .. ZombRand(1000000)
    end
    return {
        validated = true,
        alive = not player:isDead(),
        personId = md.ProjectPeopleCharacterId,
        controllerId = "account:" .. player:getUsername(),
        actorId = "player-body:" .. md.ProjectPeopleCharacterId,
        name = player:getDescriptor():getForename() .. " " .. player:getDescriptor():getSurname(),
        character = {},
    }
end

local function distance(a, b)
    if not a or not b or math.abs(a:getZ() - b:getZ()) > 0.1 then
        return math.huge
    end
    return (a:getX() - b:getX()) ^ 2 + (a:getY() - b:getY()) ^ 2
end

local function nearby(player)
    local result = {}
    for id, b in pairs(bodies) do
        if
            not b.actor:isDead()
            and distance(player, b.actor) <= 25
            and player:getCurrentSquare()
            and b.actor:getCurrentSquare()
            and not player:getCurrentSquare():isBlockedTo(b.actor:getCurrentSquare())
        then
            result[#result + 1] = id
        end
    end
    table.sort(result)
    return result
end

local function nativeBirth(id)
    local b = bodies[id]
    if not b then
        return nil
    end
    local observed = Body.observe(b)
    local count = 0
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        if list:get(i):getModData().ProjectPeoplePersonId == id then
            count = count + 1
        end
    end
    return {
        evidence = {
            kind = "native_birth",
            validated = true,
            personId = id,
            actorId = "survivor-body:" .. id,
            inWorld = observed.inWorld,
            uniqueBody = count == 1,
            character = { representation = "human-adapted-native-zombie", nativeHealth = observed.health },
            location = { x = observed.x, y = observed.y, z = observed.z },
        },
    }
end

local function open()
    if service then
        return true
    end
    metadata = ModData.getOrCreate "ProjectPeopleWorld_v1"
    if not metadata.worldId then
        metadata.worldId = "world_" .. string.format("%.0f", now()) .. "_" .. ZombRand(1000000)
        metadata.timelineId = metadata.worldId .. "_initial"
        metadata.storageVersion = 2
    end
    assert(metadata.storageVersion == 2, "legacy_save_requires_explicit_migration_use_new_development_world")
    local problem
    local function danger(id, person)
        local binding = bodies[id]
        return binding
                and InteractionDanger.check(
                    binding.actor,
                    records[id],
                    person,
                    getCell():getZombieList(),
                    players(),
                    identity,
                    function(target)
                        return combat and combat:isEnemy(id, target) or false
                    end,
                    function(z)
                        return pursued(z, id)
                    end
                )
            or false
    end
    debugTools = DebugService.new({
        bodies = bodies,
        records = records,
        players = players,
        identity = identity,
        danger = danger,
        clock = function()
            return getGameTime():getWorldAgeHours()
        end,
        worldId = function()
            return metadata.worldId
        end,
        options = function()
            return SandboxVars and SandboxVars.ProjectPeople
        end,
        elapsedDays = function()
            return getGameTime():getWorldAgeHours() / 24 + (getSandboxOptions():getTimeSinceApo() - 1) * 30
        end,
        healthBusy = function(id)
            return health and health:busy(id)
        end,
        publishHealth = function(update)
            if isServer() then
                sendServerCommand(Runtime.MODULE, "debugHealth", update)
            end
        end,
    })
    service, problem = Service.open({
        binding = function()
            return {
                authority = true,
                validated = true,
                worldId = metadata.worldId,
                timelineId = metadata.timelineId,
                journalName = metadata.worldId,
            }
        end,
        clock = function()
            return getGameTime():getWorldAgeHours()
        end,
        authenticate = identity,
        followerLimit = function()
            return SandboxVars and SandboxVars.ProjectPeople and SandboxVars.ProjectPeople.ActiveFollowerLimit
        end,
        canDebug = DebugAccess.allowed,
        debugObserve = function(...)
            return debugTools:observe(...)
        end,
        debug = function(caller, request)
            return debugTools:request(service, caller, request)
        end,
        nearby = nearby,
        interactionDanger = danger,
        io = SaveStore.io(metadata),
        job = function(caller, kind, fields)
            return jobs and jobs:request(caller, kind, fields) or { ok = false, code = "jobs_not_ready" }
        end,
        equipment = function(caller, kind, fields)
            return equipment:request(caller, kind, fields)
        end,
        health = function(caller, kind, fields)
            return health:request(caller, kind, fields)
        end,
        healthSummary = function(id)
            local b, r = bodies[id], records[id]
            return b and r and Body.matches(b, r) and b.actor:getHealth() * 100 or nil
        end,
        succession = function(caller, id)
            return succession:reserve(caller, id)
        end,
        successors = function(caller)
            return succession:view(caller)
        end,
        available = function(id)
            return bodies[id] and records[id] and Body.matches(bodies[id], records[id])
        end,
        groupAvailable = function(caller, id)
            local b = bodies[id]
            return b and not b.actor:isDead() and distance(caller, b.actor) <= 12 ^ 2,
                "Come within twelve tiles of each other on the same floor, then ask again."
        end,
        help = function(player, auth)
            local world = auth:snapshot()
            local mara = world.people.mara
            local who = identity(player)
            if not who or not bodies.mara or distance(player, bodies.mara.actor) > 25 then
                return { ok = false, code = "conversation_unconfirmed" }
            end
            local door = Work.findDoor(mara.home, player, 2)
            if not door then
                return { ok = false, code = "no_open_household_door_nearby" }
            end
            local sq = door:getSquare()
            local eventId = "secure:"
                .. sq:getX()
                .. ":"
                .. sq:getY()
                .. ":"
                .. sq:getZ()
                .. ":"
                .. tostring(door:getNorth())
            local closed, reason = Work.close(player, door)
            if not closed then
                return { ok = false, code = reason }
            end
            observedHelp[eventId] = who.personId
            return auth:recordFamilyHelp(player, eventId)
        end,
        recover = SaveStore.recover,
        observe = function(kind, data, who, world, caller)
            if kind == "community.home.set" then
                if
                    not Party.home(data)
                    or math.abs(caller:getZ() - data.z) > 0.2
                    or (caller:getX() - data.x) ^ 2 + (caller:getY() - data.y) ^ 2 > 20 ^ 2
                then
                    return nil
                end
                local sq = getCell():getGridSquare(math.floor(data.x), math.floor(data.y), data.z)
                local origin = caller:getCurrentSquare()
                if
                    not sq
                    or not origin
                    or not sq:TreatAsSolidFloor()
                    or not sq:isFree(false)
                    or sq:isWaterSquare()
                    or sq:isVehicleIntersecting()
                    or not SafeHouse
                    or SafeHouse.isSafeHouse(sq, caller:getUsername(), true)
                    or tostring(
                            LosUtil.lineClear(
                                getCell(),
                                origin:getX(),
                                origin:getY(),
                                origin:getZ(),
                                sq:getX(),
                                sq:getY(),
                                sq:getZ(),
                                false
                            )
                        )
                        ~= "Clear"
                then
                    return nil
                end
                return {
                    evidence = {
                        kind = "community_home",
                        validated = true,
                        actorId = who.personId,
                        x = data.x,
                        y = data.y,
                        z = data.z,
                        safe = true,
                    },
                }
            end
            if kind == "person.bind_initial" then
                return nativeBirth(data.personId)
            end
            if kind == "player.death" then
                return {
                    evidence = {
                        kind = "native_player_death",
                        validated = true,
                        personId = who.personId,
                        isDead = caller:isDead() and caller:getHealth() <= 0,
                    },
                }
            end
            if kind == "social.event" and observedHelp[data.eventId] == who.personId then
                return {
                    evidence = {
                        kind = "social_event",
                        validated = true,
                        eventId = data.eventId,
                        personId = data.personId,
                        actorId = who.personId,
                        relatedId = data.relatedId,
                    },
                }
            end
            if kind == "cooperation.request" or kind == "behaviour.interact" or kind == "friendly_fire.set" then
                local known = false
                for _, id in ipairs(nearby(caller)) do
                    if id == data.personId then
                        known = true
                    end
                end
                return {
                    evidence = {
                        kind = "conversation",
                        validated = true,
                        personId = data.personId,
                        actorId = who.personId,
                        inReach = known,
                        known = known,
                    },
                }
            end
        end,
    })
    if not service then
        error(problem and problem.code or "authority_unavailable")
    end
    equipment = EquipmentService.new({
        authority = service.authority,
        identity = identity,
        actor = function(id)
            if bodies[id] and records[id] and Body.matches(bodies[id], records[id]) then
                return bodies[id].actor, records[id]
            end
        end,
    })
    health = require("ProjectPeople/HealthService").new({
        authority = service.authority,
        identity = identity,
        now = now,
        danger = danger,
        actor = function(id)
            if bodies[id] and records[id] and Body.matches(bodies[id], records[id]) then
                return bodies[id].actor, records[id]
            end
        end,
    })
    succession = SuccessionService.new({
        authority = service.authority,
        identity = identity,
        inspect = function(person)
            local b = bodies[person.id]
            if not b or not Body.matches(b, records[person.id]) then
                return { ready = false, code = "native_body_not_loaded" }
            end
            -- The current zombie body has native inventory/visual persistence,
            -- but no proven faithful player reconstruction for its entire human
            -- medical/XP state. Do not disguise an ordinary respawn as succession.
            return { ready = false, code = "faithful_native_reconstruction_unproven" }
        end,
    })
    jobs = SupplyJobs.new({
        authority = service.authority,
        metadata = metadata,
        identity = identity,
        actor = function(id)
            local b = bodies[id]
            if b and records[id] and Body.matches(b, records[id]) then
                return b.actor
            end
            local online = players()
            for i = 0, online:size() - 1 do
                local p = online:get(i)
                if p:getModData().ProjectPeopleCharacterId == id then
                    return p
                end
            end
        end,
        order = function(id, goal)
            local r = records[id]
            if not r then
                return
            end
            if
                goal and (r.mode ~= "move" or r.goalX ~= goal.x or r.goalY ~= goal.y or r.goalZ ~= goal.z)
                or not goal and r.mode == "move"
            then
                Body.order(r, goal, now(), bodies[id] and bodies[id].actor)
            end
        end,
    })
    return true
end

local function free(x, y, z, room)
    local sq = getCell():getGridSquare(x, y, z)
    return sq and sq:TreatAsSolidFloor() and sq:isFree(false) and (not room or sq:getRoom() == room) and sq
end

local function seed(player)
    if Runtime.active or Runtime.error then
        return
    end
    local encounter = ProjectPeople.Encounter
    if encounter and encounter.enabled then
        return
    end
    if not open() then
        return
    end
    local saved = service.authority:snapshot()
    if saved.people.mara then
        local required, loaded = 0, 0
        for id, p in pairs(saved.people) do
            if p.controller.kind == "ai" and p.life ~= "dead" then
                required = required + 1
                bodies[id], records[id] = Body.recover(p, metadata.worldId)
                if bodies[id] then
                    loaded = loaded + 1
                end
            end
        end
        Runtime.active = true
        print(
            "[ProjectPeople] "
                .. Runtime.BUILD
                .. " recovered records "
                .. metadata.worldId
                .. " revision="
                .. saved.revision
                .. " nativeBodies="
                .. loaded
                .. "/"
                .. required
        )
        return
    end
    -- The authored household remains an explicit disposable development fixture.
    -- Ordinary fresh worlds start with the regional population director.
    if not ProjectPeople.DevelopmentHousehold then
        if not isServer() then
            initialSpawnAt = now() + 5000
        end
        Runtime.active = true
        print("[ProjectPeople] " .. Runtime.BUILD .. " regional population active " .. metadata.worldId)
        return
    end
    local origin = player:getCurrentSquare()
    local room = origin and origin:getRoom()
    if not room then
        return
    end
    local spots = {}
    for radius = 2, 5 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local x, y, z = origin:getX() + dx, origin:getY() + dy, origin:getZ()
                    local sq = free(x, y, z, room)
                    if sq and not origin:isBlockedTo(sq) then
                        spots[#spots + 1] = { x = x, y = y, z = z }
                    end
                end
            end
        end
        if #spots >= 3 then
            break
        end
    end
    if #spots < 3 or not open() then
        return
    end
    local seeded = service:seed({ x = origin:getX() + 0.5, y = origin:getY() + 0.5, z = origin:getZ() })
    assert(seeded.ok, seeded.code)
    local world = service.authority:snapshot()
    print(
        "[ProjectPeople] birth boundary safe="
            .. tostring(getCell():isSafeToAdd())
            .. " player="
            .. player:getUsername()
            .. " at="
            .. player:getX()
            .. ","
            .. player:getY()
    )
    for i, id in ipairs({ "mara", "owen", "ellis" }) do
        assert(not pendingBirths[id] and not bodies[id], "native_birth_outcome_unknown")
        pendingBirths[id] = true
        bodies[id], records[id] = Body.create(world.people[id], spots[i])
        records[id].worldId = metadata.worldId
        bodies[id].actor:getModData().ProjectPeopleWorldId = metadata.worldId
        local bound = service:bindInitial(id)
        assert(bound.ok, bound.code)
        print(
            "[ProjectPeople] born "
                .. id
                .. " native="
                .. records[id].nativeId
                .. " at="
                .. records[id].x
                .. ","
                .. records[id].y
        )
        pendingBirths[id] = nil
    end
    Runtime.active = true
    print("[ProjectPeople] " .. Runtime.BUILD .. " household entered the world")
end

local function publish(player)
    if not service then
        return
    end
    if not isServer() and player ~= getSpecificPlayer(0) then
        return
    end
    local payload = service:view(player)
    payload.build = Runtime.BUILD
    payload.bodies = {}
    payload.threats = {}
    payload.debug = debugTools:view(service.authority, player, population.diagnostics)
    if payload.world then
        local fireWorld = service.authority:snapshot()
        alarmWorld = fireWorld
        for id, person in pairs(payload.world.people) do
            local r = records[id]
            if r then
                person.activity = r.activity
                person.missing = r.missing
                person.life = r.dead and "dead" or person.life
                if
                    person.commanderId == payload.personId
                    and person.partyId
                    and bodies[id]
                    and Body.matches(bodies[id], r)
                    and not r.missing
                then
                    person.health = r.health
                    person.location = { x = r.x, y = r.y, z = r.z }
                    person.partyDanger = r.combatActive or r.fleeing or r.cautious or false
                end
            elseif person.controller and person.controller.kind == "ai" then
                person.missing = true
                person.activity = "Currently unavailable"
            end
        end
        for id, record in pairs(records) do
            -- Physical metadata is bounded to nearby native replication areas.
            local b = bodies[id]
            if b and Body.hasNetworkId(record.nativeId) and distance(player, b.actor) <= 6400 then
                payload.bodies[id] = Core.snapshot(record)
                payload.bodies[id].playerAlert = playerAlerts:line(id, payload.personId)
                payload.bodies[id].friendlyFirePlayers = FriendlyFire.players(fireWorld, id, players(), identity)
                payload.bodies[id].alliedPeople = {}
                for other in pairs(fireWorld.people) do
                    if Party.allied(fireWorld, id, other) then
                        payload.bodies[id].alliedPeople[other] = true
                    end
                end
            end
        end
        for _, order in ipairs(threatOrders or {}) do
            if payload.bodies[order.personId] then
                payload.threats[#payload.threats + 1] = order
            end
        end
    end
    if isServer() then
        sendServerCommand(player, Runtime.MODULE, "view", payload)
    else
        latest = payload
        Runtime.viewAt, Runtime.dialogueViewAt = now(), DialogueClock.now()
    end
end

local function orderFor(record, goal)
    local b = bodies[record.personId]
    Body.order(record, goal, now(), b and b.actor)
end

local function nativeHit(actor, target, weapon, damage, kind, action, knockdown)
    Combat.applyDamage(actor, target, weapon, damage, kind, action, knockdown)
    if kind ~= "player" and target:getTarget() == actor then
        target:setTarget(nil)
    end
    if isServer() then
        if kind == "player" then
            sendDamage(target)
        else
            hitSequence = (hitSequence or 0) + 1
            sendServerCommand(Runtime.MODULE, "combatDamage", {
                sequence = hitSequence,
                nativeId = target:getOnlineID(),
                health = target:getHealth(),
                personId = target:getModData().ProjectPeoplePersonId,
            })
        end
    end
end

local function simulation()
    if not ProjectPeople.DevelopmentHousehold then
        local time = getGameTime():getWorldAgeHours()
        population:step(
            service,
            time,
            SandboxVars and SandboxVars.ProjectPeople,
            time / 24 + (getSandboxOptions():getTimeSinceApo() - 1) * 30
        )
    end
    local world = service.authority:snapshot()
    local online = players()
    local human = {}
    combatPeople = world.people
    combat = combat
        or Combat.new({
            random = function()
                return ZombRand(1000000) / 1000000
            end,
            hit = nativeHit,
            person = function(id)
                return combatPeople[id]
            end,
            world = function()
                return service.authority:snapshot()
            end,
            actor = function(id)
                local b, r = bodies[id], records[id]
                return b and r and Body.matches(b, r) and b.actor or nil
            end,
        })
    threats = threats
        or ZombieThreat.new(function(z, a, damage)
            local weapon = instanceItem "Base.BareHands"
            weapon:setKnockBackOnNoDeath(false)
            nativeHit(z, a, weapon, damage, "npc")
        end)
    local zombies = getCell():getZombieList()
    locomotion:prune(records)
    for i = 0, online:size() - 1 do
        local p = online:get(i)
        local who = identity(p)
        if who and who.alive then
            human[who.personId] = p
        end
    end
    health:step()
    companionMovement:sampleLeaders(human, now())
    for id, h in pairs(human) do
        if h:isAttacking() then
            companionCombat:started(id, h, now())
        end
    end
    -- Rebind only actual saved native bodies. Never fabricate a replacement
    -- because a chunk has not loaded, a handle was recycled, or an ack was lost.
    for id, p in pairs(world.people) do
        if p.controller.kind == "ai" and p.life ~= "dead" and not p.reservationId then
            if bodies[id] and not Body.matches(bodies[id], records[id]) then
                bodies[id] = nil
                records[id] = nil
            end
            if not bodies[id] and (not p.populationGroup or p.nativeBirth) then
                bodies[id], records[id] = Body.recover(p, metadata.worldId)
            end
        end
    end
    local advanced, behaviourError =
        behaviour:step(service, bodies, records, online, identity, getGameTime():getWorldAgeHours())
    assert(advanced, behaviourError)
    world = advanced
    world = homeWork:clock(service.authority, records, getGameTime():getWorldAgeHours())
    population.world = world
    for id, b in pairs(bodies) do
        local r, p = records[id], world.people[id]
        local observed = Body.observe(b)
        r.behaviourResting = false
        r.nativeId, r.x, r.y, r.z = observed.nativeId, observed.x, observed.y, observed.z
        r.health, r.dead = observed.health, observed.dead
        r.clothing = Body.clothing(b)
        r.equipment = Equipment.hands(b.actor)
        r.missing = not observed.inWorld or observed.personId ~= id
        r.transferReserved = p.reservationId ~= nil or p.transitionId ~= nil
        homeWork:begin(p, r, b.actor, now())
        if r.homeOrderChanged then
            r.homeOrderChanged = nil
            b.homeRoute, b.workDoor = nil, nil
            orderFor(r, nil)
        end
        local flight, avoidCombat
        companionCombat:step(p, r, b.actor, human[p.commanderId], now())
        if not r.transferReserved and not observed.dead and not r.missing then
            flight, avoidCombat = locomotion:step(p, r, b.actor, zombies, now(), human[p.commanderId], pursued)
            -- Witnessed violence takes precedence over routine follow/avoidance.
            if combat:hasVisibleEnemy(id, b.actor, online) then
                flight, avoidCombat = nil, false
            end
            -- A cautious detour can pause for a nearby conversation. Actual
            -- escape still keeps the survivor focused on immediate danger.
            if flight and not r.fleeing and Movement.attention(p, r, b.actor, online, identity) then
                flight = nil
                avoidCombat = true
            end
        end
        if p.reservationId or p.transitionId then
            Movement.clearAttention(r)
            r.activity = "Transfer reserved"
            if r.mode == "move" then
                orderFor(r, nil)
            end
        elseif observed.dead or r.missing then
            Movement.clearAttention(r)
            r.activity = "Unavailable"
            if r.mode == "move" then
                orderFor(r, nil)
            end
        elseif health:busy(id) then
            Movement.clearAttention(r)
            combat:interrupt(id, r)
            if r.mode == "move" then
                orderFor(r, nil)
            end
            r.activity = "Receiving first aid"
        elseif flight then
            Movement.clearAttention(r)
            combat:interrupt(id, r)
            if
                r.mode ~= "move"
                or (flight.x - r.goalX) ^ 2 + (flight.y - r.goalY) ^ 2 > 0.01
                or flight.z ~= r.goalZ
            then
                orderFor(r, flight)
            end
        elseif avoidCombat or not combat:tick(id, b, r, zombies, online, now()) then
            if avoidCombat then
                if r.combatActive then
                    orderFor(r, nil)
                end
                combat:interrupt(id, r)
            end
            if playerAlerts:holding(id) then
                -- The alert manager below rechecks danger and owns facing.
                if r.mode == "move" then
                    orderFor(r, nil)
                end
            elseif Movement.attention(p, r, b.actor, online, identity) then
                if r.mode == "move" then
                    orderFor(r, nil)
                end
            elseif conversations and conversations:holding(id) then
                -- Danger/combat/player attention above outrank this short pause.
                -- Pair validation below releases both people together.
            else
                local relevant = false
                for _, h in pairs(human) do
                    if distance(h, b.actor) <= 6400 then
                        relevant = true
                    end
                end
                local working, activity = jobs:tick(id, relevant)
                if working then
                    r.activity = activity
                else
                    if
                        r.mode == "move"
                        and (
                            math.abs(r.z - r.goalZ) < 0.2 and (r.x - r.goalX) ^ 2 + (r.y - r.goalY) ^ 2 <= 0.25
                            or now() - r.started > 30000
                        )
                    then
                        local arrived = math.abs(r.z - r.goalZ) < 0.2
                            and (r.x - r.goalX) ^ 2 + (r.y - r.goalY) ^ 2 <= 0.25
                        orderFor(r, nil)
                        r.activity = arrived and "Arrived" or "Path blocked"
                        -- A completed doorway leg continues immediately. A
                        -- five-second wait here consumed the entry stall budget.
                        r.retryAt = (arrived or p.duty == "follow") and now() or now() + 5000
                    end
                    local home = p.duty == "base" and p.home
                    local homeSquare = home and getCell():getGridSquare(math.floor(home.x), math.floor(home.y), home.z)
                    local outsideHome = homeSquare
                        and homeSquare:getBuilding()
                        and b.actor:getCurrentSquare()
                        and b.actor:getCurrentSquare():getBuilding() ~= homeSquare:getBuilding()
                    if r.duty ~= p.duty or home and (r.homeX ~= home.x or r.homeY ~= home.y or r.homeZ ~= home.z) then
                        r.duty = p.duty
                        r.homeX, r.homeY, r.homeZ = home and home.x, home and home.y, home and home.z
                        b.workDoor, b.homeRoute = nil, nil
                        orderFor(r, nil)
                        r.retryAt = 0
                        r.behaviourVisiting = false
                    end
                    local goal, idle
                    if p.duty ~= "follow" then
                        companionMovement:clearFollower(id)
                    end
                    if p.duty == "follow" then
                        local leader = human[p.commanderId]
                        goal = companionMovement:follow(p, r, b.actor, leader, now())
                        if not goal and r.mode == "move" then
                            orderFor(r, nil)
                        end
                    elseif
                        p.duty == "base"
                        and p.home
                        and not r.homeActive
                        and not b.workDoor
                        and (
                            outsideHome
                            or (r.x - p.home.x) ^ 2 + (r.y - p.home.y) ^ 2 > 4
                            or math.abs(r.z - p.home.z) > 0.2
                        )
                    then
                        goal = p.home
                        local square = getCell():getGridSquare(math.floor(goal.x), math.floor(goal.y), goal.z)
                        local current = b.actor:getCurrentSquare()
                        if
                            square
                            and square:getBuilding()
                            and current
                            and current:getBuilding() ~= square:getBuilding()
                        then
                            b.homeRoute = b.homeRoute or {}
                            if r.mode == "wait" then
                                b.homeRoute.entryProgressAt = now()
                            end
                            -- The local scavenging scan may not contain this
                            -- home's door, or exclude an owner's claimed floor.
                            -- An explicit home order still gets a native route.
                            goal = Scavenging.entrance(b.actor, square:getBuilding(), b.homeRoute, now()) or p.home
                        end
                        r.activity = "Returning home"
                        r.behaviourVisiting = false
                    elseif p.duty == "base" and p.home and r.homeActive then
                        goal = homeWork:step(p, r, b.actor, human[p.commanderId], bodies, world, now())
                        if not goal and r.mode == "move" then
                            orderFor(r, nil)
                        end
                    elseif p.duty == "base" and p.home then
                        if not b.workDoor and now() >= (r.nextWork or 0) then
                            r.nextWork = now() + 5000
                            b.workDoor = Work.findDoor(p.home, b.actor)
                        end
                        if b.workDoor then
                            local closed, reason = Work.close(b.actor, b.workDoor)
                            if closed then
                                b.workDoor, b.workDoorAt = nil, nil
                                r.nextWork = now() + 30000
                                r.activity = "Closed an open door"
                                orderFor(r, nil)
                            else
                                goal = Work.goal(b.workDoor)
                                r.activity = goal and "Securing the house" or "Door unreachable"
                                b.workDoorAt = b.workDoorAt or now()
                                if not goal or reason == "door_no_longer_open" or now() - b.workDoorAt > 15000 then
                                    b.workDoor, b.workDoorAt = nil, nil
                                    r.nextWork = now() + 30000
                                    goal = nil
                                end
                            end
                        else
                            b.workDoorAt = nil
                            r.activity = "Watching the house"
                            idle = true
                        end
                    else
                        r.activity = p.duty == "wait" and "Waiting here" or "At home"
                        idle = true
                    end
                    if idle then
                        -- Independent population focus drives ordinary activity. Rest
                        -- for real strain and explicit household duties remain intact.
                        local tired = p.mind and (p.mind.strain >= 45 or p.mind.stress >= 60)
                        if not tired then
                            goal = population:goal(
                                p,
                                r,
                                records,
                                online,
                                SandboxVars and SandboxVars.ProjectPeople,
                                b.actor,
                                now()
                            )
                        end
                        if not goal and (not p.populationGroup or p.recruited or p.duty or tired) then
                            goal = behaviour:idle(id, p, b, r, bodies, records, getGameTime():getWorldAgeHours())
                        else
                            r.behaviourVisiting = false
                        end
                        if
                            home
                            and goal
                            and (math.abs(goal.z - home.z) > 0.2 or (goal.x - home.x) ^ 2 + (goal.y - home.y) ^ 2 > 4)
                        then
                            goal = nil
                            r.behaviourVisiting = false
                        end
                        if not goal and r.mode == "move" then
                            orderFor(r, nil)
                        end
                    end
                    if
                        goal
                        and now() >= (r.retryAt or 0)
                        and (
                            r.mode ~= "move"
                            or p.duty == "follow" and ((goal.x - r.goalX) ^ 2 + (goal.y - r.goalY) ^ 2 > 0.01 or goal.z ~= r.goalZ)
                            or r.homeActive and ((goal.x - r.goalX) ^ 2 + (goal.y - r.goalY) ^ 2 > 0.01 or goal.z ~= r.goalZ)
                            or goal.entry and ((goal.x - r.goalX) ^ 2 + (goal.y - r.goalY) ^ 2 > 0.01 or goal.z ~= r.goalZ)
                            or now() - r.started > 1500 and (goal.x - r.goalX) ^ 2 + (goal.y - r.goalY) ^ 2 > 4
                        )
                    then
                        orderFor(r, goal)
                    end
                end
            end
        else
            Movement.clearAttention(r)
        end
        if
            r.homeActive
            and p.homeWork
            and p.homeWork.breakKind == "relax"
            and conversations
            and conversations:holding(id)
            and not r.combatActive
            and not r.fleeing
        then
            r.homeResting = true
        end
        if not r.homeWorking and not r.homeResting then
            homeWork:interrupt(id, r)
        end
        companionMovement:lookAround(p, r, b.actor, now())
    end
    conversations = conversations
        or PairConversation.new({
            matches = Body.matches,
            clear = CombatSpace.clear,
            random = function(limit)
                return ZombRand(limit)
            end,
            stop = function(record)
                orderFor(record, nil)
            end,
            busy = function(id)
                return health:busy(id)
            end,
            danger = function(id, actor, record, person)
                return combat:hasVisibleEnemy(id, actor, players())
                    or InteractionDanger.check(
                        actor,
                        record,
                        person,
                        getCell():getZombieList(),
                        players(),
                        identity,
                        nil,
                        function(z)
                            return pursued(z, id)
                        end
                    )
            end,
        })
    conversations:step(
        world,
        bodies,
        records,
        human,
        DialogueClock.now(),
        not SandboxVars or not SandboxVars.ProjectPeople or SandboxVars.ProjectPeople.IdleAutonomy ~= false
    )
    local function alertEligible(id, binding, player, continuing)
        local r, p = records[id], world.people[id]
        return p
            and p.life == "alive"
            and p.controller.kind == "ai"
            and not p.reservationId
            and not p.transitionId
            and not health:busy(id)
            and not (p.homeWork and p.duty == "base" and p.homeWork.breakKind == "sleep")
            and r
            and Body.matches(binding, r)
            and PlayerAlerts.eligible(binding.actor, r, player, CombatSpace.clear, continuing)
            and not combat:hasVisibleEnemy(id, binding.actor, online)
            and not InteractionDanger.check(binding.actor, r, p, zombies, online, identity, nil, function(z)
                return pursued(z, id)
            end)
    end
    playerAlerts:step(bodies, human, DialogueClock.now(), alertEligible, function(id, binding, player)
        return alertEligible(id, binding, player, true)
    end)
    for id, r in pairs(records) do
        local recipient = playerAlerts:holding(id)
        local player = recipient and human[recipient]
        if player then
            if r.mode == "move" then
                orderFor(r, nil)
            end
            r.faceX, r.faceY = player:getX(), player:getY()
            r.activity, r.behaviourResting = "Greeting a survivor", false
        elseif r.playerAlertTarget and r.activity == "Greeting a survivor" then
            r.faceX, r.faceY, r.retryAt = nil, nil, 0
            r.activity = "Greeting ended"
        end
        r.playerAlertTarget = recipient
    end
    threatOrders = threats:plan(zombies, bodies, records, online, now())
    if now() >= nextCheckpoint then
        nextCheckpoint = now() + 15000
        local checkpoints, unique, changed = {}, {}, false
        for id, b in pairs(bodies) do
            local p = world.people[id]
            local r = records[id]
            if
                p
                and p.controller.kind == "ai"
                and not p.reservationId
                and not p.transitionId
                and not r.dead
                and not r.missing
                and r.health > 0
            then
                checkpoints[id] = Body.checkpoint(r, p.bodyRecord)
                unique[id] = Body.matches(b, r)
                if checkpoints[id] then
                    changed = true
                end
            end
        end
        if changed then
            local ack = service.authority:applySystem(
                "people.checkpoint",
                { records = checkpoints },
                { evidence = { kind = "people_checkpoint", validated = true, people = unique } }
            )
            assert(ack.ok, ack.code)
        end
    end
end

local function populationBoundary()
    if not Runtime.active or not service or ProjectPeople.DevelopmentHousehold then
        return
    end
    if initialSpawnAt and now() < initialSpawnAt then
        return
    end
    local time = getGameTime():getWorldAgeHours()
    local elapsed = time / 24 + (getSandboxOptions():getTimeSinceApo() - 1) * 30
    population:boundary(
        service,
        bodies,
        records,
        players(),
        metadata.worldId,
        time,
        now(),
        SandboxVars and SandboxVars.ProjectPeople,
        elapsed
    )
end

local function tick()
    if Runtime.error or now() < nextTick then
        return
    end
    nextTick = now() + 500
    if authority() then
        local online = players()
        local ready = true
        if isServer() then
            for i = 0, online:size() - 1 do
                local p = online:get(i)
                if not p:isDead() and (not readyClients[p] or now() - readyClients[p] < 2000) then
                    ready = false
                end
            end
        end
        if ready and not isServer() then
            for i = 0, online:size() - 1 do
                local p = online:get(i)
                if not p:isDead() then
                    seed(p)
                end
            end
        end
        if Runtime.active then
            if not isServer() then
                populationBoundary()
            end
            simulation()
            for i = 0, online:size() - 1 do
                local p = online:get(i)
                if p:isDead() then
                    service.authority:confirmDeath(p)
                end
                publish(p)
            end
        end
    else
        -- Keep the safe server client-command boundary available while travelling.
        if now() >= nextReady and getSpecificPlayer(0) and not getSpecificPlayer(0):isDead() then
            nextReady = now() + 3000
            sendClientCommand(getSpecificPlayer(0), Runtime.MODULE, "ready", {})
        end
        if latest then
            for id, record in pairs(latest.bodies or {}) do
                records[id] = record
                if bodies[id] and not Body.matches(bodies[id], record) then
                    bodies[id] = nil
                end
                if not bodies[id] then
                    bodies[id] = Body.find(record)
                end
                local update = debugHealthUpdates[id]
                if update and DebugService.applyHealth(bodies[id], records[id], update) then
                    record.health = update.health
                    debugHealthUpdates[id] = nil
                end
            end
        end
    end
end

local function command(player, args)
    if not Runtime.active or not service or Runtime.error then
        return
    end
    local result = service:request(player, args)
    if result.ok and conversations and type(args.fields) == "table" and args.fields.personId then
        conversations:cancel(args.fields.personId, records, DialogueClock.now())
        playerAlerts:cancel(args.fields.personId)
    end
    result.requestId = args.id
    result.personId = type(args.fields) == "table" and args.fields.personId or nil
    if isServer() then
        sendServerCommand(player, Runtime.MODULE, "reply", result)
    else
        Runtime.reply = result
    end
    publish(player)
end

function Runtime.request(kind, fields, revision)
    sequence = sequence + 1
    local args =
        { id = string.format("%.0f", now()) .. ":" .. sequence, kind = kind, fields = fields, revision = revision }
    if isClient() then
        sendClientCommand(getSpecificPlayer(0), Runtime.MODULE, "request", args)
    else
        command(getSpecificPlayer(0), args)
    end
    return { ok = true, pending = true, code = "request_sent", requestId = args.id }
end

function Runtime.view()
    return latest
end

function Runtime.playerAlert(id)
    if not Runtime.dialogueViewAt or DialogueClock.now() - Runtime.dialogueViewAt > 3000 then
        return nil
    end
    if authority() then
        -- SP native bodies can retain sentinel network IDs and aren't in the
        -- replication payload; use the same recipient-specific authority text.
        return latest and playerAlerts:line(id, latest.personId) or nil
    end
    local record = latest and latest.bodies and latest.bodies[id]
    return record and record.playerAlert or nil
end

function Runtime.threatFor(actor)
    return threats and threats:inspect(actor)
end

function Runtime.eachBody(visitor)
    for id, b in pairs(bodies) do
        local r = records[id]
        if r and Body.matches(b, r) then
            visitor(b.actor, r)
        end
    end
end

function Runtime.inspect()
    local result = {
        build = Runtime.BUILD,
        active = Runtime.active,
        error = Runtime.error,
        bodies = {},
        records = Core.snapshot(records),
        population = Core.snapshot(population.diagnostics),
        threats = Core.snapshot(threatOrders or {}),
        status = service and service.authority:status(),
        world = service and service.authority:snapshot(),
    }
    for id, b in pairs(bodies) do
        result.bodies[id] = Body.observe(b)
    end
    return result
end

local function guard(fn, ...)
    if Runtime.error then
        return
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        Runtime.error = tostring(err)
        print("[ProjectPeople] " .. Runtime.BUILD .. " FAULT " .. Runtime.error)
        if isServer() then
            sendServerCommand(Runtime.MODULE, "fault", { code = Runtime.error })
        end
    end
end
local function beginAlarm(player)
    if Runtime.active and not player:isDead() and not player:isGodMod() then
        local world = alarmWorld
        local who = world and identity(player)
        if who then
            alarms:begin(player, Alarm.friends(world, who.personId, Runtime.eachBody))
        end
    end
end
Events.OnPlayerUpdate.Add(function(player)
    if not isClient() and not isServer() and player:isLocalPlayer() then
        guard(beginAlarm, player)
    end
end)
Events.OnTick.Add(function()
    if DialogueClock.paused() then
        return
    end
    guard(alarms.finish, alarms)
    guard(tick)
    -- Installed multiplayer BodyDamage owns panic on the server. Remote
    -- players return before OnPlayerUpdate, so bracket their next simulation
    -- update from this tick boundary instead of changing client stats twice.
    if isServer() then
        local online = players()
        for i = 0, online:size() - 1 do
            guard(beginAlarm, online:get(i))
        end
    end
end)
Events.OnZombieUpdate.Add(function(actor)
    local id = actor:getModData().ProjectPeoplePersonId
    if
        not id
        and (not Runtime.active or Runtime.error)
        and actor:getModData().ProjectPeoplePursuitOriginalUseless ~= nil
    then
        ZombieThreat.release(actor)
    end
    if id and bodies[id] and bodies[id].actor == actor and records[id] then
        if not authority() and not Body.matches(bodies[id], records[id]) then
            bodies[id] = nil
        else
            guard(Body.update, bodies[id], records[id])
        end
    elseif not id and Runtime.active and (threats or isClient()) then
        threats = threats or ZombieThreat.new(function()
            error "client_damage_forbidden"
        end)
        local orders = not isClient() or now() - (threatReceivedAt or 0) < 2500
        guard(threats.update, threats, actor, orders and threatOrders or {}, bodies, records, now())
    end
end)
if Events.OnWeaponSwing then
    Events.OnWeaponSwing.Add(function(attacker)
        if authority() and service and attacker and instanceof(attacker, "IsoPlayer") then
            local who = identity(attacker)
            if who and who.alive then
                companionCombat:started(who.personId, attacker, now())
            end
        end
    end)
end
Events.OnWeaponHitCharacter.Add(function(attacker, victim)
    if attacker and victim then
        local attackerId = attacker:getModData().ProjectPeoplePersonId
        local victimId = victim:getModData().ProjectPeoplePersonId
        if
            attackerId
            and victimId
            and bodies[attackerId]
            and records[attackerId]
            and bodies[attackerId].actor == attacker
            and Body.matches(bodies[attackerId], records[attackerId])
            and bodies[victimId]
            and records[victimId]
            and bodies[victimId].actor == victim
            and Body.matches(bodies[victimId], records[victimId])
        then
            local record = latest and latest.bodies and latest.bodies[victimId]
            local allied = authority() and service and Party.allied(service.authority:snapshot(), attackerId, victimId)
                or record and record.alliedPeople and record.alliedPeople[attackerId] == true
            if allied then
                victim:setAvoidDamage(true)
                return
            end
        end
    end
    if
        authority()
        and service
        and attacker
        and victim
        and instanceof(attacker, "IsoPlayer")
        and instanceof(victim, "IsoZombie")
        and not victim:getModData().ProjectPeoplePersonId
    then
        local who = identity(attacker)
        if who and who.alive then
            companionCombat:started(who.personId, attacker, now())
            for id, body in pairs(bodies) do
                local record = records[id]
                if
                    record
                    and record.combatActive
                    and Body.matches(body, record)
                    and not body.actor:isDead()
                    and TrustSpace.distance(body.actor, attacker) <= 64
                    and TrustSpace.distance(body.actor, victim) <= 64
                    and TrustSpace.clear(body.actor, attacker)
                    and TrustSpace.clear(body.actor, victim)
                then
                    local reward = TrustRewards.record(service.authority, id, who.personId, "combat")
                    if not reward.ok then
                        error(reward.code)
                    end
                end
            end
        end
    end
    if attacker and victim and instanceof(attacker, "IsoPlayer") then
        local id = victim:getModData().ProjectPeoplePersonId
        if
            id
            and bodies[id]
            and records[id]
            and bodies[id].actor == victim
            and Body.matches(bodies[id], records[id])
        then
            local protected = false
            if authority() and service then
                local who = identity(attacker)
                protected = who and FriendlyFire.protected(service.authority:snapshot(), id, who.personId) or false
            else
                local record = latest and latest.bodies and latest.bodies[id]
                protected = record
                        and record.friendlyFirePlayers
                        and record.friendlyFirePlayers[tostring(attacker:getOnlineID())] == true
                    or false
            end
            if FriendlyFire.block(attacker, victim, protected) then
                return
            end
        end
    end
    if authority() and combat then
        combat:provoked(victim, attacker)
    end
    if authority() and service and victim then
        local id = victim:getModData().ProjectPeoplePersonId
        if id and bodies[id] and bodies[id].actor == victim and Body.matches(bodies[id], records[id]) then
            guard(function()
                local result =
                    behaviour:attacked(service, attacker, victim, identity, records, getGameTime():getWorldAgeHours())
                if result then
                    assert(result.ok, result.code)
                end
            end)
        end
    end
end)
if isServer() then
    Events.OnClientCommand.Add(function(module, kind, player, args)
        if module ~= Runtime.MODULE then
            return
        end
        if kind == "ready" and player and not player:isDead() then
            if not readyClients[player] then
                readyClients[player] = now()
                initialSpawnAt = initialSpawnAt and math.max(initialSpawnAt, now() + 5000) or now() + 45000
            end
            local online = players()
            local ready = now() >= (initialSpawnAt or math.huge)
            for i = 0, online:size() - 1 do
                local p = online:get(i)
                if not p:isDead() and not readyClients[p] then
                    ready = false
                end
            end
            -- Match the proven native factory boundary: server client-command
            -- dispatch, after world entry, rather than inside the world tick.
            if ready then
                guard(seed, player)
                guard(populationBoundary)
            end
        elseif kind == "request" and type(args) == "table" then
            guard(command, player, args)
        end
    end)
elseif isClient() then
    Events.OnServerCommand.Add(function(module, kind, payload)
        if module ~= Runtime.MODULE or type(payload) ~= "table" then
            return
        end
        if kind == "view" and payload.build == Runtime.BUILD then
            if not latest or not latest.world or payload.world and payload.world.revision >= latest.world.revision then
                latest = payload
                Runtime.viewAt, Runtime.dialogueViewAt = now(), DialogueClock.now()
                Runtime.active = true
                threatOrders = payload.threats or {}
                threatReceivedAt = now()
                local player = getSpecificPlayer(0)
                if player and payload.personId then
                    player:getModData().ProjectPeopleCharacterId = payload.personId
                end
            end
        elseif kind == "debugHealth" and type(payload.personId) == "string" then
            local id = payload.personId
            if DebugService.applyHealth(bodies[id], records[id], payload) then
                if latest and latest.bodies and latest.bodies[id] then
                    latest.bodies[id].health = payload.health
                end
            elseif not records[id] or not bodies[id] then
                debugHealthUpdates[id] = payload
            end
        elseif kind == "reply" then
            Runtime.reply = payload
        elseif
            kind == "combatDamage"
            and type(payload.sequence) == "number"
            and payload.sequence > (hitSequence or 0)
        then
            hitSequence = payload.sequence
            local list = getCell():getZombieList()
            for i = 0, list:size() - 1 do
                local actor = list:get(i)
                if
                    actor:getOnlineID() == payload.nativeId
                    and (not payload.personId or actor:getModData().ProjectPeoplePersonId == payload.personId)
                then
                    actor:setHealth(math.min(actor:getHealth(), payload.health))
                    break
                end
            end
        elseif kind == "fault" then
            Runtime.error = payload.code
        end
    end)
end
return Runtime
