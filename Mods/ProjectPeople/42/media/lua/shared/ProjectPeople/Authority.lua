-- Validates callers and fields, then journals commands through Core.
-- Trusted callbacks must be synchronous.
local DevTools = require "ProjectPeople/DevTools"
local Core = require "ProjectPeople/Core"
local Codec = require "ProjectPeople/Codec"
local Journal = require "ProjectPeople/Journal"
local Defaults = require "ProjectPeople/Content/Household"
local Authority = { VERSION = 1 }

local function fail(code, detail)
    return { ok = false, code = code, detail = detail }
end

local function isText(value)
    return DevTools.isText(value, 256)
end
local isFinite = DevTools.isFinite

local function fields(list)
    local result = {}
    for word in list:gmatch "%S+" do
        result[word] = true
    end
    return result
end
local requests = {
    ["friendly_fire.set"] = fields "personId enabled",
    ["behaviour.interact"] = fields "personId topic",
    ["cooperation.request"] = fields "personId request",
    ["duty.set"] = fields "personId duty",
    ["mission.propose"] = fields "missionId objective destination safeEndpoint participants deathPossible operatingLimits retreatRules",
    ["mission.authorise"] = fields "missionId acceptRisk",
    ["mission.recall"] = fields "missionId",
}
local observations = {
    ["population.observe"] = true,
    ["population.birth"] = true,
    ["person.discover"] = true,
    ["behaviour.observe"] = true,
    ["behaviour.event"] = true,
    ["mission.depart"] = true,
    ["mission.safe_return"] = true,
    ["mission.record_cargo"] = true,
    ["inventory.observe"] = true,
    ["mortality.observe"] = true,
    ["condition.release_hold"] = true,
    ["representation.prepare"] = true,
    ["operation.dispatch"] = true,
    ["representation.reconcile"] = true,
    ["transfer.reconcile"] = true,
    ["succession.reconcile"] = true,
    ["job.checkpoint"] = true,
    ["job.reconcile"] = true,
    ["person.bind_initial"] = true,
    ["person.checkpoint"] = true,
    ["people.checkpoint"] = true,
    ["transfer.prepare"] = true,
    ["job.resume"] = true,
}
local reserved =
    fields "id sequence kind worldId timelineId expectedRevision issuer actorId authority system evidence capabilities"

local function plainFields(value, allowed)
    if type(value) ~= "table" then
        return nil, "plain_fields_required"
    end
    for key in pairs(value) do
        if not isText(key) or reserved[key] or (allowed and not allowed[key]) then
            return nil, "unsupported_field:" .. tostring(key)
        end
    end
    local encoded, why = Codec.encode(value)
    if not encoded or #encoded > 32768 then
        return nil, why or "request_too_large"
    end
    return Core.snapshot(value)
end

local function binding(config)
    if isClient and isClient() then
        return nil, "authority_only"
    end
    local b = config.binding() or nil
    if
        type(b) ~= "table"
        or b.authority ~= true
        or b.validated ~= true
        or not isText(b.worldId)
        or not isText(b.timelineId)
        or not isText(b.journalName)
    then
        return nil, "native_save_binding_required"
    end
    return { worldId = b.worldId, timelineId = b.timelineId, journalName = b.journalName }
end

local function publish(world, staged)
    for key in pairs(world) do
        world[key] = nil
    end
    for key, value in pairs(staged) do
        world[key] = value
    end
end

