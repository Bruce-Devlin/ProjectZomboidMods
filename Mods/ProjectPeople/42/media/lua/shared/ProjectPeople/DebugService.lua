-- Native debug adapter. Only the existing coordinator calls this on authority.
local Access = require "ProjectPeople/DebugAccess"
local Rules = require "ProjectPeople/DebugRules"
local Population = require "ProjectPeople/Population/Rules"
local Body = require "ProjectPeople/PeopleBody"
local Core = require "ProjectPeople/Core"
local Dev = require "ProjectPeople/DevTools"
local Service = {}

-- A server health edit must reach the native simulator, which can be a different
-- player from the caller. Its next native packet otherwise restores old health.
function Service.applyHealth(binding, record, update)
    if
        not binding
        or not record
        or type(update) ~= "table"
        or not Dev.isFinite(update.revision)
        or update.revision < 1
        or update.health ~= 25 and update.health ~= 100
        or record.personId ~= update.personId
        or record.nativeId ~= update.nativeId
        or record.worldId ~= update.worldId
        or not Body.matches(binding, record)
        or binding.actor:isDead()
    then
        return false
    end
    local actor = binding.actor
    local md = actor:getModData()
    if update.revision <= (md.ProjectPeopleDebugHealthRevision or 0) then
        return false
    end
    actor:setHealth(update.health / 100)
    md.ProjectPeopleDebugHealthRevision = update.revision
    md.ProjectPeopleNativeHealth = actor:getHealth()
    record.health, binding.health = actor:getHealth() * 100, actor:getHealth() * 100
    return true
end

