AgeSystem = AgeSystem or {}
local function RollRemoveStat(stats, stat, value, chance)
    local rnd = ZombRand(100)
    if rnd < chance then
        stats:remove(stat, value)
    end
end

local function RollAddStat(stats, stat, value, chance)
    local rnd = ZombRand(100)
    if rnd < chance then
        stats:add(stat, value)
    end
end

function AgeSystem.apply(player)
    if not player then return end
    local md = player:getModData()
    if not md.Age then return end

    DevTools.debugLog("Getting Old", "Applying player age (" .. md.Age .. ")...")

    local group = AgeSystem.getGroup(md.Age)
    local stats = player:getStats()
    local fallTriggered = false

    if group == "Zoomer" or group == "Young" then
        RollAddStat(stats, CharacterStat.ENDURANCE, 0.015, 50)
        RollRemoveStat(stats, CharacterStat.FATIGUE, 0.015, 50)
        RollRemoveStat(stats, CharacterStat.PAIN, 0.015, 50)

    elseif group == "Middle" then
        RollRemoveStat(stats, CharacterStat.ENDURANCE, 0.25, 50)
        RollAddStat(stats, CharacterStat.PAIN, 0.025, 50)
        RollAddStat(stats, CharacterStat.FATIGUE, 0.025, 50)
        RollAddStat(stats, CharacterStat.STRESS, 0.025, 50)

    elseif group == "Elderly" then
        RollRemoveStat(stats, CharacterStat.ENDURANCE, 0.015, 50)
        RollAddStat(stats, CharacterStat.PAIN, 0.015, 50)
        RollAddStat(stats, CharacterStat.FATIGUE, 0.015, 50)
        RollAddStat(stats, CharacterStat.STRESS, 0.015, 50)

        local chance = ZombRand(100)
        if chance < 50 then
            fallTriggered = true;
            stats:setTripping(true)
            stats:addTrippingRotAngle(ZombRandFloat(-0.35, 0.35))
            DevTools.debugLog("Getting Old", "Elderly stumble triggered")
        end
    end

    DevTools.debugLog("Getting Old",
    string.format(
        "Age:%d End:%.2f Fat:%.2f Pain:%.2f Stress:%.2f Tripping:%s",
        md.Age,
        stats:get(CharacterStat.ENDURANCE),
        stats:get(CharacterStat.FATIGUE),
        stats:get(CharacterStat.PAIN),
        stats:get(CharacterStat.STRESS),
        tostring(fallTriggered)
    )
)
end
