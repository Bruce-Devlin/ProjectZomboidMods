-- Routes, follow trails and attention. PeopleBody owns native movement.
local Settings = require "ProjectPeople/Pathing/Settings"
local DevTools = require "ProjectPeople/DevTools"
local Space = require "ProjectPeople/Pathing/CombatSpace"
local Movement = {}
local distanceSquared = DevTools.distanceSquared
local position = DevTools.position

local function permitted(person)
    return person.life == "alive"
        and person.controller.kind == "ai"
        and not person.reservationId
        and not person.transitionId
        and not person.jobId
        and not person.missionId
end

function Movement.clearAttention(movementRecord)
    movementRecord.attentionId = nil
    movementRecord.faceX = nil
    movementRecord.faceY = nil
end

function Movement.attention(person, movementRecord, actor, online, identity)
    local previous = movementRecord.attentionId
    Movement.clearAttention(movementRecord)
    if not permitted(person) or person.duty == "follow" then
        return false
    end
    local best, bestId, bestDistance
    for i = 0, online:size() - 1 do
        local human = online:get(i)
        local who = not human:isDead() and identity(human)
        local rel = who and (person.relationships[who.personId] or {})
        local radius = person.duty == "follow" and 2.5 or 3
        if who and who.personId == previous then
            radius = radius + 1
        end
        local d = Space.distance(actor, human)
        if
            who
            and (rel.trust or 0) >= -20
            and (rel.fear or 0) < 60
            and d <= radius ^ 2
            and Space.clear(actor, human)
            and (not bestDistance or d < bestDistance)
        then
            best, bestId, bestDistance = human, who.personId, d
        end
    end
    if not best then
        return false
    end
    movementRecord.attentionId = bestId
    movementRecord.faceX = best:getX()
    movementRecord.faceY = best:getY()
    movementRecord.activity = "Ready to talk"
    movementRecord.behaviourResting = false
    return true
end

local function walkable(actor, target)
    local cell = getCell()
    local from = actor:getCurrentSquare()
    local sq = cell:getGridSquare(math.floor(target.x), math.floor(target.y), math.floor(target.z))
    if
        not from
        or not sq
        or not sq:TreatAsSolidFloor()
        or not sq:isFree(false)
        or sq:isWaterSquare()
        or sq:isVehicleIntersecting()
        or not SafeHouse
        or SafeHouse.isSafeHouse(sq, nil, false)
        or from:isBlockedTo(sq)
        or from:isSomethingTo(sq)
    then
        return nil
    end
    if
        tostring(LosUtil.lineClear(cell, from:getX(), from:getY(), from:getZ(), sq:getX(), sq:getY(), sq:getZ(), false))
        ~= "Clear"
    then
        return nil
    end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if instanceof(object, "IsoThumpable") then
            return nil
        end
        if object:hasModData() then
            for key in pairs(object:getModData()) do
                if type(key) == "string" and string.sub(key, 1, 5) == "need:" then
                    return nil
                end
            end
        end
    end
    return { x = sq:getX() + 0.5, y = sq:getY() + 0.5, z = sq:getZ(), shelter = sq:getBuilding() ~= nil }
end

