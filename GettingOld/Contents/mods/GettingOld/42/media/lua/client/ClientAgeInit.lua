local function ClientAgeInit()
    local player = getPlayer()
    if not player then return end

    local md = player:getModData()
    if md._AgeClientInit then return end
    if md._AgeAssigned == false or md._AgeAssigned == nil then return end

    local playerID = player:getOnlineID()

    DevTools.waitSeconds(5, function()
        local playerRef = getPlayerByOnlineID(playerID)
        if not playerRef then return end

        local mdRef = playerRef:getModData()
        mdRef._AgeClientInit = true

        DevTools.debugLog("Getting Old", "Starting Client Init")

        local age = tostring(mdRef.Age or "?")

        DevTools.saySafe(playerRef, "I can't believe I'm " .. age .. " and having to deal with the zombie apocalypse...")

        DevTools.debugLog("Getting Old", "Client Init complete")
    end, "ClientAgeInit-" .. tostring(playerID))
end


local function HookHealthPanel()
    if not ISHealthPanel or not ISHealthPanel.render then
        DevTools.debugLog("Getting Old", "ISHealthPanel not ready yet")
        return
    end

    if ISHealthPanel._GettingOldHooked then return end
    ISHealthPanel._GettingOldHooked = true

    local oldRender = ISHealthPanel.render

    function ISHealthPanel:render()
        oldRender(self)

        local player = getPlayer()
        if not player then return end

        local md = player:getModData()
        local age = md.Age
        if not age then return end

        local x = self.width - 100
        local y = self.height - 150

        self:drawText("Age: " .. tostring(age), x, y, 1, 1, 1, 1, UIFont.Small)

        local group = AgeSystem.getGroup(age)
        self:drawText("Life Stage: " .. group, x, y + 15, 0.8, 0.8, 0.8, 1, UIFont.Small)

        if md.birthDay and md.birthMonth and md.birthYear then
            local birthday = string.format("%02d/%02d/%04d", md.birthDay, md.birthMonth, md.birthYear)
            self:drawText("DOB: " .. birthday, x, y + 30, 0.8, 0.8, 0.8, 1, UIFont.Small)
        end
    end

    DevTools.debugLog("Getting Old", "Health panel hooked")
end

Events.OnPlayerUpdate.Add(ClientAgeInit)
Events.OnGameStart.Add(HookHealthPanel)

DevTools.debugLog("Getting Old", "Client Init Hooked.")