-- Read-only live interaction safety. Does not issue orders or grant combat permission.
local Space = require "ProjectPeople/Pathing/CombatSpace"
local Danger = { MESSAGE = "I can't talk right now", IMMEDIATE_RADIUS = 4, PURSUIT_RADIUS = 8, HOSTILE_RADIUS = 12 }
local kinds = {
    ["conversation.talk"] = true,
    ["behaviour.interact"] = true,
    ["cooperation.request"] = true,
    ["duty.set"] = true,
    ["help.secure_home"] = true,
    ["job.start"] = true,
    ["job.recall"] = true,
    ["job.resume"] = true,
    ["inventory.open"] = true,
    ["inventory.transfer"] = true,
    ["equipment.set"] = true,
    ["gift.open"] = true,
    ["inventory.gift"] = true,
}

function Danger.guards(kind)
    return kinds[kind] == true
end

function Danger.refusal()
    return { ok = false, code = "person_in_danger", message = Danger.MESSAGE }
end

local function hostile(person, id)
    local rel = person and person.relationships and person.relationships[id]
    if not rel then
        return false
    end
    local anchors = rel.anchors or {}
    return anchors["violence:" .. id] ~= nil
        or anchors["threat:" .. id] ~= nil
        or (rel.trust or 0) < -20
        or (rel.fear or 0) >= 60
end

function Danger.check(actor, record, person, zombies, humans, identity, isEnemy, pursuit)
    if not actor or actor:isDead() then
        return false
    end -- availability owns missing/dead bodies
    record = record or {}
    if
        record.combatActive
        or record.attacking
        or record.retreating
        or record.fleeing
        or actor:isOnFire()
        or actor:isKnockedDown()
    then
        return true
    end
    local function near(target, radius)
        return target ~= actor
            and not target:isDead()
            and Space.distance(actor, target) <= radius ^ 2
            and Space.clear(actor, target)
    end
    if zombies then
        for i = 0, zombies:size() - 1 do
            local target = zombies:get(i)
            -- Ordinary distant zombies are background danger, not a reason to
            -- refuse every conversation. A visible acquired pursuit is urgent.
            local pursuing = target:getTarget() == actor or pursuit and pursuit(target)
            if near(target, pursuing and Danger.PURSUIT_RADIUS or Danger.IMMEDIATE_RADIUS) then
                local id = target:getModData().ProjectPeoplePersonId
                if not id or hostile(person, id) or isEnemy and isEnemy(target) then
                    return true
                end
            end
        end
    end
    if humans then
        for i = 0, humans:size() - 1 do
            local target = humans:get(i)
            if near(target, Danger.HOSTILE_RADIUS) then
                if isEnemy and isEnemy(target) then
                    return true
                end
                local who = identity and identity(target)
                if who and who.validated and hostile(person, who.personId) then
                    return true
                end
            end
        end
    end
    return false
end
return Danger
