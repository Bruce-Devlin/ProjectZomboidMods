-- World records, decisions and command handlers. Native effects belong in the adapters.
local DevTools = require "ProjectPeople/DevTools"
ProjectPeople = ProjectPeople or {}
local Core = { VERSION = 1, RECEIPTS = 32, TERMINAL_OPERATIONS = 128 }
local Mind = require "ProjectPeople/Behaviour/Mind"
local Behaviour = require "ProjectPeople/Behaviour/Commands"
local Population = require "ProjectPeople/Population/Rules"
local Trust = require "ProjectPeople/Behaviour/Trust"
local SocialGroup = require "ProjectPeople/Behaviour/Groups"
local FriendlyFire = require "ProjectPeople/FriendlyFire"
ProjectPeople.Core = Core
local jobPhases = {
    prepared = true,
    outward = true,
    collecting = true,
    collecting_prepared = true,
    returning = true,
    home = true,
    storing = true,
    storing_prepared = true,
    completed = true,
    recalled = true,
    blocked = true,
    unknown = true,
}
local jobTerminal = { completed = true, recalled = true }

local isFinite = DevTools.isFinite

local function isText(value)
    return DevTools.isText(value, 256)
end

local function empty(values)
    for _ in pairs(values) do
        return false
    end
    return true
end
local copy = DevTools.copy
local canonical = DevTools.canonical

