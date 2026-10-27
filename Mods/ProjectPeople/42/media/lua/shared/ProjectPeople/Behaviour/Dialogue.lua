local Text = require "ProjectPeople/Content/Dialogue"
local Mind = require "ProjectPeople/Behaviour/Mind"
local Dialogue = {}

function Dialogue.reply(world, personId, visitorId)
    local p = world.people[personId]
    if not p or p.life == "dead" then
        return Text.household.unavailable
    end
    if p.life == "critical" then
        return Text.household.critical
    end
    local personal = Mind.reply(p, visitorId)
    if personal then
        return personal
    end
    if personId == "mara" then
        return Text.household.mara
    elseif personId == "owen" then
        local relation = p.relationships[visitorId]
        if relation and relation.trust >= 20 then
            return Text.household.owenTrusted
        end
        return Text.household.owen
    elseif personId == "ellis" then
        return Text.household.ellis
    end
    return p.background ~= "" and p.background or Text.household.fallback
end
return Dialogue
