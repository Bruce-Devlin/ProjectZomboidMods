Events.OnPlayerUpdate.Add(function(player)
    DevTools.waitSeconds(10, AgeSystem.apply(player))
end)

local function updatePlayerAge()
    DevTools.debugLog("Getting Old", "Updating players age...")
    for i=0,getNumActivePlayers()-1 do
        local player = getSpecificPlayer(i)
        if not player then return end
        local md = player:getModData()
        if not md.birthYear or not md.Age then return end

        local gt = getGameTime()
        local currentDay = gt:getDay()
        local currentMonth = gt:getMonth()
        local currentYear = gt:getYear()

        if currentMonth > md.birthMonth or (currentMonth == md.birthMonth and currentDay >= md.birthDay) then
            local expectedAge = currentYear - md.birthYear
            if expectedAge > md.Age then
                md.Age = expectedAge
                DevTools.saySafe(getPlayer(), "I am " .. md.Age .. " years old today!")
            end
        end
    end
end

Events.EveryHours.Add(updatePlayerAge)
DevTools.debugLog("Getting Old", "Player aging hooked")

