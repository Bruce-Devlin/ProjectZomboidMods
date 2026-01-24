require "shared/AgeConfig"

local function playerBirthday(player, oldAge, newAge)
    local md = player:getModData()
    local yearsGained = newAge - oldAge
    local newGroup = AgeSystem.getGroup(newAge)

    md.Age = newAge

    AgeSystem.removeNonFittingAgeTraits(player, newGroup)
    AgeSystem.addRandomAgeTrait(player, newGroup)

    if DevTools.chance(30, 100) then
        DevTools.saySafe(player, "I can't believe I am " .. md.Age .. " years old today, and I found a party hat!")
        local partyHat = player:getInventory():AddItem("Base.Hat_PartyHat_Stars")
        if partyHat then
            partyHat:setName(tostring(player:getUsername()) .. "'s " .. tostring(newAge) .. " birthday hat!")
            partyHat:setTooltip("A lucky birthday hat")
        end
    else 
        DevTools.saySafe(player, "I am " .. md.Age .. " years old today!")
    end

    DevTools.debugLog("Getting Old", "Player aged up by " .. yearsGained .. " years to " .. md.Age)
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

        if not md.birthDayCount then
            local yearLength = AgeConfig.getYearLengthDays()
            if yearLength < 1 then yearLength = 1 end

            md.startAge = md.Age
            md.birthDayCount = totalDaysNow - (yearLength - 1)

            DevTools.debugLog("Getting Old",
                string.format(
                    "Initialized aging: startAge=%d today=%d birthDayCount=%d yearLength=%d",
                    md.startAge,
                    totalDaysNow,
                    md.birthDayCount,
                    yearLength
                )
            )
        end

        local daysAlive = totalDaysNow - md.birthDayCount
        if daysAlive < 0 then
            DevTools.debugLog("Getting Old", "Negative age days detected, skipping")
            return
        end

        DevTools.debugLog("Getting Old", "Days alive: " .. tostring(daysAlive))

        AgeSystem.apply(player)

        local yearLength = AgeConfig.getYearLengthDays()
        if yearLength < 1 then yearLength = 1 end

        local yearsPassed = math.floor(daysAlive / yearLength)
        local expectedAge = md.startAge + yearsPassed

        local daysIntoYear = daysAlive % yearLength
        local daysUntilBirthday = yearLength - daysIntoYear
        if daysUntilBirthday == yearLength then
            daysUntilBirthday = 0
        end

        DevTools.debugLog(
            "Getting Old",
            string.format(
                "Expected age: %d | Start age: %d | Days alive: %d | Days into year: %d | Days until birthday: %d",
                expectedAge,
                md.startAge,
                daysAlive,
                daysIntoYear,
                daysUntilBirthday
            )
        )

        local player = getPlayerByOnlineID(playerID)
        if playerID == 0 then player = getPlayer() end
        if not player then return end

        if expectedAge > md.Age then
            playerBirthday(player, md.Age, expectedAge)
        end
    end
end



Events.EveryHours.Add(checkPlayerAge)
DevTools.debugLog("Getting Old", "Player aging hooked")

