-- Loaded building inspection only: never reads, removes or generates container loot.
local DevTools = require "ProjectPeople/DevTools"
local Doors = require "ProjectPeople/PeopleDoors"
local Scavenging = {}

-- Rebuilt from authoritative player records at each independent routing decision.
-- Whole buildings (including upper floors) are private; outdoor flags reserve
-- an eight-tile home area. Explicit resident/follower orders do not use this gate.
function Scavenging.homes(world)
    local homes, buildings = {}, {}
    for _, person in pairs(world.people or {}) do
        local home = person.communityHome
        if home then
            homes[#homes + 1] = home
            local sq = getCell():getGridSquare(math.floor(home.x), math.floor(home.y), math.floor(home.z))
            local building = sq and sq:getBuilding()
            if building then
                buildings[building] = true
            end
        end
    end
    return function(goal, building)
        if #homes == 0 then
            return false
        end
        if building and buildings[building] then
            return true
        end
        if goal then
            local sq = getCell():getGridSquare(math.floor(goal.x), math.floor(goal.y), math.floor(goal.z))
            if sq and buildings[sq:getBuilding()] then
                return true
            end
            for _, home in ipairs(homes) do
                if math.abs(home.z - goal.z) < 0.2 and DevTools.distanceSquared(home, goal) <= 8 ^ 2 then
                    return true
                end
            end
        end
        return false
    end
end

function Scavenging.failed(state, goal, now)
    for _, previous in ipairs(state.failedGoals or {}) do
        if
            now - previous.at < 60000
            and previous.goal.z == goal.z
            and DevTools.distanceSquared(goal, previous.goal) < 4
        then
            return true
        end
    end
    return false
end

function Scavenging.floor(square)
    if
        not square
        or not square:TreatAsSolidFloor()
        or not square:isFree(false)
        or square:isWaterSquare()
        or square:isVehicleIntersecting()
        or not SafeHouse
        or SafeHouse.isSafeHouse(square, nil, false)
    then
        return nil
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if instanceof(object, "IsoThumpable") then
            return nil
        end
        if object:hasModData() then
            for key in pairs(object:getModData()) do
                if type(key) == "string" and key:sub(1, 5) == "need:" then
                    return nil
                end
            end
        end
    end
    return { x = square:getX() + 0.5, y = square:getY() + 0.5, z = square:getZ(), shelter = square:getBuilding() ~= nil }
end

-- Stage house entry at a real usable door. An indoor container must never turn
-- into a straight-line request at the nearest window/wall from outside.
function Scavenging.entrance(actor, building, state, now)
    local origin, cell = DevTools.position(actor), getCell()
    if state.entryGoal and state.entryBuilding == building then
        if not state.entryOrigin or DevTools.distanceSquared(origin, state.entryOrigin) > 0.25 then
            state.entryOrigin, state.entryProgressAt = origin, now
        elseif now - state.entryProgressAt > 5000 then
            state.failedGoals = state.failedGoals or {}
            state.failedGoals[#state.failedGoals + 1] = { goal = state.entryGoal, at = now }
            while #state.failedGoals > 8 do
                table.remove(state.failedGoals, 1)
            end
            state.entryGoal = nil
        end
        if
            state.entryGoal
            and not Scavenging.failed(state, state.entryGoal, now)
            and now - state.entryCheckedAt < 1500
            and DevTools.distanceSquared(origin, state.entryGoal) > 1.1 ^ 2
        then
            return state.entryGoal
        end
    end
    local best, bestScore
    for dx = -20, 20 do
        for dy = -20, 20 do
            local outside =
                cell:getGridSquare(math.floor(origin.x) + dx, math.floor(origin.y) + dy, math.floor(origin.z))
            if outside and not outside:getBuilding() and Scavenging.floor(outside) then
                for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
                    local inside = cell:getGridSquare(outside:getX() + d[1], outside:getY() + d[2], outside:getZ())
                    local door = inside and inside:getBuilding() == building and outside:getDoorTo(inside)
                    if Doors.available(door) and not door:isObstructed() and Scavenging.floor(inside) then
                        local approach =
                            { x = outside:getX() + 0.5, y = outside:getY() + 0.5, z = outside:getZ(), entry = true }
                        local goal = approach
                        if
                            actor:getCurrentSquare() == outside
                            and DevTools.distanceSquared(origin, approach) <= 1.1 ^ 2
                        then
                            goal = { x = inside:getX() + 0.5, y = inside:getY() + 0.5, z = inside:getZ(), entry = true }
                        end
                        if not Scavenging.failed(state, approach, now) and not Scavenging.failed(state, goal, now) then
                            local score = DevTools.distanceSquared(origin, approach)
                            if not bestScore or score < bestScore then
                                best, bestScore = goal, score
                            end
                        end
                    end
                end
            end
        end
    end
    if
        best
        and (
            not state.entryGoal
            or state.entryBuilding ~= building
            or DevTools.distanceSquared(best, state.entryGoal) > 0.01
        )
    then
        state.entryOrigin, state.entryProgressAt = origin, now
    end
    state.entryGoal, state.entryBuilding, state.entryCheckedAt = best, building, now
    return best
end

function Scavenging.pick(actor, state, now, id, reserved, protected)
    if state.building and protected and protected(nil, state.building) then
        state.building, state.buildingUntil, state.entryGoal, state.entryBuilding = nil, nil, nil, nil
    end
    local cell, origin = getCell(), DevTools.position(actor)
    if state.buildingUntil and now >= state.buildingUntil then
        state.lastBuilding = state.building
        state.lastBuildingAt = now
        state.building, state.buildingUntil = nil, nil
    end
    local currentSquare = actor.getCurrentSquare and actor:getCurrentSquare()
    local currentBuilding = currentSquare and currentSquare:getBuilding()
    if
        not state.building
        and currentBuilding
        and not (protected and protected(origin, currentBuilding))
        and not (currentBuilding == state.lastBuilding and now - state.lastBuildingAt < 60000)
    then
        state.building = currentBuilding
        state.buildingUntil = now + 45000 + DevTools.hash(id) % 45000
    end
    local best, score, chosenBuilding
    -- At most 5 * 17 * 17 + 56 loaded squares per completed/stalled leg.
    -- Sample the immediate room densely so small rooms are not skipped by parity.
    -- The native pathfinder resolves doors and stairs; straight sight would
    -- incorrectly exclude every room and upper floor behind a wall.
    local floor = math.floor(origin.z)
    for z = math.max(-2, floor - 2), math.min(7, floor + 2) do
        for dx = -16, 16 do
            for dy = -16, 16 do
                local sample = z == floor and math.abs(dx) <= 4 and math.abs(dy) <= 4 or dx % 2 == 0 and dy % 2 == 0
                local square = sample and cell:getGridSquare(math.floor(origin.x) + dx, math.floor(origin.y) + dy, z)
                local building = square and square:getBuilding()
                if
                    building
                    and (not reserved or not reserved(building))
                    and not (protected and protected({ x = square:getX(), y = square:getY(), z = z }, building))
                    and square:getRoom()
                    and (not state.building or state.building == building)
                    and not (building == state.lastBuilding and now - state.lastBuildingAt < 60000)
                then
                    local objects = square:getObjects()
                    local container = false
                    for i = 0, objects:size() - 1 do
                        local object = objects:get(i)
                        if not instanceof(object, "IsoThumpable") and object:getContainer() then
                            container = true
                            break
                        end
                    end
                    local key = square:getX() .. ":" .. square:getY() .. ":" .. z
                    local recent = false
                    for _, visit in ipairs(state.searched) do
                        if visit.key == key and now - visit.at < 90000 then
                            recent = true
                        end
                    end
                    if not recent then
                        local offsets = container and { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } } or { { 0, 0 } }
                        for _, offset in ipairs(offsets) do
                            local at = cell:getGridSquare(square:getX() + offset[1], square:getY() + offset[2], z)
                            local goal = at and at:getBuilding() == building and Scavenging.floor(at)
                            local failed = false
                            if goal then
                                for _, previous in ipairs(state.failedGoals or {}) do
                                    if
                                        now - previous.at < 60000
                                        and previous.goal.z == z
                                        and DevTools.distanceSquared(goal, previous.goal) < 4
                                    then
                                        failed = true
                                        break
                                    end
                                end
                            end
                            if
                                goal
                                and not failed
                                and (not container or at:canReachTo(square))
                                and (z ~= floor or DevTools.distanceSquared(goal, origin) > 1)
                                and not (
                                    state.failed
                                    and now - state.failedAt < 30000
                                    and state.failed.z == z
                                    and DevTools.distanceSquared(goal, state.failed) < 4
                                )
                            then
                                local rank = (container and 40 or 0)
                                    + (#state.searched == 0 and z == floor and 20 or #state.searched > 0 and z ~= floor and 15 or 0)
                                    + DevTools.hash(id .. ":" .. state.leg .. ":" .. key) % 997 / 100
                                    - math.sqrt(DevTools.distanceSquared(goal, origin)) * 0.3
                                if not score or rank > score then
                                    best, score, chosenBuilding = goal, rank, building
                                    goal.searchKey = key
                                    goal.lookX, goal.lookY = square:getX() + 0.5, square:getY() + 0.5
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if best and currentSquare and currentBuilding ~= chosenBuilding then
        best = Scavenging.entrance(actor, chosenBuilding, state, now)
        if not best then
            state.lastBuilding, state.lastBuildingAt = chosenBuilding, now
        end
    end
    if best and state.building ~= chosenBuilding then
        state.building, state.buildingUntil = chosenBuilding, now + 45000 + DevTools.hash(id) % 45000
    elseif not best then
        state.building, state.buildingUntil = nil, nil
    end
    return best
end
return Scavenging
