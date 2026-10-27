-- Core command handlers. Only authority observations can advance a mind or
-- record an attack. Client conversations use authenticated reach evidence.
local Mind = require "ProjectPeople/Behaviour/Mind"
local Conversation = require "ProjectPeople/Behaviour/Conversation"
local Trust = require "ProjectPeople/Behaviour/Trust"
local Behaviour = {}

local function proof(context, kind)
    local evidence = context.evidence
    return type(evidence) == "table" and evidence.validated == true and evidence.kind == kind and evidence or nil
end

function Behaviour.advance(world, command, context)
    local evidence = proof(context, "survivor_observation")
    if not context.system or not evidence or type(evidence.people) ~= "table" then
        return { ok = false, code = "behaviour_observation_required" }
    end
    local count = 0
    for id, seen in pairs(evidence.people) do
        count = count + 1
        local person = world.people[id]
        if count > 20 or not person or person.controller.kind ~= "ai" or type(seen) ~= "table" then
            return { ok = false, code = "invalid_behaviour_observation" }
        end
        if person.life ~= "dead" and not person.reservationId and not person.transitionId then
            local ok, why = Mind.advance(person, context.gameTime, seen, evidence.options)
            if not ok then
                return { ok = false, code = why }
            end
            Trust.observe(world, person, seen, context.gameTime)
            person.revision = person.revision + 1
        end
    end
    return { ok = true, code = "behaviour_observed" }
end

function Behaviour.interact(world, command, context)
    local evidence = proof(context, "conversation")
    local person = world.people[command.personId]
    if
        not evidence
        or evidence.personId ~= command.personId
        or evidence.actorId ~= context.actorId
        or not evidence.inReach
        or not evidence.known
    then
        return { ok = false, code = "conversation_unconfirmed" }
    end
    if not person or person.controller.kind ~= "ai" or person.life ~= "alive" then
        return { ok = false, code = "person_unavailable" }
    end
    if person.reservationId or person.transitionId then
        return { ok = false, code = "already_committed" }
    end
    local result = command.topic == "threaten" and Conversation.threaten(person, context.actorId, context.gameTime)
        or Mind.interact(person, context.actorId, command.topic, context.gameTime)
    if result.ok then
        person.revision = person.revision + 1
    end
    return result
end

function Behaviour.event(world, command, context)
    local evidence = proof(context, "survivor_attack")
    if
        not context.system
        or not evidence
        or evidence.personId ~= command.personId
        or evidence.actorId ~= command.sourcePersonId
        or evidence.eventId ~= command.eventId
        or type(command.eventId) ~= "string"
        or #command.eventId > 128
    then
        return { ok = false, code = "behaviour_event_unconfirmed" }
    end
    local person, actor = world.people[command.personId], world.people[command.sourcePersonId]
    if not person or not actor or person.id == actor.id or person.controller.kind ~= "ai" then
        return { ok = false, code = "invalid_behaviour_event" }
    end
    Mind.attacked(person, actor.id, command.eventId, context.gameTime)
    person.revision = person.revision + 1
    return { ok = true, code = "behaviour_event_recorded" }
end
return Behaviour
