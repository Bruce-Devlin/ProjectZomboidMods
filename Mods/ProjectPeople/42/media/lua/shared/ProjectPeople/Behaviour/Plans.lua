-- Idle priorities, in order: orders, recovery, family, company, rest, watch.
local Settings = require "ProjectPeople/Behaviour/Settings"
local DevTools = require "ProjectPeople/DevTools"
local Text = require "ProjectPeople/Content/Dialogue"
local Plans = {}
local hash = DevTools.hash

function Plans.choose(person, now, seen)
    local mind = person.mind
    if
        not mind
        or not mind.policy.enabled
        or not mind.policy.autonomy
        or person.life ~= "alive"
        or person.controller.kind ~= "ai"
        or person.jobId
        or person.missionId
        or person.reservationId
        or person.transitionId
        or seen.threat
    then
        return nil
    end
    if person.duty == "follow" then
        return nil
    end
    if person.duty == "wait" then
        return {
            kind = "wait",
            activity = mind.strain >= Settings.plans.waitStrain and Text.mind.breather or "Waiting here",
            resting = true,
        }
    end
    if mind.strain >= Settings.plans.restStrain or mind.stress >= Settings.plans.restStress then
        return { kind = "rest", activity = Text.mind.rest, resting = true }
    end
    local relatives = {}
    for id, condition in pairs(seen.family or {}) do
        if person.family[id] and condition == "hurt" then
            relatives[#relatives + 1] = id
        end
    end
    table.sort(relatives)
    if relatives[1] and mind.personality.compassion >= Settings.plans.familyCompassion then
        return { kind = "company", targetId = relatives[1], activity = Text.mind.injuredCompany }
    end
    local slot = (math.floor(now * 2) + hash(person.id)) % 4
    if slot == 0 and mind.personality.sociability >= Settings.plans.companySociability and seen.companionId then
        return { kind = "company", targetId = seen.companionId, activity = Text.mind.companion }
    end
    if slot == 1 then
        return { kind = "rest", activity = Text.mind.rest, resting = true }
    end
    return {
        kind = "watch",
        activity = mind.personality.conscientiousness >= Settings.plans.watchConscientiousness and Text.mind.houseWatch
            or Text.mind.watch,
    }
end

return Plans
