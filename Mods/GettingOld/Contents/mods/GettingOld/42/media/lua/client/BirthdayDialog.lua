require "AgeConfig"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"

local MOD_ID = "GettingOld"
local MONTHS = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
}

GettingOldBirthdayDialog = ISPanel:derive("GettingOldBirthdayDialog")
local states = {}
local RETRY_MS = 5000

local function submitChoice(player, state)
    state.sentAt = getTimestampMs()
    local selected = state.month and not AgeConfig.useRandomBirthday()
    if isClient() then
        sendClientCommand(player, MOD_ID, selected and "SetBirthday" or "RequestAgeInit",
            selected and { month = state.month, day = state.day } or {})
    elseif state.month then
        local md = player:getModData()
        md._GettingOldBirthdayMonth = state.month
        md._GettingOldBirthdayDay = state.day
    end
end

function GettingOldBirthdayDialog:initialise()
    ISPanel.initialise(self)

    local comboHeight = 28
    self.monthCombo = ISComboBox:new(24, 100, 240, comboHeight, self, GettingOldBirthdayDialog.onMonthChanged)
    self.monthCombo:initialise()
    for _, monthName in ipairs(MONTHS) do
        self.monthCombo:addOption(monthName)
    end
    self:addChild(self.monthCombo)

    self.dayCombo = ISComboBox:new(276, 100, 100, comboHeight)
    self.dayCombo:initialise()
    self:addChild(self.dayCombo)
    self:populateDays(1)

    self.confirmButton = ISButton:new(125, 150, 150, 30, getText("UI_GettingOld_Birthday_Confirm"), self, GettingOldBirthdayDialog.onConfirm)
    self.confirmButton:initialise()
    self.confirmButton:instantiate()
    self:addChild(self.confirmButton)
end

function GettingOldBirthdayDialog:populateDays(month)
    local previousDay = self.dayCombo.selected > 0 and self.dayCombo.selected or 1
    self.dayCombo:clear()
    local maximum = AgeConfig.daysInMonth(month)
    for day = 1, maximum do
        self.dayCombo:addOption(tostring(day))
    end
    self.dayCombo.selected = math.min(previousDay, maximum)
end

function GettingOldBirthdayDialog:onMonthChanged()
    self:populateDays(self.monthCombo.selected)
end

function GettingOldBirthdayDialog:prerender()
    ISPanel.prerender(self)
    self:drawTextCentre(getText("UI_GettingOld_Birthday_Title"), self.width / 2, 18, 1, 1, 1, 1, UIFont.Medium)
    self:drawTextCentre(getText("UI_GettingOld_Birthday_Description"), self.width / 2, 52, 0.85, 0.85, 0.85, 1, UIFont.Small)
    self:drawText(getText("UI_GettingOld_Birthday_Month"), 24, 81, 1, 1, 1, 1, UIFont.Small)
    self:drawText(getText("UI_GettingOld_Birthday_Day"), 276, 81, 1, 1, 1, 1, UIFont.Small)
end

function GettingOldBirthdayDialog:onConfirm()
    local month = self.monthCombo.selected
    local day = self.dayCombo.selected
    local player = self.player
    if not player or not month or not day then return end

    local state = states[player:getPlayerNum()]
    if not state or state.player ~= player then return end
    state.month, state.day = month, day
    local md = player:getModData()
    md._GettingOldBirthdayMonth, md._GettingOldBirthdayDay = month, day
    submitChoice(player, state)
    self:setVisible(false)
    self:removeFromUIManager()
    state.dialog = nil
end

function GettingOldBirthdayDialog:new(player)
    local width = 400
    local height = 204
    local index = player:getPlayerNum()
    local x = getPlayerScreenLeft(index) + (getPlayerScreenWidth(index) - width) / 2
    local y = getPlayerScreenTop(index) + (getPlayerScreenHeight(index) - height) / 2
    local o = ISPanel.new(self, x, y, width, height)
    o.player = player
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
    o.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 1 }
    o.moveWithMouse = true
    return o
end

local function closeDialog(state)
    if state and state.dialog then
        state.dialog:setVisible(false)
        state.dialog:removeFromUIManager()
        state.dialog = nil
    end
end

local function updateBirthdayDialog(player, index)
    local state = states[index]
    if state and state.player ~= player then closeDialog(state); states[index] = nil; state = nil end
    if not player or not player:isAlive() then
        closeDialog(state)
        states[index] = nil
        return
    end
    if not state then
        state = { player = player }
        states[index] = state
    end
    local md = player:getModData()
    if md._AgeAssigned then
        closeDialog(state)
        state.month, state.day, state.sentAt = nil, nil, nil
        return
    end
    -- Pending state belongs to this session/character, not a saved global lock.
    -- Recover a selection made before a save or a delayed server acknowledgement.
    if not state.month then
        state.month, state.day = AgeConfig.validateBirthday(md._GettingOldBirthdayMonth, md._GettingOldBirthdayDay)
        if not state.month and md.birthYear then
            state.month, state.day = AgeConfig.validateBirthday(md.birthMonth, md.birthDay)
        end
    end
    if AgeConfig.useRandomBirthday() or state.month then
        closeDialog(state)
        if not state.sentAt or getTimestampMs() - state.sentAt >= RETRY_MS then submitChoice(player, state) end
        return
    end
    if not state.dialog then
        state.dialog = GettingOldBirthdayDialog:new(player)
        state.dialog:initialise()
        state.dialog:addToUIManager()
    end
end

Events.OnTick.Add(function()
    for index, state in pairs(states) do
        if getSpecificPlayer(index) ~= state.player then closeDialog(state); states[index] = nil end
    end
    for index = 0, getNumActivePlayers() - 1 do
        updateBirthdayDialog(getSpecificPlayer(index), index)
    end
end)
