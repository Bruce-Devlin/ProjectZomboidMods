-- Opens safe doors and closes them after the survivor passes through.
local Doors = {}
local directions = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Doors.available(door)
    if not door then
        return false
    end
    if not instanceof(door, "IsoDoor") and not (instanceof(door, "IsoThumpable") and door:isDoor()) then
        return false
    end
    if door:isDestroyed() then
        return false
    end
    if door:isLocked() or door:isLockedByKey() or door:isBarricaded() then
        return false
    end
    if door:getModData().CustomLock then
        return false
    end
    if instanceof(door, "IsoThumpable") and (door:isLockedByPadlock() or door:getLockedByCode() ~= 0) then
        return false
    end
    return true
end

local function sides(door)
    local sq = door:getSquare()
    if not sq then
        return
    end
    local other = getCell():getGridSquare(
        sq:getX() - (door:getNorth() and 0 or 1),
        sq:getY() - (door:getNorth() and 1 or 0),
        sq:getZ()
    )
    return sq, other
end

local function reachable(actor, door)
    local a, b = sides(door)
    local current = actor:getCurrentSquare()
    if not a or not b or not current or current ~= a and current ~= b then
        return false
    end
    local x = a:getX() + (door:getNorth() and 0.5 or 0)
    local y = a:getY() + (door:getNorth() and 0 or 0.5)
    return math.abs(actor:getZ() - a:getZ()) < 0.1 and (actor:getX() - x) ^ 2 + (actor:getY() - y) ^ 2 <= 2.25
end

local function groupAvailable(door)
    if IsoDoor.getDoubleDoorIndex(door) ~= -1 then
        for index = 1, 4 do
            local part = IsoDoor.getDoubleDoorObject(door, index)
            if part and not Doors.available(part) then
                return false
            end
        end
    elseif IsoDoor.getGarageDoorIndex(door) ~= -1 then
        local part = IsoDoor.getGarageDoorFirst(door)
        for index = 1, 16 do
            if not part then
                return true
            end
            if not Doors.available(part) or part:isObstructed() then
                return false
            end
            part = IsoDoor.getGarageDoorNext(part)
        end
        return part == nil
    end
    return true
end

function Doors.setOpen(actor, door, wanted)
    if isClient and isClient() then
        return false, "authority_only"
    end
    if not Doors.available(door) then
        return false, "door_locked_or_barricaded"
    end
    if not groupAvailable(door) then
        return false, "door_locked_or_barricaded"
    end
    if door:IsOpen() == wanted then
        return true, "already_set"
    end
    if not reachable(actor, door) then
        return false, "move_next_to_door"
    end
    if door:isObstructed() then
        return false, "door_blocked"
    end
    actor:faceThisObject(door)
    if instanceof(door, "IsoThumpable") then
        door:ToggleDoor(actor)
    elseif IsoDoor.getDoubleDoorIndex(door) ~= -1 then
        if IsoDoor.isDoubleDoorObstructed(door) then
            return false, "door_blocked"
        end
        IsoDoor.toggleDoubleDoor(door, true)
    elseif IsoDoor.getGarageDoorIndex(door) ~= -1 then
        -- The native garage obstruction helper is private. groupAvailable
        -- checks every leaf with the public obstruction API before toggling.
        IsoDoor.toggleGarageDoor(door, true)
    else
        -- 42.21 ToggleDoorActual dereferences a null IsoPlayer after changing
        -- an IsoDoor for an IsoZombie. Silent toggle plus native sync avoids
        -- that player-only tail, retaining collision, lighting and replication.
        door:ToggleDoorSilent()
        door:getSquare():RecalcAllWithNeighbours(true)
        door:getSquare():setSquareChanged()
        door:invalidateRenderChunkLevel(256)
        door:syncIsoObject(false, 0, nil, nil)
        actor:getEmitter():playSound(door:getSoundPrefix() .. (wanted and "Open" or "Close"))
    end
    return door:IsOpen() == wanted, door:IsOpen() == wanted and "door_changed" or "door_blocked"
end

local function occupied(door, actor)
    local a, b = sides(door)
    for _, sq in ipairs({ a, b }) do
        local list = sq:getMovingObjects()
        for i = 0, list:size() - 1 do
            if list:get(i) ~= actor then
                return true
            end
        end
    end
    return false
end

function Doors.update(binding, record, now)
    if isClient and isClient() then
        return
    end
    if record.mode ~= "move" and not binding.doorPassage then
        return
    end
    now = now or getTimestampMs()
    local actor = binding.actor
    if actor:isDead() or not actor:getCurrentSquare() then
        binding.doorPassage = nil
        return
    end
    if binding.nextDoorCheck and now < binding.nextDoorCheck then
        return
    end
    binding.nextDoorCheck = now + 150
    local pending = binding.doorPassage
    if pending then
        local door = pending.door
        if not Doors.available(door) or not door:IsOpen() or now > pending.expires then
            binding.doorPassage = nil
        else
            local sq = door:getSquare()
            local coordinate = door:getNorth() and actor:getY() - sq:getY() or actor:getX() - sq:getX()
            -- Stay within physical reach, but clear the threshold before closing.
            if
                coordinate * pending.side < 0
                and math.abs(coordinate) >= 0.45
                and reachable(actor, door)
                and not occupied(door, actor)
            then
                if Doors.setOpen(actor, door, false) then
                    binding.doorPassage = nil
                    binding.closedDoor = door
                    binding.closedDoorUntil = now + 1000
                    return
                end
            elseif (actor:getX() - sq:getX() - 0.5) ^ 2 + (actor:getY() - sq:getY() - 0.5) ^ 2 > 3 ^ 2 then
                binding.doorPassage = nil
            end
        end
    end
    if record.mode ~= "move" or record.attacking then
        return
    end
    local current = actor:getCurrentSquare()
    local path = actor:getPath2()
    local dx, dy = actor:getLookDirectionX(), actor:getLookDirectionY()
    if not path then
        dx, dy = (record.goalX or actor:getX()) - actor:getX(), (record.goalY or actor:getY()) - actor:getY()
        local length = math.sqrt(dx * dx + dy * dy)
        if length < 0.01 then
            return
        end
        dx, dy = dx / length, dy / length
    end
    local best, bestDot
    for _, d in ipairs(directions) do
        local other = getCell():getGridSquare(current:getX() + d[1], current:getY() + d[2], current:getZ())
        local dot = dx * d[1] + dy * d[2]
        -- Path is opaque in installed Kahlua. Native facing follows the current
        -- path segment; never index Java path nodes from Lua.
        if other and dot > 0.7 then
            local door = current:getDoorTo(other)
            if
                Doors.available(door)
                and not door:IsOpen()
                and not (door == binding.closedDoor and now < (binding.closedDoorUntil or 0))
                and (not bestDot or dot > bestDot)
            then
                best, bestDot = door, dot
            end
        end
    end
    if best and Doors.setOpen(actor, best, true) then
        local sq = best:getSquare()
        local coordinate = best:getNorth() and actor:getY() - sq:getY() or actor:getX() - sq:getX()
        binding.doorPassage = { door = best, side = coordinate >= 0 and 1 or -1, expires = now + 10000 }
    end
end
return Doors
