local Lines = require "ProjectPeople/Content/AmbientDialogue"
local Ambient = {}

function Ambient.category(record, actor)
    if record.dead or record.missing or record.transferReserved or record.fleeing then
        return nil
    end
    local fighting = record.combatActive == true or record.attacking == true
    if record.duty == "follow" or record.duty == "wait" then
        return fighting and "followerAggressive" or "followerPassive"
    end
    if record.duty == "base" then
        if fighting then
            return "strangerAggressive"
        end
        if
            record.homeX
            and record.homeY
            and record.homeZ
            and math.abs(actor:getZ() - record.homeZ) < 0.2
            and (actor:getX() - record.homeX) ^ 2 + (actor:getY() - record.homeY) ^ 2 <= 10 ^ 2
        then
            return "base"
        end
        return nil
    end
    return fighting and "strangerAggressive" or "strangerPassive"
end

-- Independent presentation PRNG: never consumes the world's simulation RNG.
function Ambient.new(seed)
    local state, nextSpeech, lastNow = {}, 0, 0
    seed = math.max(1, math.floor(seed or 1) % 2147483647)
    local function random(count)
        seed = (seed * 16807) % 2147483647
        return seed % count + 1
    end
    local self = {}
    function self:begin(now)
        if now < lastNow then
            state, nextSpeech = {}, 0
        end
        lastNow = now
        for id, entry in pairs(state) do
            if now - entry.seen > 120000 then
                state[id] = nil
            end
        end
    end
    function self:line(id, category, now)
        if not id or not Lines[category] then
            if id then
                state[id] = nil
            end
            return nil
        end
        local entry = state[id]
        if not entry or entry.category ~= category then
            entry = { category = category, due = now + 12000 + random(23000), seen = now }
            state[id] = entry
        end
        entry.seen = now
        if entry.text and now < entry.untilAt then
            return entry.text
        end
        entry.text = nil
        if now < entry.due or now < nextSpeech then
            return nil
        end
        local pool = Lines[category]
        local pick = random(#pool)
        if pick == entry.last and #pool > 1 then
            pick = pick % #pool + 1
        end
        entry.last, entry.text = pick, pool[pick]
        entry.untilAt = now + 5500
        entry.due = now + 35000 + random(40000)
        nextSpeech = now + 8000
        return entry.text
    end
    function self:reset()
        state, nextSpeech = {}, 0
    end
    return self
end
return Ambient
