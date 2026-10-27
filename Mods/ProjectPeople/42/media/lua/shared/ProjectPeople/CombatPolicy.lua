-- Shared rules, independent of body representation. Probability is supplied by
-- the authority; clients cannot choose hits, enemies or hostility rolls.
local Policy = { VERSION = 1, HOSTILE_PERCENT = 3, NOTICE_RADIUS = 12, MELEE_REACH = 1.25 }
local matchups = {
    player = { damage = 0.06, accuracy = 0.45, windupMs = 1200, cooldownMs = 2600 },
    npc = { damage = 0.18, accuracy = 0.65, windupMs = 850, cooldownMs = 1800 },
    zombie = { damage = 0.45, accuracy = 0.82, windupMs = 650, cooldownMs = 1400 },
}

function Policy.matchup(kind)
    local source = matchups[kind]
    if not source then
        return nil
    end
    return {
        damage = source.damage,
        accuracy = source.accuracy,
        windupMs = source.windupMs,
        cooldownMs = source.cooldownMs,
    }
end

function Policy.hostile(roll, percent)
    percent = math.max(0, math.min(100, percent or Policy.HOSTILE_PERCENT))
    return type(roll) == "number" and roll >= 0 and roll < percent
end

function Policy.choose(candidates)
    local chosen, priority, distance
    for _, candidate in ipairs(candidates) do
        local valid = candidate.alive
            and candidate.visible
            and candidate.distanceSquared >= 0
            and candidate.distanceSquared <= Policy.NOTICE_RADIUS ^ 2
        local rank = candidate.kind == "zombie" and 0 or candidate.enemy and 1 or nil
        if
            valid
            and rank
            and (
                not chosen
                or rank < priority
                or rank == priority
                    and (candidate.distanceSquared < distance or candidate.distanceSquared == distance and tostring(
                        candidate.id
                    ) < tostring(chosen.id))
            )
        then
            chosen, priority, distance = candidate, rank, candidate.distanceSquared
        end
    end
    return chosen
end

function Policy.contact(kind, roll, healthFraction)
    local rules = Policy.matchup(kind)
    if not rules or type(roll) ~= "number" or roll < 0 or roll >= 1 then
        return false, 0
    end
    local fitness = math.max(0.25, math.min(1, healthFraction or 1))
    local hit = roll < rules.accuracy * (0.6 + 0.4 * fitness)
    return hit, hit and rules.damage * fitness or 0
end
return Policy
