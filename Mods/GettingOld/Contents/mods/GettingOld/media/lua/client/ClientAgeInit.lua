local GettingOldRegistry = require("GettingOld/Registries")
local delayTicks = 0
local zoomerSpeechTicks = 0
local ZOOMER_SPEECH_INTERVAL_TICKS = 1800
local ZOOMER_SPEECH_CHANCE_PERCENT = 10

local function ClientAgeInit()
    local player = getPlayer()
    if not player then return end

    local md = player:getModData()
    if md._AgeClientInit then return end
    if md._AgeAssigned == false then return end

    delayTicks = delayTicks + 1
    if delayTicks < 120 then return end
    md._AgeClientInit = true
    DevTools.debugLog("Getting Old", "Starting Client Init")

    local age = tostring(md.Age or "?")

    DevTools.saySafe(player, "I can't believe I'm " .. age .. " and having to deal with the zombie apocalypse...")

    DevTools.debugLog("Getting Old", "Client Init complete")
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
Events.OnPlayerUpdate.Add(ZoomerRandomSpeech)
Events.OnGameStart.Add(HookHealthPanel)

DevTools.debugLog("Getting Old", "Client Init Hooked.")
