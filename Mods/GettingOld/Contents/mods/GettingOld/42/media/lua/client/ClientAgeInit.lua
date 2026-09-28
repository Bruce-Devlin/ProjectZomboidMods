require "XpSystem/ISUI/ISHealthPanel"

local GettingOldRegistry = require("GettingOld/Registries")
local zoomerSpeechTicks = 0
local ZOOMER_SPEECH_INTERVAL_TICKS = 1800
local ZOOMER_SPEECH_CHANCE_PERCENT = 10
local HEALTH_PANEL_SPACING = 10

local function ClientAgeInit()
    local player = getPlayer()
    if not player then return end

    local md = player:getModData()
    if md._AgeClientInit then return end
    if md._AgeAssigned == false or md._AgeAssigned == nil then return end

    local playerID = player:getOnlineID()

    DevTools.waitSeconds(5, function()
        local playerRef = playerID == 0 and getPlayer() or getPlayerByOnlineID(playerID)
        if not playerRef then return end

        local mdRef = playerRef:getModData()
        mdRef._AgeClientInit = true

        DevTools.debugLog("Getting Old", "Starting Client Init")

        local age = tostring(mdRef.Age or "?")

        DevTools.saySafe(playerRef, "I can't believe I'm " .. age .. " and having to deal with the zombie apocalypse...")

        DevTools.debugLog("Getting Old", "Client Init complete")
    end, "ClientAgeInit-" .. tostring(playerID))
end

local function ZoomerRandomSpeech()
    local player = getPlayer()
    if not player or not player:hasTrait(GettingOldRegistry.Zoomer) then return end

    zoomerSpeechTicks = zoomerSpeechTicks + 1
    if zoomerSpeechTicks < ZOOMER_SPEECH_INTERVAL_TICKS then return end
    zoomerSpeechTicks = 0

    if ZombRand(100) < ZOOMER_SPEECH_CHANCE_PERCENT then
        DevTools.saySafe(player, "67")
    end
end

local function HookHealthPanel()
    if not ISHealthPanel or not ISHealthPanel.render then
        DevTools.debugLog("Getting Old", "ISHealthPanel not ready yet")
        return false
    end

    if ISHealthPanel._GettingOldHooked then return true end
    ISHealthPanel._GettingOldHooked = true

    local oldRender = ISHealthPanel.render

    function ISHealthPanel:render()
        oldRender(self)

        local player = self.getPatient and self:getPatient() or getPlayer()
        if not player then return end

        local md = player:getModData()
        local age = md.Age
        if not age then return end

        local fontHeight = getTextManager():getFontHeight(UIFont.Small)
        local lineCount = md.birthDay and md.birthMonth and md.birthYear and 3 or 2
        local blockHeight = lineCount * fontHeight
        local treatmentY = self.height - HEALTH_PANEL_SPACING - fontHeight
        local y = treatmentY - HEALTH_PANEL_SPACING - blockHeight
        local x = self.healthPanel:getRight() + HEALTH_PANEL_SPACING

        -- Keep the expanding injury list above the age footer so it cannot paint
        -- over these details. The native list remains scrollable when space is tight.
        if self.listbox then
            local listHeight = math.max(0, y - HEALTH_PANEL_SPACING - self.listbox:getY())
            self.listbox:setHeight(listHeight)
            if self.listbox.vscroll then
                self.listbox.vscroll:setHeight(listHeight)
            end
        end

        self:drawText("Age: " .. tostring(age), x, y, 1, 1, 1, 1, UIFont.Small)

        local group = AgeSystem.getGroup(age)
        self:drawText("Life Stage: " .. group, x, y + fontHeight, 0.8, 0.8, 0.8, 1, UIFont.Small)

        if md.birthDay and md.birthMonth and md.birthYear then
            local birthday = string.format("%02d/%02d/%04d", md.birthDay, md.birthMonth, md.birthYear)
            self:drawText("DOB: " .. birthday, x, y + fontHeight * 2, 0.8, 0.8, 0.8, 1, UIFont.Small)
        end
    end

    DevTools.debugLog("Getting Old", "Health panel hooked")
    return true
end

local function EnsureHealthPanelHook()
    if HookHealthPanel() then
        Events.OnPlayerUpdate.Remove(EnsureHealthPanelHook)
    end
end

Events.OnPlayerUpdate.Add(ClientAgeInit)
Events.OnPlayerUpdate.Add(ZoomerRandomSpeech)
Events.OnGameStart.Add(HookHealthPanel)
Events.OnPlayerUpdate.Add(EnsureHealthPanelHook)

-- The explicit require above normally makes the panel available immediately.
-- Keep the event hooks as a retry path for unusual mod load orders.
HookHealthPanel()

DevTools.debugLog("Getting Old", "Client Init Hooked.")
