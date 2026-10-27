-- Per-person preference. Missing values in older saves mean protection is on.
local FriendlyFire = {}

function FriendlyFire.friendly(world, id, playerId)
    local p = world and world.people[id]
    local player = world and world.people[playerId]
    if
        not p
        or not player
        or not p.controller
        or p.controller.kind ~= "ai"
        or not player.controller
        or player.controller.kind ~= "player"
        or p.life == "dead"
    then
        return false
    end
    if p.commanderId == playerId then
        return true
    end
    if p.communityId and p.communityId == player.communityId then
        return true
    end
    local rel = (p.relationships or {})[playerId]
    return rel ~= nil
            and (rel.trust or 0) > 0
            and (rel.fear or 0) < 60
            and not (rel.anchors and (rel.anchors["violence:" .. playerId] or rel.anchors["threat:" .. playerId]))
        or false
end

function FriendlyFire.canSet(world, id, playerId)
    local p = world and world.people[id]
    return p ~= nil and (not p.commanderId or p.commanderId == playerId) and FriendlyFire.friendly(world, id, playerId)
end

function FriendlyFire.protected(world, id, playerId)
    local p = world and world.people[id]
    return p ~= nil and p.friendlyFire ~= true and FriendlyFire.friendly(world, id, playerId)
end
-- Only the protection decision, keyed by replicated player ID, leaves the
-- authority. Private relationships and character identities stay server-side.

function FriendlyFire.players(world, id, online, identity)
    local result = {}
    for i = 0, online:size() - 1 do
        local actor = online:get(i)
        local who = identity(actor)
        if who and who.validated and who.alive and FriendlyFire.protected(world, id, who.personId) then
            result[tostring(actor:getOnlineID())] = true
        end
    end
    return result
end

function FriendlyFire.block(attacker, victim, protected)
    if not protected or not attacker or not victim or attacker == victim or not instanceof(attacker, "IsoPlayer") then
        return false
    end
    -- IsoGameCharacter.Hit consumes this flag immediately after its Lua event,
    -- before hit consequences, including lethal damage. Never heal afterwards.
    victim:setAvoidDamage(true)
    return true
end
return FriendlyFire
