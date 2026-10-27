-- Bounded native observations and idle movement, called by the one existing
-- coordinator. No separate tick registration or actor ownership.
local Mind = require "ProjectPeople/Behaviour/Mind"
local Body = require "ProjectPeople/PeopleBody"
local Runtime = {}

local function visible(a, b, radius)
    if not a or not b or math.abs(a:getZ() - b:getZ()) > 0.1 then
        return false
    end
    if (a:getX() - b:getX()) ^ 2 + (a:getY() - b:getY()) ^ 2 > radius * radius then
        return false
    end
    local from, to = a:getCurrentSquare(), b:getCurrentSquare()
    return from
        and to
        and not from:isBlockedTo(to)
        and not from:isSomethingTo(to)
        and tostring(
                LosUtil.lineClear(
                    getCell(),
                    from:getX(),
                    from:getY(),
                    from:getZ(),
                    to:getX(),
                    to:getY(),
                    to:getZ(),
                    false
                )
            )
            == "Clear"
end

function Runtime.new()
    local self = { observations = {}, lastAt = nil, optionSignature = nil }
    function self:step(service, bodies, records, online, identity, gameHour)
        local world = service.authority:snapshot()
        local ids, observed = {}, {}
        for id, b in pairs(bodies) do
            if world.people[id] and records[id] and Body.matches(b, records[id]) then
                ids[#ids + 1] = id
            end
        end
        table.sort(ids)
        -- Respect the current physical scene budget; do not delete excess people.
        while #ids > 20 do
            table.remove(ids)
        end
        for _, id in ipairs(ids) do
            observed[id] = Body.observe(bodies[id])
        end
        local humans = {}
        for i = 0, online:size() - 1 do
            local actor = online:get(i)
            local who = not actor:isDead() and identity(actor)
            if who and world.people[who.personId] then
                humans[#humans + 1] = { id = who.personId, actor = actor }
            end
        end
        self.observations = {}
        for _, id in ipairs(ids) do
            local p, b, r = world.people[id], bodies[id], records[id]
            local state = observed[id]
            if not state.dead and state.inWorld and state.personId == id and p.controller.kind == "ai" then
                local seen = {
                    moving = r.mode == "move",
                    resting = r.behaviourResting == true,
                    hurt = state.health < 60,
                    threat = r.attacking == true
                        or r.activity == "Defending against zombies"
                        or r.activity == "Confronting an attacker",
                    family = {},
                }
                for _, otherId in ipairs(ids) do
                    if otherId ~= id and visible(b.actor, bodies[otherId].actor, 6) then
                        local other = observed[otherId]
                        if p.family[otherId] then
                            seen.family[otherId] = other.dead and "dead" or other.health < 60 and "hurt" or "well"
                        end
                        local rel = p.relationships[otherId] or {}
                        if not other.dead and (rel.trust or 0) >= -20 and (rel.fear or 0) < 60 then
                            seen.company = true
                            seen.companionId = seen.companionId or otherId
                        end
                    end
                end
                for _, human in ipairs(humans) do
                    local rel = p.relationships[human.id] or {}
                    if (rel.trust or 0) >= -20 and (rel.fear or 0) < 60 and visible(b.actor, human.actor, 6) then
                        seen.company = true
                    end
                    if
                        p.commanderId == human.id
                        and p.partyId
                        and p.duty == "follow"
                        and visible(b.actor, human.actor, 12)
                    then
                        seen.travel = {
                            leaderId = human.id,
                            person = { x = b.actor:getX(), y = b.actor:getY(), z = b.actor:getZ() },
                            leader = { x = human.actor:getX(), y = human.actor:getY(), z = human.actor:getZ() },
                        }
                    end
                end
                self.observations[id] = seen
            end
        end
        local raw = SandboxVars and SandboxVars.ProjectPeople or {}
        local options = Mind.options(raw)
        local signature = table.concat({
            tostring(options.enabled),
            options.strainRate,
            options.stressRate,
            options.socialRate,
            options.recoveryRate,
            tostring(options.autonomy),
        }, ":")
        if
            not self.lastAt
            or gameHour - self.lastAt >= 1 / 6
            or gameHour < self.lastAt
            or signature ~= self.optionSignature
        then
            local result = service.authority:applySystem("behaviour.observe", {}, {
                evidence = {
                    kind = "survivor_observation",
                    validated = true,
                    people = self.observations,
                    options = raw,
                },
            })
            if not result.ok then
                return nil, result.code
            end
            self.lastAt, self.optionSignature = gameHour, signature
        end
        return service.authority:snapshot()
    end
    function self:idle(id, p, b, r, bodies, records, gameHour)
        r.behaviourVisiting = false
        local seen = self.observations[id] or {}
        local plan = Mind.plan(p, gameHour, seen)
        if not plan then
            return nil
        end
        r.activity = plan.activity
        r.behaviourResting = plan.resting == true
        if plan.targetId then
            local other = bodies[plan.targetId]
            local otherRecord = records[plan.targetId]
            if other and otherRecord and Body.matches(other, otherRecord) and visible(b.actor, other.actor, 6) then
                local sq, from = other.actor:getCurrentSquare(), b.actor:getCurrentSquare()
                -- Social visits stay inside the current room. They never cross
                -- an unobserved doorway or become a remote rescue expedition.
                if from and sq and from:getRoom() and from:getRoom() == sq:getRoom() then
                    r.behaviourVisiting = true
                    if (b.actor:getX() - other.actor:getX()) ^ 2 + (b.actor:getY() - other.actor:getY()) ^ 2 <= 4 then
                        return nil
                    end
                    for _, offset in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
                        local dest = getCell():getGridSquare(sq:getX() + offset[1], sq:getY() + offset[2], sq:getZ())
                        if
                            dest
                            and dest:getRoom() == from:getRoom()
                            and dest:isFree(false)
                            and dest:TreatAsSolidFloor()
                            and not from:isBlockedTo(dest)
                        then
                            return { x = dest:getX() + 0.5, y = dest:getY() + 0.5, z = dest:getZ() }
                        end
                    end
                end
            end
            r.activity = "Watching the surroundings"
            r.behaviourVisiting = false
        end
        return nil
    end
    function self:attacked(service, attacker, victim, identity, records, gameHour)
        if not attacker or not victim or attacker == victim then
            return
        end
        local id = victim:getModData().ProjectPeoplePersonId
        if not id or not records[id] then
            return
        end
        local world = service.authority:snapshot()
        local actorId = attacker:getModData().ProjectPeoplePersonId
        if not actorId then
            -- Only actual registered player bodies can be attributed to people.
            if not instanceof(attacker, "IsoPlayer") then
                return
            end
            local who = identity(attacker)
            actorId = who and who.personId
        end
        if not actorId or not world.people[actorId] then
            return
        end
        local eventId = "harm:" .. id .. ":" .. actorId .. ":" .. tostring(math.floor(gameHour * 6))
        local result = service.authority:applySystem(
            "behaviour.event",
            { personId = id, sourcePersonId = actorId, eventId = eventId },
            {
                evidence = {
                    kind = "survivor_attack",
                    validated = true,
                    personId = id,
                    actorId = actorId,
                    eventId = eventId,
                },
            }
        )
        return result
    end
    return self
end
return Runtime
