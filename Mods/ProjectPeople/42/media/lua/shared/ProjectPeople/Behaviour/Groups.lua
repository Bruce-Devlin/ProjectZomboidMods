-- Durable social ties are separate from physical encounter membership.
local Group = {}

function Group.members(world, id, presentOnly)
    if not id or not world.people[id] then
        return {}
    end
    local found, queue, queued = {}, { id }, { [id] = true }
    local cursor = 1
    while cursor <= #queue do
        local current = queue[cursor]
        cursor = cursor + 1
        local p = world.people[current]
        if p and not found[current] then
            found[current] = true
            -- Dead relatives do not connect otherwise separate surviving groups.
            if p.life ~= "dead" or current == id then
                for other, q in pairs(world.people) do
                    if
                        not queued[other]
                        and q.life ~= "dead"
                        and q.controller.kind == "ai"
                        and (
                            (p.family or {})[other]
                            or (q.family or {})[current]
                            or p.populationGroup and p.populationGroup == q.populationGroup
                        )
                    then
                        queue[#queue + 1] = other
                        queued[other] = true
                    end
                end
            end
        end
    end
    local result = {}
    for member in pairs(found) do
        local p = world.people[member]
        if
            p.life ~= "dead"
            and p.controller.kind == "ai"
            and (
                not presentOnly
                or member == id
                or not p.populationAbsent and p.representation and p.representation.mode == "physical"
            )
        then
            result[#result + 1] = member
        end
    end
    table.sort(result)
    return result
end
return Group
