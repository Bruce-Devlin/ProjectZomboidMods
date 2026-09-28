AgeSystem = AgeSystem or {}
local OLD_AGE_DURATION_MIN_FACTOR = 0.9
local OLD_AGE_DURATION_MAX_FACTOR = 1.1
local OLD_AGE_WARNINGS = {
    { progress = 0.10, text = "UI_GettingOld_OldAgeWarning_1" },
    { progress = 0.45, text = "UI_GettingOld_OldAgeWarning_2" },
    { progress = 0.70, text = "UI_GettingOld_OldAgeWarning_3" },
    { progress = 0.88, text = "UI_GettingOld_OldAgeWarning_4" },
    { progress = 0.97, text = "UI_GettingOld_OldAgeWarning_5" }
}

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

local function tripPlayer(player)
    if not player or not player:isAlive() then return false end
    if player:isOnFloor() or player:isKnockedDown() then return false end

    player:setBumpType("stagger")
    player:setVariable("BumpDone", false)
    player:setVariable("BumpFall", true)
    player:setVariable("BumpFallType", "pushedFront")
    return true
end

local function getOldAgeDeclineProgress(player, md, age, declineYears, yearLength)
    local survivedHours = player:getHoursSurvived()

    -- Preserve progress from saves created before precise survival-hour timing.
    if not md._GettingOldMarkedForDeathHoursSurvived then
        local previousProgress = tonumber(md._GettingOldOldAgeDeclineProgress)
        if not previousProgress then
            local markedAge = tonumber(md._GettingOldMarkedForDeathAge)
            previousProgress = markedAge and math.max(0, age - markedAge) / declineYears or 0
        end

        md._GettingOldMarkedForDeathHoursSurvived = survivedHours
        md._GettingOldOldAgeDeclineBaseProgress = math.min(1, previousProgress)
    end

    local baseProgress = tonumber(md._GettingOldOldAgeDeclineBaseProgress) or 0
    local elapsedHours = math.max(0, survivedHours - md._GettingOldMarkedForDeathHoursSurvived)
    local progress = math.min(1, baseProgress + elapsedHours / (yearLength * 24 * declineYears))
    local previousProgress = tonumber(md._GettingOldOldAgeDeclineProgress) or baseProgress

    md._GettingOldOldAgeDeclineProgress = progress
    return progress, math.max(0, progress - previousProgress)
end

local function announceOldAgeWarning(player, md, progress)
    local warnedStage = tonumber(md._GettingOldOldAgeWarningStage) or 0
    local reachedStage = warnedStage

    for stage, warning in ipairs(OLD_AGE_WARNINGS) do
        if progress >= warning.progress then
            reachedStage = stage
        end
    end

    if reachedStage <= warnedStage then return end

    md._GettingOldOldAgeWarningStage = reachedStage
    DevTools.saySafe(player, getText(OLD_AGE_WARNINGS[reachedStage].text))
    DevTools.debugLog(
        "Getting Old",
        string.format("Old age warning stage %d at %.1f%% decline", reachedStage, progress * 100)
    )
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

local function applyOldAgeHealthDecline(player, md, age)
    local deadlyAge = AgeConfig.getDeadlyAge()
    if deadlyAge <= 0 then return end

    if not md.dyingOfOldAge and age >= deadlyAge then
        md.dyingOfOldAge = true
        md._GettingOldMarkedForDeathAge = age
        md._GettingOldMarkedForDeathDay = getGameTime():getDaysSurvived()
        md._GettingOldMarkedForDeathHoursSurvived = player:getHoursSurvived()
        md._GettingOldOldAgeDeclineBaseProgress = 0
        md._GettingOldOldAgeDeclineProgress = 0
        DevTools.debugLog("Getting Old", "Player marked for death from old age at " .. tostring(age))
    end

    if not md.dyingOfOldAge then return end

    if not md._GettingOldMarkedForDeathAge then
        md._GettingOldMarkedForDeathAge = age
        md._GettingOldMarkedForDeathDay = getGameTime():getDaysSurvived()
    end

    local declineYears = tonumber(md._GettingOldYearsUntilDeath)
    if not declineYears or declineYears <= 0 then
        local configuredYears = AgeConfig.getYearsUntilDeath()
        local randomFactor = ZombRandFloat(OLD_AGE_DURATION_MIN_FACTOR, OLD_AGE_DURATION_MAX_FACTOR)
        declineYears = configuredYears * randomFactor
        md._GettingOldYearsUntilDeath = declineYears

        DevTools.debugLog(
            "Getting Old",
            string.format("Old age decline duration assigned: %.2f years", declineYears)
        )
    end

    local yearLength = math.max(AgeConfig.getYearLengthDays(), 1)
    local declineProgress, progressGained = getOldAgeDeclineProgress(player, md, age, declineYears, yearLength)
    local healthDecay = progressGained * 100
    local playerHealthDecay = healthDecay / 100
    local bodyDamage = player:getBodyDamage()
    local bodyHealth = bodyDamage:getOverallBodyHealth()
    local playerHealth = player:getHealth()
    local nextPlayerHealth = math.max(0, playerHealth - playerHealthDecay)
    local targetBodyHealth = math.min(bodyHealth, nextPlayerHealth * 100)

    announceOldAgeWarning(player, md, declineProgress)
    if declineProgress >= 1 or healthDecay > 0 then
        -- This persistent general-health value drives the native Health panel.
        -- It is also reconciled with the existing player-health decline so an
        -- in-progress save immediately displays its true remaining health.
        bodyDamage:ReduceGeneralHealth(math.max(0, bodyHealth - targetBodyHealth))
        player:setHealth(nextPlayerHealth)
    end

    DevTools.debugLog(
        "Getting Old",
        string.format("Dying of old age | Age: %d | Health: %.3f | Body: %.3f | Body decay: %.5f | Health decay: %.5f",
            age, playerHealth, bodyHealth, healthDecay, playerHealthDecay)
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
    local oldAgeDeathEnabled = AgeConfig.getDeadlyAge() > 0

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

        if not oldAgeDeathEnabled or not md.dyingOfOldAge then
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
        end

        if DevTools.chance(50, 100) then
            fallTriggered = tripPlayer(player)
            if fallTriggered then
                DevTools.debugLog("Getting Old", "Elderly stumble triggered a fall")
            end
        end
    end

    applyOldAgeHealthDecline(player, md, age)

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
