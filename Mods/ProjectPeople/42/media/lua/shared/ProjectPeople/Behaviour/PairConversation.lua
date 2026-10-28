local Exchanges = require "ProjectPeople/Content/Conversations"
local Space = require "ProjectPeople/Pathing/CombatSpace"
local Pair = { CHANCE = 35, RADIUS = 3, COOLDOWN = 90000, LINE_MS = 4500 }

local function friendly(person, other)
    local rel = (person.relationships or {})[other] or {}
    local anchors = rel.anchors or {}
    return (rel.trust or 0) >= -20
        and (rel.fear or 0) < 60
        and not anchors["violence:" .. other]
        and not anchors["threat:" .. other]
end

function Pair.eligible(person, record, actor, leader)
    if
        not person
        or not record
        or not actor
        or person.life ~= "alive"
        or not person.controller
        or person.controller.kind ~= "ai"
        or person.jobId
        or person.missionId
        or person.reservationId
        or person.transitionId
        or record.dead
        or record.missing
        or record.transferReserved
        or record.combatActive
        or record.attacking
        or record.fleeing
        or record.retreating
        or record.cautious
        or record.attentionId
        or record.playerAlertTarget
        or actor:isDead()
        or actor:isOnFire()
        or actor:isKnockedDown()
    then
        return false
    end
    local state = actor.getCurrentStateName and tostring(actor:getCurrentStateName()):lower() or ""
    if state:find("climb", 1, true) or state:find("fall", 1, true) then
        return false
    end
    if person.duty == "follow" then
        return leader and not leader:isDead() and not leader:isMoving() and Space.distance(actor, leader) <= 9 or false
    end
    if person.duty == "base" then
        if person.homeWork then
            return record.homeActive == true and person.homeWork.breakKind == "relax"
        end
        local home = person.home
        return home
                and math.abs(actor:getZ() - home.z) < 0.2
                and (actor:getX() - home.x) ^ 2 + (actor:getY() - home.y) ^ 2 <= 4
            or false
    end
    return true
end

function Pair.new(adapters)
    local sessions, members, cooldowns, previous = {}, {}, {}, {}
    local sequence, nextScan, lastNow = 0, 0, 0
    local self = {}
    local function clear(id, records)
        local r = records[id]
        if r and r.socialPartner then
            r.socialPartner, r.socialLine = nil, nil
            -- Another higher-priority action may already own facing.
            if r.activity == "Talking with a survivor" then
                r.faceX, r.faceY = nil, nil
                r.activity, r.retryAt = "Conversation ended", 0
            end
        end
    end
    local function finish(session, records, now)
        for _, id in ipairs(session.ids) do
            clear(id, records)
            members[id] = nil
            cooldowns[id] = now + Pair.COOLDOWN
        end
        sessions[session.id] = nil
    end
    function self:cancel(id, records, now)
        if members[id] then
            finish(members[id], records, now)
        end
    end
    function self:holding(id)
        return members[id] ~= nil
    end
    function self:step(world, bodies, records, humans, now, enabled)
        if now < lastNow then
            for _, session in pairs(sessions) do
                finish(session, records, now)
            end
            cooldowns, nextScan = {}, 0
        end
        lastNow = now
        local eligible, ids = {}, {}
        for id, binding in pairs(bodies) do
            local p, r = world.people[id], records[id]
            if
                enabled
                and p
                and r
                and adapters.matches(binding, r)
                and Pair.eligible(p, r, binding.actor, humans[p.commanderId])
                and not adapters.busy(id)
                and not adapters.danger(id, binding.actor, r, p)
            then
                eligible[id] = true
                ids[#ids + 1] = id
            end
        end
        table.sort(ids)
        local function compatible(a, b)
            return eligible[a]
                and eligible[b]
                and friendly(world.people[a], b)
                and friendly(world.people[b], a)
                and Space.distance(bodies[a].actor, bodies[b].actor) <= Pair.RADIUS ^ 2
                and adapters.clear(bodies[a].actor, bodies[b].actor)
        end
        for _, session in pairs(sessions) do
            local a, b = session.ids[1], session.ids[2]
            if
                not compatible(a, b)
                or now - session.started > 30000
                or world.people[a].duty ~= session.duties[1]
                or world.people[b].duty ~= session.duties[2]
            then
                finish(session, records, now)
            elseif now >= session.nextLine then
                session.line = session.line + 1
                session.nextLine = now + Pair.LINE_MS
                if session.line > #Exchanges[session.exchange] then
                    finish(session, records, now)
                end
            end
        end
        if now >= nextScan then
            nextScan = now + 5000
            for _, a in ipairs(ids) do
                if not members[a] and now >= (cooldowns[a] or 0) then
                    for _, b in ipairs(ids) do
                        if a < b and not members[b] and now >= (cooldowns[b] or 0) and compatible(a, b) then
                            -- A failed roll consumes the opportunity too: no per-tick reroll.
                            cooldowns[a], cooldowns[b] = now + Pair.COOLDOWN, now + Pair.COOLDOWN
                            if adapters.random(100) < Pair.CHANCE then
                                local pick = adapters.random(#Exchanges) + 1
                                if #Exchanges > 1 and (pick == previous[a] or pick == previous[b]) then
                                    pick = pick % #Exchanges + 1
                                end
                                sequence = sequence + 1
                                local session = {
                                    id = sequence,
                                    ids = { a, b },
                                    started = now,
                                    nextLine = now + Pair.LINE_MS,
                                    line = 1,
                                    exchange = pick,
                                    duties = { world.people[a].duty, world.people[b].duty },
                                }
                                sessions[sequence], members[a], members[b] = session, session, session
                                previous[a], previous[b] = pick, pick
                            end
                            break
                        end
                    end
                end
            end
        end
        for _, session in pairs(sessions) do
            for i, id in ipairs(session.ids) do
                local partner = session.ids[3 - i]
                local r, other = records[id], bodies[partner].actor
                if r.mode == "move" then
                    adapters.stop(r)
                end
                r.socialPartner = partner
                r.socialLine = (session.line % 2 == i % 2) and Exchanges[session.exchange][session.line] or nil
                r.faceX, r.faceY = other:getX(), other:getY()
                r.activity, r.behaviourResting = "Talking with a survivor", false
            end
        end
        for id, untilAt in pairs(cooldowns) do
            if not bodies[id] and now >= untilAt then
                cooldowns[id], previous[id] = nil, nil
            end
        end
    end
    return self
end
return Pair