function Service.new(config)
    local self = {}
    local function binding(id)
        local b, r = config.bodies[id], config.records[id]
        return b and r and Body.matches(b, r) and not b.actor:isDead() and b.actor:getCurrentSquare() and b or nil
    end
    function self:age(world)
        return world.population and Population.age(world.population, config.clock())
            or config.elapsedDays() + Population.options(config.options()).startDays
    end
    function self:observe(kind, fields, identity, world, caller)
        if not Access.allowed(caller) then
            return nil, "debug_not_allowed"
        end
        local e = { kind = "npc_debug", validated = true, actorId = identity.personId }
        if kind == "debug.person" then
            local b = binding(fields.personId)
            if not b then
                return nil, "person_unavailable"
            end
            if config.healthBusy and config.healthBusy(fields.personId) then
                return nil, "debug_person_busy"
            end
            e.personId, e.spawned = fields.personId, true
        elseif kind == "debug.spawn" then
            if not Rules.presets[fields.preset] then
                return nil, "debug_spawn_preset"
            end
            if fields.size ~= 1 and fields.size ~= 2 and fields.size ~= 3 then
                return nil, "debug_spawn_size"
            end
            if math.floor(caller:getZ()) ~= 0 then
                return nil, "debug_ground_floor_required"
            end
            local loaded = 0
            for id in pairs(config.bodies) do
                if binding(id) then
                    loaded = loaded + 1
                end
            end
            if loaded + fields.size > Population.options(config.options()).physicalLimit then
                return nil, "debug_body_limit"
            end
            local x, y, z = fields.x, fields.y, fields.z
            if x == nil and y == nil and z == nil then
                x, y, z = math.floor(caller:getX()), math.floor(caller:getY()), 0
            elseif
                not Dev.isFinite(x)
                or not Dev.isFinite(y)
                or z ~= 0
                or (x - caller:getX()) ^ 2 + (y - caller:getY()) ^ 2 > 12 ^ 2
            then
                return nil, "debug_spawn_nearby_floor_required"
            end
            local sites, occupied = {}, {}
            local online = config.players()
            for radius = 0, 6 do
                for dx = -radius, radius do
                    for dy = -radius, radius do
                        if #sites < fields.size and (math.abs(dx) == radius or math.abs(dy) == radius) then
                            local sx, sy = math.floor(x) + dx, math.floor(y) + dy
                            local sq = getCell():getGridSquare(sx, sy, 0)
                            local clear = sq
                                and sq:TreatAsSolidFloor()
                                and sq:isFree(false)
                                and (sx + 0.5 - caller:getX()) ^ 2 + (sy + 0.5 - caller:getY()) ^ 2 <= 12 ^ 2
                            for i = 0, online:size() - 1 do
                                local p = online:get(i)
                                if (sx + 0.5 - p:getX()) ^ 2 + (sy + 0.5 - p:getY()) ^ 2 < 2.25 then
                                    clear = false
                                end
                            end
                            local key = sx .. ":" .. sy
                            if clear and not occupied[key] then
                                occupied[key] = true
                                sites[#sites + 1] = { x = sx + 0.5, y = sy + 0.5, z = 0 }
                            end
                        end
                    end
                end
            end
            if #sites ~= fields.size then
                return nil, "debug_no_free_spawn_floor"
            end
            e.sites, e.currentDays = sites, self:age(world)
            e.days = fields.preset == "current" and e.currentDays
                or fields.preset == "outbreak" and 3
                or fields.preset == "aftermath" and 60
                or 365
        else
            return nil, "request_not_supported"
        end
        return { evidence = e }
    end
    function self:request(service, caller, request)
        local result = service.authority:debug(caller, request.kind, request.fields, request.revision)
        if not result.ok then
            return result
        end
        if request.kind == "debug.spawn" then
            local world = service.authority:snapshot()
            for _, id in ipairs(result.members) do
                local p = world.people[id]
                local ok, b, r = pcall(Body.create, p, p.location, result.days)
                if not ok then
                    print("[ProjectPeople] debug native birth outcome unknown for " .. id .. ": " .. tostring(b))
                    return {
                        ok = false,
                        code = "debug_birth_outcome_unknown",
                        members = result.members,
                        message = "Native birth interrupted. The saved identities remain reserved; inspect the log before trying again.",
                    }
                end
                config.bodies[id], config.records[id] = b, r
                r.worldId = config.worldId()
                b.actor:getModData().ProjectPeopleWorldId = r.worldId
                local ack = service:bindInitial(id)
                if not ack.ok then
                    return ack
                end
            end
            result.code = "debug_people_spawned"
            result.message = "Spawned "
                .. #result.members
                .. " new NPC(s), outbreak age "
                .. math.floor(result.days)
                .. " days."
        elseif request.fields.action == "health" then
            local id, value = request.fields.personId, request.fields.value
            local b, r = binding(id), config.records[id]
            if not b then
                return { ok = false, code = "person_unavailable" }
            end
            b.actor:setHealth(value / 100)
            local md = b.actor:getModData()
            md.ProjectPeopleNativeHealth = b.actor:getHealth()
            md.ProjectPeopleHealthRevision = (md.ProjectPeopleHealthRevision or 0) + 1
            r.health = b.actor:getHealth() * 100
            local ack = service.authority:applySystem(
                "person.checkpoint",
                { personId = id, record = Body.checkpoint(r) },
                { evidence = { kind = "person_checkpoint", validated = true, personId = id, uniqueBody = true } }
            )
            if not ack.ok then
                return ack
            end
            if config.publishHealth then
                config.publishHealth({
                    personId = id,
                    nativeId = r.nativeId,
                    worldId = r.worldId,
                    health = value,
                    revision = ack.revision,
                })
            end
            result.message = "Debug: native injury health set to " .. value .. "."
        end
        result.revision = service.authority:snapshot().revision
        return result
    end
    function self:view(authority, caller, diagnostics)
        if not Access.allowed(caller) then
            return { allowed = false }
        end
        local world = authority:snapshot()
        local identity = config.identity(caller)
        local people = {}
        local saved = 0
        for id, p in pairs(world.people) do
            if p.controller.kind == "ai" and p.life ~= "dead" then
                saved = saved + 1
                local b, r = binding(id), config.records[id]
                if b then
                    local actor = b.actor
                    local _, travel = Core.decide(world, id, identity.personId, "travel")
                    local _, resident = Core.decide(world, id, identity.personId, "resident")
                    local group = p.populationGroup and world.population and world.population.groups[p.populationGroup]
                    people[#people + 1] = {
                        id = id,
                        name = p.name,
                        x = actor:getX(),
                        y = actor:getY(),
                        z = actor:getZ(),
                        health = actor:getHealth() * 100,
                        nativeId = r.nativeId,
                        activity = r.activity or "Idle",
                        duty = p.duty,
                        commanderId = p.commanderId,
                        recruited = p.recruited,
                        groupId = p.populationGroup,
                        era = group and group.era,
                        stage = group and group.stage,
                        debug = group and group.debug,
                        trust = p.relationships[identity.personId] and p.relationships[identity.personId].trust or 0,
                        strain = p.mind and p.mind.strain or 0,
                        stress = p.mind and p.mind.stress or 0,
                        travel = travel,
                        resident = resident,
                        busy = p.jobId or p.missionId or p.reservationId or p.transitionId,
                        danger = config.danger and config.danger(id, p) or false,
                    }
                end
            end
        end
        table.sort(people, function(a, b)
            return a.id < b.id
        end)
        return {
            allowed = true,
            people = people,
            revision = world.revision,
            saved = saved,
            outbreakDays = self:age(world),
            physicalLimit = Population.options(config.options()).physicalLimit,
            diagnostics = Dev.copy(diagnostics or {}),
        }
    end
    return self
end

return Service
