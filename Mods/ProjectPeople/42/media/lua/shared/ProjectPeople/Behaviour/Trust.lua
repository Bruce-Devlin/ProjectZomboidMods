-- Directed trust policy and bounded travel evidence; no native movement.
local DevTools = require "ProjectPeople/DevTools"
local Trust = {}
local isFinite = DevTools.isFinite

function Trust.requirement(p, request)
    local preferences = p.preferences or {}
    if p.populationGroup then
        -- Applies to existing regional people too. Authored household contracts
        -- retain their explicit thresholds. Four in five generated identities
        -- consider a trial journey without an existing relationship.
        local hash = 17
        for i = 1, #p.id do
            hash = (hash * 31 + string.byte(p.id, i)) % 65521
        end
        if request == "resident" then
            return 10
        end
        return hash % 5 == 0 and 10 or 0
    end
    return request == "resident" and (preferences.residentTrust or 0) or (preferences.travelTrust or 0)
end

function Trust.summary(p, visitor)
    local rel = p.relationships[visitor] or {}
    local value = rel.trust or 0
    local label = value < 0 and "Distrustful"
        or value < 10 and "Getting acquainted"
        or value < 30 and "Growing trust"
        or value < 60 and "Trusting"
        or "Strong trust"
    local travel = rel.anchors and rel.anchors.sharedTravel
    return {
        value = math.floor(value),
        label = label,
        travelHours = travel and travel.hours or 0,
        guidance = value < 0 and "Trust has been damaged. Words alone will not repair it."
            or value < Trust.requirement(p, "travel") and "They need a reason to trust you before they will travel. Respect their decision."
            or "Keep travelling together to build trust. Talking or waiting in place does not earn travel trust.",
    }
end

local function position(p)
    return type(p) == "table" and isFinite(p.x) and isFinite(p.y) and isFinite(p.z)
end

local function moved(a, b)
    if not position(a) or not position(b) or a.z ~= b.z then
        return false
    end
    local d = (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
    return d >= 1 and d <= 80 ^ 2
end

function Trust.observe(world, p, seen, now)
    local leader = p.commanderId and world.people[p.commanderId]
    if not leader or leader.life ~= "alive" or not p.partyId or p.duty ~= "follow" or p.jobId or p.missionId then
        for _, rel in pairs(p.relationships) do
            if rel.anchors and rel.anchors.sharedTravel then
                rel.anchors.sharedTravel.sample = nil
            end
        end
        return
    end
    local rel = p.relationships[leader.id]
    if not rel then
        rel = { trust = 0, affection = 0, respect = 0, fear = 0, anchors = {} }
        p.relationships[leader.id] = rel
    end
    rel.anchors = rel.anchors or {}
    local travel = rel.anchors.sharedTravel or { hours = 0, earned = 0 }
    rel.anchors.sharedTravel = travel
    if not isFinite(now) then
        return
    end
    if travel.lastAt and now <= travel.lastAt then
        if now < travel.lastAt then
            travel.sample = nil
        end
        return
    end
    travel.lastAt = now
    local sample = seen.travel
    local prior = travel.sample
    travel.sample = nil
    if
        type(sample) ~= "table"
        or sample.leaderId ~= leader.id
        or not position(sample.person)
        or not position(sample.leader)
        or seen.threat
        or seen.hurt
        or rel.trust < 0
        or rel.fear >= 60
        or rel.anchors["threat:" .. leader.id]
    then
        return
    end
    if
        sample.person.z ~= sample.leader.z
        or (sample.person.x - sample.leader.x) ^ 2 + (sample.person.y - sample.leader.y) ^ 2 > 144
    then
        return
    end
    travel.sample = { at = now, person = sample.person, leader = sample.leader }
    if
        not prior
        or now <= prior.at
        or now - prior.at > 1 / 3
        or not moved(sample.person, prior.person)
        or not moved(sample.leader, prior.leader)
    then
        return
    end
    travel.hours = math.min(6, travel.hours + math.min(1 / 6, now - prior.at))
    local earned = math.min(30, math.floor(travel.hours * 5 + 0.00001))
    rel.trust = math.min(100, rel.trust + math.max(0, earned - travel.earned))
    travel.earned = earned
end
return Trust
