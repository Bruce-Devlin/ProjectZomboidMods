require "AgeClock"

local BIRTHDAY_HAT_CHANCE = 30
local BIRTHDAY_HAT_ITEM = "Base.Hat_PartyHat_Stars"

local function syncBirthdayState(player)
    if isServer() then
        player:transmitModData()
    end
end

local function tryGiveBirthdayHat(player, md, newAge)
    if isClient() or not player:isAlive() then return false end
    local inventory = player:getInventory()
    if not inventory then return false end

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

    local partyHat = inventory:AddItem(BIRTHDAY_HAT_ITEM)
    if partyHat then
        partyHat:setName(tostring(player:getUsername()) .. "'s " .. tostring(newAge) .. " birthday hat!")
        partyHat:setTooltip("A lucky birthday hat")
        if isServer() then sendAddItemToContainer(inventory, partyHat) end
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

local function updateAge(player)
    if not player or not player:isAlive() then return end
    local md = player:getModData()
    if not md._AgeAssigned or not md.birthYear or not md.Age then return end
    local expectedAge = AgeClock.advance(player)
    if expectedAge > md.Age then playerBirthday(player, md.Age, expectedAge) end
    AgeSystem.apply(player)
end

local function checkPlayerAge()
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do updateAge(players:get(i)) end
    elseif not isClient() then
        for i = 0, getNumActivePlayers() - 1 do updateAge(getSpecificPlayer(i)) end
    end
end

Events.EveryHours.Add(checkPlayerAge)
