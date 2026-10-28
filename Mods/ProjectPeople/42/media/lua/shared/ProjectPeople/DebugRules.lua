-- Journalled debug changes remain separate from ordinary cooperation rules.
local Dev = require "ProjectPeople/DevTools"
local Mind = require "ProjectPeople/Behaviour/Mind"
local Population = require "ProjectPeople/Population/Rules"
local Party = require "ProjectPeople/Party"
local Rules = {}
Rules.presets = { current = true, outbreak = true, aftermath = true, long_term = true }
Rules.requests = {
    ["debug.spawn"] = { preset = true, size = true, x = true, y = true, z = true },
    ["debug.person"] = { personId = true, action = true, value = true },
}

local function fail(code)
    return { ok = false, code = code }
end

local function proof(world, context)
    local e = context.evidence
    local actor = e and world.people[e.actorId]
    return context.system
            and e
            and e.kind == "npc_debug"
            and e.validated == true
            and actor
            and actor.controller.kind == "player"
            and actor.life == "alive"
            and e
        or nil
end

local function detach(world, person)
    if person.partyId and world.parties[person.partyId] then
        world.parties[person.partyId].members[person.id] = nil
    end
    person.partyId = nil
end

function Rules.install(handlers, makePerson)
    handlers["debug.spawn"] = function(world, command, context)
        local e = proof(world, context)
        if not e or not Rules.presets[command.preset] or not e.sites or #e.sites ~= command.size then
            return fail "debug_spawn_unconfirmed"
        end
        if command.size ~= 1 and command.size ~= 2 and command.size ~= 3 then
            return fail "debug_spawn_size"
        end
        if not Dev.isFinite(e.days) or e.days < 0 then
            return fail "debug_spawn_age"
        end
        return Population.debugSpawn(world, e.sites, e.days, context.gameTime, makePerson, e.currentDays)
    end
    handlers["debug.person"] = function(world, command, context)
        local e = proof(world, context)
        local p = world.people[command.personId]
        if not e or e.personId ~= command.personId or e.spawned ~= true then
            return fail "debug_person_unconfirmed"
        end
        if not p or p.controller.kind ~= "ai" or p.life ~= "alive" or not p.available then
            return fail "person_unavailable"
        end
        if p.reservationId or p.transitionId or p.jobId or p.missionId then
            return fail "debug_person_busy"
        end
        for _, transfer in pairs(world.operations) do
            if
                transfer.kind == "transfer"
                and not transfer.terminal
                and (transfer.source == "person:" .. p.id or transfer.destination == "person:" .. p.id)
            then
                return fail "debug_person_busy"
            end
        end
        local action = command.action
        if action == "trust" then
            if not Dev.isFinite(command.value) or command.value < -100 or command.value > 100 then
                return fail "debug_trust_range"
            end
            local relation = p.relationships[e.actorId]
                or { trust = 0, affection = 0, respect = 0, fear = 0, anchors = {} }
            relation.trust = command.value
            p.relationships[e.actorId] = relation
        elseif action == "recruit" then
            if not Party.fits(world, e.actorId, { p.id }, context.followerLimit) then
                return fail "follower_limit"
            end
            detach(world, p)
            local partyId = "party:" .. e.actorId
            world.parties[partyId] = world.parties[partyId] or { id = partyId, leaderId = e.actorId, members = {} }
            world.parties[partyId].members[p.id] = true
            p.recruited, p.commanderId, p.partyId, p.duty = true, e.actorId, partyId, "follow"
        elseif action == "release" then
            detach(world, p)
            p.recruited, p.commanderId, p.duty = false, nil, nil
        elseif action == "follow" or action == "wait" or action == "base" then
            if p.commanderId ~= e.actorId then
                return fail "debug_recruit_first"
            end
            if action == "follow" and not p.partyId then
                if not Party.fits(world, e.actorId, { p.id }, context.followerLimit) then
                    return fail "follower_limit"
                end
                local partyId = "party:" .. e.actorId
                world.parties[partyId] = world.parties[partyId] or { id = partyId, leaderId = e.actorId, members = {} }
                world.parties[partyId].members[p.id], p.partyId = true, partyId
            end
            if action == "base" then
                local home = world.people[e.actorId].communityHome
                if not Party.home(home) then
                    return fail "home_required"
                end
                p.home = Dev.copy(home)
                detach(world, p)
            end
            p.duty = action
        elseif action == "calm" or action == "strain" or action == "panic" then
            local mind = Mind.ensure(p, context.gameTime)
            if action == "calm" then
                mind.strain, mind.stress, mind.loneliness, mind.morale = 0, 0, 0, 75
            elseif action == "strain" then
                mind.strain = 90
            else
                mind.stress = 95
            end
        elseif action == "health" then
            if command.value ~= 100 and command.value ~= 25 then
                return fail "debug_health_range"
            end
        else
            return fail "debug_action_unknown"
        end
        p.debugLastAction = { action = action, value = command.value, by = e.actorId, at = context.gameTime }
        p.revision = p.revision + 1
        return {
            ok = true,
            code = "debug_person_updated",
            personId = p.id,
            message = "Debug: " .. action .. " applied to " .. p.name .. ".",
        }
    end
end

return Rules
