-- Local detours, cautious approaches and escape decisions.
local Settings = require "ProjectPeople/Pathing/Settings"
local DevTools = require "ProjectPeople/DevTools"
local Space = require "ProjectPeople/Pathing/CombatSpace"
local Locomotion = {
    MAX_RETRIES = Settings.avoidance.maxRetries,
    RETRY_MS = Settings.avoidance.retryMs,
    RISK_MS = Settings.avoidance.riskMs,
    STALL_MS = Settings.avoidance.stallMs,
    ESCAPE_MS = Settings.avoidance.escapeMs,
}
local distanceSquared = DevTools.distanceSquared
local position = DevTools.position
-- Only zombies along the next part of the route obstruct it. A zombie off to
-- one side must not make a survivor abandon the destination to maximise stealth.

local function blocked(origin, goal, seen, radius, reach)
    local dx, dy = goal.x - origin.x, goal.y - origin.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 or math.abs(goal.z - origin.z) > 0.2 then
        return false
    end
    for _, threat in ipairs(seen) do
        local tx, ty = threat.actor:getX() - origin.x, threat.actor:getY() - origin.y
        local along = (tx * dx + ty * dy) / length
        local across = math.abs(tx * dy - ty * dx) / length
        if along > 0 and along <= math.min(length, reach) and across < radius then
            return true
        end
    end
    return false
end

function Locomotion.notice(distanceSquared, dot, gait, moving, tracking)
    if distanceSquared <= Settings.notice.contactDistance ^ 2 then
        return true
    end
    -- Crouching does not erase an existing pursuit. Break sight to lose it.
    if tracking then
        return distanceSquared <= Settings.notice.trackingDistance ^ 2
    end
    local quiet = gait == "sneak" or gait == "hurry"
    local hearing = moving
            and (gait == "run" and Settings.notice.runHearing or quiet and Settings.notice.quietHearing or Settings.notice.walkHearing)
        or 0
    if distanceSquared <= hearing ^ 2 then
        return true
    end
    return dot >= Settings.notice.sightDot
        and distanceSquared <= (quiet and Settings.notice.quietSight ^ 2 or Settings.notice.normalSight ^ 2)
end

function Locomotion.detects(zombie, actor, record, tracking)
    local d = Space.distance(zombie, actor)
    local dx, dy = actor:getX() - zombie:getX(), actor:getY() - zombie:getY()
    local length = math.sqrt(dx * dx + dy * dy)
    local dot = length > 0 and (zombie:getLookDirectionX() * dx + zombie:getLookDirectionY() * dy) / length or 1
    return Locomotion.notice(d, dot, record.gait, record.mode == "move", tracking)
end

local function floor(actor, x, y)
    local from = actor:getCurrentSquare()
    local sq = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(actor:getZ()))
    if
        not from
        or not sq
        or not sq:isFree(false)
        or not sq:TreatAsSolidFloor()
        or sq:isWaterSquare()
        or sq:isVehicleIntersecting()
        or from:isBlockedTo(sq)
        or from:isSomethingTo(sq)
        or not SafeHouse
        or SafeHouse.isSafeHouse(sq, nil, false)
    then
        return nil
    end
    if
        tostring(
            LosUtil.lineClear(getCell(), from:getX(), from:getY(), from:getZ(), sq:getX(), sq:getY(), sq:getZ(), false)
        ) ~= "Clear"
    then
        return nil
    end
    return { x = sq:getX() + 0.5, y = sq:getY() + 0.5, z = sq:getZ() }
end

