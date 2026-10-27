-- Ordinary zombie senses do not enumerate zombie-backed people. Bridge only
-- visible local prey. Never pass an IsoZombie to vanilla's player-only bite.
local Space = require "ProjectPeople/Pathing/CombatSpace"
local Body = require "ProjectPeople/PeopleBody"
local Locomotion = require "ProjectPeople/Pathing/Locomotion"
local Threat = { RADIUS = 10, REACH = 0.9, WINDUP = 850, COOLDOWN = 1900 }
local CONTROL = "ProjectPeoplePursuitOriginalUseless"

function Threat.release(z)
    local md = z:getModData()
    if md[CONTROL] ~= nil then
        z:setUseless(md[CONTROL])
        md[CONTROL] = nil
    end
    z:setVariable("ProjectPeoplePreyAttack", false)
end

local function interrupted(z)
    local state = string.lower(tostring(z:getCurrentStateName()))
    return z:isOnFloor()
        or string.find(state, "hit", 1, true)
        or string.find(state, "stagger", 1, true)
        or string.find(state, "fall", 1, true)
        or string.find(state, "getup", 1, true)
        or string.find(state, "climb", 1, true)
end

function Threat.prefer(npcDistance, currentDistance, alreadyChosen)
    return npcDistance <= Threat.RADIUS ^ 2
        and (not currentDistance or npcDistance < currentDistance * (alreadyChosen and 1.15 or 0.75))
end

function Threat.new(hit)
    local assignments = setmetatable({}, { __mode = "k" })
    local simulation = setmetatable({}, { __mode = "k" })
    local self = {}
    function self:plan(zombies, bodies, records, humans, now)
        assert(not isClient(), "threat_authority_only")
        local orders = {}
        for i = 0, zombies:size() - 1 do
            local z = zombies:get(i)
            if
                not z:getModData().ProjectPeoplePersonId
                and not z:isDead()
                and (not z:isUseless() or z:getModData()[CONTROL] == false)
            then
                local old = assignments[z]
                local nearestHuman
                for j = 0, humans:size() - 1 do
                    local h = humans:get(j)
                    local d = Space.distance(z, h)
                    if d <= Threat.RADIUS ^ 2 and not h:isDead() and not h:isGhostMode() and Space.clear(z, h) then
                        nearestHuman = math.min(nearestHuman or math.huge, d)
                    end
                end
                local chosen, best
                for id, b in pairs(bodies) do
                    local r = records[id]
                    local a = b.actor
                    local d = Space.distance(z, a)
                    if
                        r
                        and not r.dead
                        and not r.missing
                        and not r.transferReserved
                        and not a:isDead()
                        and d <= Threat.RADIUS ^ 2
                        and Body.matches(b, r)
                        and Space.clear(z, a)
                        and Locomotion.detects(z, a, r, old and old.actor == a)
                    then
                        if
                            Threat.prefer(d, nearestHuman, old and old.actor == a)
                            and (not best or d < best or d == best and id < chosen.id)
                        then
                            chosen = { id = id, actor = a }
                            best = d
                        end
                    end
                end
                if chosen then
                    local state = old and old.actor == chosen.actor and old or { actor = chosen.actor, ready = now }
                    assignments[z] = state
                    local attacking = best <= Threat.REACH ^ 2 and not interrupted(z) and not z:isNoTeeth()
                    if not attacking then
                        state.contact = nil
                    elseif not state.contact and now >= state.ready then
                        state.contact = now + Threat.WINDUP
                    elseif state.contact and now >= state.contact then
                        state.contact = nil
                        state.ready = now + Threat.COOLDOWN
                        hit(z, chosen.actor, 0.14)
                    end
                    orders[#orders + 1] = {
                        nativeId = z:getOnlineID(),
                        personId = chosen.id,
                        x = chosen.actor:getX(),
                        y = chosen.actor:getY(),
                        z = chosen.actor:getZ(),
                        attack = state.contact ~= nil,
                    }
                    state.order = orders[#orders]
                else
                    assignments[z] = nil
                end
            else
                assignments[z] = nil
            end
        end
        return orders
    end
    function self:update(z, orders, bodies, records, now)
        if z:getModData().ProjectPeoplePersonId then
            return
        end
        local order
        if not isClient() then
            order = assignments[z] and assignments[z].order
        else
            for _, candidate in ipairs(orders or {}) do
                if candidate.nativeId == z:getOnlineID() then
                    order = candidate
                    break
                end
            end
        end
        local b = order and bodies[order.personId]
        local r = order and records[order.personId]
        if not b or not r or not Body.matches(b, r) or b.actor:isDead() or z:isDead() then
            order = nil
        end
        if order then
            local md = z:getModData()
            -- Authority admits only autonomous zombies. A new peer can receive
            -- the temporary true flag in a native packet before this order;
            -- that must not become its permanent state on release.
            if md[CONTROL] == nil then
                md[CONTROL] = false
            end
            -- Vanilla re-spots spottedLast AFTER OnZombieUpdate. Suspend only
            -- autonomous spotting while this visible NPC pursuit is owned;
            -- PathFindState still supplies ordinary collision and locomotion.
            z:setUseless(true)
        else
            Threat.release(z)
        end
        z:setVariable("ProjectPeoplePreyAttack", order and order.attack == true or false)
        if not z:isLocal() then
            simulation[z] = nil
            return
        end
        if interrupted(z) then
            z:setVariable("ProjectPeoplePreyAttack", false)
            simulation[z] = nil
            return
        end
        local state = simulation[z]
        if not order then
            if state then
                Body.stop(z)
                simulation[z] = nil
            end
            return
        end
        -- Clear any native retaliation target: AttackState casts victims to
        -- IsoPlayer. This custom path leaves player combat entirely vanilla.
        z:setTarget(nil)
        if not state or state.personId ~= order.personId then
            Body.stop(z)
            simulation[z] = { personId = order.personId, nextPath = now, pending = true }
            return
        end
        if Space.distance(z, b.actor) <= Threat.REACH ^ 2 then
            if not state.stopped then
                Body.stop(z)
                state.stopped = true
            end
            z:faceThisObject(b.actor)
        elseif state.stopped or now >= state.nextPath then
            state.stopped = false
            state.nextPath = now + 1200
            z:pathToLocationF(order.x, order.y, order.z)
            z:setVariable("bPathfind", true)
            z:setMoving(false)
        end
    end
    function self:inspect(z)
        return assignments[z] and assignments[z].order
    end
    return self
end
return Threat
