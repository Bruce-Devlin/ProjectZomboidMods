-- Persistent membership, independent of current movement/AI body ownership.
local DevTools = require "ProjectPeople/DevTools"
local Party = {}

function Party.limit(value)
    return DevTools.isFinite(value) and math.max(1, math.min(40, math.floor(value))) or 3
end

function Party.home(point)
    return type(point) == "table"
        and DevTools.isFinite(point.x)
        and DevTools.isFinite(point.y)
        and DevTools.isFinite(point.z)
        and point.z % 1 == 0
        and point.z >= -2
        and point.z <= 7
end

function Party.members(world, leaderId)
    local result = {}
    for id, person in pairs(world.people) do
        if
            person.controller.kind == "ai"
            and person.life ~= "dead"
            and person.commanderId == leaderId
            and person.partyId
        then
            result[#result + 1] = id
        end
    end
    table.sort(result)
    return result
end

function Party.fits(world, leaderId, joining, limit)
    local present, count, added = {}, 0, 0
    for _, id in ipairs(Party.members(world, leaderId)) do
        present[id], count = true, count + 1
    end
    for _, id in ipairs(joining) do
        if not present[id] then
            present[id], added = true, added + 1
        end
    end
    -- Lowering the option never dismisses existing people or blocks their wait/resume.
    return added == 0 or count + added <= Party.limit(limit)
end

function Party.alliedPeople(a, b)
    return a
            and b
            and a.controller.kind == "ai"
            and b.controller.kind == "ai"
            and ((a.recruited and b.recruited and a.commanderId and a.commanderId == b.commanderId) or (a.communityId and a.communityId == b.communityId))
        or false
end

function Party.allied(world, firstId, secondId)
    return Party.alliedPeople(world and world.people[firstId], world and world.people[secondId])
end

return Party
