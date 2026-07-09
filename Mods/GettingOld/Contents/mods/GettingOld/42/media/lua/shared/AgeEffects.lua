AgeSystem = AgeSystem or {}
local function RollRemoveStat(stats, stat, value, chance)
    if DevTools.chance(chance, 100) then
        stats:remove(stat, value)
    end
end

local function RollAddStat(stats, stat, value, chance)
    if DevTools.chance(chance, 100) then
        stats:add(stat, value)
    end
end

function AgeSystem.updatePlayerHair(player)
    if not player then return end

    local md = player:getModData()
    if not md.Age then return end

    local visual = player:getHumanVisual()
    if not visual then return end

    if not md.baseHairColor then
        local base = visual:getHairColor()
        md.baseHairColor = {
            r = base:getRedFloat(),
            g = base:getGreenFloat(),
            b = base:getBlueFloat()
        }
    end

    local age = md.Age
    local greyFactor = 0

    if age >= 30 then
        greyFactor = math.min((age - 30) / 50, 1.0)
    end

    if md.lastGreyFactor and math.abs(md.lastGreyFactor - greyFactor) < 0.01 then
        return
    end
    md.lastGreyFactor = greyFactor

    local r = md.baseHairColor.r + (1.0 - md.baseHairColor.r) * greyFactor
    local g = md.baseHairColor.g + (1.0 - md.baseHairColor.g) * greyFactor
    local b = md.baseHairColor.b + (1.0 - md.baseHairColor.b) * greyFactor

    local newColor = ImmutableColor.new(r, g, b)

    visual:setHairColor(newColor)
    visual:setBeardColor(newColor)

    player:resetModelNextFrame()

    DevTools.debugLog(
        "Getting Old",
        string.format(
            "Hair updated | Age:%d Grey:%.2f RGB:(%.2f,%.2f,%.2f)",
            age, greyFactor, r, g, b
        )
    )
end

function AgeSystem.apply(player)
    if not player then return end
    local md = player:getModData()
    if not md.Age then return end
    local age = md.Age

    DevTools.debugLog("Getting Old", "Applying player age (" .. age .. ")...")

    local group = AgeSystem.getGroup(age)
    local stats = player:getStats()
    local fallTriggered = false
    local deathTriggered = false

    AgeSystem.updatePlayerHair(player)

    if group == "Zoomer" or group == "Young" then
        RollAddStat(stats, CharacterStat.ENDURANCE, 0.015, 60)
        RollRemoveStat(stats, CharacterStat.FATIGUE, 0.015, 60)
        RollRemoveStat(stats, CharacterStat.PAIN, 0.015, 60)

    elseif group == "Middle" then
        RollRemoveStat(stats, CharacterStat.ENDURANCE, 0.010, 60)
        RollAddStat(stats, CharacterStat.PAIN, 0.010, 60)
        RollAddStat(stats, CharacterStat.FATIGUE, 0.010, 60)
        RollAddStat(stats, CharacterStat.STRESS, 0.010, 60)

    elseif group == "Elderly" then
        local ageFactor = math.max((age - 70) / 30, 0)

        if not md.dyingOfOldAge then
            local baseDeathChance = 0.002
            local tickChance = baseDeathChance * (1 + ageFactor * 5)

            if age > 80 and ZombRandFloat(0, 1) < tickChance then
                md.dyingOfOldAge = true
                DevTools.debugLog("Getting Old", "Elderly player marked for death...")
            end

            RollRemoveStat(stats, CharacterStat.ENDURANCE, 0.02, 60)
            RollAddStat(stats, CharacterStat.FATIGUE, 0.02, 60)
            RollAddStat(stats, CharacterStat.PAIN, 0.02, 60)
            RollAddStat(stats, CharacterStat.STRESS, 0.02, 60)
        else
            local decayBase = 0.030
            local decayVariance = ZombRandFloat(0, 0.002)
            local decay = decayBase + decayVariance
            local scaledDecay = decay * (1 + ageFactor * 5)

            RollRemoveStat(stats, CharacterStat.ENDURANCE, scaledDecay, 50)
            RollAddStat(stats, CharacterStat.FATIGUE, scaledDecay, 50)
            RollAddStat(stats, CharacterStat.PAIN, scaledDecay, 50)
            RollAddStat(stats, CharacterStat.STRESS, scaledDecay, 50)

            local bodyDamage = player:getBodyDamage()
            local currBodyHealth = bodyDamage:getOverallBodyHealth()
            local currHealth = player:getHealth()

            bodyDamage:setOverallBodyHealth(currBodyHealth - scaledDecay)
            local healthDecay = scaledDecay / 2
            player:setHealth(currHealth - healthDecay)

            DevTools.debugLog("Getting Old",
                string.format("Dying of old age | Health: %.3f | Body: %.3f | Decay: %.4f",
                    currHealth, currBodyHealth, scaledDecay)
            )
        end

        if DevTools.chance(50, 100) then
            fallTriggered = true;
            stats:setTripping(true)
            stats:addTrippingRotAngle(ZombRandFloat(-0.35, 0.35))
            DevTools.debugLog("Getting Old", "Elderly stumble triggered")
        end
    end

    if isServer() then
        player:transmitModData()
        player:transmitVisual()
    end

    DevTools.debugLog("Getting Old",
    string.format(
        "Age:%d End:%.2f Fat:%.2f Pain:%.2f Stress:%.2f Tripping:%s",
        age,
        stats:get(CharacterStat.ENDURANCE),
        stats:get(CharacterStat.FATIGUE),
        stats:get(CharacterStat.PAIN),
        stats:get(CharacterStat.STRESS),
        tostring(fallTriggered)
    )
)
end