function Authority.open(config)
    if
        type(config) ~= "table"
        or type(config.binding) ~= "function"
        or type(config.clock) ~= "function"
        or type(config.authenticate) ~= "function"
    then
        return nil, fail "trusted_authority_callbacks_required"
    end
    local ok, service, problem = pcall(function()
        local bound, why = binding(config)
        if not bound then
            return nil, fail(why)
        end
        local journal, err = Journal.new(bound.journalName, bound.worldId, bound.timelineId, config.io)
        if not journal then
            return nil, fail(err)
        end
        local read = journal:read()
        if not read.ok then
            return nil, read
        end
        local world, lastAck
        if read.empty then
            world = Core.newWorld(bound.worldId, bound.timelineId)
            lastAck = journal:persist(world, "authority_created")
            if not lastAck.ok then
                return nil, lastAck
            end
        else
            local adopted = journal:adopt()
            if not adopted.ok then
                return nil, adopted
            end
            if type(config.recover) ~= "function" then
                return nil, fail "native_recovery_required"
            end
            local verified = config.recover(Core.snapshot(adopted.world), Core.snapshot(bound), Core.snapshot(adopted))
                or nil
            if
                type(verified) ~= "table"
                or verified.validated ~= true
                or verified.worldId ~= bound.worldId
                or verified.timelineId ~= bound.timelineId
                or verified.revision ~= adopted.world.revision
            then
                return nil, fail "native_recovery_required"
            end
            world = adopted.world
        end
        local self = {}
        local blocked, busy, mode
        local function block(code, detail)
            blocked = code
            return fail(code, detail)
        end
        local function currentBinding()
            local current, reason = binding(config)
            if
                not current
                or current.worldId ~= bound.worldId
                or current.timelineId ~= bound.timelineId
                or current.journalName ~= bound.journalName
            then
                return block("native_save_binding_changed", reason)
            end
            return { ok = true }
        end
        local function guarded(kind, fn)
            if blocked then
                return fail("authority_recovery_required", blocked)
            end
            if busy then
                return fail "authority_busy"
            end
            busy, mode = true, kind
            local worked, result = pcall(function()
                local current = currentBinding()
                if not current.ok then
                    return current
                end
                return fn()
            end)
            busy, mode = false, nil
            if not worked then
                return block("authority_callback_failed", tostring(result))
            end
            return result
        end
        local function time()
            local now = config.clock() or nil
            assert(isFinite(now) and now >= 0, "authoritative_game_time_required")
            return now
        end
        local function authenticate(caller, alive)
            local identity = config.authenticate(caller) or nil
            if
                type(identity) ~= "table"
                or identity.validated ~= true
                or not isText(identity.controllerId)
                or not isText(identity.personId)
                or not isText(identity.actorId)
                or type(identity.alive) ~= "boolean"
            then
                return nil, fail "native_identity_unconfirmed"
            end
            if alive and not identity.alive then
                return nil, fail "living_character_required"
            end
            return identity
        end
        local function registered(identity)
            local p = world.people[identity.personId]
            return p
                and p.controller.kind == "player"
                and p.controller.id == identity.controllerId
                and world.controllers[identity.controllerId] == p.id
                and p.representation.mode == "physical"
                and p.representation.actorId == identity.actorId
        end
        local function observe(kind, data, identity, caller)
            if type(config.observe) ~= "function" then
                return nil
            end
            -- Normalize zero-result callbacks as an explicit nil in both Lua
            -- and MoonSharp, whose Void is not a valid argument to type().
            return config.observe(kind, Core.snapshot(data), identity, Core.snapshot(world), caller) or nil
        end
        local function context(identity, system, proof)
            return {
                authority = true,
                issuer = system and "project-people-authority" or identity.controllerId,
                actorId = identity and identity.personId or nil,
                system = system,
                gameTime = time(),
                evidence = proof and proof.evidence,
                capabilities = proof and proof.capabilities,
            }
        end
        local function persist(snapshot, stage, operationId)
            local valid = currentBinding()
            if not valid.ok then
                return valid
            end
            local ack = journal:persist(snapshot, stage, operationId)
            if
                not ack.ok
                or (ack.level ~= "file_readback" and ack.level ~= "world_save_memory")
                or not isText(ack.token)
                or ack.worldId ~= bound.worldId
                or ack.timelineId ~= bound.timelineId
                or ack.revision ~= snapshot.revision
                or ack.stage ~= stage
            then
                return block("authority_persistence_unconfirmed", ack.code or "matching_ack_required")
            end
            valid = currentBinding()
            if not valid.ok then
                return valid
            end
            lastAck = ack
            return ack
        end
        local function commit(staged, stage, result)
            local ack = persist(staged, stage, result.operationId)
            if not ack.ok then
                return ack
            end
            publish(world, staged)
            result.revision, result.persistenceLevel, result.durable = world.revision, ack.level, false
            return result
        end
        local function apply(kind, data, ctx)
            local staged = Core.snapshot(world)
            local result = Core.apply(staged, Core.command(staged, ctx.issuer, kind, data), ctx)
            if not result.ok then
                return result
            end
            return commit(staged, kind, result)
        end
        function self:snapshot()
            return Core.snapshot(world)
        end
        function self:reserveSuccessor(caller, personId, proof)
            return guarded("command", function()
                local identity, why = authenticate(caller, false)
                if not identity then
                    return why
                end
                if identity.alive or not registered(identity) then
                    return fail "confirmed_player_death_required"
                end
                return apply("succession.reserve", { personId = personId }, context(identity, false, proof))
            end)
        end
        function self:status()
            return {
                ready = not blocked,
                blocked = blocked,
                revision = world.revision,
                binding = Core.snapshot(bound),
                lastAcknowledgment = lastAck and Core.snapshot(lastAck),
                nativeWorldAtomic = false,
            }
        end
        function self:registerPlayer(caller)
            return guarded("command", function()
                local identity, reason = authenticate(caller, true)
                if not identity then
                    return reason
                end
                if world.people[identity.personId] then
                    if not registered(identity) or world.people[identity.personId].life == "dead" then
                        return fail "native_identity_changed"
                    end
                    return {
                        ok = true,
                        code = "player_already_registered",
                        personId = identity.personId,
                        revision = world.revision,
                    }
                end
                if not isText(identity.name) then
                    return fail "native_player_name_required"
                end
                local proof = {
                    evidence = {
                        kind = "player_identity",
                        validated = true,
                        personId = identity.personId,
                        controllerId = identity.controllerId,
                        actorId = identity.actorId,
                    },
                }
                return apply("player.register", {
                    person = { id = identity.personId, name = identity.name, character = identity.character or {} },
                    controllerId = identity.controllerId,
                }, context(identity, true, proof))
            end)
        end
        function self:confirmDeath(caller)
            return guarded("command", function()
                local identity, reason = authenticate(caller, false)
                if not identity then
                    return reason
                end
                if not registered(identity) then
                    return fail "native_identity_changed"
                end
                if identity.alive then
                    return fail "death_unconfirmed"
                end
                local p = world.people[identity.personId]
                if p.life == "dead" then
                    return { ok = true, code = "player_death_already_recorded", revision = world.revision }
                end
                local data = { personId = p.id, cause = "native" }
                local proof = observe("player.death", data, identity, caller)
                return apply("player.death", data, context(identity, true, proof))
            end)
        end
        function self:request(caller, kind, data, expectedRevision)
            return guarded("command", function()
                if not requests[kind] then
                    return fail "request_not_supported"
                end
                if expectedRevision ~= world.revision then
                    return fail("stale_revision", world.revision)
                end
                local clean, reason = plainFields(data, requests[kind])
                if not clean then
                    return fail("invalid_request", reason)
                end
                if
                    kind == "mission.propose"
                    and (type(clean.participants) ~= "table" or #clean.participants > Defaults.MAX_PARTICIPANTS)
                then
                    return fail "bounded_participants_required"
                end
                local identity, authError = authenticate(caller, true)
                if not identity then
                    return authError
                end
                if not registered(identity) then
                    return fail "native_identity_changed"
                end
                local proof = (
                    kind == "cooperation.request"
                    or kind == "behaviour.interact"
                    or kind == "friendly_fire.set"
                )
                        and observe(kind, clean, identity, caller)
                    or nil
                return apply(kind, clean, context(identity, false, proof))
            end)
        end
        function self:observe(kind, data)
            return guarded("command", function()
                if not observations[kind] then
                    return fail "observation_not_supported"
                end
                local clean, reason = plainFields(data)
                if not clean then
                    return fail("invalid_observation", reason)
                end
                local proof = observe(kind, clean)
                if type(proof) ~= "table" then
                    return fail "native_observation_required"
                end
                return apply(kind, clean, context(nil, true, proof))
            end)
        end
        -- Trusted runtime entry only. Never route a client kind/observation here.
        function self:applySystem(kind, data, proof)
            return guarded("command", function()
                if not observations[kind] then
                    return fail "observation_not_supported"
                end
                local clean, reason = plainFields(data)
                if not clean then
                    return fail("invalid_observation", reason)
                end
                if type(proof) ~= "table" then
                    return fail "native_observation_required"
                end
                return apply(kind, clean, context(nil, true, proof))
            end)
        end
        function self:checkpointJob(record, proof)
            if proof then
                return self:applySystem("job.checkpoint", { record = record }, proof)
            end
            return self:observe("job.checkpoint", { record = record })
        end
        function self:seedHousehold(home, characters)
            return guarded("command", function()
                if type(home) ~= "table" or not isFinite(home.x) or not isFinite(home.y) or not isFinite(home.z) then
                    return fail "household_home_required"
                end
                local blueprint = Defaults.household({ x = home.x, y = home.y, z = home.z }, characters)
                local staged, ctx, changed = Core.snapshot(world), context(nil, true), false
                local function seed(kind, data)
                    local result = Core.apply(staged, Core.command(staged, ctx.issuer, kind, data), ctx)
                    if result.ok then
                        changed = true
                    end
                    return result
                end
                local members = {}
                for _, p in ipairs(blueprint.people) do
                    members[#members + 1] = p.id
                    if staged.people[p.id] then
                        if staged.people[p.id].name ~= p.name then
                            return fail("household_identity_conflict", p.id)
                        end
                    else
                        p.location = Core.snapshot(blueprint.home)
                        local result = seed("person.create", { person = p })
                        if not result.ok then
                            return result
                        end
                    end
                end
                local community = staged.communities[blueprint.id]
                if community then
                    for _, id in ipairs(members) do
                        if not community.members[id] then
                            return fail("household_membership_conflict", id)
                        end
                    end
                    for _, key in ipairs({ "x", "y", "z" }) do
                        if community.home[key] ~= blueprint.home[key] then
                            return fail "household_home_conflict"
                        end
                    end
                else
                    local result = seed("community.create", {
                        communityId = blueprint.id,
                        name = blueprint.name,
                        members = members,
                        leaderId = blueprint.leaderId,
                        home = blueprint.home,
                    })
                    if not result.ok then
                        return result
                    end
                end
                local f = blueprint.family
                local first, second =
                    staged.people[f.firstId].family[f.secondId], staged.people[f.secondId].family[f.firstId]
                if first or second then
                    if first ~= f.relationship or second ~= f.relationship then
                        return fail "household_family_conflict"
                    end
                else
                    local result = seed("family.link", f)
                    if not result.ok then
                        return result
                    end
                end
                local result = {
                    ok = true,
                    code = changed and "household_seeded" or "household_already_seeded",
                    personIds = members,
                    revision = world.revision,
                }
                return changed and commit(staged, "household.seed", result) or result
            end)
        end
        function self:recordFamilyHelp(caller, eventId)
            return guarded("command", function()
                local identity, reason = authenticate(caller, true)
                if not identity then
                    return reason
                end
                if not registered(identity) or not isText(eventId) then
                    return fail "help_identity_required"
                end
                local data = {
                    personId = "owen",
                    actorId = identity.personId,
                    relatedId = "mara",
                    event = "helped_family",
                    eventId = eventId,
                }
                local proof = observe("social.event", data, identity, caller)
                local e = proof and proof.evidence
                if
                    not e
                    or e.validated ~= true
                    or e.kind ~= "social_event"
                    or e.eventId ~= eventId
                    or e.personId ~= data.personId
                    or e.actorId ~= data.actorId
                    or e.relatedId ~= data.relatedId
                then
                    return fail "help_event_unconfirmed"
                end
                local p = world.people.owen
                local rel = p and p.relationships[identity.personId]
                if rel and rel.anchors[eventId] then
                    return { ok = true, code = "event_already_recorded", revision = world.revision }
                end
                return apply("social.event", data, context(identity, true, proof))
            end)
        end
        -- Only trusted runtime adapters may hold this live table. UI receives a
        -- snapshot. Existing native candidates retain their own unknown locks.
        function self:adapterContext()
            return {
                world = world,
                persist = function(snapshot, stage, operationId)
                    if blocked then
                        return fail("authority_recovery_required", blocked)
                    end
                    if not busy or mode ~= "adapter" then
                        return fail "authority_adapter_scope_required"
                    end
                    return persist(snapshot, stage, operationId)
                end,
            }
        end
        function self:runAdapter(adapter, method, ...)
            local args = { ... }
            return guarded("adapter", function()
                if
                    type(adapter) ~= "table"
                    or (method ~= "prepare" and method ~= "dispatch" and method ~= "reconcile" and method ~= "observe")
                    or type(adapter[method]) ~= "function"
                then
                    return fail "native_adapter_method_required"
                end
                return adapter[method](adapter, unpack(args))
            end)
        end
        return self
    end)
    if not ok then
        return nil, fail("authority_open_failed", tostring(service))
    end
    return service, problem
end
return Authority