function Locomotion.new(adapters)
    adapters = adapters or {}
    local destination = adapters.floor or floor
    -- Authority-local, transient planning state. Never part of the person/save
    -- record or replicated body payload, and discarded when that binding leaves.
    local states = {}
    local self = {}
    function self:prune(records)
        for id, state in pairs(states) do
            if records[id] ~= state.record then
                states[id] = nil
            end
        end
    end
    function self:step(person, movementRecord, actor, zombies, now, leader, pursuit)
        local wasAvoiding = movementRecord.avoiding
        movementRecord.avoiding = false
        movementRecord.fleeing = false
        movementRecord.riskySneak = false
        movementRecord.cautious = false
        if person.life ~= "alive" or person.controller.kind ~= "ai" or person.reservationId or person.transitionId then
            states[person.id] = nil
            movementRecord.gait = "walk"
            return nil, false
        end
        local state = states[person.id]
        if
            not state
            or state.record ~= movementRecord
            or state.duty ~= person.duty
            or state.job ~= person.jobId
            or state.mission ~= person.missionId
        then
            state = {
                record = movementRecord,
                duty = person.duty,
                job = person.jobId,
                mission = person.missionId,
                attempts = 0,
            }
            states[person.id] = state
        end
        local origin = position(actor)
        if not wasAvoiding and not movementRecord.combatActive and not state.riskAt then
            local route = movementRecord.mode == "move"
                    and movementRecord.goalX
                    and { x = movementRecord.goalX, y = movementRecord.goalY, z = movementRecord.goalZ }
                or nil
            if
                route and (not state.route or distanceSquared(route, state.route) > 0.25 or route.z ~= state.route.z)
            then
                state.route = route
                state.attempts = 0
                state.detour = nil
                state.riskAt = nil
                state.escape = nil
            elseif not route then
                state.route = nil
            end
        end
        local nearest, closest, seen = nil, math.huge, {}
        local alerted = false
        for i = 0, zombies:size() - 1 do
            local zombie = zombies:get(i)
            local d = Space.distance(actor, zombie)
            if
                not zombie:isDead()
                and not zombie:getModData().ProjectPeoplePersonId
                and d <= Settings.avoidance.scanDistance ^ 2
                and Space.clear(actor, zombie)
            then
                local chasing = zombie:getTarget() == actor or pursuit and pursuit(zombie, person.id)
                seen[#seen + 1] = { actor = zombie, distance = d }
                if d < closest then
                    nearest, closest = zombie, d
                end
                if chasing and d <= Settings.avoidance.pursuitDistance ^ 2 then
                    alerted = true
                end
            end
        end
        local urgent = closest < Settings.avoidance.urgentDistance ^ 2 or alerted
        movementRecord.gait = urgent and "run" or closest < Settings.avoidance.scanDistance ^ 2 and "sneak" or "hurry"
        movementRecord.cautious = nearest ~= nil
        local square = actor:getCurrentSquare()
        movementRecord.indoors = square and square:getRoom() ~= nil or false
        if movementRecord.indoors and not urgent then
            movementRecord.gait = "walk"
        end
        -- A travelling companion trusts the human's route. Danger tightens
        -- spacing instead of choosing an unrelated escape or combat path.
        if person.duty == "follow" and not person.jobId and not person.missionId and leader and not leader:isDead() then
            states[person.id] = nil
            if nearest and not movementRecord.indoors and not urgent then
                movementRecord.gait = "hurry"
            end
            local separation = (actor:getX() - leader:getX()) ^ 2 + (actor:getY() - leader:getY()) ^ 2
            -- Hysteresis keeps catch-up from alternating every simulation tick.
            movementRecord.catchingUp = separation
                > (
                    movementRecord.catchingUp and Settings.follow.settleDistance ^ 2
                    or Settings.follow.catchUpDistance ^ 2
                )
            if movementRecord.catchingUp then
                movementRecord.gait = "run"
            end
            -- Contact defense is retained when both companions have stopped
            -- together; moving leaders and catch-up always keep route priority.
            local defend = closest <= Settings.follow.defendDistance ^ 2
                and not leader:isMoving()
                and Space.distance(actor, leader) <= Settings.follow.defendLeaderDistance ^ 2
            return nil, not defend
        end
        movementRecord.catchingUp = nil
        if movementRecord.attentionId and not urgent and not state.escape then
            state.attempts = 0
            state.detour = nil
            state.riskAt = nil
            return nil, true
        end
        if state.escape and now - state.escapeAt >= Locomotion.ESCAPE_MS and not urgent then
            state.escape = nil
            state.riskAt = nil
            state.attempts = 0
            state.detour = nil
        end
        local obstruction = state.route and blocked(origin, state.route, seen, 2, 6)
        if not urgent and not state.escape then
            if not obstruction then
                state.clearAt = state.clearAt or now
                if now - state.clearAt >= Settings.avoidance.clearMs then
                    state.attempts = 0
                    state.detour = nil
                    state.riskAt = nil
                end
                return nil, nearest ~= nil
            end
            state.clearAt = nil
            -- Two short forward detours at most. Hold each choice instead of
            -- reversing whenever the nearest zombie changes sides in an alley.
            if not state.riskAt then
                if
                    state.detour
                    and distanceSquared(origin, state.detour) > 0.75 ^ 2
                    and now - state.detourAt < Locomotion.RETRY_MS
                then
                    movementRecord.avoiding = true
                    movementRecord.behaviourResting = false
                    movementRecord.activity = "Trying a way around"
                    return state.detour, true
                end
                state.detour = nil
                if state.attempts < Locomotion.MAX_RETRIES then
                    state.attempts = state.attempts + 1
                    local dx, dy = state.route.x - origin.x, state.route.y - origin.y
                    local length = math.sqrt(dx * dx + dy * dy)
                    local forward = math.min(3, length)
                    local side = state.attempts == 1 and 2.5 or -2.5
                    local goal = destination(
                        actor,
                        origin.x + (dx * forward - dy * side) / length,
                        origin.y + (dy * forward + dx * side) / length
                    )
                    if
                        goal
                        and distanceSquared(goal, state.route) < distanceSquared(origin, state.route)
                        and not blocked(origin, goal, seen, 1.5, 6)
                    then
                        local clear = true
                        for _, threat in ipairs(seen) do
                            if distanceSquared(goal, position(threat.actor)) < 2 ^ 2 then
                                clear = false
                            end
                        end
                        if clear then
                            state.detour = goal
                            state.detourAt = now
                        end
                    end
                    if state.detour then
                        movementRecord.avoiding = true
                        movementRecord.behaviourResting = false
                        movementRecord.activity = "Trying a way around"
                        return state.detour, true
                    end
                    -- An unavailable detour counts as an attempt; keep the
                    -- intended native route while trying the other side next.
                    if state.attempts < Locomotion.MAX_RETRIES then
                        return nil, true
                    end
                end
                state.riskAt = now
                state.progressAt = now
                state.distance = math.sqrt(distanceSquared(origin, state.route))
            end
            local remaining = math.sqrt(distanceSquared(origin, state.route))
            if remaining < state.distance - Settings.avoidance.progressDistance then
                state.distance = remaining
                state.progressAt = now
            end
            if now - state.riskAt < Locomotion.RISK_MS and now - state.progressAt < Locomotion.STALL_MS then
                movementRecord.gait = movementRecord.indoors and "walk" or "sneak"
                movementRecord.riskySneak = true
                movementRecord.activity = "Risking a way through"
                return nil, true
            end
            -- No useful progress or too long exposed: survival now wins.
            urgent = true
        end
        if not nearest then
            state.escape = nil
            return nil, false
        end
        movementRecord.fleeing = true
        movementRecord.gait = "run"
        movementRecord.behaviourResting = false
        movementRecord.activity = "Escaping danger"
        if
            state.escape
            and distanceSquared(origin, state.escape) > 0.75 ^ 2
            and now - state.escapeAt < Locomotion.ESCAPE_MS
            and not blocked(origin, state.escape, seen, 1.25, 6)
        then
            movementRecord.avoiding = true
            return state.escape, true
        end
        local dx, dy = actor:getX() - nearest:getX(), actor:getY() - nearest:getY()
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.01 then
            dx, dy, length = 1, 0, 1
        end
        local best, score
        for _, side in ipairs({ 0, 0.65, -0.65, 1.3, -1.3 }) do
            for _, reach in ipairs({ 5, 2 }) do
                local goal = destination(
                    actor,
                    actor:getX() + (dx - dy * side) / length * reach,
                    actor:getY() + (dy + dx * side) / length * reach
                )
                if goal and not blocked(origin, goal, seen, 1.25, 6) then
                    local clearance = math.huge
                    for _, threat in ipairs(seen) do
                        clearance =
                            math.min(clearance, (goal.x - threat.actor:getX()) ^ 2 + (goal.y - threat.actor:getY()) ^ 2)
                    end
                    local value = clearance
                    if state.escape then
                        local ex, ey = state.escape.x - origin.x, state.escape.y - origin.y
                        local el = math.sqrt(ex * ex + ey * ey)
                        if el > 0.01 then
                            value = value + 3 * ((goal.x - origin.x) * ex + (goal.y - origin.y) * ey) / (reach * el)
                        end
                    end
                    if clearance > closest + 0.5 and (not score or value > score) then
                        best, score = goal, value
                    end
                end
            end
        end
        if best then
            state.escape = best
            state.escapeAt = now
            state.detour = nil
            movementRecord.avoiding = true
            movementRecord.behaviourResting = false
            return best, true
        end
        -- Cornered survivors defend at close range; do not charge distant
        -- zombies just because the native combat selector can see them.
        state.escape = nil
        return nil, closest > 2.5 ^ 2
    end
    return self
end

function Locomotion.apply(actor, record)
    local gait = record.combatActive and "walk" or record.gait or "walk"
    -- Idle pose follows the current surroundings, including conversation and
    -- the short stops between paths. Running/fighting still needs an upright gait.
    local crouch = not record.combatActive
        and record.indoors ~= true
        and (record.mode == "wait" or gait == "sneak" or gait == "hurry")
    crouch = crouch == true
    actor:setVariable("ProjectPeopleGait", gait)
    actor:setVariable("ProjectPeopleCrouch", crouch)
    actor:setSneaking(crouch)
    actor:setRunning(gait == "run" and record.mode == "move")
    actor:setSprinting(false)
end
return Locomotion