local function fail(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function success(code, values)
    local result = values or {}
    result.ok, result.code = true, code or "accepted"
    return result
end

local function person(world, id)
    return world.people[id]
end

local function alive(personRecord)
    return personRecord and personRecord.life ~= "dead"
end

local function touch(personRecord)
    personRecord.revision = personRecord.revision + 1
end

local function locked(personRecord)
    return personRecord.reservationId or personRecord.transitionId
end

local function hasTransfer(world, id)
    for _, operation in pairs(world.operations) do
        if operation.kind == "transfer" and not operation.terminal then
            for _, itemId in ipairs(operation.items) do
                local item = world.items[itemId]
                if item and (operation.source == "person:" .. id or operation.destination == "person:" .. id) then
                    return true
                end
            end
        end
    end
    return false
end

local function canCommand(world, personRecord, actor)
    if not personRecord or not actor or not alive(actor) then
        return false
    end
    if personRecord.commanderId == actor.id then
        return true
    end
    local community = personRecord.communityId and world.communities[personRecord.communityId]
    return community and actor.communityId == personRecord.communityId and community.commanders[actor.id] == true
end

local function evidence(context, kind, operationId)
    local proof = context.evidence
    return type(proof) == "table"
            and proof.validated == true
            and proof.kind == kind
            and (not operationId or proof.operationId == operationId)
            and proof
        or nil
end

local function capabilities(context, names)
    for _, name in ipairs(names) do
        if not context.capabilities or context.capabilities[name] ~= true then
            return false
        end
    end
    return true
end

local function controllerPending(world, controllerId)
    for _, operation in pairs(world.operations) do
        if operation.kind == "succession" and not operation.terminal and operation.controllerId == controllerId then
            return true
        end
    end
    return false
end

local function actorAvailable(world, actorId, personId)
    if not isText(actorId) then
        return false
    end
    for id, personRecord in pairs(world.people) do
        if id ~= personId and personRecord.representation.actorId == actorId then
            return false
        end
    end
    return true
end

local function ownedItems(world, personId)
    local items = {}
    for id, item in pairs(world.items) do
        if item.owner == "person:" .. personId then
            items[id] = copy(item.data)
        end
    end
    return items
end

local function inventoryMatches(proof, personId, expected)
    if proof.soleInventory ~= true or type(proof.items) ~= "table" or type(proof.itemOwners) ~= "table" then
        return false
    end
    local owners = {}
    for id in pairs(expected) do
        owners[id] = "person:" .. personId
    end
    return canonical(proof.items) == canonical(expected) and canonical(proof.itemOwners) == canonical(owners)
end

local function finishOperation(world, operation, state)
    operation.state, operation.terminal, operation.finishedRevision = state, true, world.revision + 1
    local terminal = {}
    for id, value in pairs(world.operations) do
        if value.terminal then
            table.insert(terminal, { id = id, revision = value.finishedRevision })
        end
    end
    table.sort(terminal, function(a, b)
        return a.revision < b.revision
    end)
    for i = 1, #terminal - Core.TERMINAL_OPERATIONS do
        world.operations[terminal[i].id] = nil
    end
end

local function relation(personRecord, target)
    personRecord.relationships[target] = personRecord.relationships[target]
        or { trust = 0, affection = 0, respect = 0, fear = 0, anchors = {} }
    return personRecord.relationships[target]
end

local function clamp(n)
    return math.max(-100, math.min(100, n))
end

local function makePerson(data, controller)
    if type(data) ~= "table" or not isText(data.id) or not isText(data.name) then
        return nil
    end
    return {
        id = data.id,
        name = data.name,
        revision = 0,
        life = "alive",
        available = true,
        character = copy(data.character or {}),
        preferences = copy(data.preferences or {}),
        personality = copy(data.personality or {}),
        background = data.background or "",
        family = {},
        relationships = {},
        knowledge = {},
        recruited = false,
        attachment = data.attachment or 0,
        location = copy(data.location or {}),
        controller = controller or { kind = "ai" },
        representation = { mode = "abstract", owner = "record" },
    }
end

function Core.newWorld(worldId, timelineId)
    assert(isText(worldId) and isText(timelineId), "world_and_timeline_required")
    return {
        schema = Core.VERSION,
        worldId = worldId,
        timelineId = timelineId,
        revision = 0,
        people = {},
        communities = {},
        parties = {},
        missions = {},
        items = {},
        inventories = {},
        operations = {},
        controllers = {},
        issuers = {},
        jobs = {},
    }
end

function Core.snapshot(world)
    return copy(world)
end

-- Save recovery is deliberately conservative. Unsupported schemas are retained by
-- the caller for recovery, rather than migrated destructively or silently reset.

function Core.restore(snapshot)
    if type(snapshot) ~= "table" or snapshot.schema ~= Core.VERSION then
        return nil, "unsupported_schema"
    end
    if
        not isText(snapshot.worldId)
        or not isText(snapshot.timelineId)
        or not isFinite(snapshot.revision)
        or snapshot.revision < 0
        or snapshot.revision % 1 ~= 0
    then
        return nil, "invalid_snapshot"
    end
    for _, key in ipairs({
        "people",
        "communities",
        "parties",
        "missions",
        "items",
        "inventories",
        "operations",
        "controllers",
        "issuers",
    }) do
        if type(snapshot[key]) ~= "table" then
            return nil, "invalid_snapshot:" .. key
        end
    end
    local ok, restored = pcall(copy, snapshot)
    if not ok then
        return nil, "invalid_snapshot_values"
    end
    if restored.jobs ~= nil and type(restored.jobs) ~= "table" then
        return nil, "invalid_jobs"
    end
    if not Population.valid(restored) then
        return nil, "invalid_population"
    end
    local actors = {}
    for id, personRecord in pairs(restored.people) do
        if personRecord.friendlyFire ~= nil and type(personRecord.friendlyFire) ~= "boolean" then
            return nil, "invalid_friendly_fire"
        end
        if not Mind.valid(personRecord.mind) then
            return nil, "invalid_survivor_mind"
        end
        if
            personRecord.id ~= id
            or not isText(personRecord.name)
            or type(personRecord.controller) ~= "table"
            or type(personRecord.representation) ~= "table"
            or type(personRecord.character) ~= "table"
            or type(personRecord.family) ~= "table"
            or type(personRecord.relationships) ~= "table"
            or not isFinite(personRecord.revision)
        then
            return nil, "invalid_person"
        end
        if personRecord.life ~= "alive" and personRecord.life ~= "critical" and personRecord.life ~= "dead" then
            return nil, "invalid_life_state"
        end
        if personRecord.controller.kind ~= "ai" and personRecord.controller.kind ~= "player" then
            return nil, "invalid_controller"
        end
        if
            personRecord.controller.kind == "player"
            and alive(personRecord)
            and restored.controllers[personRecord.controller.id] ~= id
        then
            return nil, "controller_mismatch"
        end
        local representation = personRecord.representation
        if representation.mode == "physical" then
            if
                representation.owner ~= "engine"
                or not isText(representation.actorId)
                or actors[representation.actorId]
            then
                return nil, "duplicate_or_invalid_actor"
            end
            actors[representation.actorId] = true
        elseif representation.mode ~= "abstract" or representation.owner ~= "record" or representation.actorId then
            return nil, "invalid_representation"
        end
        if
            personRecord.transitionId
            and (
                not restored.operations[personRecord.transitionId]
                or restored.operations[personRecord.transitionId].terminal
            )
        then
            return nil, "missing_transition_journal"
        end
        if
            personRecord.reservationId
            and (
                not restored.operations[personRecord.reservationId]
                or restored.operations[personRecord.reservationId].terminal
            )
        then
            return nil, "missing_succession_journal"
        end
        if
            personRecord.jobId
            and (
                not restored.jobs
                or type(restored.jobs[personRecord.jobId]) ~= "table"
                or restored.jobs[personRecord.jobId].personId ~= id
                or jobTerminal[restored.jobs[personRecord.jobId].phase]
            )
        then
            return nil, "missing_active_job"
        end
        for relativeId in pairs(personRecord.family) do
            if not restored.people[relativeId] then
                return nil, "missing_family_member"
            end
        end
    end
    for controllerId, id in pairs(restored.controllers) do
        local personRecord = restored.people[id]
        if
            not personRecord
            or personRecord.controller.kind ~= "player"
            or personRecord.controller.id ~= controllerId
        then
            return nil, "controller_mismatch"
        end
    end
    for itemId, item in pairs(restored.items) do
        if item.id ~= itemId or not restored.inventories[item.owner] then
            return nil, "invalid_item_owner"
        end
        if item.lock and not restored.operations[item.lock] then
            return nil, "missing_transfer_journal"
        end
    end
    for id, job in pairs(restored.jobs or {}) do
        if
            type(job) ~= "table"
            or job.id ~= id
            or not restored.people[job.personId]
            or not jobPhases[job.phase]
            or (not jobTerminal[job.phase] and restored.people[job.personId].jobId ~= id)
        then
            return nil, "invalid_job_owner"
        end
    end
    return restored
end

-- Build a request at the current revision. Clients may submit requests, but only a
-- server/local-authority adapter may construct the authenticated context for apply.

function Core.command(world, issuer, kind, fields)
    local prior = world.issuers[issuer]
    local sequence = (prior and prior.sequence or 0) + 1
    local command = copy(fields or {})
    command.id, command.sequence, command.kind = issuer .. ":" .. tostring(sequence), sequence, kind
    command.worldId, command.timelineId, command.expectedRevision = world.worldId, world.timelineId, world.revision
    return command
end

local function decidePerson(world, personId, actorId, request, risk)
    local personRecord, actor = person(world, personId), person(world, actorId)
    if not alive(personRecord) or not alive(actor) then
        return false, "person_unavailable"
    end
    if
        personRecord.controller.kind ~= "ai"
        or locked(personRecord)
        or personRecord.missionId
        or personRecord.jobId
        or hasTransfer(world, personRecord.id)
    then
        return false, "already_committed"
    end
    if not personRecord.available or personRecord.life ~= "alive" then
        return false, "needs_help"
    end
    if
        personRecord.commanderId
        and personRecord.commanderId ~= actor.id
        and alive(person(world, personRecord.commanderId))
    then
        return false, "another_commander"
    end
    local rel = personRecord.relationships[actorId] or { trust = 0, fear = 0 }
    if rel.trust < -20 or rel.fear >= 60 then
        return false, "trust_broken"
    end
    local personalReason = Mind.refusal(personRecord, actorId, request, risk)
    if personalReason then
        return false, personalReason
    end
    if request == "resident" then
        if not personRecord.communityId then
            return false, "home_required"
        end
        if rel.trust < Trust.requirement(personRecord, "resident") then
            return false, "prefers_temporary_cooperation"
        end
        return true, "cooperation_agreed"
    end
    if request ~= "travel" and request ~= "mission" then
        return false, "unknown_request"
    end
    if personRecord.preferences.baseOnly then
        return false, "prefers_home"
    end
    local agreement = personRecord.communityAgreement
    if
        personRecord.preferences.protectCommunity
        and personRecord.attachment >= 60
        and agreement
        and agreement.communityId == personRecord.communityId
        and agreement.partnerId ~= actor.id
        and actor.communityId ~= personRecord.communityId
    then
        return false, "committed_to_community"
    end
    if risk and personRecord.preferences.refusesRisk then
        return false, "declines_lethal_risk"
    end
    if rel.trust < Trust.requirement(personRecord, "travel") then
        return false, "needs_trust"
    end
    return true, "travel_agreed"
end

function Core.decide(world, personId, actorId, request, risk)
    local accepted, reason = decidePerson(world, personId, actorId, request, risk)
    if not accepted or (request ~= "travel" and request ~= "resident") then
        return accepted, reason
    end
    for _, id in ipairs(SocialGroup.members(world, personId, true)) do
        if id ~= personId then
            local willing, why = decidePerson(world, id, actorId, request, risk)
            if not willing then
                return false, "group_not_ready", why
            end
        end
    end
    return true, reason
end

-- The adapter must provide a complete current authority-side player enumeration.
-- A loaded actor, missing observation, camera visibility or one commander's area
-- alone never establishes encounter relevance.

function Core.inspectRelevance(world, personId, observation)
    if not person(world, personId) then
        return nil, "unknown_person"
    end
    if
        type(observation) ~= "table"
        or observation.complete ~= true
        or observation.worldId ~= world.worldId
        or observation.timelineId ~= world.timelineId
        or type(observation.players) ~= "table"
    then
        return nil, "relevance_unknown"
    end
    local position = observation.position
    if
        type(position) ~= "table"
        or not isFinite(position.x)
        or not isFinite(position.y)
        or not isFinite(position.z)
    then
        return nil, "position_unknown"
    end
    local relevant, seen = {}, {}
    for key in pairs(observation.players) do
        if not isFinite(key) or key % 1 ~= 0 or key < 1 or key > #observation.players then
            return nil, "players_unknown"
        end
    end
    for _, player in ipairs(observation.players) do
        if type(player) ~= "table" or not isText(player.id) or seen[player.id] or type(player.active) ~= "boolean" then
            return nil, "players_unknown"
        end
        seen[player.id] = true
        if player.active then
            if
                not isFinite(player.x)
                or not isFinite(player.y)
                or not isFinite(player.z)
                or not isFinite(player.radius)
                or player.radius < 0
                or (player.verticalRadius ~= nil and (not isFinite(player.verticalRadius) or player.verticalRadius < 0))
            then
                return nil, "player_position_unknown"
            end
            local dx, dy = position.x - player.x, position.y - player.y
            if
                player.interactingWith == personId
                or (
                    dx * dx + dy * dy <= player.radius * player.radius
                    and math.abs(position.z - player.z) <= (player.verticalRadius or 3)
                )
            then
                table.insert(relevant, player.id)
            end
        end
    end
    return { relevant = #relevant > 0, players = relevant, physicalLoaded = observation.physicalLoaded == true }
end

function Core.mortalityPolicy(world, personId, observation)
    local personRecord = person(world, personId)
    if not personRecord then
        return { mayDie = false, reason = "unknown_person" }
    end
    if personRecord.controller.kind == "player" then
        return { mayDie = true, reason = "player_survival" }
    end
    local relevance, err = Core.inspectRelevance(world, personId, observation)
    if not relevance then
        return { mayDie = false, reason = err, uncertain = true }
    end
    if relevance.relevant then
        return { mayDie = true, reason = "active_encounter", players = relevance.players }
    end
    if not personRecord.recruited then
        return { mayDie = true, reason = "independent_person" }
    end
    local mission = personRecord.missionId and world.missions[personRecord.missionId]
    if
        mission
        and mission.participants[personId]
        and not (mission.safeParticipants and mission.safeParticipants[personId])
        and mission.acceptedRisk == true
        and (mission.stage == "away" or mission.stage == "returning")
    then
        return { mayDie = true, reason = "accepted_assignment_risk", missionId = mission.id }
    end
    return { mayDie = false, reason = "protected_background" }
end

local handlers = {}

-- People and physical checkpoints
handlers["person.create"] = function(world, command, context)
    if not context.system then
        return fail "system_only"
    end
    local personRecord = makePerson(command.person)
    if not personRecord then
        return fail "invalid_person"
    end
    if world.people[personRecord.id] then
        return fail "person_exists"
    end
    world.people[personRecord.id] = personRecord
    world.inventories["person:" .. personRecord.id] = { kind = "person", personId = personRecord.id }
    return success("person_created", { personId = personRecord.id })
end

handlers["player.register"] = function(world, command, context)
    local proof = evidence(context, "player_identity")
    if
        not context.system
        or not proof
        or not isText(command.controllerId)
        or type(command.person) ~= "table"
        or proof.personId ~= command.person.id
        or proof.controllerId ~= command.controllerId
        or not actorAvailable(world, proof.actorId, command.person.id)
    then
        return fail "identity_unconfirmed"
    end
    if controllerPending(world, command.controllerId) then
        return fail "controller_transfer_unresolved"
    end
    local previousId = world.controllers[command.controllerId]
    if previousId and alive(world.people[previousId]) then
        return fail "controller_in_use"
    end
    local personRecord = makePerson(command.person, { kind = "player", id = command.controllerId })
    if not personRecord or world.people[personRecord.id] then
        return fail "new_identity_required"
    end
    personRecord.representation = { mode = "physical", owner = "engine", actorId = context.evidence.actorId }
    world.people[personRecord.id], world.controllers[command.controllerId] = personRecord, personRecord.id
    world.inventories["person:" .. personRecord.id] = { kind = "person", personId = personRecord.id }
    return success("new_player_registered", { personId = personRecord.id })
end

-- Initial native birth is distinct from reconstructing an existing survivor.
-- It may only adopt an empty, never-materialised authored record and observed
-- original native state. It does not grant faithful reconstruction capability.
handlers["person.bind_initial"] = function(world, command, context)
    local personRecord, proof = person(world, command.personId), evidence(context, "native_birth")
    if
        not context.system
        or not personRecord
        or personRecord.controller.kind ~= "ai"
        or not alive(personRecord)
        or personRecord.representation.mode ~= "abstract"
        or personRecord.nativeBirth
        or locked(personRecord)
        or not empty(personRecord.character)
        or not empty(ownedItems(world, personRecord.id))
    then
        return fail "new_native_person_required"
    end
    if
        not proof
        or proof.personId ~= personRecord.id
        or proof.uniqueBody ~= true
        or proof.inWorld ~= true
        or not actorAvailable(world, proof.actorId, personRecord.id)
        or type(proof.character) ~= "table"
        or type(proof.location) ~= "table"
        or not isFinite(proof.location.x)
        or not isFinite(proof.location.y)
        or not isFinite(proof.location.z)
    then
        return fail "native_birth_unconfirmed"
    end
    personRecord.character, personRecord.location = copy(proof.character), copy(proof.location)
    personRecord.representation = { mode = "physical", owner = "engine", actorId = proof.actorId }
    personRecord.nativeBirth = { actorId = proof.actorId, gameTime = context.gameTime }
    touch(personRecord)
    return success "native_person_bound"
end

-- Periodic native observation; cannot create bodies, revive people or overwrite
-- a reserved successor/transition. Native owner reconciliation happens first.
handlers["person.checkpoint"] = function(world, command, context)
    local personRecord, proof = person(world, command.personId), evidence(context, "person_checkpoint")
    if
        not context.system
        or not personRecord
        or personRecord.controller.kind ~= "ai"
        or locked(personRecord)
        or not alive(personRecord)
        or not proof
        or proof.personId ~= personRecord.id
        or proof.uniqueBody ~= true
    then
        return fail "checkpoint_unconfirmed"
    end
    local r = command.record
    if
        type(r) ~= "table"
        or r.personId ~= personRecord.id
        or not isFinite(r.x)
        or not isFinite(r.y)
        or not isFinite(r.z)
        or not isFinite(r.health)
        or r.health <= 0
        or r.health > 100
    then
        return fail "invalid_native_checkpoint"
    end
    personRecord.location = { x = r.x, y = r.y, z = r.z }
    personRecord.character.nativeHealth = r.health
    personRecord.bodyRecord = copy(r)
    touch(personRecord)
    return success "person_checkpointed"
end

-- A scene checkpoint is one transaction, not one whole-world journal per NPC.
handlers["people.checkpoint"] = function(world, command, context)
    local proof = evidence(context, "people_checkpoint")
    if not context.system or not proof or type(proof.people) ~= "table" or type(command.records) ~= "table" then
        return fail "checkpoint_unconfirmed"
    end
    local count = 0
    for _ in pairs(command.records) do
        count = count + 1
    end
    if count > 40 then
        return fail "checkpoint_scene_limit"
    end
    if count == 0 then
        return fail "checkpoint_empty"
    end
    for id, r in pairs(command.records) do
        local result = handlers["person.checkpoint"](world, { personId = id, record = r }, {
            system = true,
            evidence = {
                kind = "person_checkpoint",
                validated = true,
                personId = id,
                uniqueBody = proof.people[id] == true,
            },
        })
        if not result.ok then
            return result
        end
    end
    return success("people_checkpointed", { count = count })
end

-- Communities and cooperation
handlers["community.create"] = function(world, command, context)
    if not context.system then
        return fail "system_only"
    end
    if not isText(command.communityId) or not isText(command.name) or world.communities[command.communityId] then
        return fail "invalid_community"
    end
    if type(command.members) ~= "table" or #command.members == 0 then
        return fail "members_required"
    end
    local members = {}
    for _, id in ipairs(command.members) do
        local personRecord = person(world, id)
        if not alive(personRecord) or personRecord.communityId or members[id] then
            return fail "member_unavailable"
        end
        members[id] = true
    end
    if not members[command.leaderId] then
        return fail "leader_must_be_member"
    end
    world.communities[command.communityId] = {
        id = command.communityId,
        name = command.name,
        home = copy(command.home or {}),
        members = members,
        commanders = { [command.leaderId] = true },
        revision = 0,
    }
    for id in pairs(members) do
        world.people[id].communityId, world.people[id].home = command.communityId, copy(command.home or {})
        touch(world.people[id])
    end
    return success "community_created"
end

handlers["family.link"] = function(world, command, context)
    if not context.system then
        return fail "system_only"
    end
    local a, b = person(world, command.firstId), person(world, command.secondId)
    if not a or not b or a == b or not isText(command.relationship) then
        return fail "invalid_family_link"
    end
    if a.family[b.id] or b.family[a.id] then
        return fail "family_link_exists"
    end
    a.family[b.id], b.family[a.id] = command.relationship, command.relationship
    touch(a)
    touch(b)
    return success "family_linked"
end

handlers["social.event"] = function(world, command, context)
    if not context.system or not evidence(context, "social_event") then
        return fail "event_unconfirmed"
    end
    local personRecord, actor = person(world, command.personId), person(world, command.actorId)
    if not personRecord or not actor or not isText(command.eventId) then
        return fail "invalid_event"
    end
    local effects = {
        helped_family = { 25, 20, 10 },
        kept_promise = { 10, 2, 10 },
        shared_work = { 5, 3, 5 },
        betrayed = { -50, -30, -30 },
    }
    local effect = effects[command.event]
    if not effect then
        return fail "unknown_social_event"
    end
    if command.event == "helped_family" and not personRecord.family[command.relatedId] then
        return fail "family_not_known"
    end
    local rel = relation(personRecord, actor.id)
    if rel.anchors[command.eventId] then
        return success "event_already_recorded"
    end
    rel.trust, rel.affection, rel.respect =
        clamp(rel.trust + effect[1]), clamp(rel.affection + effect[2]), clamp(rel.respect + effect[3])
    rel.anchors[command.eventId] = { event = command.event, relatedId = command.relatedId, gameTime = context.gameTime }
    Mind.social(personRecord, command.event, command.actorId, command.eventId, context.gameTime, command.relatedId)
    touch(personRecord)
    return success "social_event_recorded"
end

handlers["cooperation.request"] = function(world, command, context)
    local personRecord, actor = person(world, command.personId), person(world, context.actorId)
    if command.request ~= "travel" and command.request ~= "resident" then
        return fail "unknown_request"
    end
    local proof = evidence(context, "conversation")
    if
        not proof
        or proof.personId ~= command.personId
        or proof.actorId ~= context.actorId
        or proof.inReach ~= true
        or proof.known ~= true
    then
        return fail "conversation_unconfirmed"
    end
    local accepted, reason = Core.decide(world, command.personId, context.actorId, command.request)
    if not accepted then
        return fail(reason)
    end
    local members = SocialGroup.members(world, personRecord.id, true)
    for _, id in ipairs(members) do
        local personRecord = person(world, id)
        if not personRecord.communityAgreement and personRecord.communityId then
            personRecord.communityAgreement = { communityId = personRecord.communityId, partnerId = actor.id }
        end
        personRecord.recruited, personRecord.commanderId = true, actor.id
        if command.request == "travel" then
            local partyId = "party:" .. actor.id
            world.parties[partyId] = world.parties[partyId] or { id = partyId, leaderId = actor.id, members = {} }
            if personRecord.partyId and world.parties[personRecord.partyId] then
                world.parties[personRecord.partyId].members[personRecord.id] = nil
            end
            world.parties[partyId].members[personRecord.id], personRecord.partyId, personRecord.duty =
                true, partyId, "follow"
        else
            if personRecord.partyId and world.parties[personRecord.partyId] then
                world.parties[personRecord.partyId].members[personRecord.id] = nil
            end
            personRecord.partyId, personRecord.duty = nil, "base"
        end
        touch(personRecord)
    end
    return success(reason, { members = members })
end

handlers["friendly_fire.set"] = function(world, command, context)
    if type(command.enabled) ~= "boolean" then
        return fail "invalid_friendly_fire"
    end
    local personRecord = person(world, command.personId)
    if not personRecord or not FriendlyFire.canSet(world, command.personId, context.actorId) then
        return fail "not_authorised"
    end
    if
        not personRecord.available
        or personRecord.life == "dead"
        or personRecord.transitionId
        or personRecord.reservationId
    then
        return fail "person_unavailable"
    end
    local proof = evidence(context, "conversation")
    if
        not proof
        or proof.personId ~= command.personId
        or proof.actorId ~= context.actorId
        or not proof.inReach
        or not proof.known
    then
        return fail "conversation_unconfirmed"
    end
    personRecord.friendlyFire = command.enabled
    touch(personRecord)
    return success("friendly_fire_updated", {
        message = command.enabled and "Friendly fire enabled. Attacks will damage your relationship."
            or "Friendly fire disabled. This person is protected from friendly player weapon hits.",
    })
end

handlers["duty.set"] = function(world, command, context)
    local personRecord, actor = person(world, command.personId), person(world, context.actorId)
    if not canCommand(world, personRecord, actor) then
        return fail "not_authorised"
    end
    if
        not alive(personRecord)
        or not personRecord.available
        or locked(personRecord)
        or personRecord.missionId
        or personRecord.jobId
    then
        return fail "person_unavailable"
    end
    if command.duty ~= "wait" and command.duty ~= "follow" and command.duty ~= "base" then
        return fail "unsupported_duty"
    end
    if command.duty == "follow" and not personRecord.partyId then
        return fail "travel_agreement_required"
    end
    local members = SocialGroup.members(world, personRecord.id, true)
    if command.duty == "base" or command.duty == "follow" then
        local accepted, reason =
            Core.decide(world, personRecord.id, actor.id, command.duty == "base" and "resident" or "travel")
        if not accepted then
            return fail(reason)
        end
    end
    for _, id in ipairs(members) do
        local member = person(world, id)
        if
            not canCommand(world, member, actor)
            or not member.available
            or member.life ~= "alive"
            or locked(member)
            or member.missionId
            or member.jobId
            or hasTransfer(world, id)
            or command.duty == "follow" and not member.partyId
        then
            return fail "group_not_ready"
        end
    end
    for _, id in ipairs(members) do
        local member = person(world, id)
        member.duty = command.duty
        touch(member)
    end
    return success "duty_requested"
end

-- Missions
handlers["mission.propose"] = function(world, command, context)
    local actor = person(world, context.actorId)
    if
        not actor
        or not isText(command.missionId)
        or world.missions[command.missionId]
        or not isText(command.objective)
        or not isText(command.destination)
        or not isText(command.safeEndpoint)
        or type(command.deathPossible) ~= "boolean"
        or type(command.participants) ~= "table"
        or #command.participants == 0
        or type(command.operatingLimits) ~= "table"
        or type(command.retreatRules) ~= "table"
    then
        return fail "invalid_proposal"
    end
    local participants = {}
    for _, id in ipairs(command.participants) do
        local personRecord = person(world, id)
        if
            participants[id]
            or not canCommand(world, personRecord, actor)
            or not alive(personRecord)
            or not personRecord.available
            or personRecord.missionId
            or personRecord.jobId
            or locked(personRecord)
            or hasTransfer(world, id)
        then
            return fail "participant_unavailable"
        end
        participants[id] = true
    end
    world.missions[command.missionId] = {
        id = command.missionId,
        revision = 0,
        proposedBy = actor.id,
        objective = command.objective,
        destination = command.destination,
        safeEndpoint = command.safeEndpoint,
        participants = participants,
        deathPossible = command.deathPossible,
        operatingLimits = copy(command.operatingLimits),
        retreatRules = copy(command.retreatRules),
        stage = "proposed",
        acceptedRisk = false,
        progress = 0,
        cargoDelivered = false,
    }
    return success("assignment_proposed", { missionId = command.missionId })
end

handlers["mission.authorise"] = function(world, command, context)
    local m, actor = world.missions[command.missionId], person(world, context.actorId)
    if not m or m.stage ~= "proposed" then
        return fail "proposal_required"
    end
    if m.proposedBy ~= context.actorId or not alive(actor) then
        return fail "not_authorised"
    end
    if m.deathPossible and command.acceptRisk ~= true then
        return fail "explicit_risk_acceptance_required"
    end
    for id in pairs(m.participants) do
        local personRecord = person(world, id)
        if
            not canCommand(world, personRecord, actor)
            or personRecord.missionId
            or personRecord.jobId
            or hasTransfer(world, id)
        then
            return fail "participant_unavailable"
        end
        local accepted, reason = Core.decide(world, id, actor.id, "mission", m.deathPossible)
        if not accepted then
            return fail(reason, id)
        end
    end
    m.stage, m.acceptedRisk, m.authorisedBy, m.authorisedRole = "authorised", m.deathPossible, actor.id, "commander"
    m.authorisedAt, m.revision = context.gameTime, m.revision + 1
    for id in pairs(m.participants) do
        world.people[id].missionId = m.id
        touch(world.people[id])
    end
    return success "assignment_authorised"
end

handlers["mission.depart"] = function(world, command, context)
    local m, proof = world.missions[command.missionId], evidence(context, "mission_departure")
    if
        not context.system
        or not proof
        or proof.missionId ~= command.missionId
        or type(proof.participants) ~= "table"
    then
        return fail "departure_unconfirmed"
    end
    if not m or m.stage ~= "authorised" then
        return fail "authorised_assignment_required"
    end
    for id in pairs(m.participants) do
        local personRecord = person(world, id)
        if not alive(personRecord) or not personRecord.available or locked(personRecord) or hasTransfer(world, id) then
            return fail "participant_unavailable"
        end
        if proof.participants[id] ~= true then
            return fail "departure_participant_unconfirmed"
        end
    end
    m.stage, m.startedAt, m.revision = "away", context.gameTime, m.revision + 1
    return success "assignment_departed"
end

handlers["mission.recall"] = function(world, command, context)
    local m = world.missions[command.missionId]
    if not m or m.authorisedBy ~= context.actorId then
        return fail "not_authorised"
    end
    if m.stage == "authorised" then
        m.stage = "cancelled"
        for id in pairs(m.participants) do
            world.people[id].missionId = nil
            touch(world.people[id])
        end
    elseif m.stage == "away" or m.stage == "returning" then
        m.stage = "returning"
    else
        return fail "assignment_not_recallable"
    end
    m.revision = m.revision + 1
    return success(m.stage == "cancelled" and "cancelled_before_departure" or "return_requested_risk_continues")
end

handlers["mission.safe_return"] = function(world, command, context)
    local m, proof = world.missions[command.missionId], evidence(context, "safe_return")
    if not context.system or not proof or proof.missionId ~= command.missionId or proof.safe ~= true then
        return fail "safety_unconfirmed"
    end
    if not m or (m.stage ~= "away" and m.stage ~= "returning") or proof.endpoint ~= m.safeEndpoint then
        return fail "return_endpoint_mismatch"
    end
    if type(proof.participants) ~= "table" or empty(proof.participants) then
        return fail "participants_unconfirmed"
    end
    -- Partial returns close risk per person; missing participants retain their own
    -- agreement. Unloading and debrief are independent of the safety boundary.
    m.safeParticipants = m.safeParticipants or {}
    for id, returned in pairs(proof.participants) do
        if returned ~= true or not m.participants[id] or not alive(person(world, id)) then
            return fail "invalid_return_participant"
        end
        if not m.safeParticipants[id] then
            if world.people[id].missionId ~= m.id then
                return fail "participant_assignment_changed"
            end
            m.safeParticipants[id] = true
            world.people[id].missionId = nil
            touch(world.people[id])
        end
    end
    local everyoneResolved = true
    for id in pairs(m.participants) do
        if alive(person(world, id)) and not m.safeParticipants[id] then
            everyoneResolved = false
        end
    end
    if everyoneResolved then
        m.stage, m.safeAt = "safe", context.gameTime
    end
    m.revision = m.revision + 1
    return success("return_safety_recorded", { cargoPending = not m.cargoDelivered })
end

handlers["mission.record_cargo"] = function(world, command, context)
    local m, proof = world.missions[command.missionId], evidence(context, "mission_cargo")
    if
        not context.system
        or not proof
        or proof.missionId ~= command.missionId
        or not m
        or (m.stage ~= "away" and m.stage ~= "returning")
        or type(command.items) ~= "table"
    then
        return fail "cargo_unconfirmed"
    end
    m.cargo, m.deliveredItems = m.cargo or {}, m.deliveredItems or {}
    for _, id in ipairs(command.items) do
        local item = world.items[id]
        local inventory = item and world.inventories[item.owner]
        if
            not item
            or item.lock
            or not inventory
            or (item.owner ~= "mission:" .. m.id and not (inventory.personId and m.participants[inventory.personId]))
        then
            return fail "cargo_not_owned_by_mission"
        end
        if m.deliveredItems[id] then
            return fail "cargo_already_delivered"
        end
        m.cargo[id] = true
    end
    m.cargoDelivered, m.revision = empty(m.cargo), m.revision + 1
    return success "observed_cargo_recorded"
end

-- Injuries and death
handlers["mortality.observe"] = function(world, command, context)
    local proof = evidence(context, "condition")
    if not context.system or not proof or proof.personId ~= command.personId then
        return fail "condition_unconfirmed"
    end
    local personRecord = person(world, command.personId)
    if not alive(personRecord) then
        return fail "person_not_alive"
    end
    if personRecord.controller.kind == "player" then
        return fail "use_native_player_death"
    end
    if personRecord.transitionId then
        return fail "representation_unresolved"
    end
    local owner = personRecord.representation.owner
    if
        (command.source == "native" and owner ~= "engine")
        or (command.source == "abstract" and owner ~= "record")
        or (command.source ~= "native" and command.source ~= "abstract")
    then
        return fail "wrong_state_authority"
    end
    if type(command.condition) ~= "table" or not isText(command.cause) then
        return fail "condition_required"
    end
    local policy = Core.mortalityPolicy(world, personRecord.id, proof.relevance)
    if
        command.fatal == true
        and (not policy.mayDie or personRecord.protectionHold)
        and command.source == "native"
        and proof.fatalTransitionPrevented ~= true
    then
        return fail "native_protection_not_enforced"
    end
    personRecord.character.condition = copy(command.condition)
    if command.fatal == true then
        if policy.mayDie and not personRecord.protectionHold then
            personRecord.life, personRecord.available = "dead", false
            personRecord.death = {
                confirmed = true,
                cause = command.cause,
                gameTime = context.gameTime,
                permission = policy.reason,
                missionId = policy.missionId,
            }
            personRecord.missionId = nil
        else
            personRecord.life, personRecord.available, personRecord.protectionHold = "critical", false, true
            personRecord.incident = {
                cause = command.cause,
                fatalHeld = true,
                reason = policy.reason,
                location = copy(personRecord.location),
                gameTime = context.gameTime,
            }
        end
    end
    touch(personRecord)
    return success(
        personRecord.life == "dead" and "death_recorded"
            or (personRecord.protectionHold and "critical_held" or "condition_recorded"),
        { policy = policy }
    )
end

handlers["condition.release_hold"] = function(world, command, context)
    local personRecord, proof = person(world, command.personId), evidence(context, "intervention_opportunity")
    if not context.system or not proof or proof.personId ~= command.personId or proof.opportunityProvided ~= true then
        return fail "intervention_unconfirmed"
    end
    if not alive(personRecord) or not personRecord.protectionHold or locked(personRecord) then
        return fail "no_protected_condition"
    end
    local relevance = Core.inspectRelevance(world, personRecord.id, proof.relevance)
    if not relevance or not relevance.relevant then
        return fail "active_intervention_required"
    end
    personRecord.protectionHold = nil
    touch(personRecord)
    return success "hold_released_condition_preserved"
end

handlers["player.death"] = function(world, command, context)
    local personRecord, proof = person(world, command.personId), evidence(context, "native_player_death")
    if not context.system or not proof or proof.personId ~= command.personId or proof.isDead ~= true then
        return fail "death_unconfirmed"
    end
    if not alive(personRecord) or personRecord.controller.kind ~= "player" then
        return fail "living_player_required"
    end
    personRecord.life, personRecord.available, personRecord.death =
        "dead", false, { confirmed = true, gameTime = context.gameTime, cause = command.cause or "native" }
    touch(personRecord)
    return success "player_death_confirmed"
end

-- Physical and background representation
handlers["representation.prepare"] = function(world, command, context)
    local personRecord = person(world, command.personId)
    if
        not context.system
        or not capabilities(context, { "faithfulState", command.target == "physical" and "materialize" or "abstract" })
    then
        return fail "adapter_capability_unproven"
    end
    if
        not alive(personRecord)
        or personRecord.controller.kind ~= "ai"
        or locked(personRecord)
        or personRecord.jobId
        or hasTransfer(world, command.personId)
    then
        return fail "person_unavailable"
    end
    if
        (command.target == "physical" and personRecord.representation.mode ~= "abstract")
        or (command.target == "abstract" and personRecord.representation.mode ~= "physical")
        or (command.target ~= "physical" and command.target ~= "abstract")
    then
        return fail "invalid_representation_transition"
    end
    if personRecord.protectionHold and not capabilities(context, { "criticalStateTransfer" }) then
        return fail "critical_transfer_unproven"
    end
    if command.target == "abstract" then
        local proof = evidence(context, "abstraction_boundary")
        if not proof or proof.personId ~= personRecord.id or proof.interactionPending or proof.vehicleUnsupported then
            return fail "unsafe_abstraction_boundary"
        end
        local rel = Core.inspectRelevance(world, personRecord.id, proof.relevance)
        if not rel or rel.relevant then
            return fail "encounter_still_active"
        end
    end
    world.operations[command.id] = {
        id = command.id,
        kind = "representation",
        personId = personRecord.id,
        target = command.target,
        state = "prepared",
        before = copy(personRecord.representation),
        character = copy(personRecord.character),
        items = ownedItems(world, personRecord.id),
        createdRevision = world.revision + 1,
    }
    personRecord.transitionId = command.id
    touch(personRecord)
    world.operations[command.id].personRevision = personRecord.revision
    return success("representation_prepared", { operationId = command.id })
end

handlers["operation.dispatch"] = function(world, command, context)
    local operation = world.operations[command.operationId]
    if not context.system or not operation or operation.state ~= "prepared" then
        return fail "prepared_operation_required"
    end
    if operation.personId and not alive(person(world, operation.personId)) then
        return fail "person_not_alive"
    end
    if operation.personRevision and person(world, operation.personId).revision ~= operation.personRevision then
        return fail(operation.kind == "succession" and "candidate_changed" or "person_changed")
    end
    operation.state = "dispatched"
    return success("dispatch_recorded_no_replay", { operationId = operation.id })
end

handlers["representation.reconcile"] = function(world, command, context)
    local operation, proof =
        world.operations[command.operationId], evidence(context, "representation_result", command.operationId)
    if not context.system or not proof or not operation or operation.kind ~= "representation" then
        return fail "representation_unconfirmed"
    end
    if operation.terminal then
        return success "operation_already_resolved"
    end
    local personRecord = person(world, operation.personId)
    if proof.outcome == "unknown" then
        operation.state = "unresolved"
        return success "operation_unresolved_no_replay"
    end
    if proof.outcome == "not_applied" and proof.reconciled == true then
        personRecord.transitionId = nil
        finishOperation(world, operation, "cancelled")
        touch(personRecord)
        return success "representation_cancelled"
    end
    if operation.state == "prepared" then
        return fail "dispatch_not_recorded"
    end
    if not alive(personRecord) or personRecord.revision ~= operation.personRevision then
        return fail "person_changed"
    end
    if canonical(ownedItems(world, personRecord.id)) ~= canonical(operation.items) then
        return fail "person_inventory_changed"
    end
    if
        proof.outcome ~= "applied"
        or proof.personId ~= personRecord.id
        or proof.uniqueRepresentation ~= true
        or proof.faithful ~= true
        or type(proof.character) ~= "table"
    then
        return fail "representation_unconfirmed"
    end
    if not inventoryMatches(proof, personRecord.id, operation.items) then
        return fail "inventory_transfer_unconfirmed"
    end
    if operation.target == "physical" and not actorAvailable(world, proof.actorId, personRecord.id) then
        return fail "actor_identity_required"
    end
    if operation.target == "physical" and canonical(proof.character) ~= canonical(operation.character) then
        return fail "state_mismatch"
    end
    if operation.target == "abstract" and proof.actorRemoved ~= true then
        return fail "actor_removal_unconfirmed"
    end
    personRecord.character = copy(proof.character)
    personRecord.representation = {
        mode = operation.target,
        owner = operation.target == "physical" and "engine" or "record",
        actorId = operation.target == "physical" and proof.actorId or nil,
    }
    personRecord.transitionId = nil
    touch(personRecord)
    finishOperation(world, operation, "committed")
    return success "representation_committed"
end

-- Inventory and original-item transfers
handlers["inventory.observe"] = function(world, command, context)
    local proof = evidence(context, "inventory_scan")
    if
        not context.system
        or not proof
        or proof.owner ~= command.owner
        or proof.uniqueItems ~= true
        or not isText(command.owner)
        or type(command.items) ~= "table"
    then
        return fail "inventory_unconfirmed"
    end
    if not world.inventories[command.owner] then
        if command.inventoryKind ~= "container" and command.inventoryKind ~= "mission" then
            return fail "unknown_inventory"
        end
        world.inventories[command.owner] = { kind = command.inventoryKind, location = copy(command.location or {}) }
    end
    local seen, changed = {}, false
    for _, item in ipairs(command.items) do
        if not isText(item.id) or seen[item.id] then
            return fail "invalid_item_identity"
        end
        seen[item.id] = true
        local existing = world.items[item.id]
        if existing and (existing.owner ~= command.owner or existing.lock) then
            return fail "item_ownership_requires_reconciliation"
        end
        if not existing or canonical(existing.data) ~= canonical(item.data or {}) then
            changed = true
        end
        world.items[item.id] = { id = item.id, owner = command.owner, data = copy(item.data or {}) }
    end
    local inventory = world.inventories[command.owner]
    if changed and inventory.personId then
        touch(world.people[inventory.personId])
    end
    return success "observed_items_recorded"
end

handlers["transfer.prepare"] = function(world, command, context)
    local proof = evidence(context, "transfer_access")
    if
        not proof
        or proof.source ~= command.source
        or proof.destination ~= command.destination
        or proof.allowed ~= true
    then
        return fail "transfer_access_unconfirmed"
    end
    if
        command.source == command.destination
        or not world.inventories[command.source]
        or not world.inventories[command.destination]
        or type(command.items) ~= "table"
        or #command.items == 0
    then
        return fail "invalid_transfer"
    end
    for _, owner in ipairs({ command.source, command.destination }) do
        local inventory = world.inventories[owner]
        if inventory.personId then
            local personRecord = person(world, inventory.personId)
            if locked(personRecord) or not alive(personRecord) then
                return fail "person_unavailable"
            end
            if
                not context.system
                and inventory.personId ~= context.actorId
                and not canCommand(world, personRecord, person(world, context.actorId))
            then
                return fail "not_authorised"
            end
        end
    end
    local seen = {}
    local mission = command.missionId and world.missions[command.missionId]
    if command.missionId and (not mission or not mission.cargo) then
        return fail "mission_cargo_required"
    end
    for _, id in ipairs(command.items) do
        local item = world.items[id]
        if seen[id] or not item or item.owner ~= command.source or item.lock then
            return fail "item_unavailable"
        end
        if mission and (not mission.cargo[id] or mission.deliveredItems[id]) then
            return fail "cargo_not_pending"
        end
        seen[id] = true
    end
    world.operations[command.id] = {
        id = command.id,
        kind = "transfer",
        state = "prepared",
        source = command.source,
        destination = command.destination,
        items = copy(command.items),
        createdRevision = world.revision + 1,
        missionId = command.missionId,
    }
    for id in pairs(seen) do
        world.items[id].lock = command.id
    end
    return success("transfer_prepared", { operationId = command.id })
end

handlers["transfer.reconcile"] = function(world, command, context)
    local operation, proof =
        world.operations[command.operationId], evidence(context, "transfer_result", command.operationId)
    if not context.system or not proof or not operation or operation.kind ~= "transfer" then
        return fail "transfer_unconfirmed"
    end
    if operation.terminal then
        return success "operation_already_resolved"
    end
    if proof.outcome == "unknown" then
        operation.state = "unresolved"
        return success "operation_unresolved_no_replay"
    end
    if proof.outcome == "applied" and operation.state == "prepared" then
        return fail "dispatch_not_recorded"
    end
    if
        (proof.outcome ~= "applied" and proof.outcome ~= "not_applied")
        or proof.uniqueItems ~= true
        or type(proof.owners) ~= "table"
    then
        return fail "transfer_unconfirmed"
    end
    local expectedOwner = proof.outcome == "applied" and operation.destination or operation.source
    for _, id in ipairs(operation.items) do
        if proof.owners[id] ~= expectedOwner then
            operation.state, operation.observedOwners = "unresolved", copy(proof.owners)
            return success "partial_transfer_requires_reconciliation"
        end
    end
    for _, id in ipairs(operation.items) do
        world.items[id].owner, world.items[id].lock = expectedOwner, nil
    end
    if proof.outcome == "applied" and operation.missionId then
        local m = world.missions[operation.missionId]
        for _, id in ipairs(operation.items) do
            m.deliveredItems[id] = operation.destination
        end
        m.cargoDelivered = true
        for id in pairs(m.cargo) do
            if not m.deliveredItems[id] then
                m.cargoDelivered = false
            end
        end
        m.revision = m.revision + 1
    end
    finishOperation(world, operation, proof.outcome == "applied" and "committed" or "cancelled")
    return success(proof.outcome == "applied" and "transfer_committed" or "transfer_cancelled")
end

-- Direct trading temporarily registers native items to journal their move.
-- Afterwards the native inventory resumes sole ownership of newly observed
-- entries, so later ordinary eating/reloading cannot leave phantom cargo.
handlers["inventory.release_native"] = function(world, command, context)
    local operation, proof =
        world.operations[command.operationId], evidence(context, "native_inventory_release", command.operationId)
    if
        not context.system
        or not proof
        or proof.uniqueItems ~= true
        or not operation
        or operation.kind ~= "transfer"
        or (operation.state ~= "committed" and operation.state ~= "cancelled")
        or not operation.terminal
        or operation.missionId
        or type(command.items) ~= "table"
    then
        return fail "native_inventory_release_unconfirmed"
    end
    local moved = {}
    for _, id in ipairs(operation.items) do
        moved[id] = true
    end
    local owner = operation.state == "committed" and operation.destination or operation.source
    for _, id in ipairs(command.items) do
        local item = world.items[id]
        if not moved[id] or not item or item.lock or item.owner ~= owner or proof.owners[id] ~= item.owner then
            return fail "native_inventory_release_unconfirmed"
        end
        for _, job in pairs(world.jobs or {}) do
            for _, used in ipairs(job.items or {}) do
                if used == id then
                    return fail "job_item_requires_reconciliation"
                end
            end
        end
        for _, mission in pairs(world.missions) do
            if mission.cargo and mission.cargo[id] then
                return fail "mission_item_requires_reconciliation"
            end
        end
    end
    for _, id in ipairs(command.items) do
        world.items[id] = nil
    end
    return success "native_inventory_ownership_restored"
end

local jobNext = {
    prepared = { outward = true, returning = true },
    outward = { collecting = true, returning = true },
    collecting = { collecting_prepared = true },
    collecting_prepared = { returning = true },
    returning = { home = true },
    home = { storing = true, recalled = true },
    storing = { storing_prepared = true },
    storing_prepared = { completed = true },
}

local function jobItemsAt(world, job, owner)
    for _, id in ipairs(job.items) do
        local item = world.items[id]
        if not item or item.owner ~= owner or item.lock then
            return false
        end
    end
    return true
end

local function jobSafetyClosed(world, job)
    local personRecord = person(world, job.personId)
    if personRecord.missionId then
        return false
    end
    local m = job.missionId and world.missions[job.missionId]
    return not job.missionId
        or (m and (m.stage == "cancelled" or (m.safeParticipants and m.safeParticipants[personRecord.id] == true)))
end
-- Supply jobs
handlers["job.checkpoint"] = function(world, command, context)
    local r, proof = command.record, evidence(context, "job_progress")
    if
        not context.system
        or type(r) ~= "table"
        or not proof
        or proof.jobId ~= r.id
        or proof.personId ~= r.personId
        or proof.phase ~= r.phase
    then
        return fail "job_progress_unconfirmed"
    end
    local personRecord = person(world, r.personId)
    if
        not alive(personRecord)
        or personRecord.controller.kind ~= "ai"
        or locked(personRecord)
        or not isText(r.id)
        or not isText(r.source)
        or not isText(r.destination)
        or type(r.items) ~= "table"
        or #r.items < 1
        or #r.items > 64
        or not jobPhases[r.phase]
        or type(r.recall) ~= "boolean"
        or type(r.safeReturned) ~= "boolean"
    then
        return fail "invalid_job_checkpoint"
    end
    for _, point in ipairs({ r.pickup or false, r.home or false }) do
        if type(point) ~= "table" or not isFinite(point.x) or not isFinite(point.y) or not isFinite(point.z) then
            return fail "job_endpoint_required"
        end
    end
    local seen = {}
    for _, id in ipairs(r.items) do
        if not isText(id) or seen[id] then
            return fail "invalid_job_items"
        end
        seen[id] = true
    end
    for key in pairs(r.items) do
        if not isFinite(key) or key % 1 ~= 0 or key < 1 or key > #r.items then
            return fail "invalid_job_items"
        end
    end
    world.jobs = world.jobs or {} -- Additive optional field; older snapshots remain readable.
    local previous = world.jobs[r.id]
    if personRecord.jobId and personRecord.jobId ~= r.id then
        return fail("worker_job_unresolved", personRecord.jobId)
    end
    if previous then
        if jobTerminal[previous.phase] then
            return fail "job_already_resolved"
        end
        for _, key in ipairs({ "personId", "source", "destination", "items", "pickup", "home" }) do
            if canonical(previous[key]) ~= canonical(r[key]) then
                return fail("job_identity_changed", key)
            end
        end
        if previous.recall and not r.recall or previous.safeReturned and not r.safeReturned then
            return fail "job_progress_reversed"
        end
        if
            r.phase ~= previous.phase
            and r.phase ~= "blocked"
            and r.phase ~= "unknown"
            and not (jobNext[previous.phase] and jobNext[previous.phase][r.phase])
        then
            return fail "job_phase_requires_reconciliation"
        end
        if (previous.phase == "blocked" or previous.phase == "unknown") and r.phase ~= previous.phase then
            return fail "job_phase_requires_reconciliation"
        end
        if previous.transferId and r.transferId ~= previous.transferId then
            local transfer = world.operations[previous.transferId]
            if not transfer or transfer.state ~= "committed" or not transfer.terminal then
                return fail "job_transfer_unreconciled"
            end
        end
    elseif
        (r.phase ~= "prepared" and r.phase ~= "outward" and r.phase ~= "returning")
        or not personRecord.available
        or hasTransfer(world, personRecord.id)
    then
        return fail "initial_job_phase_required"
    end
    local job = copy(r)
    if previous then
        job.missionId = previous.missionId
    else
        job.missionId = personRecord.missionId
    end
    if r.phase == "collecting_prepared" or r.phase == "storing_prepared" then
        local transfer = world.operations[r.transferId]
        local source = r.phase == "collecting_prepared" and r.source or "person:" .. personRecord.id
        local destination = r.phase == "collecting_prepared" and "person:" .. personRecord.id or r.destination
        if
            not transfer
            or transfer.kind ~= "transfer"
            or transfer.state ~= "prepared"
            or transfer.source ~= source
            or transfer.destination ~= destination
            or canonical(transfer.items) ~= canonical(r.items)
        then
            return fail "job_transfer_unconfirmed"
        end
    elseif
        r.transferId
        and (not previous or r.transferId ~= previous.transferId or (r.phase ~= "blocked" and r.phase ~= "unknown"))
    then
        return fail "unexpected_job_transfer"
    end
    if
        r.safeReturned
        and (
            not jobSafetyClosed(world, job)
            or (not (previous and previous.safeReturned) and proof.safeReturnValidated ~= true)
        )
    then
        return fail "job_safe_return_unconfirmed"
    end
    if
        (r.phase == "home" or r.phase == "storing" or r.phase == "storing_prepared" or jobTerminal[r.phase])
        and not r.safeReturned
    then
        return fail "job_safe_return_required"
    end
    if r.phase == "completed" and not jobItemsAt(world, job, r.destination) then
        return fail "job_delivery_unconfirmed"
    end
    job.revision, job.updatedAt = (previous and previous.revision or 0) + 1, context.gameTime
    world.jobs[r.id], personRecord.jobId = job, not jobTerminal[r.phase] and r.id or nil
    touch(personRecord)
    return success("job_checkpointed", { jobId = r.id, jobRevision = job.revision })
end
handlers["job.reconcile"] = function(world, command, context)
    local job = world.jobs and world.jobs[command.jobId]
    local proof = evidence(context, "job_reconciliation")
    if
        not context.system
        or not job
        or not proof
        or proof.jobId ~= command.jobId
        or proof.personId ~= job.personId
        or proof.workerStopped ~= true
        or proof.atSafeEndpoint ~= true
        or proof.uniqueItems ~= true
        or type(proof.itemOwners) ~= "table"
        or (command.outcome ~= "completed" and command.outcome ~= "recalled")
    then
        return fail "job_reconciliation_unconfirmed"
    end
    if jobTerminal[job.phase] then
        return success "job_already_resolved"
    end
    if not jobSafetyClosed(world, job) then
        return fail "job_safe_return_required"
    end
    if job.transferId and (not world.operations[job.transferId] or not world.operations[job.transferId].terminal) then
        return fail "job_transfer_unreconciled"
    end
    for _, id in ipairs(job.items) do
        local item = world.items[id]
        if
            not item
            or item.lock
            or proof.itemOwners[id] ~= item.owner
            or (item.owner ~= job.source and item.owner ~= "person:" .. job.personId and item.owner ~= job.destination)
            or (command.outcome == "completed" and item.owner ~= job.destination)
        then
            return fail "job_inventory_unreconciled"
        end
    end
    job.phase, job.safeReturned, job.revision, job.updatedAt = command.outcome, true, job.revision + 1, context.gameTime
    person(world, job.personId).jobId = nil
    touch(person(world, job.personId))
    return success("job_reconciled", { jobId = job.id, jobRevision = job.revision })
end

handlers["job.resume"] = function(world, command, context)
    local j = world.jobs and world.jobs[command.jobId]
    local proof = evidence(context, "job_resume")
    if
        not context.system
        or not j
        or not proof
        or proof.jobId ~= j.id
        or proof.uniqueItems ~= true
        or type(proof.owners) ~= "table"
        or proof.workerStopped ~= true
    then
        return fail "job_recovery_unconfirmed"
    end
    local personRecord = world.people[j.personId]
    if
        not alive(personRecord)
        or personRecord.controller.kind ~= "ai"
        or locked(personRecord)
        or hasTransfer(world, personRecord.id)
        or personRecord.missionId
    then
        return fail "person_unavailable"
    end
    if jobTerminal[j.phase] then
        return success "job_already_resolved"
    end
    local owner
    for _, id in ipairs(j.items) do
        local item = world.items[id]
        if not item or item.lock or proof.owners[id] ~= item.owner or owner and owner ~= item.owner then
            return fail "job_inventory_unreconciled"
        end
        owner = item.owner
    end
    if owner == j.source and not j.safeReturned then
        j.phase = j.recall and "returning" or "outward"
    elseif owner == "person:" .. personRecord.id then
        j.phase = "returning"
    elseif owner == j.destination and proof.atSafeEndpoint == true then
        j.phase = "completed"
        j.safeReturned = true
    else
        return fail "job_inventory_unreconciled"
    end
    j.transferId = nil
    j.reason = nil
    j.revision = j.revision + 1
    j.updatedAt = context.gameTime
    personRecord.jobId = not jobTerminal[j.phase] and j.id or nil
    touch(personRecord)
    return success("job_resumed_from_native_ownership", { jobId = j.id, phase = j.phase })
end

-- Succession
handlers["succession.reserve"] = function(world, command, context)
    local deceased, candidate = person(world, context.actorId), person(world, command.personId)
    if
        not deceased
        or deceased.life ~= "dead"
        or not deceased.death
        or deceased.death.confirmed ~= true
        or deceased.controller.kind ~= "player"
        or deceased.controller.id ~= context.issuer
        or world.controllers[context.issuer] ~= deceased.id
    then
        return fail "confirmed_player_death_required"
    end
    if not capabilities(context, { "succession", "faithfulState" }) then
        return fail "adapter_capability_unproven"
    end
    if controllerPending(world, context.issuer) then
        return fail "controller_transfer_unresolved"
    end
    local proof = evidence(context, "succession_boundary")
    if
        not proof
        or proof.personId ~= command.personId
        or proof.dueEventsResolved ~= true
        or proof.inventoryReconciled ~= true
    then
        return fail "candidate_state_unresolved"
    end
    if
        not alive(candidate)
        or not candidate.recruited
        or candidate.controller.kind ~= "ai"
        or locked(candidate)
        or candidate.jobId
        or candidate.missionId
        or hasTransfer(world, command.personId)
        or candidate.missing
    then
        return fail "candidate_unavailable"
    end
    if proof.candidateAlive ~= true or proof.personRevision ~= candidate.revision then
        return fail "candidate_life_unconfirmed"
    end
    if
        candidate.commanderId ~= deceased.id
        and (not deceased.communityId or candidate.communityId ~= deceased.communityId)
    then
        return fail "not_your_community"
    end
    if candidate.protectionHold and not capabilities(context, { "criticalStateTransfer" }) then
        return fail "critical_transfer_unproven"
    end
    world.operations[command.id] = {
        id = command.id,
        kind = "succession",
        state = "prepared",
        personId = candidate.id,
        deceasedId = deceased.id,
        controllerId = context.issuer,
        character = copy(candidate.character),
        items = ownedItems(world, candidate.id),
        actorId = candidate.representation.actorId,
        createdRevision = world.revision + 1,
    }
    candidate.reservationId = command.id
    touch(candidate)
    world.operations[command.id].personRevision = candidate.revision
    return success("successor_reserved", { operationId = command.id })
end

handlers["succession.reconcile"] = function(world, command, context)
    local operation, proof =
        world.operations[command.operationId], evidence(context, "succession_result", command.operationId)
    if not context.system or not proof or not operation or operation.kind ~= "succession" then
        return fail "succession_unconfirmed"
    end
    if operation.terminal then
        return success "operation_already_resolved"
    end
    local personRecord = person(world, operation.personId)
    if proof.outcome == "unknown" then
        operation.state = "unresolved"
        return success "operation_unresolved_no_replay"
    end
    if proof.outcome == "not_applied" and proof.reconciled == true then
        personRecord.reservationId = nil
        touch(personRecord)
        finishOperation(world, operation, "cancelled")
        return success "succession_cancelled"
    end
    if operation.state == "prepared" then
        return fail "dispatch_not_recorded"
    end
    if not alive(personRecord) then
        return fail "candidate_died"
    end
    if personRecord.revision ~= operation.personRevision then
        return fail "candidate_changed"
    end
    if canonical(ownedItems(world, personRecord.id)) ~= canonical(operation.items) then
        return fail "candidate_inventory_changed"
    end
    if
        world.controllers[operation.controllerId] ~= operation.deceasedId
        or not world.people[operation.deceasedId].death.confirmed
    then
        return fail "controller_changed"
    end
    -- A trusted SP adapter can witness the identical live actor and every native
    -- state owner through handover. Normal physiology continues during native
    -- AddCoopPlayer stages; record that observed state instead of echoing the
    -- older reserved snapshot. Reconstructed actors never qualify for this path.
    local continuity = proof.continuity
    local originalNative = capabilities(context, { "sameNativeSuccession" })
        and type(continuity) == "table"
        and isText(operation.actorId)
        and proof.actorId == operation.actorId
        and personRecord.representation.actorId == operation.actorId
        and continuity.kind == "same_native_actor"
        and continuity.personRevision == operation.personRevision
        and continuity.confirmedNativeDeath == true
        and continuity.currentCharacterObserved == true
        and continuity.originalActor == true
        and continuity.originalBody == true
        and continuity.originalXp == true
        and continuity.originalVisual == true
        and continuity.originalInventory == true
        and continuity.originalItems == true
        and continuity.originalDescriptor == true
        and continuity.originalStats == true
        and continuity.originalTraits == true
        and continuity.originalNutrition == true
        and type(proof.character) == "table"
    if
        proof.outcome ~= "applied"
        or proof.personId ~= personRecord.id
        or proof.controllerId ~= operation.controllerId
        or proof.faithful ~= true
        or proof.soleController ~= true
        or proof.soleInventory ~= true
        or not actorAvailable(world, proof.actorId, personRecord.id)
        or (not originalNative and canonical(proof.character) ~= canonical(operation.character))
        or not inventoryMatches(proof, personRecord.id, operation.items)
    then
        return fail "faithful_transfer_unconfirmed"
    end
    if originalNative then
        personRecord.character = copy(proof.character)
    end
    personRecord.controller = { kind = "player", id = operation.controllerId }
    personRecord.representation = { mode = "physical", owner = "engine", actorId = proof.actorId }
    personRecord.reservationId, personRecord.protectionHold, personRecord.available = nil, nil, true
    world.controllers[operation.controllerId] = personRecord.id
    touch(personRecord)
    finishOperation(world, operation, "committed")
    return success("succession_committed", { personId = personRecord.id })
end

handlers["behaviour.observe"] = Behaviour.advance
handlers["behaviour.interact"] = Behaviour.interact
handlers["behaviour.event"] = Behaviour.event
Population.install(handlers, makePerson)

function Core.apply(world, suppliedCommand, suppliedContext)
    local context = suppliedContext or {}
    if context.authority ~= true or not isText(context.issuer) then
        return fail "authority_required"
    end
    if type(world) ~= "table" or world.schema ~= Core.VERSION or type(suppliedCommand) ~= "table" then
        return fail "invalid_command"
    end
    local safe, command = pcall(copy, suppliedCommand)
    if not safe then
        return fail "plain_command_required"
    end
    if command.worldId ~= world.worldId or command.timelineId ~= world.timelineId then
        return fail "wrong_timeline"
    end
    if
        not isFinite(command.sequence)
        or command.sequence < 1
        or command.sequence % 1 ~= 0
        or command.id ~= context.issuer .. ":" .. tostring(command.sequence)
    then
        return fail "invalid_command_identity"
    end
    local prior, signature = world.issuers[context.issuer], canonical(command)
    if prior and command.sequence <= prior.sequence then
        local receipt = prior.receipts[command.sequence]
        if receipt and receipt.signature == signature then
            local result = copy(receipt.result)
            result.duplicate = true
            return result
        end
        return fail(receipt and "command_identity_reused" or "retired_command")
    end
    if command.sequence ~= (prior and prior.sequence or 0) + 1 then
        return fail "command_sequence_gap"
    end
    if command.expectedRevision ~= world.revision then
        return fail("stale_revision", world.revision)
    end
    if not context.system then
        local actor = person(world, context.actorId)
        if
            not actor
            or actor.controller.kind ~= "player"
            or actor.controller.id ~= context.issuer
            or world.controllers[context.issuer] ~= actor.id
        then
            return fail "authenticated_character_required"
        end
        if not alive(actor) and command.kind ~= "succession.reserve" then
            return fail "living_character_required"
        end
    end
    if not isFinite(context.gameTime) or context.gameTime < 0 then
        return fail "game_time_required"
    end
    local handler = handlers[command.kind]
    if not handler then
        return fail "unknown_command"
    end
    local working = copy(world)
    local ok, result = pcall(handler, working, command, context)
    if not ok then
        return fail "invalid_command_data"
    end
    if not result.ok then
        return result
    end
    working.revision = world.revision + 1
    result.revision = working.revision
    local ledger = working.issuers[context.issuer] or { sequence = 0, receipts = {} }
    ledger.sequence = command.sequence
    ledger.receipts[command.sequence] = { signature = signature, result = copy(result) }
    ledger.receipts[command.sequence - Core.RECEIPTS] = nil
    working.issuers[context.issuer] = ledger
    for key in pairs(world) do
        world[key] = nil
    end
    for key, value in pairs(working) do
        world[key] = value
    end
    return result
end

return Core
