-- Select content once. Conversations read the saved copy, never today's template.
local Templates = require "ProjectPeople/Content/HouseholdTemplates"
local DevTools = require "ProjectPeople/DevTools"
local Households = {}
local stages = { "escaping", "seeking_refuge", "settling", "established", "relocating" }

function Households.select(size, value)
    local matching = {}
    for _, template in ipairs(Templates) do
        if #template.members == size then
            matching[#matching + 1] = template
        end
    end
    assert(#matching > 0, "household_size_content_missing")
    return matching[math.floor(value * #matching) + 1]
end

function Households.snapshot(template)
    return {
        version = 1,
        contentId = template.id,
        label = template.label,
        history = template.history,
        tension = template.tension,
        plans = DevTools.copy(template.plans),
        members = {},
    }
end

function Households.addMember(saved, id, resident)
    saved.members[id] = {
        role = resident.role,
        thoughts = resident.thoughts,
        outlook = resident.outlook,
        chatter = DevTools.copy(resident.chatter),
    }
end

function Households.content(world, person)
    local group = person.populationGroup and world.population and world.population.groups[person.populationGroup]
    local saved = group and group.household
    return saved, saved and saved.members[person.id]
end

function Households.reply(world, person, topic, now)
    local saved, member = Households.content(world, person)
    if not member then
        return nil
    end
    if topic == "household" then
        return saved.history .. " " .. saved.tension .. (saved.separation and " " .. saved.separation or "")
    elseif topic == "outlook" then
        return member.outlook
    elseif topic == "thoughts" then
        return member.thoughts
    elseif topic == "chat" then
        -- Same hour, same answer: reading never consumes RNG or changes a save.
        local hour = math.floor(now or 0)
        return member.chatter[(DevTools.hash(person.id) + hour) % #member.chatter + 1]
    end
end

function Households.plan(world, person, stage)
    local saved, member = Households.content(world, person)
    return member and saved.plans[stage] or nil
end

local function text(value)
    return type(value) == "string" and #value > 0 and #value <= 900
end

function Households.valid(saved, roster)
    if saved == nil then
        return true
    end
    if
        type(saved) ~= "table"
        or saved.version ~= 1
        or not text(saved.contentId)
        or not text(saved.label)
        or not text(saved.history)
        or not text(saved.tension)
        or type(saved.plans) ~= "table"
        or type(saved.members) ~= "table"
        or saved.separation ~= nil and not text(saved.separation)
    then
        return false
    end
    for _, stage in ipairs(stages) do
        if not text(saved.plans[stage]) then
            return false
        end
    end
    for id in pairs(roster) do
        if type(saved.members[id]) ~= "table" then
            return false
        end
    end
    for id, member in pairs(saved.members) do
        if
            not roster[id]
            or type(member) ~= "table"
            or not text(member.role)
            or not text(member.thoughts)
            or not text(member.outlook)
            or type(member.chatter) ~= "table"
            or #member.chatter < 2
            or #member.chatter > 8
        then
            return false
        end
        for _, line in ipairs(member.chatter) do
            if not text(line) then
                return false
            end
        end
    end
    return true
end

return Households
