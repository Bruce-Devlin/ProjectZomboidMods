-- Session-local permission to assist a commander's fight. Never grants person hostility.
local Settings = require "ProjectPeople/Pathing/Settings"
local Space = require "ProjectPeople/Pathing/CombatSpace"
local Companion = {}

function Companion.new()
    local fighting, assisting = {}, {}
    local self = {}
    function self:started(id, actor, now)
        if id and actor and not actor:isDead() then
            fighting[id] = { actor = actor, at = now }
        end
    end
    function self:step(person, record, actor, leader, now)
        local signal = fighting[person.commanderId]
        local active = person.duty == "follow"
            and person.life == "alive"
            and not person.jobId
            and not person.missionId
            and not person.reservationId
            and not person.transitionId
            and leader
            and not leader:isDead()
            and Space.distance(actor, leader) <= Settings.follow.assistLeash ^ 2
        if not active then
            assisting[person.id] = nil
        elseif signal and signal.actor == leader and now - signal.at <= 1500 then
            assisting[person.id] = leader
        end
        local enabled = active and assisting[person.id] == leader or false
        record.companionCombat = enabled
        record.leaderX = enabled and leader:getX() or nil
        record.leaderY = enabled and leader:getY() or nil
        record.leaderZ = enabled and leader:getZ() or nil
        -- Expired start signals cannot re-enable combat after catching up.
        for id, event in pairs(fighting) do
            if now - event.at > 1500 then
                fighting[id] = nil
            end
        end
        return enabled
    end
    return self
end
return Companion
