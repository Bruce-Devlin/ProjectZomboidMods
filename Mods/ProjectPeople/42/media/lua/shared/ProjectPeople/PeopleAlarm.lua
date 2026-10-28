local FriendlyFire = require "ProjectPeople/FriendlyFire"
local Alarm = {}

-- Evaluate the actual observer, independently of friendly-fire preferences.
-- Multiplayer does this on the authority; no relationships need replicating.
function Alarm.friends(world, playerId, eachBody)
    local friends = {}
    eachBody(function(actor, record)
        if FriendlyFire.friendly(world, record.personId, playerId) then
            friends[actor] = true
        end
    end)
    return friends
end

local function snapshot(list)
    local result = {}
    for i = 0, list:size() - 1 do
        result[list:get(i)] = true
    end
    return result
end

-- Replay only the count made by installed IsoPlayer.updateLOS, in its spotted
-- order. New close sightings add two as well as the ordinary same-room count;
-- the surprise radius expands after the running raw count exceeds four.
function Alarm.contribution(player, friends, previouslySpotted)
    local raw, friendly = 0, 0
    local spotted = player:getSpottedList()
    local square = player:getCurrentSquare()
    if not square then
        return 0, 0
    end
    for i = 0, spotted:size() - 1 do
        local actor = spotted:get(i)
        if instanceof(actor, "IsoZombie") and actor:getCurrentSquare() then
            local dx, dy = actor:getX() - player:getX(), actor:getY() - player:getY()
            local distance = math.sqrt(dx * dx + dy * dy)
            local count = 0
            if
                actor:getZ() >= player:getZ() - 1
                and distance < 7
                and not actor:isFakeDead()
                and actor:getCurrentSquare():getRoom() == square:getRoom()
            then
                count = 1
            end
            raw = raw + count
            local radius = raw > 4 and 7 or 4
            if
                distance < radius
                and math.floor(actor:getZ()) == math.floor(player:getZ())
                and not previouslySpotted[actor]
            then
                raw = raw + 2
                count = count + 2
            end
            if friends[actor] then
                friendly = friendly + count
            end
        end
    end
    return friendly, raw
end

function Alarm.new()
    local self = { pending = {}, previous = setmetatable({}, { __mode = "k" }) }

    function self:begin(player, friends)
        local hasFriends = false
        for _ in pairs(friends) do
            hasFriends = true
            break
        end
        local previous = self.previous[player]
        if not hasFriends and (not previous or previous.raw == previous.filtered) then
            self.pending[player], self.previous[player] = nil, nil
            return
        end
        local stats = player:getStats()
        local damage = player:getBodyDamage()
        local oldRaw = damage:getOldNumZombiesVisible()
        self.pending[player] = {
            friends = friends,
            spotted = snapshot(player:getLastSpotted()),
            panic = stats:get(CharacterStat.PANIC),
            raw = oldRaw,
            -- A different native baseline means a load/reset or another mod's
            -- change. Start conservatively rather than suppress a real threat.
            filtered = previous and previous.raw == oldRaw and previous.filtered or oldRaw,
        }
    end

    function self:finish()
        for player, before in pairs(self.pending) do
            self.pending[player] = nil
            if not player:isDead() then
                local stats = player:getStats()
                local damage = player:getBodyDamage()
                local raw = stats:getNumVisibleZombies()
                local friendly, replayed = Alarm.contribution(player, before.friends, before.spotted)
                -- Native ghost is an unexposed field. Ghost/debug bodies,
                -- engine changes or competing LOS modifications can differ:
                -- never guess and suppress a real threat in those cases.
                if replayed == raw and damage:getOldNumZombiesVisible() == raw then
                    local filtered = math.max(0, raw - friendly)
                    local actual = math.max(0, raw - before.raw)
                    local wanted = math.max(0, filtered - before.filtered)
                    if actual ~= wanted then
                        local after = stats:get(CharacterStat.PANIC)
                        -- Use native panic rules for traits, beta blockers,
                        -- vehicles, survival time, sleep and saturation. Keep
                        -- changes from other panic sources in the same update.
                        local function outcome(count)
                            stats:set(CharacterStat.PANIC, before.panic)
                            -- Even a zero increase applies the native
                            -- Desensitized reset before ordinary recovery.
                            damage:IncreasePanic(count)
                            if count == 0 then
                                damage:ReducePanic()
                            end
                            return stats:get(CharacterStat.PANIC)
                        end
                        local native = outcome(actual)
                        local desired = outcome(wanted)
                        stats:set(CharacterStat.PANIC, after + desired - native)
                    end
                    self.previous[player] = { raw = raw, filtered = filtered }
                else
                    self.previous[player] = nil
                end
            else
                self.previous[player] = nil
            end
        end
    end

    return self
end

return Alarm
