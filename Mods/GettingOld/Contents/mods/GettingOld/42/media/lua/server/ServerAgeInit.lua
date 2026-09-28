local GettingOldRegistry = require("GettingOld/Registries")
local MOD_ID = "GettingOld"

local function assignAgeFromTraits(player)
    if not player then return end
    local md = player:getModData()
    if not md then return end
    if md.Age then return end

    if player:hasTrait(GettingOldRegistry.Zoomer) then
        md.Age = 12
    elseif player:hasTrait(GettingOldRegistry.Young) then
        md.Age = 21
    elseif player:hasTrait(GettingOldRegistry.Adult) then
        md.Age = 30
    elseif player:hasTrait(GettingOldRegistry.Middle) then
        md.Age = 45
    elseif player:hasTrait(GettingOldRegistry.Elderly) then
        md.Age = 70
    else
        md.Age = AgeConfig.getStartingAge()
    end

    DevTools.debugLog("Getting Old", "Assigned Age: " .. md.Age)
end

local function finishAgeAssignment(player, birthdayMonth, birthdayDay)
    if not player then return end

    local md = player:getModData()
    if md._AgeAssigned then return end

    DevTools.debugLog("Getting Old", "Starting Server Init")

    assignAgeFromTraits(player)
    if not md.birthDay or not md.birthMonth or not md.birthYear then
        local gt = getGameTime()
        local currentYear = gt:getYear()

        md.birthYear = currentYear - md.Age
        if birthdayMonth and birthdayDay then
            md.birthMonth = birthdayMonth
            md.birthDay = birthdayDay
        else
            md.birthMonth, md.birthDay = AgeConfig.getBirthday(md.birthYear)
        end

        DevTools.debugLog(
            "Getting Old",
            string.format("Assigned Birthday: %02d/%02d/%04d", md.birthDay, md.birthMonth, md.birthYear)
        )
    end
    md._AgeAssigned = true
    md._GettingOldBirthdayChoicePending = nil
    md._GettingOldBirthdayMonth = nil
    md._GettingOldBirthdayDay = nil

    -- Use the player's exact survival time for aging. GameTime days are whole
    -- numbers, which is too coarse when a configured year is only one day.
    local yearLength = math.max(AgeConfig.getYearLengthDays(), 1)
    md.startAge = md.Age
    md._GettingOldAgeHoursSurvivedAnchor = player:getHoursSurvived()
    md._GettingOldAgeCycleHoursAtAnchor = (yearLength - 1) * 24

    AgeSystem.apply(player)
    player:transmitModData()
    DevTools.debugLog("Getting Old", "Server Init complete")
end

local function updatePlayer(player)
    player = player or getPlayer()
    if not player then return end

    local md = player:getModData()
    if md._AgeAssigned then return end

    if AgeConfig.useRandomBirthday() then
        finishAgeAssignment(player)
        return
    end

    local month, day = AgeConfig.validateBirthday(md._GettingOldBirthdayMonth, md._GettingOldBirthdayDay)
    if month and day then
        finishAgeAssignment(player, month, day)
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= MOD_ID then return end
    if not player or not player:isAlive() then return end

    local md = player:getModData()
    if md._AgeAssigned then return end

    if command == "RequestAgeInit" and AgeConfig.useRandomBirthday() then
        finishAgeAssignment(player)
        return
    end

    if command ~= "SetBirthday" or AgeConfig.useRandomBirthday() then return end

    local month, day = AgeConfig.validateBirthday(args and args.month, args and args.day)
    if not month or not day then
        DevTools.debugLog("Getting Old", "Rejected invalid birthday selection")
        return
    end

    finishAgeAssignment(player, month, day)
end

Events.OnPlayerUpdate.Add(updatePlayer)
Events.OnClientCommand.Add(onClientCommand)
DevTools.debugLog("Getting Old", "Server Init Hooked.")
