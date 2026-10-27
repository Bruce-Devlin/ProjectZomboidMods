-- A bounded, useful base duty: close actual open doors in the occupied room.
-- Closing is idempotent; no resource or completion is invented.
local Work = {}
local Doors = require "ProjectPeople/PeopleDoors"

function Work.findDoor(home, worker, maxRadius)
    local cell = getCell()
    local center = cell:getGridSquare(home.x, home.y, home.z)
    local room = center and center:getRoom()
    if not room then
        return nil
    end
    local best, bestDistance
    for dx = -8, 8 do
        for dy = -8, 8 do
            local sq = cell:getGridSquare(math.floor(home.x) + dx, math.floor(home.y) + dy, home.z)
            if sq and sq:getRoom() == room then
                local list = sq:getObjects()
                for i = 0, list:size() - 1 do
                    local object = list:get(i)
                    if Doors.available(object) and object:IsOpen() then
                        local d = (worker:getX() - sq:getX() - 0.5) ^ 2 + (worker:getY() - sq:getY() - 0.5) ^ 2
                        if d <= (maxRadius or 12) ^ 2 and (not best or d < bestDistance) then
                            best, bestDistance = object, d
                        end
                    end
                end
            end
        end
    end
    return best
end

function Work.goal(door)
    local sq = door:getSquare()
    for _, d in ipairs({ { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
        local near = getCell():getGridSquare(sq:getX() + d[1], sq:getY() + d[2], sq:getZ())
        if near and near:TreatAsSolidFloor() and near:isFree(false) and not near:isBlockedTo(sq) then
            return { x = near:getX() + 0.5, y = near:getY() + 0.5, z = near:getZ() }
        end
    end
end

function Work.close(worker, door)
    if not door or not door:IsOpen() or door:isDestroyed() then
        return false, "door_no_longer_open"
    end
    local square = door:getSquare()
    local origin = worker:getCurrentSquare()
    if
        not origin
        or math.abs(worker:getZ() - square:getZ()) > 0.1
        or math.abs(origin:getX() - square:getX()) > 1
        or math.abs(origin:getY() - square:getY()) > 1
        or origin:isBlockedTo(square)
    then
        return false, "move_next_to_open_door"
    end
    worker:faceThisObject(door)
    if instanceof(worker, "IsoZombie") then
        return Doors.setOpen(worker, door, false)
    end
    door:ToggleDoor(worker)
    return not door:IsOpen(), door:IsOpen() and "door_blocked" or "door_closed"
end
return Work
