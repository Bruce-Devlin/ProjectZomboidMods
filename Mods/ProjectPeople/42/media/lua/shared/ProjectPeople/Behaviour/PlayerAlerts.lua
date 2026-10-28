local Lines = require "ProjectPeople/Content/PlayerAlerts"
local Space = require "ProjectPeople/Pathing/CombatSpace"
local Alerts = { RADIUS = 6, COOLDOWN = 15 * 60 * 1000, DURATION = 5500, CROWD_GAP = 8000 }

function Alerts.eligible(actor, record, player, clear, continuing)
    return actor
            and player
            and record
            and not actor:isDead()
            and not player:isDead()
            and not record.dead
            and not record.missing
            and not record.transferReserved
            and not record.socialPartner
            and not record.combatActive
            and not record.attacking
            and not record.fleeing
            and not record.retreating
            and not record.cautious
            and (continuing or Space.distance(actor, player) <= Alerts.RADIUS ^ 2 and clear(actor, player))
        or false
end

function Alerts.new(random)
    local states, nextSpeech, output, holds, lastNow = {}, {}, {}, {}, 0
    local self = {}
    function self:step(candidates, players, now, eligible, continuing)
        if now < lastNow then
            states, nextSpeech = {}, {}
        end
        lastNow, output, holds = now, {}, {}
        local ids, playerIds = {}, {}
        for id in pairs(candidates) do
            ids[#ids + 1] = id
        end
        for id in pairs(players) do
            playerIds[#playerIds + 1] = id
        end
        table.sort(ids)
        table.sort(playerIds)
        for _, playerId in ipairs(playerIds) do
            local perPlayer = states[playerId] or {}
            states[playerId], output[playerId] = perPlayer, {}
            for _, id in ipairs(ids) do
                local entry = perPlayer[id]
                local canNotice = eligible(id, candidates[id], players[playerId])
                if canNotice then
                    entry = entry or { nextAt = 0 }
                    perPlayer[id] = entry
                    if not entry.inside then
                        entry.pending = now >= entry.nextAt
                    end
                    entry.inside, entry.seen = true, now
                    if entry.pending and now >= (nextSpeech[playerId] or 0) then
                        local pick = random(#Lines) + 1
                        if pick == entry.last then
                            pick = pick % #Lines + 1
                        end
                        entry.last, entry.text = pick, Lines[pick]
                        entry.untilAt, entry.nextAt = now + Alerts.DURATION, now + Alerts.COOLDOWN
                        entry.pending = false
                        nextSpeech[playerId] = now + Alerts.CROWD_GAP
                    end
                    if entry.text and now < entry.untilAt then
                        output[playerId][id] = entry.text
                    end
                elseif entry then
                    entry.inside, entry.pending = false, false
                    if not continuing or not continuing(id, candidates[id], players[playerId]) then
                        entry.text = nil
                    end
                end
                if entry and entry.text and now < entry.untilAt then
                    output[playerId][id] = entry.text
                    holds[id] = holds[id] or playerId
                end
            end
        end
        for playerId, perPlayer in pairs(states) do
            local count = 0
            for id, entry in pairs(perPlayer) do
                if not players[playerId] or not candidates[id] then
                    entry.inside, entry.pending, entry.text = false, false, nil
                end
                if now >= entry.nextAt and now - entry.seen > Alerts.COOLDOWN then
                    perPlayer[id] = nil
                else
                    count = count + 1
                end
            end
            if count == 0 then
                states[playerId], nextSpeech[playerId] = nil, nil
            end
        end
    end
    function self:line(personId, playerId)
        return output[playerId] and output[playerId][personId] or nil
    end
    function self:holding(personId)
        return holds[personId]
    end
    function self:cancel(personId)
        holds[personId] = nil
        for playerId, entries in pairs(states) do
            if entries[personId] then
                entries[personId].text = nil
                entries[personId].pending = false
            end
            if output[playerId] then
                output[playerId][personId] = nil
            end
        end
    end
    return self
end
return Alerts
