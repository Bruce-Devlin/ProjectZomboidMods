-- Death-only succession boundary. Candidate ownership is never inferred from
-- account continuity or a client-side death screen. Native adapters must prove
-- faithful state before the existing Core reservation can be dispatched.
local Core = require "ProjectPeople/Core"
local Succession = { VERSION = 1 }

function Succession.new(config)
    local authority = config.authority
    local self = {}
    local function candidate(world, dead, p)
        if
            not p
            or p.life == "dead"
            or p.controller.kind ~= "ai"
            or not p.recruited
            or p.missing
            or not p.available
        then
            return "candidate_unavailable"
        end
        if p.commanderId ~= dead.id and (not dead.communityId or p.communityId ~= dead.communityId) then
            return "not_your_community"
        end
        if p.reservationId or p.transitionId or p.jobId or p.missionId then
            return "candidate_state_unresolved"
        end
        for _, op in pairs(world.operations) do
            if
                not op.terminal
                and (op.personId == p.id or op.source == "person:" .. p.id or op.destination == "person:" .. p.id)
            then
                return "candidate_state_unresolved"
            end
        end
        if p.protectionHold then
            return "critical_transfer_unproven"
        end
    end
    local function death(caller)
        local identity = config.identity(caller)
        if not identity or not identity.validated or identity.alive then
            return nil, "confirmed_player_death_required"
        end
        local confirmed = authority:confirmDeath(caller)
        if not confirmed.ok then
            return nil, confirmed.code
        end
        local world = authority:snapshot()
        local dead = world.people[identity.personId]
        if
            not dead
            or dead.life ~= "dead"
            or not dead.death
            or not dead.death.confirmed
            or world.controllers[identity.controllerId] ~= dead.id
        then
            return nil, "confirmed_player_death_required"
        end
        return identity, nil, world, dead
    end
    function self:view(caller)
        local who, reason, world, dead = death(caller)
        if not who then
            return { eligible = false, reason = reason, candidates = {} }
        end
        local result = { eligible = true, deceasedId = dead.id, candidates = {} }
        for id, p in pairs(world.people) do
            if
                p.recruited
                and p.controller.kind == "ai"
                and (p.commanderId == dead.id or dead.communityId and p.communityId == dead.communityId)
            then
                local why = candidate(world, dead, p)
                local native
                if not why then
                    native = config.inspect(p, who) or {}
                    if native.ready ~= true then
                        why = native.code or "faithful_native_reconstruction_unproven"
                    end
                end
                result.candidates[#result.candidates + 1] = { id = id, name = p.name, enabled = not why, reason = why }
            end
        end
        table.sort(result.candidates, function(a, b)
            return a.name < b.name
        end)
        return result
    end
    function self:reserve(caller, personId)
        local who, reason, world, dead = death(caller)
        if not who then
            return { ok = false, code = reason }
        end
        local p = world.people[personId]
        local why = candidate(world, dead, p)
        if why then
            return { ok = false, code = why }
        end
        local native = config.inspect(p, who) or {}
        if native.ready ~= true or type(native.proof) ~= "table" or not native.adapter then
            return { ok = false, code = native.code or "faithful_native_reconstruction_unproven" }
        end
        -- The adapter must have reconciled due events and all item owners.
        -- Re-read Core checks inside the authority; the client supplies no proof.
        local reserved = authority:reserveSuccessor(caller, personId, native.proof)
        if not reserved.ok then
            return reserved
        end
        local dispatched = authority:runAdapter(native.adapter, "dispatch", reserved.operationId)
        if not dispatched.ok then
            return dispatched
        end
        return authority:runAdapter(native.adapter, "reconcile", reserved.operationId)
    end
    return self
end
return Succession
