local PrisonSpawns = {}

local PRISON_ANCHORS = {
    { name = "Kentucky State Penitentiary", x = 7681, y = 11819 },
    { name = "Louisville Police Station", x = 12407, y = 1621 },
    { name = "Brandenburg Prison", x = 1354, y = 5863 },
}

local cachedSpawns = nil

local function addCellRooms(metaGrid, building, spawns, seen)
    local rooms = building:getRooms()

    for index = 0, rooms:size() - 1 do
        local room = rooms:get(index)
        if tostring(room:getName()) == "prisoncells" then
            local x = math.floor((room:getX() + room:getX2() - 1) / 2)
            local y = math.floor((room:getY() + room:getY2() - 1) / 2)
            local z = room:getZ()
            local key = string.format("%d:%d:%d", x, y, z)

            if not seen[key] and metaGrid:getRoomAt(x, y, z) then
                seen[key] = true
                table.insert(spawns, { x = x, y = y, z = z })
            end
        end
    end
end

function PrisonSpawns.getAll()
    if cachedSpawns then
        return cachedSpawns
    end

    local world = getWorld()
    if not world then
        return {}
    end

    local metaGrid = world:getMetaGrid()
    if not metaGrid then
        return {}
    end

    local spawns = {}
    local seenBuildings = {}
    local seenSpawns = {}

    for _, anchor in ipairs(PRISON_ANCHORS) do
        local building = metaGrid:getBuildingAt(anchor.x, anchor.y)
        if building then
            local buildingKey = tostring(building)
            if not seenBuildings[buildingKey] then
                seenBuildings[buildingKey] = true
                addCellRooms(metaGrid, building, spawns, seenSpawns)
            end
        end
    end

    if #spawns > 0 then
        cachedSpawns = spawns
    end

    return spawns
end

return PrisonSpawns