function Movement.new(adapters)
    adapters = adapters or {}
    local validate = adapters.walkable or walkable
    local states = {}
    local trails, followers, glances = {}, {}, {}
    local self = {}
    -- One bounded history per registered living human, sampled by the existing
    -- authority tick. Neither trails nor glance timers enter durable person data.
    function self:sampleLeaders(humans, now)
        for id in pairs(trails) do
            if not humans[id] then
                trails[id] = nil
            end
        end
        for id, human in pairs(humans) do
            local at = position(human)
            at.z = math.floor(at.z)
            local trail = trails[id]
            local last = trail and trail.points[#trail.points]
            if
                not trail
                or trail.actor ~= human
                or last
                    and (distanceSquared(at, last) > Settings.follow.resetDistance ^ 2 or math.abs(at.z - last.z) > 1)
            then
                trail = { actor = human, points = {}, sequence = 0 }
                trails[id] = trail
                last = nil
            end
            if not last or distanceSquared(at, last) >= Settings.follow.sampleDistance ^ 2 or at.z ~= last.z then
                trail.sequence = trail.sequence + 1
                at.sequence = trail.sequence
                at.at = now
                trail.points[#trail.points + 1] = at
            end
            while
                #trail.points > Settings.follow.trailLimit
                or #trail.points > 1 and now - trail.points[1].at > Settings.follow.trailAgeMs
            do
                table.remove(trail.points, 1)
            end
        end
    end
    function self:clearFollower(id)
        followers[id] = nil
    end
    function self:follow(person, movementRecord, actor, leader, now)
        if not permitted(person) or person.duty ~= "follow" or not leader or leader:isDead() then
            followers[person.id] = nil
            movementRecord.activity = "Waiting for companion"
            return nil
        end
        local trail = trails[person.commanderId]
        if not trail then
            return nil
        end
        local points = trail.points
        local origin = position(actor)
        local gap = movementRecord.cautious and Settings.follow.cautiousGap or Settings.follow.gap
        movementRecord.activity = movementRecord.cautious and "Following closely" or "Following"
        local state = followers[person.id]
        if not state or state.trail ~= trail then
            state = { trail = trail }
            followers[person.id] = state
        end
        if Space.distance(actor, leader) <= gap ^ 2 and Space.clear(actor, leader) then
            state.target = nil
            state.cursor = points[#points].sequence
            return nil
        end
        -- A U-turn can leave an unconsumed waypoint behind the human. Rejoin
        -- the newer trail when that waypoint leads away across clear ground;
        -- retain bends/obstacles when a direct connection is not walkable.
        if
            state.target
            and distanceSquared(state.target, position(leader)) > distanceSquared(origin, position(leader)) + 1
            and validate(actor, position(leader))
        then
            local nearest, best
            for i, point in ipairs(points) do
                local d = distanceSquared(origin, point)
                if
                    point.sequence > state.target.sequence
                    and math.abs(point.z - origin.z) < 0.2
                    and (not best or d <= best)
                then
                    nearest = i
                    best = d
                end
            end
            if nearest then
                state.cursor = points[nearest].sequence
                state.target = nil
            end
        end
        -- Join at the nearest same-floor footprint, then consume in order.
        -- Native pathfinding still handles doors, stairs and obstructed floor.
        local first
        if not state.cursor or state.cursor < points[1].sequence then
            local best
            for i, point in ipairs(points) do
                local d = distanceSquared(origin, point)
                if math.abs(point.z - origin.z) < 0.2 and (not best or d <= best) then
                    first = i
                    best = d
                end
            end
            first = first or 1
            state.cursor = points[first].sequence
        end
        if state.target then
            if
                math.abs(origin.z - state.target.z) < 0.2
                and distanceSquared(origin, state.target) <= Settings.follow.waypointRadius ^ 2
            then
                state.cursor = state.target.sequence + 1
                state.target = nil
            elseif state.target.sequence >= points[1].sequence then
                return state.target
            else
                state.target = nil
            end
        end
        -- Leave a little room behind the human along their actual route.
        local limit = #points
        local behind = 0
        for i = #points - 1, 1, -1 do
            behind = behind + math.sqrt(distanceSquared(points[i], points[i + 1]))
            if behind >= gap then
                limit = i
                break
            end
        end
        local index
        for i, point in ipairs(points) do
            if point.sequence >= state.cursor then
                if
                    math.abs(origin.z - point.z) < 0.2
                    and distanceSquared(origin, point) <= Settings.follow.waypointRadius ^ 2
                then
                    state.cursor = point.sequence + 1
                else
                    index = i
                    break
                end
            end
        end
        if not index then
            return nil
        end
        -- Consume straight stretches in one native order, but preserve bends.
        local target = points[index]
        for i = index + 1, limit do
            local candidate = points[i]
            local prior = points[i - 1]
            local dx, dy = prior.x - origin.x, prior.y - origin.y
            local ex, ey = candidate.x - prior.x, candidate.y - prior.y
            local lengths = math.sqrt((dx * dx + dy * dy) * (ex * ex + ey * ey))
            if
                candidate.z ~= origin.z
                or prior.z ~= origin.z
                or distanceSquared(origin, candidate) > Settings.follow.straightReach ^ 2
                or lengths < 0.01
                or (dx * ex + dy * ey) / lengths < Settings.follow.straightDot
            then
                break
            end
            target = candidate
        end
        -- Never walk into the leader merely to consume a final breadcrumb.
        if index > limit and Space.clear(actor, leader) and Space.distance(actor, leader) <= (gap + 0.4) ^ 2 then
            return nil
        end
        state.target = target
        return target
    end
    function self:lookAround(person, movementRecord, actor, now)
        if
            not permitted(person)
            or movementRecord.dead
            or movementRecord.missing
            or movementRecord.transferReserved
            or movementRecord.mode ~= "wait"
            or movementRecord.combatActive
            or movementRecord.avoiding
            or movementRecord.cautious
            or movementRecord.attentionId
            or movementRecord.faceX
        then
            glances[person.id] = nil
            return
        end
        local state = glances[person.id]
        if not state then
            local seed = 0
            for i = 1, #person.id do
                seed = (seed + string.byte(person.id, i) * i) % 997
            end
            state = { started = now, seed = seed, x = actor:getLookDirectionX(), y = actor:getLookDirectionY() }
            glances[person.id] = state
        end
        -- Two held glances, separated by time, rather than spinning each tick.
        local elapsed = now - state.started
        local cycle = 2800 + state.seed % 1200
        local phase = elapsed % cycle
        if phase < 250 then
            return
        end
        local angle = phase < 1300 and 0.65 or -0.55
        if state.seed % 2 == 0 then
            angle = -angle
        end
        local c, s = math.cos(angle), math.sin(angle)
        movementRecord.faceX = actor:getX() + state.x * c - state.y * s
        movementRecord.faceY = actor:getY() + state.y * c + state.x * s
    end
    local function search(actor, state, now)
        if adapters.search then
            return adapters.search(actor, state, now)
        end
        local origin = position(actor)
        local cell = getCell()
        local best, bestDistance
        -- Loaded local storage only. We approach and inspect; we do not take,
        -- generate, reserve or claim any items in this movement-only pass.
        for dx = -4, 4 do
            for dy = -4, 4 do
                local sq =
                    cell:getGridSquare(math.floor(origin.x) + dx, math.floor(origin.y) + dy, math.floor(origin.z))
                if sq and sq:getRoom() and SafeHouse and not SafeHouse.isSafeHouse(sq, nil, false) then
                    local key = sq:getX() .. ":" .. sq:getY() .. ":" .. sq:getZ()
                    local recent = false
                    for _, visit in ipairs(state.searched) do
                        if visit.key == key and now - visit.at < 60000 then
                            recent = true
                        end
                    end
                    if not recent then
                        local objects = sq:getObjects()
                        local storage = false
                        for i = 0, objects:size() - 1 do
                            local obj = objects:get(i)
                            if not instanceof(obj, "IsoThumpable") and obj:getContainer() then
                                storage = true
                                break
                            end
                        end
                        if storage then
                            for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
                                local at = cell:getGridSquare(sq:getX() + d[1], sq:getY() + d[2], sq:getZ())
                                if at and at:getRoom() == sq:getRoom() and at:canReachTo(sq) then
                                    local goal =
                                        validate(actor, { x = at:getX() + 0.5, y = at:getY() + 0.5, z = at:getZ() })
                                    if
                                        goal
                                        and distanceSquared(origin, goal) > 1
                                        and (not bestDistance or distanceSquared(origin, goal) < bestDistance)
                                    then
                                        best, bestDistance = goal, distanceSquared(origin, goal)
                                        best.searchKey = key
                                        best.lookX = sq:getX() + 0.5
                                        best.lookY = sq:getY() + 0.5
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return best
    end
    function self:clear(id)
        states[id] = nil
    end
    function self:flee(person, movementRecord, actor, group, zombies, now)
        if not permitted(person) or person.recruited or person.duty or not group or group.stage ~= "escaping" then
            return nil
        end
        local threats, nearest, closest = {}, nil, 10 ^ 2
        for i = 0, zombies:size() - 1 do
            local z = zombies:get(i)
            local d = Space.distance(actor, z)
            if
                not z:isDead()
                and not z:getModData().ProjectPeoplePersonId
                and d <= 10 ^ 2
                and Space.clear(actor, z)
            then
                threats[#threats + 1] = position(z)
                if d <= closest then
                    nearest = z
                    closest = d
                end
            end
        end
        if not nearest then
            return nil
        end
        local origin = position(actor)
        local dx, dy = origin.x - nearest:getX(), origin.y - nearest:getY()
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.01 then
            dx, dy, length = 1, 0, 1
        end
        local best, score
        for _, side in ipairs({ 0, 0.65, -0.65, 1.3, -1.3 }) do
            for _, reach in ipairs({ 6, 3 }) do
                local goal = validate(actor, {
                    x = origin.x + (dx - dy * side) / length * reach,
                    y = origin.y + (dy + dx * side) / length * reach,
                    z = origin.z,
                })
                if goal then
                    local clearance = math.huge
                    for _, threat in ipairs(threats) do
                        clearance = math.min(clearance, distanceSquared(goal, threat))
                    end
                    if clearance > closest + 1 and (not score or clearance > score) then
                        best, score = goal, clearance
                    end
                end
            end
        end
        if best then
            states[person.id] = nil
            movementRecord.activity = "Fleeing from zombies"
            movementRecord.behaviourResting = false
            return best
        end
        -- Trapped survivors retain the ordinary defensive combat path.
        return nil
    end
    function self:goal(person, movementRecord, actor, group, records, world, now)
        if not permitted(person) or person.recruited or person.duty or not group then
            self:clear(person.id)
            return nil
        end
        local leader
        for _, id in ipairs(group.members) do
            local member = world.people[id]
            local record = records[id]
            if member and member.life ~= "dead" and not member.recruited and not member.duty then
                if not record or record.missing then
                    movementRecord.activity = "Waiting for the group"
                    return nil
                end
                if not record.dead then
                    leader = leader or record
                end
            end
        end
        local origin = position(actor)
        if leader and leader.personId ~= person.id then
            self:clear(person.id)
            if leader.z ~= origin.z or distanceSquared(origin, leader) > 24 ^ 2 then
                movementRecord.activity = "Waiting for the group"
                return nil
            end
            if distanceSquared(origin, leader) <= 3 ^ 2 then
                movementRecord.activity = "Staying with the group"
                return nil
            end
            movementRecord.activity = "Staying with the group"
            for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
                local goal = validate(actor, { x = leader.x + d[1], y = leader.y + d[2], z = leader.z })
                if goal then
                    return goal
                end
            end
            return nil
        end
        -- Leaders wait for trailing family, rather than walking out of reach.
        for _, id in ipairs(group.members) do
            local member = world.people[id]
            local other = records[id]
            if
                member
                and not member.recruited
                and not member.duty
                and other
                and not other.dead
                and (other.z ~= origin.z or distanceSquared(origin, other) > 8 ^ 2)
            then
                movementRecord.activity = "Waiting for the group"
                return nil
            end
        end
        local state = states[person.id]
        if not state or state.stage ~= group.stage then
            state = { stage = group.stage, leg = 0, nextSearch = 0, searched = {} }
            states[person.id] = state
        end
        local travelling = group.stage == "escaping" or group.stage == "relocating" or group.stage == "seeking_refuge"
        local activity = group.stage == "escaping" and "Moving away from the outbreak"
            or group.stage == "relocating" and "Moving to a new refuge"
            or group.stage == "seeking_refuge" and "Searching for shelter"
            or group.stage == "settling" and "Checking the refuge"
            or "Patrolling the refuge"
        movementRecord.activity = activity
        if state.goal then
            local d = distanceSquared(origin, state.goal)
            if d <= 1 then
                local reached = state.goal
                state.goal = nil
                state.leg = state.leg + 1
                state.nextSearch = now + (reached.searchKey and 5000 or travelling and 750 or 3500)
                state.inspect = reached.searchKey and reached or nil
                if reached.searchKey then
                    state.searched[#state.searched + 1] = { key = reached.searchKey, at = now }
                    while #state.searched > 8 do
                        table.remove(state.searched, 1)
                    end
                end
            elseif now - state.progressAt > 10000 then
                state.failed = state.goal
                state.failedAt = now
                state.goal = nil
                state.leg = state.leg + 1
                state.nextSearch = now + 1000
                movementRecord.activity = "Looking for another route"
            else
                if d < state.distance - 0.5 then
                    state.progressAt = now
                    state.distance = d
                end
                movementRecord.activity = state.activity
                return state.goal
            end
        end
        if now < state.nextSearch then
            if state.inspect then
                movementRecord.activity = "Searching for supplies"
                movementRecord.faceX = state.inspect.lookX
                movementRecord.faceY = state.inspect.lookY
            end
            return nil
        end
        state.inspect = nil
        state.nextSearch = now + 3000
        local bearing = (group.seed % 8) * math.pi / 4
        local best, bestScore
        if group.stage == "settling" or group.stage == "established" and state.leg % 3 == 1 then
            best = search(actor, state, now)
            if best and state.failed and now - state.failedAt < 30000 and distanceSquared(best, state.failed) < 4 then
                best = nil
            end
            if best then
                bestScore = 100
            end
        end
        for n = 0, 15 do
            local angle = bearing + (n % 8) * math.pi / 4 + (travelling and 0 or state.leg * math.pi / 3)
            local radius = n < 8 and (travelling and 8 or 5) or (travelling and 4 or 3)
            local anchor = travelling and origin or group.home
            local goal = validate(
                actor,
                { x = anchor.x + math.cos(angle) * radius, y = anchor.y + math.sin(angle) * radius, z = origin.z }
            )
            if
                goal
                and distanceSquared(origin, goal) > 2.25
                and not (state.failed and now - state.failedAt < 30000 and distanceSquared(goal, state.failed) < 4)
            then
                local score = -(n % 8)
                if travelling then
                    score = math.cos(angle - bearing) * 10 - (n >= 8 and 1 or 0)
                end
                if group.stage == "seeking_refuge" and goal.shelter then
                    score = score + 30
                end
                -- After a stall choose another bearing instead of repeating forever.
                if travelling and state.leg > 0 then
                    score = score + math.cos(angle - bearing - (state.leg % 3 - 1) * math.pi / 4) * 3
                end
                if not bestScore or score > bestScore then
                    best, bestScore = goal, score
                end
            end
        end
        if best then
            state.goal = best
            state.distance = distanceSquared(origin, best)
            state.progressAt = now
            state.activity = activity
            if best.searchKey then
                state.activity = "Looking for supplies"
            end
            if group.stage == "seeking_refuge" and best.shelter then
                state.activity = "Checking possible shelter"
            end
            movementRecord.activity = state.activity
        else
            state.leg = state.leg + 1
            movementRecord.activity = "Looking for a clear route"
        end
        return best
    end
    return self
end
return Movement
