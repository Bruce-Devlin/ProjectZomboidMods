local GettingOldRegistry = require("GettingOld/Registries")

local function assignAgeFromTraits(player)
    if not player then return end
    local md = player:getModData()
    if not md then return end
    if md.Age then return end

    if player:hasTrait(GettingOldRegistry.Young) then
        md.Age = 21
    elseif player:hasTrait(GettingOldRegistry.Adult) then
        md.Age = 30
    elseif player:hasTrait(GettingOldRegistry.Middle) then
        md.Age = 45
    elseif player:hasTrait(GettingOldRegistry.Elderly) then
        md.Age = 70
    else
        md.Age = ZombRand(25, 35)
    end

    DevTools.debugLog("Getting Old", "Assigned Age: " .. md.Age)
end

Events.OnPlayerUpdate.Add(function()
    local player = getPlayer()
    if not player then return end

    local md = player:getModData()
    if md._AgeAssigned then return end

    DevTools.debugLog("Getting Old", "Starting Server Init")

    assignAgeFromTraits(player)
    if not md.birthDay or not md.birthMonth or not md.birthYear then
        local gt = getGameTime()
        local currentYear = gt:getYear()
        local currentMonth = gt:getMonth() + 1
        local currentDay = gt:getDay() + 1
        
        md.birthYear = currentYear - md.Age
        md.birthMonth = currentMonth
        md.birthDay = currentDay + 1
    end
    md._AgeAssigned = true

    AgeSystem.apply(player)
    DevTools.debugLog("Getting Old", "Server Init complete")
end)
DevTools.debugLog("Getting Old", "Server Init Hooked.")