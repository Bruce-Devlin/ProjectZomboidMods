require "AgeConfig"

local BIRTHDAY_HAT_CHANCE = 30
local BIRTHDAY_HAT_ITEM = "Base.Hat_PartyHat_Stars"

local function syncBirthdayState(player)
    if isServer() then
        player:transmitModData()
    end
end

local function tryGiveBirthdayHat(player, md, newAge)
    if not AgeConfig.areBirthdayHatsEnabled() then
        md._GettingOldBirthdayHatCheckedAge = newAge
        return false
    end

    if md._GettingOldBirthdayHatCheckedAge == newAge then
        return false
    end

    md._GettingOldBirthdayHatCheckedAge = newAge

    if not DevTools.chance(BIRTHDAY_HAT_CHANCE, 100) then
        return false
    end

    local partyHat = player:getInventory():AddItem(BIRTHDAY_HAT_ITEM)
    if partyHat then
        partyHat:setName(tostring(player:getUsername()) .. "'s " .. tostring(newAge) .. " birthday hat!")
        partyHat:setTooltip("A lucky birthday hat")
        return true
    end

    return false
end

local function playerBirthday(player, oldAge, newAge)
    local md = player:getModData()
    local yearsGained = newAge - oldAge
    local newGroup = AgeSystem.getGroup(newAge)

    if md._GettingOldLastBirthdayAge == newAge then
        md.Age = newAge
        syncBirthdayState(player)
        DevTools.debugLog("Getting Old", "Birthday already handled for age " .. tostring(newAge))
        return
    end

    md.Age = newAge
    md._GettingOldLastBirthdayAge = newAge

    AgeSystem.removeNonFittingAgeTraits(player, newGroup)
    AgeSystem.addRandomAgeTrait(player, newGroup)

    if tryGiveBirthdayHat(player, md, newAge) then
        DevTools.saySafe(player, "I can't believe I am " .. md.Age .. " years old today, and I found a party hat!")
    else 
        DevTools.saySafe(player, "I am " .. md.Age .. " years old today!")
    end

    DevTools.debugLog("Getting Old", "Player aged up by " .. yearsGained .. " years to " .. md.Age)
    syncBirthdayState(player)
end

local function checkPlayerAge()
    DevTools.debugLog("Getting Old", "Updating players age...")

    local gt = getGameTime()
    local totalDaysNow = gt:getDaysSurvived()

    for i = 0, getNumActivePlayers() - 1 do
        local tmpPlayer = getSpecificPlayer(i)
        if not tmpPlayer then return end

        local playerID = tmpPlayer:getOnlineID()
        local player = getPlayerByOnlineID(playerID)
        if playerID == 0 then player = getPlayer() end
        if not player then return end

        local md = player:getModData()
        if not md.birthYear or not md.Age then return end

        DevTools.debugLog("Getting Old", "Checking player \"" .. tostring(player:getUsername()) .. "\" (age:" .. md.Age .. ") for age update...")

        local yearLength = AgeConfig.getYearLengthDays()
        if yearLength < 1 then yearLength = 1 end

        if not md._GettingOldAgeHoursSurvivedAnchor then
            local oldCycleDays
            if md.birthDayCount then
                oldCycleDays = math.max(0, totalDaysNow - md.birthDayCount)
            else
                md.birthDayCount = totalDaysNow - (yearLength - 1)
                oldCycleDays = yearLength - 1
            end

            md.startAge = md.startAge or md.Age
            md._GettingOldAgeHoursSurvivedAnchor = player:getHoursSurvived()
            md._GettingOldAgeCycleHoursAtAnchor = oldCycleDays * 24

            DevTools.debugLog("Getting Old",
                string.format(
                    "Initialized precise aging: startAge=%d survivedHours=%.2f cycleHours=%.2f yearLength=%d",
                    md.startAge,
                    md._GettingOldAgeHoursSurvivedAnchor,
                    md._GettingOldAgeCycleHoursAtAnchor,
                    yearLength
                )
            )
        end

        local survivedHours = player:getHoursSurvived()
        local hoursSinceAnchor = survivedHours - md._GettingOldAgeHoursSurvivedAnchor
        if hoursSinceAnchor < 0 then
            DevTools.debugLog("Getting Old", "Negative age hours detected, resetting aging anchor")
            md._GettingOldAgeHoursSurvivedAnchor = survivedHours
            hoursSinceAnchor = 0
        end

        local cycleHours = (tonumber(md._GettingOldAgeCycleHoursAtAnchor) or 0) + hoursSinceAnchor
        local yearHours = yearLength * 24
        local yearsPassed = math.floor(cycleHours / yearHours)
        local expectedAge = md.startAge + yearsPassed

        local hoursIntoYear = cycleHours % yearHours
        local hoursUntilBirthday = yearHours - hoursIntoYear
        if hoursUntilBirthday == yearHours then hoursUntilBirthday = 0 end

        DevTools.debugLog(
            "Getting Old",
            string.format(
                "Expected age: %d | Start age: %d | Hours survived: %.2f | Cycle hours: %.2f | Hours until birthday: %.2f",
                expectedAge,
                md.startAge,
                survivedHours,
                cycleHours,
                hoursUntilBirthday
            )
        )

        local player = getPlayerByOnlineID(playerID)
        if playerID == 0 then player = getPlayer() end
        if not player then return end

        if expectedAge > md.Age then
            playerBirthday(player, md.Age, expectedAge)
        end

        -- Birthday processing comes first so a terminal old-age update cannot
        -- kill the player while the UI still displays the previous age.
        AgeSystem.apply(player)

    end
end



Events.EveryHours.Add(checkPlayerAge)
DevTools.debugLog("Getting Old", "Player aging hooked")

