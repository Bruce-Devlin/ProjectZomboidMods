-- Consent and proficiency are domain rules; no client may supply either.
local Policy = { TRADE_TRUST = 10 }

function Policy.access(person, visitor, record, gift)
    if not person or person.life ~= "alive" or not person.controller or person.controller.kind ~= "ai" then
        return false, "This person is unavailable."
    end
    if person.reservationId or person.transitionId or person.missionId or person.jobId then
        return false, "They must finish their current assignment first."
    end
    if
        record
        and (record.combatActive or record.attacking or record.fleeing or record.avoiding or record.transferReserved)
    then
        return false, "Wait until they are safe before exchanging equipment."
    end
    local rel = (person.relationships or {})[visitor] or {}
    local threshold = gift and 0 or Policy.TRADE_TRUST
    if (rel.trust or 0) < threshold or (rel.fear or 0) >= 60 then
        if gift then
            return false, "They do not feel comfortable accepting a gift from you."
        end
        return false, "They need at least " .. Policy.TRADE_TRUST .. " trust in you before sharing their inventory."
    end
    if person.commanderId and person.commanderId ~= visitor then
        return false, "They are travelling with someone else."
    end
    return true
end

local function clamp(n, lo, hi)
    return math.max(lo, math.min(hi, tonumber(n) or lo))
end

function Policy.skill(person, name)
    local skills = person.character and person.character.skills or person.skills or {}
    local value = skills[name]
    if type(value) == "table" then
        value = value.level
    end
    if type(value) == "number" then
        return clamp(value, 0, 10)
    end
    -- Stable starting aptitude for people without authored skill records.
    local hash = 17
    local key = tostring(person.id) .. ":" .. name
    for i = 1, #key do
        hash = (hash * 31 + string.byte(key, i)) % 65521
    end
    return hash % 4
end

function Policy.proficiency(person, ranged, health, distance, range, category)
    local personality = person.personality or {}
    local skill = Policy.skill(person, ranged and "Aiming" or category or "Blunt")
    local focus = clamp(personality.conscientiousness or 50, 0, 100) / 100
    local caution = clamp(personality.caution or 50, 0, 100) / 100
    local fitness = clamp(health, 0.25, 1)
    local accuracy = (ranged and (0.3 + skill * 0.055 + focus * 0.1) or (0.62 + skill * 0.025 + focus * 0.08)) * fitness
    if ranged then
        accuracy = accuracy * (1 - 0.45 * clamp(distance / math.max(1, range), 0, 1))
    end
    return {
        skill = skill,
        accuracy = clamp(accuracy, 0.05, 0.96),
        damage = (0.65 + skill * 0.055) * fitness,
        windupMs = math.floor((ranged and 1100 or 700) * (1.2 - skill * 0.035 + caution * 0.15)),
        cooldownMs = math.floor((ranged and 1500 or 1300) * (1.2 - skill * 0.035)),
    }
end
return Policy
