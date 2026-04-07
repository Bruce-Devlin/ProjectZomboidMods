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
        md.Age = ZombRand(25, 60)
    end

    DevTools.debugLog("Getting Old", "Assigned Age: " .. md.Age)
end

Events.OnCreatePlayer.Add(function(player)
    if not player then return end

    local md = player:getModData()
    if md._AgeAssigned then return end

    DevTools.debugLog("Getting Old", "Starting Server Player Init")

    assignAgeFromTraits(player)
    if not md.birthDay or not md.birthMonth or not md.birthYear then
        local gt = getGameTime()
        local currentYear = gt:getYear()
        
        md.birthYear = currentYear - md.Age
        md.birthMonth = ZombRand(1, 13) -- 1–12
        local currentYear = getGameTime():getYear()
        md.birthDay = ZombRand(1, 20 + 1)
    end
    md._AgeAssigned = true

    AgeSystem.apply(player)

    DevTools.debugLog("Getting Old", "Server Init complete")
end)
DevTools.debugLog("Getting Old", "Server Init Hooked.")